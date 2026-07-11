use std::collections::HashSet;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{sync_channel, SyncSender, TrySendError};
use std::sync::Arc;

use chrono::{DateTime, Utc};
use portable_pty::{native_pty_system, ChildKiller, CommandBuilder, MasterPty, PtySize};
use serde_json::{json, Value};

use crate::terminal_host::buffer::ScrollbackBuffer;
use crate::terminal_host::history_store::{TerminalHostCheckpoint, TerminalHostHistoryStore};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{encode_bytes, TerminalHostLaunch};

/// Bytes read from the PTY per `read` call.
const READ_CHUNK_BYTES: usize = 8192;
const INPUT_QUEUE_CAPACITY: usize = 64;
static NEXT_SESSION_INSTANCE_ID: AtomicU64 = AtomicU64::new(1);

fn next_session_instance_id() -> u64 {
    NEXT_SESSION_INSTANCE_ID.fetch_add(1, Ordering::Relaxed)
}

/// A message produced by a session's PTY reader thread.
#[derive(Debug)]
pub enum PtyEvent {
    Output(Vec<u8>),
    Exit(i32),
    Error(String),
    InputWritten {
        completion: PtyWriteCompletion,
        error: Option<String>,
    },
}

#[derive(Debug)]
pub enum PtyWriteCompletion {
    ClientRequest {
        client_id: u64,
        request_id: i64,
    },
    OrchestrationPaste {
        session_instance_id: u64,
        message_ids: Vec<String>,
    },
    OrchestrationEnter {
        session_instance_id: u64,
        message_ids: Vec<String>,
    },
}

struct PtyWrite {
    completion: PtyWriteCompletion,
    bytes: Vec<u8>,
}

pub struct OutputBatch {
    pub payload: Value,
}

pub struct DurableOutputBatch {
    pub data: Vec<u8>,
    pub sequence: i64,
}

/// A hosted terminal session. The PTY is read on a dedicated OS thread; other
/// state transitions run in its owning server actor, so no locks are required.
pub struct Session {
    instance_id: u64,
    pub id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub working_directory: String,
    pub clients: HashSet<u64>,
    output_paused_clients: HashSet<u64>,
    pub(super) buffer: ScrollbackBuffer,
    running: bool,
    exit_code: Option<i32>,
    ended_at: Option<DateTime<Utc>>,
    master: Option<Box<dyn MasterPty + Send>>,
    input_tx: Option<SyncSender<PtyWrite>>,
    killer: Option<Box<dyn ChildKiller + Send + Sync>>,
    terminated: bool,
    checkpoint_gen: u64,
    checkpoint_armed: bool,
    output_batch: Vec<u8>,
    output_batch_gen: u64,
    output_batch_armed: bool,
    durable_output_batch: Vec<u8>,
    durable_output_batch_gen: u64,
    durable_output_batch_armed: bool,
    durable_output_batch_sequence: i64,
}

impl Session {
    /// Spawn a fresh shell PTY, persist an initial checkpoint, and start the
    /// reader thread.
    #[allow(clippy::too_many_arguments)]
    pub async fn start(
        id: String,
        workspace_id: String,
        tab_id: String,
        working_directory: String,
        launch: &TerminalHostLaunch,
        cols: u16,
        rows: u16,
        max_bytes: usize,
        initial_scrollback: &[u8],
        store: &TerminalHostHistoryStore,
        on_event: impl Fn(PtyEvent) + Send + Sync + 'static,
    ) -> HostResult<Session> {
        let durable_output_batch_sequence = store
            .next_output_sequence(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|error| HostError::state(error.to_string()))?;

        let mut command = CommandBuilder::new(&launch.shell);
        command.args(&launch.arguments);
        // Always pass the configured environment map explicitly so portable_pty
        // clears the inherited environment and applies only these entries.
        command.env_clear();
        for (key, value) in &launch.environment {
            command.env(key, value);
        }
        // The orchestration identity: agents inside this PTY self-identify in
        // `alera orchestration` commands without an RPC round-trip. The handle
        // is the session id, which is also the key the app uses for agent
        // status entries.
        command.env("ALERA_TERMINAL_HANDLE", &id);
        // The working directory is persisted as session metadata; shell startup
        // preparation owns any cwd changes that should happen inside the PTY.

        let child = pair
            .slave
            .spawn_command(command)
            .map_err(|error| HostError::state(error.to_string()))?;
        // Drop the slave so the master observes EOF once the child exits.
        drop(pair.slave);

        let killer = child.clone_killer();
        let reader = pair
            .master
            .try_clone_reader()
            .map_err(|error| HostError::state(error.to_string()))?;
        let writer = pair
            .master
            .take_writer()
            .map_err(|error| HostError::state(error.to_string()))?;
        let (input_tx, input_rx) = sync_channel(INPUT_QUEUE_CAPACITY);
        let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(on_event);

        let mut session = Session {
            instance_id: next_session_instance_id(),
            id,
            workspace_id,
            tab_id,
            working_directory,
            clients: HashSet::new(),
            output_paused_clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(max_bytes, initial_scrollback),
            running: true,
            exit_code: None,
            ended_at: None,
            master: Some(pair.master),
            input_tx: Some(input_tx),
            killer: Some(killer),
            terminated: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
            output_batch: Vec::new(),
            output_batch_gen: 0,
            output_batch_armed: false,
            durable_output_batch: Vec::new(),
            durable_output_batch_gen: 0,
            durable_output_batch_armed: false,
            durable_output_batch_sequence,
        };
        session.write_checkpoint(store, None).await?;
        spawn_reader(reader, child, Arc::clone(&on_event));
        spawn_writer(writer, input_rx, on_event);
        Ok(session)
    }

