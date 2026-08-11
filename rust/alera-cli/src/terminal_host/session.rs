use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{sync_channel, SyncSender};
use std::sync::Arc;

use chrono::{DateTime, Utc};
use portable_pty::{native_pty_system, Child, ChildKiller, CommandBuilder, MasterPty, PtySize};
use serde_json::{json, Value};

use crate::terminal_host::buffer::ScrollbackBuffer;
use crate::terminal_host::history_store::{TerminalHostCheckpoint, TerminalHostHistoryStore};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{encode_bytes, TerminalHostLaunch};
use crate::terminal_host::resources::{seal_shell_process, ShellProcess};

mod checkpoint_restore;
#[cfg(test)]
mod driver_test_stub;
mod input_queue;
mod io_threads;
mod output_backpressure;
mod output_batching;
mod shell_tree_termination;
#[cfg(test)]
mod tests;
mod title_tracker;

#[cfg(test)]
use input_queue::PtyDeferredWrite;
use input_queue::PtyWrite;
use io_threads::{spawn_reader, spawn_writer};
use shell_tree_termination::kill_shell_tree;
use title_tracker::TerminalTitleTracker;

const INPUT_QUEUE_CAPACITY: usize = 64;
static NEXT_SESSION_INSTANCE_ID: AtomicU64 = AtomicU64::new(1);

struct SpawnedPty {
    child: Box<dyn Child + Send + Sync>,
    master: Box<dyn MasterPty + Send>,
    reader: Box<dyn std::io::Read + Send>,
    writer: Box<dyn std::io::Write + Send>,
    killer: Box<dyn ChildKiller + Send + Sync>,
    shell: Option<ShellProcess>,
}

fn next_session_instance_id() -> u64 {
    NEXT_SESSION_INSTANCE_ID.fetch_add(1, Ordering::Relaxed)
}

fn resumed_output_stream_bytes(previous: u64, scrollback_len: usize) -> u64 {
    previous.max(scrollback_len as u64)
}

/// A message produced by a session's PTY reader thread.
#[derive(Debug)]
pub enum PtyEvent {
    Output(Vec<u8>),
    #[cfg(windows)]
    ChildExited,
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
        force_submit: bool,
    },
    OrchestrationEnter {
        session_instance_id: u64,
        message_ids: Vec<String>,
    },
    StartupPlain {
        session_instance_id: u64,
    },
    StartupPaste {
        session_instance_id: u64,
    },
    StartupSubmit {
        session_instance_id: u64,
    },
}

/// Raw PTY bytes, not an encoded payload.
///
/// Whether these travel as a binary frame or as base64 inside JSON depends on
/// what each client negotiated, so the encoding decision belongs to the writer
/// and a binary client never pays for base64 at all.
pub struct OutputBatch {
    pub data: Vec<u8>,
}

mod driver;

