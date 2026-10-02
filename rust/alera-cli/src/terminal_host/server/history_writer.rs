use std::collections::VecDeque;
use std::future::Future;
use std::pin::Pin;

use anyhow::{anyhow, Result};
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;

use super::{ServerCommand, ServerInbox};
use crate::terminal_host::history_store::TerminalHostHistoryStore;
use crate::terminal_host::session::DurableOutputBatch;

#[cfg(test)]
mod tests;

/// Seven queued batches plus the one currently being written bounds writer
/// admission to eight 64 KiB batches per session. The actor retains a
/// completion copy for each in-flight request, so callers must account for
/// both copies when budgeting memory.
pub(crate) const HISTORY_WRITER_QUEUE_CAPACITY: usize = 7;
const HISTORY_WRITER_MAX_PENDING: usize = HISTORY_WRITER_QUEUE_CAPACITY + 1;
const HISTORY_WRITE_MAX_ATTEMPTS: usize = 3;
const HISTORY_WRITE_RETRY_DELAYS: [std::time::Duration; 2] = [
    std::time::Duration::from_millis(10),
    std::time::Duration::from_millis(50),
];

type AppendFuture<'a> = Pin<Box<dyn Future<Output = Result<()>> + Send + 'a>>;
type WriteResult = std::result::Result<(), HistoryWriteFailure>;

/// Storage used by the ordered writer. Keeping this boundary small makes the
/// ordering and failure contract testable without coupling it to SQLite.
pub(crate) trait HistoryOutputSink: Clone + Send + Sync + 'static {
    fn append_output<'a>(
        &'a self,
        session_id: &'a str,
        sequence: i64,
        data: &'a [u8],
    ) -> AppendFuture<'a>;
}

impl HistoryOutputSink for TerminalHostHistoryStore {
    fn append_output<'a>(
        &'a self,
        session_id: &'a str,
        sequence: i64,
        data: &'a [u8],
    ) -> AppendFuture<'a> {
        Box::pin(TerminalHostHistoryStore::append_output(
            self, session_id, sequence, data,
        ))
    }
}

#[derive(Debug)]
pub(crate) struct HistoryWriteFailure {
    pub batch: DurableOutputBatch,
    pub error: anyhow::Error,
}

struct HistoryWriteRequest {
    session_id: String,
    batch: DurableOutputBatch,
    completion: oneshot::Sender<WriteResult>,
}

struct PendingWrite {
    batch: DurableOutputBatch,
    completion: oneshot::Receiver<WriteResult>,
}

/// One serial writer and a bounded queue for one terminal session.
///
/// Enqueue is deliberately non-blocking. A full writer returns the exact
/// batch to the actor, which keeps the actor available for control commands
/// while the PTY producer is paused by the session backpressure gate.
/// Completion polling is also non-blocking: callers must retain this writer
/// until every accepted request has produced a result.
pub(crate) struct OrderedHistoryWriter<S> {
    sender: Option<mpsc::Sender<HistoryWriteRequest>>,
    pending: VecDeque<PendingWrite>,
    worker: Option<JoinHandle<()>>,
    last_enqueued_sequence: Option<i64>,
    failed: bool,
    _sink: std::marker::PhantomData<S>,
}