    /// Rebuild a non-running session from a persisted checkpoint, or `None` if
    /// there is no usable checkpoint.
    pub async fn restore_exited(
        session_id: String,
        workspace_id: String,
        tab_id: String,
        store: &TerminalHostHistoryStore,
        max_bytes: usize,
    ) -> Option<Session> {
        let checkpoint = match store.read(&session_id, max_bytes).await {
            Ok(Some(checkpoint)) => checkpoint,
            _ => return None,
        };
        let (exit_code, ended_at) = if checkpoint.ended_at.is_none() {
            (Some(-1), None)
        } else {
            (Some(checkpoint.exit_code.unwrap_or(0)), checkpoint.ended_at)
        };
        Some(Session {
            instance_id: next_session_instance_id(),
            id: session_id,
            workspace_id,
            tab_id,
            working_directory: checkpoint.working_directory,
            clients: HashSet::new(),
            output_paused_clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(max_bytes, &checkpoint.buffer),
            running: false,
            exit_code,
            ended_at,
            master: None,
            input_tx: None,
            killer: None,
            terminated: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
            output_batch: Vec::new(),
            output_batch_gen: 0,
            output_batch_armed: false,
            durable_output_batch: Vec::new(),
            durable_output_batch_gen: 0,
            durable_output_batch_armed: false,
            durable_output_batch_sequence: 0,
        })
    }

    pub fn running(&self) -> bool {
        self.running
    }

    pub fn instance_id(&self) -> u64 {
        self.instance_id
    }

    pub fn set_max_bytes(&mut self, max_bytes: usize) {
        self.buffer.set_max_bytes(max_bytes);
    }

    pub fn attach(&mut self, client_id: u64) {
        self.clients.insert(client_id);
        self.output_paused_clients.remove(&client_id);
    }

    pub fn detach(&mut self, client_id: u64) {
        self.clients.remove(&client_id);
        self.output_paused_clients.remove(&client_id);
    }

    pub fn set_output_paused(&mut self, client_id: u64, paused: bool) {
        if paused {
            self.output_paused_clients.insert(client_id);
        } else {
            self.output_paused_clients.remove(&client_id);
        }
    }

    pub fn output_clients(&self) -> Vec<u64> {
        self.clients
            .iter()
            .copied()
            .filter(|client_id| !self.output_paused_clients.contains(client_id))
            .collect()
    }

    /// Queue input for the session-local blocking writer.
    pub fn queue_write(&mut self, completion: PtyWriteCompletion, bytes: &[u8]) -> HostResult<()> {
        if bytes.is_empty() {
            return Ok(());
        }
        if !self.running {
            return Err(HostError::state("Terminal session is not running."));
        }
        let Some(input_tx) = self.input_tx.as_ref() else {
            return Err(HostError::state("terminal input writer is unavailable"));
        };
        input_tx
            .try_send(PtyWrite {
                completion,
                bytes: bytes.to_vec(),
            })
            .map_err(|error| match error {
                TrySendError::Full(_) => {
                    HostError::state("terminal_input_backpressure: terminal input queue is full")
                }
                TrySendError::Disconnected(_) => {
                    HostError::state("terminal input writer is unavailable")
                }
            })
    }

