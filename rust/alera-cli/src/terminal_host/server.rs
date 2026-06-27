use std::collections::HashMap;
use std::net::Ipv4Addr;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::Result;
use serde_json::Value;
use tokio::net::TcpListener;
use tokio::sync::mpsc::{self, UnboundedSender};
use tokio::task::JoinHandle;

use crate::terminal_host::client::{connection_loop, ClientHandle};
use crate::terminal_host::control_file;
use crate::terminal_host::history_store::TerminalHostHistoryStore;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{event, TerminalHostConfig};
use crate::terminal_host::session::{PtyEvent, Session};

mod requests;

/// Delay before a debounced checkpoint write fires.
const CHECKPOINT_DELAY: Duration = Duration::from_secs(5);

const OUTPUT_BATCH_DELAY: Duration = Duration::from_millis(8);
const OUTPUT_BATCH_MAX_BYTES: usize = 64 * 1024;

/// Messages processed serially by the single server actor. Every state mutation
/// happens here, which keeps session/client transitions deterministic.
pub enum ServerCommand {
    ClientConnected { id: u64, handle: ClientHandle },
    ClientLine { id: u64, line: String },
    ClientDisconnected { id: u64 },
    Pty { session_id: String, event: PtyEvent },
    OutputBatchTick { session_id: String, generation: u64 },
    CheckpointTick { session_id: String, generation: u64 },
    ShutdownTick { generation: u64 },
}

struct ClientState {
    handle: ClientHandle,
    authenticated: bool,
}

/// Run the persistent terminal host until it shuts down (idle timeout or the
/// last session terminating). Binds a loopback socket, publishes the control
/// file, and serves clients.
pub async fn run_terminal_host_server(
    runtime_dir: PathBuf,
    control_file_path: PathBuf,
    token: String,
    config: TerminalHostConfig,
) -> Result<()> {
    if !runtime_dir.exists() {
        std::fs::create_dir_all(&runtime_dir)?;
    }
    let store = TerminalHostHistoryStore::open(&runtime_dir).await?;
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    control_file::write_control_file(&control_file_path, port, &token)?;

    let (inbox, mut rx) = mpsc::unbounded_channel::<ServerCommand>();
    spawn_accept_loop(listener, inbox.clone());

    let mut actor = ServerActor {
        control_file_path,
        token,
        config,
        store,
        sessions: HashMap::new(),
        clients: HashMap::new(),
        pending_output_writes: HashMap::new(),
        inbox,
        shutdown_gen: 0,
        disposed: false,
    };
    actor.schedule_shutdown_if_idle();

    while let Some(command) = rx.recv().await {
        actor.handle(command).await;
        if actor.disposed {
            break;
        }
    }
    Ok(())
}

fn spawn_accept_loop(listener: TcpListener, inbox: UnboundedSender<ServerCommand>) {
    tokio::spawn(async move {
        let mut next_id: u64 = 1;
        while let Ok((stream, _)) = listener.accept().await {
            let _ = stream.set_nodelay(true);
            let id = next_id;
            next_id += 1;
            let (out_tx, out_rx) = mpsc::unbounded_channel::<Value>();
            // Register the client before its lines can arrive: the
            // ClientConnected command is enqueued before the connection loop
            // (and thus any ClientLine) starts.
            if inbox
                .send(ServerCommand::ClientConnected {
                    id,
                    handle: ClientHandle { out: out_tx },
                })
                .is_err()
            {
                break;
            }
            tokio::spawn(connection_loop(stream, id, inbox.clone(), out_rx));
        }
    });
}

struct ServerActor {
    control_file_path: PathBuf,
    token: String,
    config: TerminalHostConfig,
    store: TerminalHostHistoryStore,
    sessions: HashMap<String, Session>,
    clients: HashMap<u64, ClientState>,
    pending_output_writes: HashMap<String, Vec<JoinHandle<()>>>,
    inbox: UnboundedSender<ServerCommand>,
    shutdown_gen: u64,
    disposed: bool,
}

