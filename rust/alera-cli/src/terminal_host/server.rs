use std::collections::{HashMap, HashSet};
use std::net::{Ipv4Addr, Ipv6Addr};
use std::path::PathBuf;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
use std::time::Duration;

use alera_core::runtime::{
    MobileAccessSettings, RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget,
};
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
use crate::terminal_host::mobile_gateway::spawn_mobile_gateway_accept_loop;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceRegistry;
use crate::terminal_host::orchestration::agent_prompt_injection as prompt_injection;
use crate::terminal_host::orchestration::coordinator_loop::CoordinatorHandle;
use crate::terminal_host::orchestration::message_delivery::{
    skips_auto_enter, DEFERRED_ENTER_DELAY_MS,
};
use crate::terminal_host::orchestration::message_formatter::format_messages_for_injection;
use crate::terminal_host::orchestration::message_waiters::MessageWaiterRegistry;
use crate::terminal_host::protocol::{event, TerminalHostConfig};
use crate::terminal_host::session::{PtyEvent, PtyWriteCompletion, Session};

mod coordinator_requests;
mod orchestration_requests;
mod requests;

/// Delay before a debounced checkpoint write fires.
const CHECKPOINT_DELAY: Duration = Duration::from_secs(5);

const OUTPUT_BATCH_DELAY: Duration = Duration::from_millis(8);
const DURABLE_OUTPUT_BATCH_DELAY: Duration = Duration::from_millis(100);
const OUTPUT_PERSISTENCE_BARRIER_TIMEOUT: Duration = Duration::from_secs(2);
const TERMINAL_INPUT_BACKPRESSURE_CODE: &str = "terminal_input_backpressure";
/// Cap coalesced PTY→client batches so a verbose agent/build cannot grow an
/// unbounded `output_batch` between timer flushes (early flush when exceeded).
const OUTPUT_BATCH_MAX_BYTES: usize = 64 * 1024;