    pub fn resize(&mut self, cols: u16, rows: u16) {
        if !self.running {
            return;
        }
        if let Some(master) = self.master.as_ref() {
            let _ = master.resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            });
        }
    }

    /// Append PTY output to the scrollback and live-output batch. Returns a
    /// timer generation when a delayed flush should be armed.
    pub fn append_output(&mut self, data: &[u8]) -> (Option<u64>, Option<u64>) {
        self.buffer.append(data);
        self.output_batch.extend_from_slice(data);
        self.durable_output_batch.extend_from_slice(data);
        let output_generation = if self.output_batch_armed {
            None
        } else {
            self.output_batch_armed = true;
            Some(self.output_batch_gen)
        };
        let durable_generation = if self.durable_output_batch_armed {
            None
        } else {
            self.durable_output_batch_armed = true;
            Some(self.durable_output_batch_gen)
        };
        (output_generation, durable_generation)
    }

    pub fn output_batch_len(&self) -> usize {
        self.output_batch.len()
    }

    pub fn output_batch_due(&self, generation: u64) -> bool {
        self.output_batch_armed && self.output_batch_gen == generation
    }

    pub fn flush_output_batch(&mut self) -> Option<OutputBatch> {
        if self.output_batch.is_empty() {
            self.output_batch_armed = false;
            return None;
        }
        self.output_batch_gen = self.output_batch_gen.wrapping_add(1);
        self.output_batch_armed = false;
        let data = std::mem::take(&mut self.output_batch);
        let payload = json!({ "sessionId": self.id, "dataBase64": encode_bytes(&data) });
        Some(OutputBatch { payload })
    }

    pub fn durable_output_batch_len(&self) -> usize {
        self.durable_output_batch.len()
    }

    pub fn durable_output_batch_due(&self, generation: u64) -> bool {
        self.durable_output_batch_armed && self.durable_output_batch_gen == generation
    }

    pub fn flush_durable_output_batch(&mut self) -> Option<DurableOutputBatch> {
        if self.durable_output_batch.is_empty() {
            self.durable_output_batch_armed = false;
            return None;
        }
        self.durable_output_batch_gen = self.durable_output_batch_gen.wrapping_add(1);
        self.durable_output_batch_armed = false;
        let data = std::mem::take(&mut self.durable_output_batch);
        let sequence = self.durable_output_batch_sequence;
        self.durable_output_batch_sequence = self.durable_output_batch_sequence.wrapping_add(1);
        Some(DurableOutputBatch { data, sequence })
    }

    /// Mark the session as exited. Returns the `exit` event payload to broadcast,
    /// or `None` if the session had already exited.
    pub fn handle_exit(&mut self, exit_code: i32) -> Option<Value> {
        if !self.running {
            return None;
        }
        self.running = false;
        self.exit_code = Some(exit_code);
        self.ended_at = Some(Utc::now());
        Some(json!({ "sessionId": self.id, "exitCode": exit_code }))
    }

    pub fn error_payload(&self, message: &str) -> Value {
        json!({ "sessionId": self.id, "error": message })
    }

    pub fn attachment_payload(&self, created: bool) -> Value {
        json!({
            "sessionId": self.id,
            "created": created,
            "running": self.running,
            "exitCode": self.exit_code,
            "snapshotBase64": encode_bytes(&self.buffer.to_bytes()),
        })
    }

    pub fn snapshot_payload(&self) -> Value {
        json!({
            "sessionId": self.id,
            "snapshotBase64": encode_bytes(&self.buffer.to_bytes()),
        })
    }

    /// Terminate the session: kill the child, release the PTY, and either delete
    /// or finalize the checkpoint.
    pub async fn terminate(&mut self, remove_history: bool, store: &TerminalHostHistoryStore) {
        self.terminated = true;
        self.running = false;
        if let Some(mut killer) = self.killer.take() {
            // The child may have already exited between checks.
            let _ = killer.kill();
        }
        self.input_tx = None;
        self.master = None;
        self.checkpoint_armed = false;
        self.output_batch.clear();
        self.output_batch_armed = false;
        self.output_batch_gen = self.output_batch_gen.wrapping_add(1);
        self.durable_output_batch.clear();
        self.durable_output_batch_armed = false;
        self.durable_output_batch_gen = self.durable_output_batch_gen.wrapping_add(1);
        if remove_history {
            let _ = store.delete(&self.id).await;
        } else {
            let ended = self.ended_at.unwrap_or_else(Utc::now);
            let _ = self.write_checkpoint(store, Some(ended)).await;
        }
    }

    /// Arm a debounced checkpoint timer if one is not already pending. Returns
    /// the generation to fire the timer with, or `None` if already armed.
    pub fn arm_checkpoint(&mut self) -> Option<u64> {
        if self.checkpoint_armed {
            return None;
        }
        self.checkpoint_armed = true;
        Some(self.checkpoint_gen)
    }

    /// Whether a fired debounce timer is still current (not superseded by an
    /// immediate checkpoint). Consumes the armed state when true.
    pub fn checkpoint_due(&mut self, generation: u64) -> bool {
        if self.checkpoint_armed && self.checkpoint_gen == generation {
            self.checkpoint_armed = false;
            true
        } else {
            false
        }
    }

    /// Invalidate any pending debounce timer (used before an immediate write).
    pub fn invalidate_checkpoint(&mut self) {
        self.checkpoint_gen = self.checkpoint_gen.wrapping_add(1);
        self.checkpoint_armed = false;
    }

    /// Persist the current session state.
    pub async fn write_checkpoint(
        &mut self,
        store: &TerminalHostHistoryStore,
        ended_at_override: Option<DateTime<Utc>>,
    ) -> HostResult<()> {
        if let Some(ended_at) = ended_at_override {
            self.ended_at = Some(ended_at);
        }
        let checkpoint = TerminalHostCheckpoint {
            session_id: self.id.clone(),
            workspace_id: self.workspace_id.clone(),
            tab_id: self.tab_id.clone(),
            working_directory: self.working_directory.clone(),
            running: self.running,
            exit_code: self.exit_code,
            ended_at: self.ended_at,
            updated_at: Utc::now(),
            buffer: Vec::new(),
        };
        store
            .upsert(checkpoint)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
}

