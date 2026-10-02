use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

pub(super) const PROCESS_STDIN_QUEUE_CAPACITY: usize = 32;
pub(super) const PROCESS_STDIN_MAX_QUEUED_BYTES: usize = 4 * 1024 * 1024;

pub(super) struct StdinChunk {
    pub(super) data: Vec<u8>,
    budget: Arc<StdinBudget>,
}

impl Drop for StdinChunk {
    fn drop(&mut self) {
        self.budget.release(self.data.len());
    }
}

pub(super) struct StdinBudget {
    queued_bytes: AtomicUsize,
}

impl StdinBudget {
    pub(super) fn new() -> Arc<Self> {
        Arc::new(Self {
            queued_bytes: AtomicUsize::new(0),
        })
    }

    pub(super) fn try_reserve(&self, bytes: usize) -> bool {
        if bytes > PROCESS_STDIN_MAX_QUEUED_BYTES {
            return false;
        }
        let mut current = self.queued_bytes.load(Ordering::Acquire);
        loop {
            let Some(next) = current.checked_add(bytes) else {
                return false;
            };
            if next > PROCESS_STDIN_MAX_QUEUED_BYTES {
                return false;
            }
            match self.queued_bytes.compare_exchange_weak(
                current,
                next,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => return true,
                Err(observed) => current = observed,
            }
        }
    }

    fn release(&self, bytes: usize) {
        self.queued_bytes.fetch_sub(bytes, Ordering::Release);
    }
}

impl StdinChunk {
    pub(super) fn new(data: Vec<u8>, budget: Arc<StdinBudget>) -> Self {
        Self { data, budget }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use std::process::Stdio;
    use std::sync::atomic::Ordering;
    use std::sync::Arc;

    use tokio::io::AsyncWriteExt;
    use tokio::sync::{mpsc, Notify};

    use super::*;

    #[test]
    fn stalled_child_input_stays_within_the_bounded_queue() {
        let (accepted_bytes, remaining_bytes) = super::super::runtime().block_on(async {
            let mut command = super::super::build_command(
                "sh",
                &["-c".to_string(), "sleep 2".to_string()],
                None,
                None,
                true,
            );
            command
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            let mut child = command.spawn().expect("stalled child starts");
            let stdin = child.stdin.take().expect("stalled child has stdin");
            let (sender, mut incoming) = mpsc::channel(PROCESS_STDIN_QUEUE_CAPACITY);
            let budget = StdinBudget::new();
            let id = super::super::NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
            super::super::sessions()
                .lock()
                .expect("process registry lock")
                .insert(
                    id,
                    super::super::Session {
                        stdin: Some(sender),
                        stdin_budget: Arc::clone(&budget),
                        kill: Arc::new(Notify::new()),
                    },
                );
            let writer = tokio::spawn(async move {
                let mut stdin = stdin;
                while let Some(chunk) = incoming.recv().await {
                    if stdin.write_all(&chunk.data).await.is_err() {
                        break;
                    }
                }
            });

            let payload = vec![b'x'; 256 * 1024];
            let mut accepted_bytes = 0;
            while super::super::write_stdin(id, payload.clone()) {
                accepted_bytes += payload.len();
            }
            super::super::close_stdin(id);
            super::super::sessions()
                .lock()
                .expect("process registry lock")
                .remove(&id);
            let _ = child.kill().await;
            let _ = child.wait().await;
            writer.abort();
            let _ = writer.await;
            (accepted_bytes, budget.queued_bytes.load(Ordering::Acquire))
        });

        assert!(accepted_bytes > 0);
        assert!(accepted_bytes <= PROCESS_STDIN_MAX_QUEUED_BYTES);
        assert_eq!(remaining_bytes, 0);
    }
}