pub use driver::SessionDriver;

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
    pub driver: SessionDriver,
    /// Last dims a desktop client applied or requested; restored on reclaim
    /// and when the mobile driver releases the session.
    pub desktop_dims: Option<(u16, u16)>,
    /// Dims currently applied to the PTY.
    pub current_dims: (u16, u16),
    output_paused_clients: HashSet<u64>,
    output_resync_pending_clients: HashSet<u64>,
    /// How far into the output stream each client has actually been served.
    ///
    /// It only advances when a frame is accepted by that client's queue, so a
    /// pause or a full queue leaves it where the client really is. That is what
    /// lets a resume send the gap instead of the whole scrollback.
    delivered_output_cursors: HashMap<u64, u64>,
    pub(super) buffer: ScrollbackBuffer,
    running: bool,
    exit_code: Option<i32>,
    ended_at: Option<DateTime<Utc>>,
    /// The shell this session spawned, while it is still alive. Cleared on exit
    /// and on terminate: the OS recycles pids, so a stale value would attribute
    /// an unrelated process to this session.
    ///
    /// Carries the start time observed at spawn, because clearing alone is not
    /// enough. The OS reaps the shell before the reader thread reports the
    /// exit, and a pid recycled inside that window would still read as live.
    shell: Option<ShellProcess>,
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
    output_stream_bytes: u64,
    title_tracker: TerminalTitleTracker,
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
        initial_output_stream_bytes: u64,
        store: &TerminalHostHistoryStore,
        on_event: impl Fn(PtyEvent) + Send + Sync + 'static,
    ) -> HostResult<Session> {
        let durable_output_batch_sequence = store
            .next_output_sequence(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        #[cfg(windows)]
        let spawned = {
            let launch = launch.clone();
            let terminal_handle = id.clone();
            tokio::task::spawn_blocking(move || spawn_pty(launch, terminal_handle, cols, rows))
                .await
                .map_err(|error| HostError::state(format!("PTY setup worker failed: {error}")))??
        };
        #[cfg(not(windows))]
        let spawned = spawn_pty(launch.clone(), id.clone(), cols, rows)?;
        let SpawnedPty {
            child,
            master,
            reader,
            writer,
            killer,
            shell,
        } = spawned;
        let (input_tx, input_rx) = sync_channel(INPUT_QUEUE_CAPACITY);
        let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(on_event);

        let mut title_tracker = TerminalTitleTracker::default();
        title_tracker.feed(initial_scrollback);
        let mut session = Session {
            instance_id: next_session_instance_id(),
            id,
            workspace_id,
            tab_id,
            working_directory,
            clients: HashSet::new(),
            driver: SessionDriver::Idle,
            desktop_dims: None,
            current_dims: (cols, rows),
            output_paused_clients: HashSet::new(),
            output_resync_pending_clients: HashSet::new(),
            delivered_output_cursors: HashMap::new(),
            buffer: ScrollbackBuffer::new(max_bytes, initial_scrollback),
            running: true,
            exit_code: None,
            ended_at: None,
            shell,
            master: Some(master),
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
            output_stream_bytes: resumed_output_stream_bytes(
                initial_output_stream_bytes,
                initial_scrollback.len(),
            ),
            title_tracker,
        };
        session.write_checkpoint(store, None).await?;
        spawn_reader(reader, child, Arc::clone(&on_event));
        spawn_writer(writer, input_rx, on_event);
        Ok(session)
    }

    pub fn running(&self) -> bool {
        self.running
    }

    pub fn workspace_id(&self) -> &str {
        &self.workspace_id
    }

    /// The live shell, or `None` once it has exited or was never spawned
    /// (restored checkpoints and test stubs have no process behind them).
    pub fn shell(&self) -> Option<ShellProcess> {
        self.shell
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
        self.output_resync_pending_clients.remove(&client_id);
        // The attach reply carries the whole buffer, so the client starts
        // caught up with the stream as it stands right now.
        self.delivered_output_cursors
            .insert(client_id, self.output_stream_bytes);
    }

    pub fn attach_for_resync(&mut self, client_id: u64) {
        self.clients.insert(client_id);
        self.delivered_output_cursors.remove(&client_id);
        self.output_paused_clients.insert(client_id);
        self.output_resync_pending_clients.insert(client_id);
    }

    pub fn detach(&mut self, client_id: u64) {
        self.clients.remove(&client_id);
        self.output_paused_clients.remove(&client_id);
        self.output_resync_pending_clients.remove(&client_id);
        self.delivered_output_cursors.remove(&client_id);
    }

    pub fn resize(&mut self, cols: u16, rows: u16) {
        if !self.running {
            return;
        }
        self.current_dims = (cols, rows);
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
    pub fn append_output(&mut self, data: &[u8]) -> (Option<u64>, Option<u64>, Option<String>) {
        self.output_stream_bytes = self.output_stream_bytes.saturating_add(data.len() as u64);
        self.buffer.append(data);
        self.output_batch.extend_from_slice(data);
        self.durable_output_batch.extend_from_slice(data);
        let title_change = self.title_tracker.feed(data);
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
        (output_generation, durable_generation, title_change)
    }

    pub fn runtime_title(&self) -> Option<&str> {
        self.title_tracker.current_title()
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
        self.shell = None;
        Some(json!({ "sessionId": self.id, "exitCode": exit_code }))
    }

    #[cfg(windows)]
    pub fn close_pty_after_child_exit(&mut self) {
        self.input_tx = None;
        self.master = None;
        self.killer = None;
    }

    pub fn error_payload(&self, message: &str) -> Value {
        json!({ "sessionId": self.id, "error": message })
    }

    pub fn attachment_payload(&self, created: bool, restore_bytes: usize) -> Value {
        json!({
            "sessionId": self.id,
            "created": created,
            "running": self.running,
            "exitCode": self.exit_code,
            "driver": self.driver.payload(),
            "snapshotBase64": encode_bytes(&self.buffer.tail(restore_bytes)),
        })
    }

    /// What a client that lost its place should replay, capped so a resync does
    /// not hand it more history than its emulator will keep.
    pub fn restore_payload(&self, restore_bytes: usize) -> Value {
        json!({
            "sessionId": self.id,
            "snapshotBase64": encode_bytes(&self.buffer.tail(restore_bytes)),
            "resetInteractionModes": true,
        })
    }

    pub fn snapshot_payload(&self) -> Value {
        json!({
            "sessionId": self.id,
            "snapshotBase64": encode_bytes(&self.buffer.to_bytes()),
        })
    }

    /// Terminate the session: kill the shell and everything it spawned, release
    /// the PTY, and either delete or finalize the checkpoint.
    pub async fn terminate(&mut self, remove_history: bool, store: &TerminalHostHistoryStore) {
        self.terminated = true;
        self.running = false;
        // Read before clearing. The sweep needs the sealed shell to prove which
        // tree it is allowed to signal, and it has to run before the root is
        // killed: a dead root's children reparent away and stop being findable.
        let shell = self.shell.take();
        if let Some(mut killer) = self.killer.take() {
            kill_shell_tree(shell, move || {
                // The child may have already exited between checks.
                let _ = killer.kill();
            })
            .await;
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
            if let Err(error) = store.delete(&self.id).await {
                tracing::warn!(
                    session_id = %self.id,
                    "failed to remove terminal history: {error}"
                );
            }
        } else {
            let ended = self.ended_at.unwrap_or_else(Utc::now);
            // A dropped final checkpoint is what the user sees as a terminal
            // that came back with its scrollback truncated.
            if let Err(error) = self.write_checkpoint(store, Some(ended)).await {
                tracing::warn!(
                    session_id = %self.id,
                    "failed to write the final terminal checkpoint: {error}"
                );
            }
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
            output_stream_bytes: self.output_stream_bytes,
            updated_at: Utc::now(),
            buffer: Vec::new(),
        };
        store
            .upsert(checkpoint)
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }
}

fn spawn_pty(
    launch: TerminalHostLaunch,
    terminal_handle: String,
    cols: u16,
    rows: u16,
) -> HostResult<SpawnedPty> {
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
    // Session launch environments are explicit so terminals do not inherit
    // stale variables from the long-running host process.
    command.env_clear();
    for (key, value) in &launch.environment {
        command.env(key, value);
    }
    // Agents inside this PTY use the session id as their orchestration identity.
    command.env("ALERA_TERMINAL_HANDLE", terminal_handle);
    let child = pair
        .slave
        .spawn_command(command)
        .map_err(|error| HostError::state(error.to_string()))?;
    // The master must be the only remaining PTY endpoint owned by the host.
    drop(pair.slave);
    let killer = child.clone_killer();
    // Capture identity before the reader owns the child so resource samples can
    // prove that a later PID still belongs to this shell process.
    let shell = child.process_id().and_then(seal_shell_process);
    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|error| HostError::state(error.to_string()))?;
    let writer = pair
        .master
        .take_writer()
        .map_err(|error| HostError::state(error.to_string()))?;
    Ok(SpawnedPty {
        child,
        master: pair.master,
        reader,
        writer,
        killer,
        shell,
    })
}