/// Read the PTY on a dedicated thread, forwarding output and the final exit code
/// through `on_event`.
fn spawn_reader(
    mut reader: Box<dyn Read + Send>,
    mut child: Box<dyn portable_pty::Child + Send + Sync>,
    on_event: Arc<dyn Fn(PtyEvent) + Send + Sync>,
) {
    std::thread::Builder::new()
        .name("alera-pty-reader".to_string())
        .spawn(move || {
            let mut buffer = vec![0u8; READ_CHUNK_BYTES];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(read) => on_event(PtyEvent::Output(buffer[..read].to_vec())),
                    Err(error) => {
                        let code = child
                            .try_wait()
                            .ok()
                            .flatten()
                            .map(|status| status.exit_code() as i32)
                            .unwrap_or(-1);
                        on_event(PtyEvent::Error(error.to_string()));
                        on_event(PtyEvent::Exit(code));
                        return;
                    }
                }
            }
            let code = child
                .wait()
                .map(|status| status.exit_code() as i32)
                .unwrap_or(-1);
            on_event(PtyEvent::Exit(code));
        })
        .expect("failed to spawn pty reader thread");
}

fn spawn_writer(
    mut writer: Box<dyn Write + Send>,
    input_rx: std::sync::mpsc::Receiver<PtyWrite>,
    on_event: Arc<dyn Fn(PtyEvent) + Send + Sync>,
) {
    std::thread::Builder::new()
        .name("alera-pty-writer".to_string())
        .spawn(move || {
            let mut writer_failure: Option<String> = None;
            while let Ok(request) = input_rx.recv() {
                let error = match writer_failure.as_ref() {
                    Some(message) => Some(message.clone()),
                    None => writer
                        .write_all(&request.bytes)
                        .and_then(|_| writer.flush())
                        .err()
                        .map(|error| error.to_string()),
                };
                if writer_failure.is_none() {
                    writer_failure.clone_from(&error);
                }
                on_event(PtyEvent::InputWritten {
                    completion: request.completion,
                    error,
                });
            }
        })
        .expect("failed to spawn PTY writer thread");
}

#[cfg(test)]
mod tests {
    use super::*;

    struct BlockingWriter {
        started_tx: std::sync::mpsc::Sender<()>,
        release_rx: std::sync::mpsc::Receiver<()>,
    }

    impl Write for BlockingWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.started_tx.send(()).unwrap();
            self.release_rx.recv().unwrap();
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    struct FailingWriter;