impl<S> OrderedHistoryWriter<S>
where
    S: HistoryOutputSink,
{
    pub(crate) fn new(sink: S, session_id: String, inbox: ServerInbox) -> Self {
        let (sender, mut receiver) =
            mpsc::channel::<HistoryWriteRequest>(HISTORY_WRITER_QUEUE_CAPACITY);
        let worker_session_id = session_id.clone();
        let worker = tokio::spawn(async move {
            while let Some(request) = receiver.recv().await {
                let result = match append_with_retries(&sink, &request).await {
                    Ok(()) => Ok(()),
                    Err(error) => Err(HistoryWriteFailure {
                        batch: request.batch,
                        error,
                    }),
                };
                let failed = result.is_err();
                let _ = request.completion.send(result);
                // Readiness is level-triggered by the writer's completion
                // queue. The actor also drains completions at barriers, so a
                // dropped wake under control pressure cannot drop data or
                // leave the worker waiting on the actor during shutdown.
                let _ = inbox
                    .send_wait(ServerCommand::HistoryWriterReady {
                        session_id: worker_session_id.clone(),
                    })
                    .await;
                if failed {
                    // Once storage fails, return all accepted queued batches
                    // to the actor instead of writing later chunks out of
                    // order or silently dropping them.
                    while let Ok(request) = receiver.try_recv() {
                        let _ = request.completion.send(Err(HistoryWriteFailure {
                            batch: request.batch,
                            error: anyhow!("history writer stopped after a storage failure"),
                        }));
                        let _ = inbox
                            .send_wait(ServerCommand::HistoryWriterReady {
                                session_id: worker_session_id.clone(),
                            })
                            .await;
                    }
                    break;
                }
            }
        });
        Self {
            sender: Some(sender),
            pending: VecDeque::new(),
            worker: Some(worker),
            last_enqueued_sequence: None,
            failed: false,
            _sink: std::marker::PhantomData,
        }
    }

    pub(crate) fn failed(&self) -> bool {
        self.failed
    }

    pub(crate) fn pending_len(&self) -> usize {
        self.pending.len()
    }

    /// Stop an idle worker without awaiting a storage future.
    ///
    /// This is safe only after `pending_len() == 0`; every accepted request is
    /// represented by one pending completion until its storage operation has
    /// finished. The actor uses this at session teardown and checkpoint
    /// barriers so a healthy idle worker cannot leak after its session closes.
    pub(crate) fn stop_when_idle(&mut self) {
        debug_assert!(self.pending.is_empty());
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            worker.abort();
        }
    }

    pub(crate) fn try_enqueue(
        &mut self,
        session_id: &str,
        batch: DurableOutputBatch,
    ) -> std::result::Result<(), HistoryWriteFailure> {
        if self.failed {
            return Err(HistoryWriteFailure {
                batch,
                error: anyhow!("history writer is closed after a storage failure"),
            });
        }
        if let Some(last) = self.last_enqueued_sequence {
            let expected = last.saturating_add(1);
            if batch.sequence != expected {
                let actual = batch.sequence;
                return Err(HistoryWriteFailure {
                    batch,
                    error: anyhow!(
                        "history sequence gap for {session_id}: expected {expected}, got {actual}"
                    ),
                });
            }
        }
        if self.pending.len() >= HISTORY_WRITER_MAX_PENDING {
            return Err(HistoryWriteFailure {
                batch,
                error: anyhow!("history writer queue is full"),
            });
        }
        let retained_batch = DurableOutputBatch {
            data: batch.data.clone(),
            sequence: batch.sequence,
        };
        let (completion, result) = oneshot::channel();
        let request = HistoryWriteRequest {
            session_id: session_id.to_string(),
            batch,
            completion,
        };
        let Some(sender) = self.sender.as_ref() else {
            return Err(HistoryWriteFailure {
                batch: retained_batch,
                error: anyhow!("history writer is closed"),
            });
        };
        match sender.try_send(request) {
            Ok(()) => {}
            Err(mpsc::error::TrySendError::Full(request)) => {
                return Err(HistoryWriteFailure {
                    batch: request.batch,
                    error: anyhow!("history writer queue is full"),
                });
            }
            Err(mpsc::error::TrySendError::Closed(request)) => {
                self.failed = true;
                return Err(HistoryWriteFailure {
                    batch: request.batch,
                    error: anyhow!("history writer task stopped"),
                });
            }
        }
        self.last_enqueued_sequence = Some(retained_batch.sequence);
        self.pending.push_back(PendingWrite {
            batch: retained_batch,
            completion: result,
        });
        Ok(())
    }

    pub(crate) fn poll_completed(&mut self) -> Vec<HistoryWriteFailure> {
        let mut failures = Vec::new();
        while let Some(pending) = self.pending.front_mut() {
            match pending.completion.try_recv() {
                Ok(Ok(())) => {
                    self.pending.pop_front();
                }
                Ok(Err(failure)) => {
                    self.pending.pop_front();
                    self.failed = true;
                    failures.push(failure);
                }
                Err(oneshot::error::TryRecvError::Empty) => break,
                Err(oneshot::error::TryRecvError::Closed) => {
                    let pending = self.pending.pop_front().expect("pending write exists");
                    self.failed = true;
                    failures.push(HistoryWriteFailure {
                        batch: pending.batch,
                        error: anyhow!("history writer completion was dropped"),
                    });
                }
            }
        }
        failures
    }

    #[cfg(test)]
    pub(crate) async fn drain(&mut self) -> Vec<HistoryWriteFailure> {
        let mut failures = Vec::new();
        while !self.pending.is_empty() {
            if let Some(failure) = self.await_one().await {
                self.failed = true;
                failures.push(failure);
            }
        }
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            let _ = worker.await;
        }
        failures
    }

    #[cfg(test)]
    async fn await_one(&mut self) -> Option<HistoryWriteFailure> {
        let pending = self.pending.pop_front()?;
        match pending.completion.await {
            Ok(Ok(())) => None,
            Ok(Err(failure)) => Some(failure),
            Err(_) => Some(HistoryWriteFailure {
                batch: pending.batch,
                error: anyhow!("history writer completion was dropped"),
            }),
        }
    }
}

async fn append_with_retries<S: HistoryOutputSink>(
    sink: &S,
    request: &HistoryWriteRequest,
) -> Result<()> {
    let mut last_error = None;
    for attempt in 0..HISTORY_WRITE_MAX_ATTEMPTS {
        match sink
            .append_output(
                &request.session_id,
                request.batch.sequence,
                &request.batch.data,
            )
            .await
        {
            Ok(()) => return Ok(()),
            Err(error) => {
                last_error = Some(error);
                if let Some(delay) = HISTORY_WRITE_RETRY_DELAYS.get(attempt) {
                    tokio::time::sleep(*delay).await;
                }
            }
        }
    }
    Err(last_error.expect("history write attempts always run at least once"))
}

impl<S> Drop for OrderedHistoryWriter<S> {
    fn drop(&mut self) {
        if let Some(worker) = self.worker.take() {
            worker.abort();
        }
    }
}
