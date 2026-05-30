use std::collections::HashSet;
use std::io::{Read, Write};

use chrono::{DateTime, Utc};
use portable_pty::{native_pty_system, ChildKiller, CommandBuilder, MasterPty, PtySize};
use serde_json::{json, Value};

use crate::terminal_host::buffer::ScrollbackBuffer;
use crate::terminal_host::history_store::{TerminalHostCheckpoint, TerminalHostHistoryStore};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{encode_bytes, TerminalHostLaunch};

/// Bytes read from the PTY per `read` call, matching the Dart host.
const READ_CHUNK_BYTES: usize = 8192;

/// A message produced by a session's PTY reader thread.
#[derive(Debug)]
pub enum PtyEvent {
    Output(Vec<u8>),
    Exit(i32),
    Error(String),
}

/// A hosted terminal session. Port of the Dart `_TerminalHostSession`. The PTY
/// is read on a dedicated OS thread (mirroring the Dart reader isolate); all
/// other state transitions are driven by the single server actor that owns this
/// struct, so no internal locking is required.
pub struct Session {
    pub id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub working_directory: String,
    pub clients: HashSet<u64>,
    buffer: ScrollbackBuffer,
    running: bool,
    exit_code: Option<i32>,
    ended_at: Option<DateTime<Utc>>,
    master: Option<Box<dyn MasterPty + Send>>,
    writer: Option<Box<dyn std::io::Write + Send>>,
    killer: Option<Box<dyn ChildKiller + Send + Sync>>,
    terminated: bool,
    checkpoint_gen: u64,
    checkpoint_armed: bool,
}

impl Session {
    /// Spawn a fresh shell PTY, persist an initial checkpoint, and start the
    /// reader thread. Port of `_TerminalHostSession.start`.
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
        store: &TerminalHostHistoryStore,
        on_event: impl Fn(PtyEvent) + Send + 'static,
    ) -> HostResult<Session> {
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
        // The Dart host always passes a (possibly empty) environment map, which
        // makes the underlying portable_pty clear the inherited environment and
        // apply only the provided entries. Replicate that exactly.
        command.env_clear();
        for (key, value) in &launch.environment {
            command.env(key, value);
        }
        // The working directory is intentionally not applied to the child: the
        // Dart host persists it but never sets it as the PTY cwd, so the child
        // inherits this process's directory. Kept 1:1 on purpose.

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

        let mut session = Session {
            id,
            workspace_id,
            tab_id,
            working_directory,
            clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(max_bytes, &[]),
            running: true,
            exit_code: None,
            ended_at: None,
            master: Some(pair.master),
            writer: Some(writer),
            killer: Some(killer),
            terminated: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
        };
        session.write_checkpoint(store, None).await?;
        spawn_reader(reader, child, on_event);
        Ok(session)
    }

    /// Rebuild a non-running session from a persisted checkpoint, or `None` if
    /// there is no usable checkpoint. Port of `_TerminalHostSession.restoreExited`.
    pub async fn restore_exited(
        session_id: String,
        workspace_id: String,
        tab_id: String,
        store: &TerminalHostHistoryStore,
        max_bytes: usize,
    ) -> Option<Session> {
        let checkpoint = match store.read(&session_id).await {
            Ok(Some(checkpoint)) => checkpoint,
            _ => return None,
        };
        let (exit_code, ended_at) = if checkpoint.ended_at.is_none() {
            (Some(-1), None)
        } else {
            (Some(checkpoint.exit_code.unwrap_or(0)), checkpoint.ended_at)
        };
        Some(Session {
            id: session_id,
            workspace_id,
            tab_id,
            working_directory: checkpoint.working_directory,
            clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(max_bytes, &checkpoint.buffer),
            running: false,
            exit_code,
            ended_at,
            master: None,
            writer: None,
            killer: None,
            terminated: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
        })
    }

    pub fn running(&self) -> bool {
        self.running
    }

    pub fn set_max_bytes(&mut self, max_bytes: usize) {
        self.buffer.set_max_bytes(max_bytes);
    }

    pub fn attach(&mut self, client_id: u64) {
        self.clients.insert(client_id);
    }

    pub fn detach(&mut self, client_id: u64) {
        self.clients.remove(&client_id);
    }

    /// Write input to the PTY. No-op when the session is not running, matching
    /// the Dart `write`.
    pub fn write(&mut self, bytes: &[u8]) {
        if bytes.is_empty() || !self.running {
            return;
        }
        if let Some(writer) = self.writer.as_mut() {
            let _ = writer.write_all(bytes);
            let _ = writer.flush();
        }
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

    /// Append PTY output to the scrollback. Returns the `output` event payload
    /// the caller should broadcast.
    pub fn append_output(&mut self, data: &[u8]) -> Value {
        self.buffer.append(data);
        json!({ "sessionId": self.id, "dataBase64": encode_bytes(data) })
    }

    /// Mark the session as exited. Returns the `exit` event payload to broadcast,
    /// or `None` if the session had already exited. Port of `_handleExit`.
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

    /// Terminate the session: kill the child, release the PTY, and either delete
    /// or finalize the checkpoint. Port of `_TerminalHostSession.terminate`.
    pub async fn terminate(&mut self, remove_history: bool, store: &TerminalHostHistoryStore) {
        self.terminated = true;
        self.running = false;
        if let Some(mut killer) = self.killer.take() {
            // The child may have already exited between checks.
            let _ = killer.kill();
        }
        self.writer = None;
        self.master = None;
        self.checkpoint_armed = false;
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

    /// Persist the current session state. Port of `_writeCheckpoint`.
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
            buffer: self.buffer.to_bytes(),
        };
        store
            .upsert(checkpoint)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
}

/// Read the PTY on a dedicated thread, forwarding output and the final exit code
/// through `on_event`. Mirrors the Dart `_terminalHostPtyReader` isolate.
fn spawn_reader(
    mut reader: Box<dyn Read + Send>,
    mut child: Box<dyn portable_pty::Child + Send + Sync>,
    on_event: impl Fn(PtyEvent) + Send + 'static,
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
