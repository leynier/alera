use std::collections::HashMap;
use std::net::Ipv4Addr;
use std::path::PathBuf;
use std::time::Duration;

use alera_core::runtime::{RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget};
use anyhow::Result;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::sync::mpsc::{self, UnboundedSender};
use tokio::task::JoinHandle;

use crate::ssh_bootstrap::{
    cancel_ssh_bootstrap, mark_ssh_bootstrap_installing, new_bootstrap_job_id, run_ssh_bootstrap,
    SshTargetBootstrapJob, SshTargetBootstrapProgress, SshTargetBootstrapRequest,
};
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
    ClientConnected {
        id: u64,
        handle: ClientHandle,
    },
    ClientLine {
        id: u64,
        line: String,
    },
    ClientDisconnected {
        id: u64,
    },
    Pty {
        session_id: String,
        event: PtyEvent,
    },
    OutputBatchTick {
        session_id: String,
        generation: u64,
    },
    CheckpointTick {
        session_id: String,
        generation: u64,
    },
    ShutdownTick {
        generation: u64,
    },
    SshBootstrapProgress {
        progress: SshTargetBootstrapProgress,
    },
    SshBootstrapFinished {
        target_id: String,
        job_id: String,
        status: SshBootstrapStatus,
    },
}

struct ClientState {
    handle: ClientHandle,
    authenticated: bool,
}

struct SshBootstrapJobState {
    job_id: String,
    target_id: String,
    status: SshBootstrapStatus,
    handle: JoinHandle<()>,
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
    let runtime_store = RuntimeStore::open(&runtime_dir).await?;
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    control_file::write_control_file(&control_file_path, port, &token)?;

    let (inbox, mut rx) = mpsc::unbounded_channel::<ServerCommand>();
    spawn_accept_loop(listener, inbox.clone());