impl ServerActor {
    async fn handle(&mut self, command: ServerCommand) {
        match command {
            ServerCommand::ClientConnected { id, handle } => {
                self.clients.insert(
                    id,
                    ClientState {
                        handle,
                        authenticated: false,
                    },
                );
            }
            ServerCommand::ClientLine { id, line } => self.handle_line(id, line).await,
            ServerCommand::ClientDisconnected { id } => self.dispose_client(id).await,
            ServerCommand::Pty { session_id, event } => {
                self.handle_pty_event(session_id, event).await
            }
            ServerCommand::OutputBatchTick {
                session_id,
                generation,
            } => self.handle_output_batch_tick(session_id, generation),
            ServerCommand::CheckpointTick {
                session_id,
                generation,
            } => self.handle_checkpoint_tick(session_id, generation).await,
            ServerCommand::ShutdownTick { generation } => {
                self.handle_shutdown_tick(generation).await
            }
        }
    }

    // --- PTY and checkpoint events ---------------------------------------

    async fn handle_pty_event(&mut self, session_id: String, pty_event: PtyEvent) {
        match pty_event {
            PtyEvent::Output(data) => {
                let state = self.sessions.get_mut(&session_id).map(|session| {
                    let output_generation = session.append_output(&data);
                    let output_len = session.output_batch_len();
                    let checkpoint_generation = session.arm_checkpoint();
                    (output_generation, output_len, checkpoint_generation)
                });
                if let Some((output_generation, output_len, checkpoint_generation)) = state {
                    if let Some(generation) = output_generation {
                        self.spawn_output_batch_timer(session_id.clone(), generation);
                    }
                    if output_len >= OUTPUT_BATCH_MAX_BYTES {
                        self.flush_output_batch(&session_id);
                    }
                    if let Some(generation) = checkpoint_generation {
                        self.spawn_checkpoint_timer(session_id, generation);
                    }
                }
            }
            PtyEvent::Error(message) => {
                self.flush_output_batch(&session_id);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    let payload = session.error_payload(&message);
                    let clients: Vec<u64> = session.clients.iter().copied().collect();
                    self.broadcast(&clients, event("error", payload));
                }
            }
            PtyEvent::Exit(code) => self.handle_session_exit(session_id, code).await,
        }
    }

    async fn handle_session_exit(&mut self, session_id: String, exit_code: i32) {
        self.flush_output_batch(&session_id);
        let broadcast = self.sessions.get_mut(&session_id).and_then(|session| {
            let payload = session.handle_exit(exit_code)?;
            let clients: Vec<u64> = session.clients.iter().copied().collect();
            Some((event("exit", payload), clients))
        });
        let Some((frame, clients)) = broadcast else {
            return;
        };
        self.broadcast(&clients, frame);
        self.immediate_checkpoint(&session_id).await;
        self.schedule_shutdown_if_idle();
    }

    fn handle_output_batch_tick(&mut self, session_id: String, generation: u64) {
        let due = self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.output_batch_due(generation));
        if due {
            self.flush_output_batch(&session_id);
        }
    }

    fn flush_output_batch(&mut self, session_id: &str) {
        let broadcast = self.sessions.get_mut(session_id).and_then(|session| {
            let batch = session.flush_output_batch()?;
            let clients = session.output_clients();
            Some((
                event("output", batch.payload),
                batch.sequence,
                batch.data,
                clients,
            ))
        });
        if let Some((frame, sequence, data, clients)) = broadcast {
            self.broadcast(&clients, frame);
            self.persist_output_batch(session_id.to_string(), sequence, data);
        }
    }

    async fn handle_checkpoint_tick(&mut self, session_id: String, generation: u64) {
        let store = self.store.clone();
        let due = self
            .sessions
            .get_mut(&session_id)
            .is_some_and(|session| session.checkpoint_due(generation));
        if due {
            self.await_output_writes(&session_id).await;
            if let Some(session) = self.sessions.get_mut(&session_id) {
                let _ = session.write_checkpoint(&store, None).await;
            }
            let _ = store
                .trim_session(&session_id, self.config.scrollback_bytes as usize)
                .await;
        }
    }

    async fn immediate_checkpoint(&mut self, session_id: &str) {
        let store = self.store.clone();
        self.await_output_writes(session_id).await;
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.invalidate_checkpoint();
            let _ = session.write_checkpoint(&store, None).await;
            let _ = store
                .trim_session(session_id, self.config.scrollback_bytes as usize)
                .await;
        }
    }

    fn persist_output_batch(&mut self, session_id: String, sequence: i64, data: Vec<u8>) {
        let store = self.store.clone();
        let task_session_id = session_id.clone();
        let handle = tokio::spawn(async move {
            let _ = store.append_output(&task_session_id, sequence, &data).await;
        });
        self.pending_output_writes
            .entry(session_id)
            .or_default()
            .push(handle);
    }

    async fn await_output_writes(&mut self, session_id: &str) {
        let Some(handles) = self.pending_output_writes.remove(session_id) else {
            return;
        };
        for handle in handles {
            let _ = handle.await;
        }
    }

    fn spawn_checkpoint_timer(&self, session_id: String, generation: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(CHECKPOINT_DELAY).await;
            let _ = inbox.send(ServerCommand::CheckpointTick {
                session_id,
                generation,
            });
        });
    }

    // --- Client lifecycle -------------------------------------------------

    async fn dispose_client(&mut self, client_id: u64) {
        if !self.clients.contains_key(&client_id) {
            return;
        }
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.flush_output_batch(&session_id);
            if let Some(session) = self.sessions.get_mut(&session_id) {
                session.detach(client_id);
            }
            self.immediate_checkpoint(&session_id).await;
        }
        // Dropping the handle ends the connection loop and closes the socket.
        self.clients.remove(&client_id);
        self.schedule_shutdown_if_idle();
    }

    fn client_write(&self, client_id: u64, message: Value) {
        if let Some(client) = self.clients.get(&client_id) {
            let _ = client.handle.out.send(message);
        }
    }

    fn broadcast(&self, client_ids: &[u64], message: Value) {
        for id in client_ids {
            if let Some(client) = self.clients.get(id) {
                let _ = client.handle.out.send(message.clone());
            }
        }
    }

    fn require_auth(&self, client_id: u64) -> HostResult<()> {
        match self.clients.get(&client_id) {
            Some(client) if client.authenticated => Ok(()),
            _ => Err(HostError::state(
                "Terminal host client is not authenticated.",
            )),
        }
    }

    fn require_session(&self, payload: &Value) -> HostResult<String> {
        let session_id = match payload.get("sessionId") {
            Some(Value::String(value)) => value.clone(),
            _ => return Err(HostError::format("Terminal session id is required.")),
        };
        if !self.sessions.contains_key(&session_id) {
            return Err(HostError::state(format!(
                "Terminal session is not attached: {session_id}"
            )));
        }
        Ok(session_id)
    }

    // --- Configuration and shutdown --------------------------------------

    async fn apply_config(&mut self, config: TerminalHostConfig) {
        self.config = config;
        let max_bytes = config.scrollback_bytes as usize;
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.flush_output_batch(&session_id);
            if let Some(session) = self.sessions.get_mut(&session_id) {
                session.set_max_bytes(max_bytes);
            }
            self.await_output_writes(&session_id).await;
            let _ = self.store.trim_session(&session_id, max_bytes).await;
            self.immediate_checkpoint(&session_id).await;
        }
        self.schedule_shutdown_if_idle();
    }

    fn has_authenticated_clients(&self) -> bool {
        self.clients.values().any(|client| client.authenticated)
    }

    fn has_running_sessions(&self) -> bool {
        self.sessions.values().any(Session::running)
    }

    fn schedule_shutdown_if_idle(&mut self) {
        if self.disposed || self.has_authenticated_clients() {
            self.cancel_shutdown_timer();
            return;
        }
        let seconds = if self.has_running_sessions() {
            self.config.detached_session_shutdown_delay_seconds
        } else {
            self.config.empty_shutdown_delay_seconds
        };
        self.shutdown_gen += 1;
        let generation = self.shutdown_gen;
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(seconds)).await;
            let _ = inbox.send(ServerCommand::ShutdownTick { generation });
        });
    }

    fn spawn_output_batch_timer(&self, session_id: String, generation: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(OUTPUT_BATCH_DELAY).await;
            let _ = inbox.send(ServerCommand::OutputBatchTick {
                session_id,
                generation,
            });
        });
    }

    fn cancel_shutdown_timer(&mut self) {
        // Bumping the generation invalidates any pending ShutdownTick.
        self.shutdown_gen += 1;
    }

    async fn handle_shutdown_tick(&mut self, generation: u64) {
        if generation == self.shutdown_gen && !self.disposed && !self.has_authenticated_clients() {
            self.dispose().await;
        }
    }

    async fn dispose(&mut self) {
        if self.disposed {
            return;
        }
        self.disposed = true;
        self.cancel_shutdown_timer();
        // Closing client handles ends their connection loops.
        self.clients.clear();
        let store = self.store.clone();
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.flush_output_batch(&session_id);
            self.await_output_writes(&session_id).await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                session.terminate(false, &store).await;
            }
        }
        control_file::delete_control_file(&self.control_file_path);
    }
}