/// Messages processed serially by the single server actor. Every state mutation
/// happens here, which keeps session/client transitions deterministic.
pub enum ServerCommand {
    ClientConnected {
        id: u64,
        handle: ClientHandle,
        kind: ClientKind,
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
    DurableOutputBatchTick {
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
    ManagedWorkspaceCreated {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    ManagedWorkspaceRemoved {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    /// A parked `check --wait`/`ask` request hit its server-side deadline.
    OrchestrationWaitTimeout {
        waiter_id: u64,
    },
    /// Fires the deferred Enter after an injected orchestration banner.
    OrchestrationDeferredEnter {
        session_id: String,
        session_instance_id: u64,
        message_ids: Vec<String>,
    },
    /// One coordinator loop iteration, enqueued by the ticker task.
    CoordinatorTick {
        run_id: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ClientKind {
    Local,
    Mobile,
}

struct ClientState {
    handle: ClientHandle,
    authenticated: bool,
    kind: ClientKind,
    mobile_device_id: Option<String>,
    app_client: bool,
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
    let next_client_id = Arc::new(AtomicU64::new(1));
    spawn_accept_loop(listener, inbox.clone(), next_client_id.clone());

    let mut actor = ServerActor {
        runtime_dir,
        control_file_path,
        token,
        config,
        store,
        runtime_store,
        sessions: HashMap::new(),
        ssh_bootstrap_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        clients: HashMap::new(),
        pending_output_writes: HashMap::new(),
        agent_presence: AgentPresenceRegistry::default(),
        orchestration_waiters: MessageWaiterRegistry::default(),
        orchestration_delivery_in_flight: HashSet::new(),
        orchestration_delivery_backpressured: HashSet::new(),
        coordinator: None,
        inbox,
        next_client_id,
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    };
    if let Err(error) = actor.restart_mobile_gateway().await {
        eprintln!("alera mobile gateway unavailable: {}", error.wire_message());
    }
    actor.schedule_shutdown_if_idle();

    while let Some(command) = rx.recv().await {
        actor.handle(command).await;
        if actor.disposed {
            break;
        }
    }
    Ok(())
}

fn spawn_accept_loop(
    listener: TcpListener,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
) {
    tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let _ = stream.set_nodelay(true);
            let id = next_client_id.fetch_add(1, Ordering::Relaxed);
            let (out_tx, out_rx) = mpsc::unbounded_channel::<Value>();
            // Register the client before its lines can arrive: the
            // ClientConnected command is enqueued before the connection loop
            // (and thus any ClientLine) starts.
            if inbox
                .send(ServerCommand::ClientConnected {
                    id,
                    handle: ClientHandle { out: out_tx },
                    kind: ClientKind::Local,
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
    managed_workspace_jobs: usize,
    clients: HashMap<u64, ClientState>,
    pending_output_writes: HashMap<String, Vec<JoinHandle<()>>>,
    agent_presence: AgentPresenceRegistry,
    orchestration_waiters: MessageWaiterRegistry,
    orchestration_delivery_in_flight: HashSet<String>,
    orchestration_delivery_backpressured: HashSet<String>,
    coordinator: Option<CoordinatorHandle>,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
    mobile_gateway: Option<JoinHandle<()>>,
    shutdown_gen: u64,
    disposed: bool,
}

enum MobileGatewayReplacement {
    Keep,
    Disabled,
    Bound {
        listener: TcpListener,
        bind_address: String,
    },
}

impl ServerActor {
    pub(super) async fn restart_mobile_gateway(&mut self) -> HostResult<()> {
        let settings = self
            .runtime_store
            .mobile_access_settings()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let replacement = self.prepare_mobile_gateway_replacement(&settings).await?;
        self.replace_mobile_gateway(replacement).await;
        Ok(())
    }

    pub(super) async fn apply_mobile_gateway_settings(
        &mut self,
        current: MobileAccessSettings,
        next: MobileAccessSettings,
    ) -> HostResult<MobileAccessSettings> {
        let replacement = if self.can_keep_mobile_gateway(&current, &next) {
            MobileGatewayReplacement::Keep
        } else {
            let release_before_bind =
                self.should_release_mobile_gateway_before_bind(&current, &next);
            if release_before_bind {
                self.stop_mobile_gateway().await;
                self.dispose_mobile_clients().await;
            }
            match self.prepare_mobile_gateway_replacement(&next).await {
                Ok(replacement) => replacement,
                Err(error) => {
                    if release_before_bind {
                        if let Ok(restored) =
                            self.prepare_mobile_gateway_replacement(&current).await
                        {
                            self.replace_mobile_gateway(restored).await;
                        }
                    }
                    return Err(error);
                }
            }
        };
        let saved = self
            .runtime_store
            .set_mobile_access_settings(next)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.replace_mobile_gateway(replacement).await;
        Ok(saved)
    }

    fn can_keep_mobile_gateway(
        &self,
        current: &MobileAccessSettings,
        next: &MobileAccessSettings,
    ) -> bool {
        self.mobile_gateway.is_some()
            && current.enabled
            && next.enabled
            && current.bind_host == next.bind_host
            && current.port == next.port
    }

    fn should_release_mobile_gateway_before_bind(
        &self,
        current: &MobileAccessSettings,
        next: &MobileAccessSettings,
    ) -> bool {
        self.mobile_gateway.is_some()
            && current.enabled
            && next.enabled
            && current.port == next.port
            && current.bind_host != next.bind_host
    }

    async fn prepare_mobile_gateway_replacement(
        &self,
        settings: &MobileAccessSettings,
    ) -> HostResult<MobileGatewayReplacement> {
        if !settings.enabled {
            return Ok(MobileGatewayReplacement::Disabled);
        }
        let port: u16 = settings.port.try_into().map_err(|_| {
            HostError::state(format!(
                "mobile gateway port is outside the valid range: {}",
                settings.port
            ))
        })?;
        let bind_address = display_socket_address(&settings.bind_host, port);
        let listener = TcpListener::bind((settings.bind_host.as_str(), port))
            .await
            .map_err(|error| {
                HostError::state(format!(
                    "mobile gateway bind failed for {bind_address}: {error}"
                ))
            })?;
        let local_address = listener
            .local_addr()
            .map(|address| address.to_string())
            .unwrap_or(bind_address);
        Ok(MobileGatewayReplacement::Bound {
            listener,
            bind_address: local_address,
        })
    }

    async fn replace_mobile_gateway(&mut self, replacement: MobileGatewayReplacement) {
        match replacement {
            MobileGatewayReplacement::Keep => {}
            MobileGatewayReplacement::Disabled => {
                self.stop_mobile_gateway().await;
                self.dispose_mobile_clients().await;
                self.broadcast_authenticated(event(
                    "mobileGatewayChanged",
                    json!({ "enabled": false }),
                ));
            }
            MobileGatewayReplacement::Bound {
                listener,
                bind_address,
            } => {
                self.stop_mobile_gateway().await;
                self.dispose_mobile_clients().await;
                self.mobile_gateway = Some(spawn_mobile_gateway_accept_loop(
                    listener,
                    self.inbox.clone(),
                    self.next_client_id.clone(),
                ));
                self.cancel_shutdown_timer();
                self.broadcast_authenticated(event(
                    "mobileGatewayChanged",
                    json!({
                        "enabled": true,
                        "bindAddress": bind_address,
                    }),
                ));
            }
        }
    }

    async fn stop_mobile_gateway(&mut self) {
        if let Some(handle) = self.mobile_gateway.take() {
            handle.abort();
            let _ = handle.await;
        }
    }

    async fn handle(&mut self, command: ServerCommand) {
        match command {
            ServerCommand::ClientConnected { id, handle, kind } => {
                self.clients.insert(
                    id,
                    ClientState {
                        handle,
                        authenticated: false,
                        kind,
                        mobile_device_id: None,
                        app_client: false,
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
            ServerCommand::DurableOutputBatchTick {
                session_id,
                generation,
            } => self.handle_durable_output_batch_tick(session_id, generation),
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
            ServerCommand::ManagedWorkspaceCreated {
                client_id,
                request_id,
                result,
            } => {
                self.handle_managed_workspace_created(client_id, request_id, result)
                    .await
            }
            ServerCommand::ManagedWorkspaceRemoved {
                client_id,
                request_id,
                result,
            } => {
                self.handle_managed_workspace_removed(client_id, request_id, result)
                    .await
            }
            ServerCommand::OrchestrationWaitTimeout { waiter_id } => {
                self.handle_orchestration_wait_timeout(waiter_id).await
            }
            ServerCommand::OrchestrationDeferredEnter {
                session_id,
                session_instance_id,
                message_ids,
            } => {
                self.handle_orchestration_deferred_enter(
                    session_id,
                    session_instance_id,
                    message_ids,
                )
                .await
            }
            ServerCommand::CoordinatorTick { run_id } => self.handle_coordinator_tick(run_id).await,
        }
    }

    // --- Orchestration push-on-idle delivery -------------------------------

    /// Pushes unread messages to an idle agent and stamps `delivered_at` only
    /// after the deferred Enter succeeds. Active coordinators are excluded so
    /// auto-submit cannot steal their prompt.
    pub(super) async fn deliver_pending_messages(&mut self, handle: &str) {
        if self.is_active_coordinator_handle(handle) {
            return;
        }
        let running = self.sessions.get(handle).is_some_and(Session::running);
        if !running {
            return;
        }
        if self.orchestration_delivery_in_flight.contains(handle) {
            return;
        }
        self.orchestration_delivery_backpressured.remove(handle);
        let messages = match self
            .runtime_store
            .undelivered_unread_orchestration_messages(handle)
            .await
        {
            Ok(messages) if !messages.is_empty() => messages,
            _ => return,
        };
        let formatted = format_messages_for_injection(&messages);
        let Some(session) = self.sessions.get_mut(handle) else {
            return;
        };
        let session_instance_id = session.instance_id();
        let ids: Vec<String> = messages.iter().map(|message| message.id.clone()).collect();
        let paste = prompt_injection::build_agent_prompt_paste_bytes(&formatted);
        if let Err(error) = session.queue_write(
            PtyWriteCompletion::OrchestrationPaste {
                session_instance_id,
                message_ids: ids,
            },
            &paste,
        ) {
            let message = error.wire_message();
            if message.contains(TERMINAL_INPUT_BACKPRESSURE_CODE) {
                self.orchestration_delivery_backpressured
                    .insert(handle.to_string());
            } else {
                self.broadcast_terminal_error(handle, message);
            }
            return;
        }
        self.orchestration_delivery_in_flight
            .insert(handle.to_string());
    }

    fn is_active_coordinator_handle(&self, handle: &str) -> bool {
        self.coordinator
            .as_ref()
            .and_then(|c| c.config.coordinator_handle.as_deref())
            == Some(handle)
    }

    /// Send-time hook: deliver immediately only when the recipient's agent is
    /// already idle right now.
    pub(super) async fn deliver_pending_messages_if_idle(&mut self, handle: &str) {
        if self.agent_presence.is_injection_ready(handle) {
            self.deliver_pending_messages(handle).await;
        }
    }

    async fn retry_backpressured_delivery_if_idle(&mut self, handle: &str) {
        if self.orchestration_delivery_backpressured.contains(handle)
            && self.agent_presence.is_injection_ready(handle)
        {
            self.deliver_pending_messages(handle).await;
        }
    }

    async fn handle_orchestration_deferred_enter(
        &mut self,
        session_id: String,
        session_instance_id: u64,
        message_ids: Vec<String>,
    ) {
        let skip_auto_enter =
            message_ids.is_empty() && skips_auto_enter(self.agent_presence.agent_type(&session_id));
        let current_instance_id = self.sessions.get(&session_id).map(Session::instance_id);
        if current_instance_id != Some(session_instance_id) {
            self.orchestration_delivery_in_flight.remove(&session_id);
            return;
        }
        if !message_ids.is_empty() && self.is_active_coordinator_handle(&session_id) {
            self.orchestration_delivery_in_flight.remove(&session_id);
            return;
        }
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if !session.running() {
            // Terminal closed in the 500ms window: leave delivered_at NULL so
            // the batch is redelivered on the next idle transition.
            self.orchestration_delivery_in_flight.remove(&session_id);
            return;
        }
        if skip_auto_enter {
            return;
        }
        if let Err(error) = session.queue_write(
            PtyWriteCompletion::OrchestrationEnter {
                session_instance_id,
                message_ids: message_ids.clone(),
            },
            prompt_injection::AGENT_PROMPT_SUBMIT,
        ) {
            let message = error.wire_message();
            if message.contains(TERMINAL_INPUT_BACKPRESSURE_CODE) {
                self.schedule_orchestration_enter(session_id, session_instance_id, message_ids);
                return;
            }
            self.orchestration_delivery_in_flight.remove(&session_id);
            self.broadcast_terminal_error(&session_id, message);
        }
    }

    fn schedule_orchestration_enter(
        &self,
        session_id: String,
        session_instance_id: u64,
        message_ids: Vec<String>,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(DEFERRED_ENTER_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::OrchestrationDeferredEnter {
                session_id,
                session_instance_id,
                message_ids,
            });
        });
    }

    pub(super) fn queue_orchestration_paste(
        &mut self,
        session_id: &str,
        prompt: &str,
        message_ids: Vec<String>,
    ) -> HostResult<()> {
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or_else(|| HostError::state(format!("terminal {session_id} vanished")))?;
        let session_instance_id = session.instance_id();
        let paste = prompt_injection::build_agent_prompt_paste_bytes(prompt);
        session.queue_write(
            PtyWriteCompletion::OrchestrationPaste {
                session_instance_id,
                message_ids,
            },
            &paste,
        )
    }

    fn broadcast_terminal_error(&self, session_id: &str, message: String) {
        if let Some(session) = self.sessions.get(session_id) {
            let clients: Vec<u64> = session.clients.iter().copied().collect();
            self.broadcast(&clients, event("error", session.error_payload(&message)));
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
                    let (output_generation, durable_generation) = session.append_output(&data);
                    let output_len = session.output_batch_len();
                    let durable_len = session.durable_output_batch_len();
                    let checkpoint_generation = session.arm_checkpoint();
                    (
                        output_generation,
                        output_len,
                        durable_generation,
                        durable_len,
                        checkpoint_generation,
                    )
                });
                if let Some((
                    output_generation,
                    output_len,
                    durable_generation,
                    durable_len,
                    checkpoint_generation,
                )) = state
                {
                    if let Some(generation) = output_generation {
                        self.spawn_output_batch_timer(session_id.clone(), generation);
                    }
                    if let Some(generation) = durable_generation {
                        self.spawn_durable_output_batch_timer(session_id.clone(), generation);
                    }
                    if output_len >= OUTPUT_BATCH_MAX_BYTES {
                        self.flush_output_batch(&session_id);
                    }
                    if durable_len >= OUTPUT_BATCH_MAX_BYTES {
                        self.flush_durable_output_batch(&session_id);
                    }
                    if let Some(generation) = checkpoint_generation {
                        self.spawn_checkpoint_timer(session_id, generation);
                    }
                }
            }
            PtyEvent::Error(message) => {
                self.flush_all_output(&session_id);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    let payload = session.error_payload(&message);
                    let clients: Vec<u64> = session.clients.iter().copied().collect();
                    self.broadcast(&clients, event("error", payload));
                }
            }
            PtyEvent::InputWritten { completion, error } => {
                self.handle_pty_input_written(session_id, completion, error)
                    .await;
            }
            PtyEvent::Exit(code) => self.handle_session_exit(session_id, code).await,
        }
    }

    async fn handle_pty_input_written(
        &mut self,
        session_id: String,
        completion: PtyWriteCompletion,
        error: Option<String>,
    ) {
        match completion {
            PtyWriteCompletion::ClientRequest {
                client_id,
                request_id,
            } => match error {
                Some(message) => self.client_write(
                    client_id,
                    crate::terminal_host::protocol::error_response(
                        request_id,
                        &HostError::state(message),
                    ),
                ),
                None => {
                    self.client_write(
                        client_id,
                        crate::terminal_host::protocol::ok_response(request_id, json!({})),
                    );
                    self.retry_backpressured_delivery_if_idle(&session_id).await;
                }
            },
            PtyWriteCompletion::OrchestrationPaste {
                session_instance_id,
                message_ids,
            } => {
                if let Some(message) = error {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                    self.broadcast_terminal_error(&session_id, message);
                    return;
                }
                if self.sessions.get(&session_id).map(Session::instance_id)
                    != Some(session_instance_id)
                {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                    return;
                }
                if skips_auto_enter(self.agent_presence.agent_type(&session_id)) {
                    if !message_ids.is_empty() {
                        let delivered = self
                            .runtime_store
                            .mark_orchestration_messages_delivered(&message_ids)
                            .await
                            .is_ok();
                        self.orchestration_delivery_in_flight.remove(&session_id);
                        if delivered && self.agent_presence.is_injection_ready(&session_id) {
                            self.deliver_pending_messages(&session_id).await;
                        }
                    }
                    return;
                }
                self.schedule_orchestration_enter(session_id, session_instance_id, message_ids);
            }
            PtyWriteCompletion::OrchestrationEnter {
                session_instance_id,
                message_ids,
            } => {
                let current = self.sessions.get(&session_id).map(Session::instance_id);
                if error.is_some() || current != Some(session_instance_id) {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                    if let Some(message) = error {
                        self.broadcast_terminal_error(&session_id, message);
                    }
                    return;
                }
                let message_backed = !message_ids.is_empty();
                let delivered = !message_backed
                    || self
                        .runtime_store
                        .mark_orchestration_messages_delivered(&message_ids)
                        .await
                        .is_ok();
                if message_backed {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                }
                if delivered
                    && self.agent_presence.is_injection_ready(&session_id)
                    && (message_backed
                        || self
                            .orchestration_delivery_backpressured
                            .contains(&session_id))
                {
                    self.deliver_pending_messages(&session_id).await;
                }
            }
        }
    }

    async fn handle_session_exit(&mut self, session_id: String, exit_code: i32) {
        let reason = format!("terminal exited with code {exit_code}");
        self.cleanup_orchestration_for_closed_session(&session_id, &reason)
            .await;
        self.flush_all_output(&session_id);
        let broadcast = self.sessions.get_mut(&session_id).and_then(|session| {
            let payload = session.handle_exit(exit_code)?;
            let clients: Vec<u64> = session.clients.iter().copied().collect();
            Some((event("exit", payload), clients))
        });
        if let Some((frame, clients)) = broadcast {
            self.broadcast(&clients, frame);
            self.immediate_checkpoint(&session_id).await;
        }
        self.schedule_shutdown_if_idle();
    }

    async fn cleanup_orchestration_for_closed_session(&mut self, session_id: &str, reason: &str) {
        // The agent (if any) died with its PTY; stale presence must not keep
        // attracting group messages or push-on-idle deliveries.
        self.agent_presence.remove(session_id);
        self.orchestration_delivery_in_flight.remove(session_id);
        self.orchestration_delivery_backpressured.remove(session_id);
        self.fail_active_dispatch_for_closed_session(session_id, reason)
            .await;
    }

    async fn fail_active_dispatch_for_closed_session(&self, session_id: &str, reason: &str) {
        let dispatch = match self
            .runtime_store
            .active_orchestration_dispatch_for_handle(session_id)
            .await
        {
            Ok(dispatch) => dispatch,
            Err(error) => {
                eprintln!(
                    "failed to inspect active orchestration dispatch for exited terminal {session_id}: {error}"
                );
                return;
            }
        };
        let Some(dispatch) = dispatch else {
            return;
        };
        if let Err(error) = self
            .runtime_store
            .fail_orchestration_dispatch(&dispatch.id, reason)
            .await
        {
            eprintln!(
                "failed to mark orchestration dispatch {} failed after terminal close: {error}",
                dispatch.id
            );
        }
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

    fn handle_durable_output_batch_tick(&mut self, session_id: String, generation: u64) {
        let due = self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.durable_output_batch_due(generation));
        if due {
            self.flush_durable_output_batch(&session_id);
        }
    }

    fn flush_output_batch(&mut self, session_id: &str) {
        let broadcast = self.sessions.get_mut(session_id).and_then(|session| {
            let batch = session.flush_output_batch()?;
            let clients = session.output_clients();
            Some((event("output", batch.payload), clients))
        });
        if let Some((frame, clients)) = broadcast {
            self.broadcast(&clients, frame);
        }
    }

    fn flush_durable_output_batch(&mut self, session_id: &str) {
        let batch = self
            .sessions
            .get_mut(session_id)
            .and_then(Session::flush_durable_output_batch);
        if let Some(batch) = batch {
            self.persist_output_batch(session_id.to_string(), batch.sequence, batch.data);
        }
    }

    fn flush_all_output(&mut self, session_id: &str) {
        self.flush_output_batch(session_id);
        self.flush_durable_output_batch(session_id);
    }

    async fn handle_checkpoint_tick(&mut self, session_id: String, generation: u64) {
        let store = self.store.clone();
        let due = self
            .sessions
            .get_mut(&session_id)
            .is_some_and(|session| session.checkpoint_due(generation));
        if due {
            self.flush_durable_output_batch(&session_id);
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
        self.flush_durable_output_batch(session_id);
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
        let pending = self.pending_output_writes.entry(session_id).or_default();
        pending.retain(|existing| !existing.is_finished());
        pending.push(handle);
    }

    async fn await_output_writes(&mut self, session_id: &str) {
        let Some(handles) = self.pending_output_writes.remove(session_id) else {
            return;
        };
        if tokio::time::timeout(
            OUTPUT_PERSISTENCE_BARRIER_TIMEOUT,
            futures_util::future::join_all(handles),
        )
        .await
        .is_err()
        {
            eprintln!(
                "terminal output persistence barrier timed out for session {session_id}; continuing without blocking the host actor"
            );
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
            self.cleanup_orchestration_for_closed_session(
                &session_id,
                "terminal was explicitly terminated",
            )
            .await;
            self.flush_all_output(&session_id);
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
        let Some(disconnecting_client) = self.clients.get(&client_id) else {
            return;
        };
        let disconnects_app_client = disconnecting_client.app_client;
        // Parked long-poll requests die with their connection.
        self.orchestration_waiters.remove_client(client_id);
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.flush_all_output(&session_id);
            if let Some(session) = self.sessions.get_mut(&session_id) {
                session.detach(client_id);
            }
            self.immediate_checkpoint(&session_id).await;
        }
        // Dropping the handle ends the connection loop and closes the socket.
        self.clients.remove(&client_id);
        if disconnects_app_client && !self.has_app_clients() {
            self.agent_presence.clear();
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn dispose_mobile_clients(&mut self) {
        let client_ids = self
            .clients
            .iter()
            .filter_map(|(id, client)| (client.kind == ClientKind::Mobile).then_some(*id))
            .collect::<Vec<_>>();
        for client_id in client_ids {
            self.dispose_client(client_id).await;
        }
    }

    pub(super) async fn dispose_mobile_clients_for_device(&mut self, device_id: &str) {
        let client_ids = self
            .clients
            .iter()
            .filter_map(|(id, client)| {
                (client.kind == ClientKind::Mobile
                    && client.mobile_device_id.as_deref() == Some(device_id))
                .then_some(*id)
            })
            .collect::<Vec<_>>();
        for client_id in client_ids {
            self.dispose_client(client_id).await;
        }
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
            self.flush_all_output(&session_id);
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

    fn has_app_clients(&self) -> bool {
        self.clients
            .values()
            .any(|client| client.authenticated && client.app_client)
    }

    fn has_running_sessions(&self) -> bool {
        self.sessions.values().any(Session::running)
    }

    fn has_active_bootstrap_jobs(&self) -> bool {
        !self.ssh_bootstrap_jobs.is_empty()
    }

    fn has_active_managed_workspace_jobs(&self) -> bool {
        self.managed_workspace_jobs > 0
    }

    fn has_active_mobile_gateway(&self) -> bool {
        self.mobile_gateway.is_some()
    }

    fn schedule_shutdown_if_idle(&mut self) {
        if self.disposed
            || self.has_authenticated_clients()
            || self.has_active_bootstrap_jobs()
            || self.has_active_managed_workspace_jobs()
            || self.has_active_mobile_gateway()
            || self.coordinator.is_some()
        {
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

    fn spawn_durable_output_batch_timer(&self, session_id: String, generation: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(DURABLE_OUTPUT_BATCH_DELAY).await;
            let _ = inbox.send(ServerCommand::DurableOutputBatchTick {
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
        if let Some(handle) = self.mobile_gateway.take() {
            handle.abort();
        }
        // Closing client handles ends their connection loops.
        self.clients.clear();
        let store = self.store.clone();
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.cleanup_orchestration_for_closed_session(&session_id, "terminal host shut down")
                .await;
            self.flush_all_output(&session_id);
            self.await_output_writes(&session_id).await;
            if let Some(mut session) = self.sessions.remove(&session_id) {
                session.terminate(false, &store).await;
            }
        }
        control_file::delete_control_file(&self.control_file_path);
    }
}

fn display_socket_address(host: &str, port: u16) -> String {
    if host.parse::<Ipv6Addr>().is_ok() {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::history_store::TerminalHostCheckpoint;
    use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
    use alera_core::runtime::{
        NewOrchestrationTask, OrchestrationDispatchStatus, OrchestrationTaskStatus,
    };

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
            managed_workspace_jobs: 0,
            clients: HashMap::from([(
                1,
                ClientState {
                    handle: ClientHandle { out },
                    authenticated: true,
                    kind: ClientKind::Local,
                    mobile_device_id: None,
                    app_client: true,
                },
            )]),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(2)),
            mobile_gateway: None,
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

    #[tokio::test]
    async fn mobile_gateway_rebinds_same_port_after_releasing_old_listener() {
        let port_probe = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let port = port_probe.local_addr().unwrap().port();
        drop(port_probe);
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let current = MobileAccessSettings {
            enabled: true,
            bind_host: "127.0.0.1".to_string(),
            port: i64::from(port),
            ..MobileAccessSettings::default()
        };
        let next = MobileAccessSettings {
            enabled: true,
            bind_host: "0.0.0.0".to_string(),
            port: i64::from(port),
            ..MobileAccessSettings::default()
        };
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(1)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };

        actor
            .apply_mobile_gateway_settings(MobileAccessSettings::default(), current.clone())
            .await
            .unwrap();
        let saved = actor
            .apply_mobile_gateway_settings(current, next)
            .await
            .unwrap();

        assert_eq!(saved.bind_host, "0.0.0.0");
        assert!(actor.mobile_gateway.is_some());
        actor.dispose().await;
    }

    #[tokio::test]
    async fn mobile_gateway_binds_ipv6_loopback() {
        let port_probe = match TcpListener::bind((Ipv6Addr::LOCALHOST, 0)).await {
            Ok(listener) => listener,
            Err(_) => return,
        };
        let port = port_probe.local_addr().unwrap().port();
        drop(port_probe);
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(1)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };
        let settings = MobileAccessSettings {
            enabled: true,
            bind_host: "::1".to_string(),
            port: i64::from(port),
            ..MobileAccessSettings::default()
        };

        let replacement = actor
            .prepare_mobile_gateway_replacement(&settings)
            .await
            .unwrap();

        match replacement {
            MobileGatewayReplacement::Bound { bind_address, .. } => {
                assert!(bind_address.starts_with("[::1]:"));
            }
            MobileGatewayReplacement::Disabled => panic!("expected bound mobile gateway"),
            MobileGatewayReplacement::Keep => panic!("expected bound mobile gateway"),
        }
    }

    #[tokio::test]
    async fn run_stop_clears_persisted_run_without_in_memory_ticker() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let run = runtime_store
            .create_orchestration_coordinator_run("coordinate", Some("coord"), 1000)
            .await
            .unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(1)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };

        let response = actor.orchestration_run_stop().await.unwrap();
        assert_eq!(response["runId"], json!(run.id));
        assert_eq!(response["status"], json!("failed"));
        assert!(actor
            .runtime_store
            .active_orchestration_coordinator_run()
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn terminal_exit_fails_active_orchestration_dispatch() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let task = runtime_store
            .create_orchestration_task(NewOrchestrationTask {
                spec: "do work".to_string(),
                task_title: None,
                display_name: None,
                deps: Vec::new(),
                parent_id: None,
                created_by_terminal_handle: None,
            })
            .await
            .unwrap();
        let dispatch = runtime_store
            .create_orchestration_dispatch(&task.id, "term-1")
            .await
            .unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(1)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };

        actor.handle_session_exit("term-1".to_string(), 9).await;

        let updated_dispatch = actor
            .runtime_store
            .orchestration_dispatch_by_id(&dispatch.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(updated_dispatch.status, OrchestrationDispatchStatus::Failed);
        assert_eq!(updated_dispatch.failure_count, 1);
        assert_eq!(
            updated_dispatch.last_failure.as_deref(),
            Some("terminal exited with code 9")
        );
        let updated_task = actor
            .runtime_store
            .orchestration_task_by_id(&task.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(updated_task.status, OrchestrationTaskStatus::Ready);
    }

    #[tokio::test]
    async fn host_dispose_fails_active_orchestration_dispatch() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let task = runtime_store
            .create_orchestration_task(NewOrchestrationTask {
                spec: "do work".to_string(),
                task_title: None,
                display_name: None,
                deps: Vec::new(),
                parent_id: None,
                created_by_terminal_handle: None,
            })
            .await
            .unwrap();
        let dispatch = runtime_store
            .create_orchestration_dispatch(&task.id, "term-1")
            .await
            .unwrap();
        store
            .upsert(TerminalHostCheckpoint {
                session_id: "term-1".to_string(),
                workspace_id: "workspace-1".to_string(),
                tab_id: "tab-1".to_string(),
                working_directory: "/tmp".to_string(),
                running: false,
                exit_code: None,
                ended_at: None,
                updated_at: chrono::Utc::now(),
                buffer: Vec::new(),
            })
            .await
            .unwrap();
        let session = Session::restore_exited(
            "term-1".to_string(),
            "workspace-1".to_string(),
            "tab-1".to_string(),
            &store,
            1024,
        )
        .await
        .unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::from([("term-1".to_string(), session)]),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(1)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };

        actor.dispose().await;

        let updated_dispatch = actor
            .runtime_store
            .orchestration_dispatch_by_id(&dispatch.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(updated_dispatch.status, OrchestrationDispatchStatus::Failed);
        assert_eq!(updated_dispatch.failure_count, 1);
        assert_eq!(
            updated_dispatch.last_failure.as_deref(),
            Some("terminal host shut down")
        );
        let updated_task = actor
            .runtime_store
            .orchestration_task_by_id(&task.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(updated_task.status, OrchestrationTaskStatus::Ready);
    }

    #[tokio::test]
    async fn coordinator_does_not_spawn_worker_tab_for_cli_only_client() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        runtime_store
            .create_orchestration_task(NewOrchestrationTask {
                spec: "do work".to_string(),
                task_title: None,
                display_name: None,
                deps: Vec::new(),
                parent_id: None,
                created_by_terminal_handle: None,
            })
            .await
            .unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let (out, _out_rx) = mpsc::unbounded_channel();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::from([(
                1,
                ClientState {
                    handle: ClientHandle { out },
                    authenticated: true,
                    kind: ClientKind::Local,
                    mobile_device_id: None,
                    app_client: false,
                },
            )]),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(2)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };
        let response = actor
            .orchestration_run(&json!({
                "spec": "coordinate",
                "from": "coord",
                "workspace": "workspace-1",
                "pollIntervalMs": 600_000,
            }))
            .await
            .unwrap();

        actor
            .handle(ServerCommand::CoordinatorTick {
                run_id: response["runId"].as_str().unwrap().to_string(),
            })
            .await;

        assert!(actor
            .runtime_store
            .list_workspace_tabs("workspace-1")
            .await
            .unwrap()
            .is_empty());
    }

    #[tokio::test]
    async fn last_app_client_disconnect_clears_agent_presence() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let (first_app_out, _first_app_rx) = mpsc::unbounded_channel();
        let (second_app_out, _second_app_rx) = mpsc::unbounded_channel();
        let (cli_out, _cli_rx) = mpsc::unbounded_channel();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            clients: HashMap::from([
                (
                    1,
                    ClientState {
                        handle: ClientHandle { out: first_app_out },
                        authenticated: true,
                        kind: ClientKind::Local,
                        mobile_device_id: None,
                        app_client: true,
                    },
                ),
                (
                    2,
                    ClientState {
                        handle: ClientHandle {
                            out: second_app_out,
                        },
                        authenticated: true,
                        kind: ClientKind::Local,
                        mobile_device_id: None,
                        app_client: true,
                    },
                ),
                (
                    3,
                    ClientState {
                        handle: ClientHandle { out: cli_out },
                        authenticated: true,
                        kind: ClientKind::Local,
                        mobile_device_id: None,
                        app_client: false,
                    },
                ),
            ]),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            coordinator: None,
            inbox,
            next_client_id: Arc::new(AtomicU64::new(4)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };
        actor
            .agent_presence
            .update("term-1", "claude".to_string(), AgentPresenceState::Done);

        actor.dispose_client(3).await;
        assert!(actor.agent_presence.is_injection_ready("term-1"));
        actor.dispose_client(1).await;
        assert!(actor.agent_presence.is_injection_ready("term-1"));
        actor.dispose_client(2).await;

        assert!(actor.agent_presence.get("term-1").is_none());
    }
}
