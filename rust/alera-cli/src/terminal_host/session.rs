use std::collections::{HashMap, HashSet};
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::{sync_channel, SyncSender};
use std::sync::Arc;

use chrono::{DateTime, Utc};
use portable_pty::{ChildKiller, MasterPty, PtySize};
use serde_json::{json, Value};

use crate::terminal_host::buffer::ScrollbackBuffer;
use crate::terminal_host::history_store::{TerminalHostCheckpoint, TerminalHostHistoryStore};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{encode_bytes, TerminalHostLaunch};
use crate::terminal_host::resources::ShellProcess;

#[cfg(test)]
use crate::terminal_host::resources::seal_shell_process;

mod checkpoint_restore;
#[cfg(test)]
mod driver_test_stub;
mod input_queue;
mod instance_state;
mod io_threads;
mod output_backpressure;
mod output_batching;
mod pty_spawn;
#[cfg(unix)]
mod shell_tree_termination;
#[cfg(test)]
mod tests;
mod title_tracker;
#[cfg(windows)]
mod windows_process_job;

#[cfg(test)]
use input_queue::PtyDeferredWrite;
use input_queue::PtyWrite;
use instance_state::next_session_instance_id;
use io_threads::{spawn_reader, spawn_writer};
use pty_spawn::{spawn_pty, SpawnedPty};
#[cfg(unix)]
use shell_tree_termination::kill_shell_tree;
use title_tracker::TerminalTitleTracker;
#[cfg(windows)]
use windows_process_job::WindowsProcessJob;

const INPUT_QUEUE_CAPACITY: usize = 64;

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
    TerminalPulse {
        session_instance_id: u64,
        active: Arc<AtomicBool>,
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
    /// Guards against re-delivery after this PTY accepts its after-ready prompt.
    pub(super) initial_agent_prompt_delivered: bool,
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
    #[cfg(windows)]
    process_job: Option<WindowsProcessJob>,
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
            #[cfg(windows)]
            process_job,
            shell,
        } = spawned;
        let (input_tx, input_rx) = sync_channel(INPUT_QUEUE_CAPACITY);
        let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(on_event);

        let mut title_tracker = TerminalTitleTracker::default();
        title_tracker.feed(initial_scrollback);
        let mut session = Session {
            instance_id: next_session_instance_id(),
            initial_agent_prompt_delivered: false,
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
            #[cfg(windows)]
            process_job: Some(process_job),
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
        #[cfg(windows)]
        {
            self.process_job = None;
        }
        Some(json!({ "sessionId": self.id, "exitCode": exit_code }))
    }

    #[cfg(windows)]
    pub fn close_pty_after_child_exit(&mut self) {
        // Closing the job here catches descendants that outlived the shell;
        // waiting for the user to remove the exited tab would leak them.
        self.process_job = None;
        self.input_tx = None;
        self.master = None;
        self.killer = None;
    }

    pub fn error_payload(&self, message: &str) -> Value {
        json!({ "sessionId": self.id, "error": message })
    }

    pub fn attachment_payload(&self, created: bool, restore_bytes: usize) -> Value {
        let (cols, rows) = self.current_dims;
        json!({
            "sessionId": self.id,
            "created": created,
            "running": self.running,
            "exitCode": self.exit_code,
            "driver": self.driver.payload(),
            "snapshotBase64": encode_bytes(&self.buffer.tail(restore_bytes)),
            // The size the snapshot bytes were written at. A client whose own
            // viewport is narrower has to replay them here and then resize,
            // letting its emulator reflow wrapped lines, because re-parsing the
            // stream at another width lands every absolute cursor move and hard
            // wrap in the wrong column. Additive: a client that ignores these
            // behaves exactly as it does today.
            "snapshotCols": cols,
            "snapshotRows": rows,
        })
    }

    /// What a client that lost its place should replay, capped so a resync does
    /// not hand it more history than its emulator will keep.
    pub fn restore_payload(&self, restore_bytes: usize) -> Value {
        let (cols, rows) = self.current_dims;
        json!({
            "sessionId": self.id,
            "snapshotBase64": encode_bytes(&self.buffer.tail(restore_bytes)),
            "resetInteractionModes": true,
            "snapshotCols": cols,
            "snapshotRows": rows,
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
        #[cfg(unix)]
        // Read before clearing. The sweep needs the sealed shell to prove which
        // tree it is allowed to signal, and it has to run before the root is
        // killed: a dead root's children reparent away and stop being findable.
        let shell = self.shell.take();
        #[cfg(windows)]
        {
            self.shell = None;
        }
        #[cfg(windows)]
        {
            // KILL_ON_JOB_CLOSE terminates the shell and every associated
            // descendant, including processes that detached from the console.
            self.process_job = None;
        }
        #[cfg(unix)]
        if let Some(mut killer) = self.killer.take() {
            kill_shell_tree(shell, move || {
                // The child may have already exited between checks.
                let _ = killer.kill();
            })
            .await;
        }
        #[cfg(windows)]
        if let Some(mut killer) = self.killer.take() {
            // The job normally killed the root already. Keep the PTY's direct
            // killer as a best-effort fallback if Windows raced job teardown.
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