    let mut actor = ServerActor {
        runtime_dir,
        control_file_path,
        token,
        config,
        store,
        runtime_store,
        sessions: HashMap::new(),
        ssh_bootstrap_jobs: HashMap::new(),
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
    runtime_dir: PathBuf,
    control_file_path: PathBuf,
    token: String,
    config: TerminalHostConfig,
    store: TerminalHostHistoryStore,
    runtime_store: RuntimeStore,
    sessions: HashMap<String, Session>,
    ssh_bootstrap_jobs: HashMap<String, SshBootstrapJobState>,
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
            ServerCommand::SshBootstrapProgress { progress } => {
                self.handle_ssh_bootstrap_progress(progress)
            }
            ServerCommand::SshBootstrapFinished {
                target_id,
                job_id,
                status,
            } => self.handle_ssh_bootstrap_finished(target_id, job_id, status),
        }
    }

    async fn start_ssh_bootstrap_job(
        &mut self,
        request: SshTargetBootstrapRequest,
    ) -> HostResult<Value> {
        if let Some(existing) = self.ssh_bootstrap_jobs.get(&request.target_id) {
            return Ok(json!(SshTargetBootstrapJob {
                job_id: existing.job_id.clone(),
                target_id: existing.target_id.clone(),
                status: existing.status,
            }));
        }
        let target = self
            .runtime_store
            .find_ssh_target(&request.target_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("ssh target not found: {}", request.target_id))
            })?;
        if matches!(target.auth_kind, SshAuthKind::Password) {
            return Err(HostError::state(
                "password SSH targets are not supported for bootstrap; configure SSH agent or key authentication.",
            ));
        }
        let job_id = new_bootstrap_job_id();
        mark_ssh_bootstrap_installing(&self.runtime_store, &target.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_authenticated(event(
            "sshTargetBootstrapProgress",
            json!(SshTargetBootstrapProgress {
                job_id: job_id.clone(),
                target_id: target.id.clone(),
                status: SshBootstrapStatus::Installing,
                stage: "auth".to_string(),
                message: "Checking SSH Authentication".to_string(),
                error: None,
            }),
        ));
        self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
        let target_id = request.target_id.clone();
        let store = self.runtime_store.clone();
        let cache_dir = self.runtime_dir.join("runtime-artifacts");
        let inbox = self.inbox.clone();
        let task_job_id = job_id.clone();
        let task_target_id = target_id.clone();
        let handle = tokio::spawn(async move {
            let result =
                run_ssh_bootstrap(store, cache_dir, request, task_job_id.clone(), |progress| {
                    let _ = inbox.send(ServerCommand::SshBootstrapProgress { progress });
                })
                .await;
            let status = if result.is_ok() {
                SshBootstrapStatus::Installed
            } else {
                SshBootstrapStatus::Failed
            };
            let _ = inbox.send(ServerCommand::SshBootstrapFinished {
                target_id: task_target_id,
                job_id: task_job_id,
                status,
            });
        });
        let job = SshBootstrapJobState {
            job_id: job_id.clone(),
            target_id: target_id.clone(),
            status: SshBootstrapStatus::Installing,
            handle,
        };
        self.ssh_bootstrap_jobs.insert(target_id.clone(), job);
        self.cancel_shutdown_timer();
        Ok(json!(SshTargetBootstrapJob {
            job_id,
            target_id,
            status: SshBootstrapStatus::Installing,
        }))
    }

    async fn cancel_ssh_bootstrap_job(&mut self, target_id: &str) -> HostResult<Value> {
        if let Some(target) = self
            .cancel_active_ssh_bootstrap_job(target_id, "Remote Runtime Install Cancelled")
            .await?
        {
            self.schedule_shutdown_if_idle();
            return Ok(json!(target));
        }
        if let Some(target) = self
            .runtime_store
            .find_ssh_target(target_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            if target.bootstrap_status == SshBootstrapStatus::Installing {
                let target = self
                    .mark_ssh_bootstrap_cancelled(
                        target_id,
                        new_bootstrap_job_id(),
                        "Stale Remote Runtime Install Cancelled",
                    )
                    .await?;
                self.schedule_shutdown_if_idle();
                return Ok(json!(target));
            }
        }
        Err(HostError::state(format!(
            "No active bootstrap job for SSH target: {target_id}"
        )))
    }

    async fn cancel_ssh_bootstrap_job_before_remove(&mut self, target_id: &str) -> HostResult<()> {
        self.cancel_active_ssh_bootstrap_job(target_id, "Remote Runtime Install Cancelled")
            .await?;
        self.schedule_shutdown_if_idle();
        Ok(())
    }

    async fn cancel_active_ssh_bootstrap_job(
        &mut self,
        target_id: &str,
        message: &str,
    ) -> HostResult<Option<SshTarget>> {
        let Some(job) = self.ssh_bootstrap_jobs.remove(target_id) else {
            return Ok(None);
        };
        job.handle.abort();
        self.mark_ssh_bootstrap_cancelled(target_id, job.job_id, message)
            .await
            .map(Some)
    }

    async fn mark_ssh_bootstrap_cancelled(
        &mut self,
        target_id: &str,
        job_id: String,
        message: &str,
    ) -> HostResult<SshTarget> {
        let target = cancel_ssh_bootstrap(&self.runtime_store, target_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let progress = SshTargetBootstrapProgress {
            job_id,
            target_id: target_id.to_string(),
            status: SshBootstrapStatus::Cancelled,
            stage: "cancelled".to_string(),
            message: message.to_string(),
            error: None,
        };
        self.broadcast_authenticated(event("sshTargetBootstrapProgress", json!(progress)));
        self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
        Ok(target)
    }

    fn list_ssh_bootstrap_jobs(&self) -> Value {
        let jobs = self
            .ssh_bootstrap_jobs
            .values()
            .map(|job| {
                json!(SshTargetBootstrapJob {
                    job_id: job.job_id.clone(),
                    target_id: job.target_id.clone(),
                    status: job.status,
                })
            })
            .collect::<Vec<_>>();
        json!(jobs)
    }

    fn handle_ssh_bootstrap_progress(&mut self, progress: SshTargetBootstrapProgress) {
        let Some(job) = self.ssh_bootstrap_jobs.get_mut(&progress.target_id) else {
            return;
        };
        if job.job_id != progress.job_id {
            return;
        }
        job.status = progress.status;
        self.broadcast_authenticated(event("sshTargetBootstrapProgress", json!(progress)));
        self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
    }

    fn handle_ssh_bootstrap_finished(
        &mut self,
        target_id: String,
        job_id: String,
        status: SshBootstrapStatus,
    ) {
        if self
            .ssh_bootstrap_jobs
            .get(&target_id)
            .is_some_and(|job| job.job_id == job_id)
        {
            self.ssh_bootstrap_jobs.remove(&target_id);
            self.broadcast_authenticated(event(
                "sshTargetBootstrapProgress",
                json!(SshTargetBootstrapProgress {
                    job_id,
                    target_id,
                    status,
                    stage: status.as_str().to_string(),
                    message: match status {
                        SshBootstrapStatus::Installed => "Remote Runtime Installed",
                        SshBootstrapStatus::Failed => "Remote Runtime Install Failed",
                        SshBootstrapStatus::Cancelled => "Remote Runtime Install Cancelled",
                        _ => "Remote Runtime Bootstrap Updated",
                    }
                    .to_string(),
                    error: None,
                }),
            ));
            self.broadcast_authenticated(event("sshTargetsChanged", json!({})));
            self.schedule_shutdown_if_idle();
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

    pub(super) async fn terminate_sessions_for_tab(&mut self, tab_id: &str) {
        let session_ids: Vec<String> = self
            .sessions
            .iter()
            .filter(|(_, session)| session.tab_id == tab_id)
            .map(|(session_id, _)| session_id.clone())
            .collect();
        self.terminate_sessions(session_ids).await;
    }

    pub(super) async fn terminate_sessions_for_workspace(&mut self, workspace_id: &str) {
        let session_ids: Vec<String> = self
            .sessions
            .iter()
            .filter(|(_, session)| session.workspace_id == workspace_id)
            .map(|(session_id, _)| session_id.clone())
            .collect();
        self.terminate_sessions(session_ids).await;
    }

    pub(super) async fn terminate_sessions_for_workspaces(&mut self, workspace_ids: &[String]) {
        let session_ids: Vec<String> = self
            .sessions
            .iter()
            .filter(|(_, session)| {
                workspace_ids
                    .iter()
                    .any(|workspace_id| workspace_id == &session.workspace_id)
            })
            .map(|(session_id, _)| session_id.clone())
            .collect();
        self.terminate_sessions(session_ids).await;
    }

    async fn terminate_sessions(&mut self, session_ids: Vec<String>) {
        if session_ids.is_empty() {
            return;
        }
        let store = self.store.clone();
        for session_id in session_ids {
            self.flush_output_batch(&session_id);
            self.await_output_writes(&session_id).await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                session.terminate(true, &store).await;
            }
        }
        self.schedule_shutdown_if_idle();
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

    pub(super) fn broadcast_authenticated(&self, message: Value) {
        for client in self.clients.values() {
            if client.authenticated {
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

    fn has_active_bootstrap_jobs(&self) -> bool {
        !self.ssh_bootstrap_jobs.is_empty()
    }

    fn schedule_shutdown_if_idle(&mut self) {
        if self.disposed || self.has_authenticated_clients() || self.has_active_bootstrap_jobs() {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn stale_ssh_bootstrap_progress_is_not_broadcast() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let (out, mut out_rx) = mpsc::unbounded_channel();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::from([(
                "remote".to_string(),
                SshBootstrapJobState {
                    job_id: "active-job".to_string(),
                    target_id: "remote".to_string(),
                    status: SshBootstrapStatus::Installing,
                    handle: tokio::spawn(async {}),
                },
            )]),
            clients: HashMap::from([(
                1,
                ClientState {
                    handle: ClientHandle { out },
                    authenticated: true,
                },
            )]),
            pending_output_writes: HashMap::new(),
            inbox,
            shutdown_gen: 0,
            disposed: false,
        };

        actor.handle_ssh_bootstrap_progress(SshTargetBootstrapProgress {
            job_id: "stale-job".to_string(),
            target_id: "remote".to_string(),
            status: SshBootstrapStatus::Failed,
            stage: "failed".to_string(),
            message: "Stale failure".to_string(),
            error: Some("stale".to_string()),
        });

        assert!(out_rx.try_recv().is_err());
        assert_eq!(
            actor.ssh_bootstrap_jobs["remote"].status,
            SshBootstrapStatus::Installing
        );
    }
}