    impl Write for FailingWriter {
        fn write(&mut self, _bytes: &[u8]) -> std::io::Result<usize> {
            Err(std::io::Error::other("writer failed"))
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    fn test_session() -> Session {
        Session {
            instance_id: next_session_instance_id(),
            id: "session-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            working_directory: "/repo".to_string(),
            clients: HashSet::new(),
            output_paused_clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(1024, &[]),
            running: true,
            exit_code: None,
            ended_at: None,
            master: None,
            input_tx: None,
            killer: None,
            terminated: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
            output_batch: Vec::new(),
            output_batch_gen: 0,
            output_batch_armed: false,
            durable_output_batch: Vec::new(),
            durable_output_batch_gen: 0,
            durable_output_batch_armed: false,
            durable_output_batch_sequence: 0,
        }
    }

    #[test]
    fn output_batch_coalesces_until_flush() {
        let mut session = test_session();

        assert_eq!(session.append_output(b"ab"), (Some(0), Some(0)));
        assert_eq!(session.append_output(b"cd"), (None, None));
        assert!(session.output_batch_due(0));

        let batch = session.flush_output_batch().expect("batch");

        assert_eq!(batch.payload["sessionId"], "session-1");
        assert_eq!(
            batch.payload["dataBase64"],
            serde_json::Value::String(encode_bytes(b"abcd"))
        );
        assert_eq!(session.output_batch_len(), 0);
        assert!(!session.output_batch_due(0));

        let durable = session.flush_durable_output_batch().expect("durable batch");
        assert_eq!(durable.data, b"abcd");
        assert_eq!(durable.sequence, 0);
    }

    #[test]
    fn output_batch_empty_flush_disarms_timer() {
        let mut session = test_session();

        assert_eq!(session.append_output(b"a"), (Some(0), Some(0)));
        assert!(session.flush_output_batch().is_some());
        assert!(session.flush_output_batch().is_none());

        assert_eq!(session.append_output(b"b"), (Some(1), None));
        assert!(!session.output_batch_due(0));
        assert!(session.output_batch_due(1));
        assert!(session.flush_output_batch().is_some());
        let durable = session.flush_durable_output_batch().expect("durable batch");
        assert_eq!(durable.data, b"ab");
        assert_eq!(durable.sequence, 0);
    }

    #[test]
    fn blocked_writer_applies_local_backpressure_without_blocking_sender() {
        let (input_tx, input_rx) = sync_channel(1);
        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let (event_tx, event_rx) = std::sync::mpsc::channel();
        let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(move |event| {
            event_tx.send(event).unwrap();
        });
        spawn_writer(
            Box::new(BlockingWriter {
                started_tx,
                release_rx,
            }),
            input_rx,
            on_event,
        );

        input_tx
            .try_send(PtyWrite {
                completion: PtyWriteCompletion::ClientRequest {
                    client_id: 1,
                    request_id: 10,
                },
                bytes: b"first".to_vec(),
            })
            .unwrap();
        started_rx
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap();
        input_tx
            .try_send(PtyWrite {
                completion: PtyWriteCompletion::ClientRequest {
                    client_id: 1,
                    request_id: 11,
                },
                bytes: b"second".to_vec(),
            })
            .unwrap();
        let full = input_tx.try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 12,
            },
            bytes: b"third".to_vec(),
        });
        assert!(matches!(full, Err(TrySendError::Full(_))));

        release_tx.send(()).unwrap();
        assert!(matches!(
            event_rx
                .recv_timeout(std::time::Duration::from_secs(1))
                .unwrap(),
            PtyEvent::InputWritten {
                completion: PtyWriteCompletion::ClientRequest { request_id: 10, .. },
                error: None,
            }
        ));
        started_rx
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap();
        release_tx.send(()).unwrap();
        assert!(matches!(
            event_rx
                .recv_timeout(std::time::Duration::from_secs(1))
                .unwrap(),
            PtyEvent::InputWritten {
                completion: PtyWriteCompletion::ClientRequest { request_id: 11, .. },
                error: None,
            }
        ));
    }

    #[test]
    fn failed_writer_completes_every_queued_request_with_the_same_error() {
        let (input_tx, input_rx) = sync_channel(3);
        for request_id in 10..13 {
            input_tx
                .try_send(PtyWrite {
                    completion: PtyWriteCompletion::ClientRequest {
                        client_id: 1,
                        request_id,
                    },
                    bytes: vec![request_id as u8],
                })
                .unwrap();
        }
        let (event_tx, event_rx) = std::sync::mpsc::channel();
        let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(move |event| {
            event_tx.send(event).unwrap();
        });

        spawn_writer(Box::new(FailingWriter), input_rx, on_event);

        for request_id in 10..13 {
            assert!(matches!(
                event_rx
                    .recv_timeout(std::time::Duration::from_secs(1))
                    .unwrap(),
                PtyEvent::InputWritten {
                    completion: PtyWriteCompletion::ClientRequest {
                        request_id: actual,
                        ..
                    },
                    error: Some(ref message),
                } if actual == request_id && message == "writer failed"
            ));
        }
    }

    #[test]
    fn exited_session_rejects_input_instead_of_leaving_request_pending() {
        let mut session = test_session();
        session.running = false;

        let error = session
            .queue_write(
                PtyWriteCompletion::ClientRequest {
                    client_id: 1,
                    request_id: 10,
                },
                b"input",
            )
            .expect_err("exited session should reject input");

        assert!(error.wire_message().contains("not running"));
    }
}
