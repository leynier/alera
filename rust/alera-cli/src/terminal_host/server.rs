use std::collections::{HashMap, HashSet};
use std::net::Ipv4Addr;
use std::path::PathBuf;
use std::sync::{atomic::AtomicU64, Arc};
use std::time::{Duration, Instant};

use alera_core::runtime::{
    prepare_private_runtime_directory, MobileAccessSettings, RuntimeStore, SshAuthKind,
    SshBootstrapStatus, SshTarget,
};
use anyhow::Result;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::sync::mpsc::error::TrySendError;
use tokio::sync::mpsc::{self, UnboundedSender};
use tokio::sync::Mutex;
use tokio::sync::Notify;
use tokio::task::JoinHandle;

use crate::agent_status::{start_agent_integrations, start_hook_receiver};
use crate::ssh_bootstrap::{
    cancel_ssh_bootstrap, mark_ssh_bootstrap_installing, new_bootstrap_job_id, run_ssh_bootstrap,
    SshTargetBootstrapJob, SshTargetBootstrapProgress, SshTargetBootstrapRequest,
};
use crate::terminal_host::client::{
    connection_loop, ClientFrame, ClientHandle, CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
};
use crate::terminal_host::control_file;
use crate::terminal_host::emulator::EmulatorManager;
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
use crate::terminal_host::session::{PtyWriteCompletion, Session};
use crate::terminal_host::sleep_detector::SleepDetector;

use client_accept_loop::{display_socket_address, spawn_accept_loop};

use browser_broker::BrowserBroker;
use resource_requests::ResourceMonitorState;

mod account_push_state;
mod account_requests;
#[cfg(test)]
mod account_requests_tests;
#[cfg(test)]
mod actor_test_harness;
mod agent_canvas_requests;
mod agent_hook_events;
mod agent_profile_launch_requests;
mod agent_prompt_composition;
mod ai_dictation_requests;
mod ai_text_grok_plan;
mod ai_text_open_code;
mod ai_text_requests;
mod ai_text_workspace_identity;
mod automation_actor;
mod automation_catalog_requests;
mod automation_definition_requests;
mod automation_dispatch;
mod automation_policy_requests;
mod automation_request_authorization;
mod automation_request_routes;
mod automation_requests;
mod automation_run_target_requests;
mod automation_scheduler;
mod browser_artifact_requests;
mod browser_artifact_store;
mod browser_broker;
#[cfg(test)]
mod browser_broker_tests;
mod browser_catalog_requests;
mod browser_driver_requests;
mod browser_requests;
mod browser_tab_requests;
mod browser_tab_rollback;
mod browser_url_privacy;
mod client_accept_loop;
mod client_delivery;
mod codex_app_server;
mod codex_app_server_history;
mod codex_app_server_session_state;
mod codex_event_routing;
mod codex_events;
mod codex_goal_requests;
mod codex_nonblocking_questions;
mod codex_presence;
mod codex_requests;
mod codex_runtime_cleanup;
mod codex_state;
mod codex_tab_lifecycle;
mod codex_thread_identity;
mod codex_user_messages;
mod codex_workspace_inputs;
mod computer_request_payloads;
mod computer_requests;
mod coordinator_requests;
mod coordinator_stall_policy;
mod declared_catalog_requests;
mod deferred_requests;
mod emulator_request_payloads;
mod emulator_request_queue;
mod emulator_requests;
mod host_service_agent_quota;
mod host_service_requests;
mod host_status;
mod lifecycle;
mod managed_workspace_requests;
mod mobile_terminal_requests;
mod mobile_workspace_file_paths;
mod mobile_workspace_file_requests;
mod orchestration_agent_spawn_requests;
mod orchestration_owned_spawn;
mod orchestration_policy_requests;
mod orchestration_profile_spawn;
mod orchestration_requests;
mod orchestration_terminal_requests;
mod orchestration_validation;
mod orchestration_wait_requests;
mod output_delivery;
#[cfg(test)]
mod output_resume_tests;
mod project_requests;
mod prompt_file_requests;
mod prompt_file_store;
mod prompt_image_requests;
mod prompt_image_store;
mod pty_event_forwarder;
mod pty_events;
mod push_delivery;
mod request_payloads;
mod requests;
mod resource_requests;
mod runtime_change_broadcasts;
mod runtime_mutation_barrier;
mod runtime_mutations;
mod server_command;
#[path = "server_runner.rs"]
mod server_runner;
mod session_termination;
#[cfg(test)]
mod session_termination_tests;
mod tab_compatibility;
#[cfg(test)]
mod tab_compatibility_tests;
mod terminal_driver;
mod terminal_input_requests;
mod terminal_launch_defaults;
mod terminal_pulse;
mod terminal_session_requests;
mod terminal_spawn;
mod terminal_startup_commands;
mod workspace_pinning;
mod workspace_sidebar_requests;

pub use server_command::ServerCommand;

/// Delay before a debounced checkpoint write fires.
const CHECKPOINT_DELAY: Duration = Duration::from_secs(5);

const OUTPUT_BATCH_DELAY: Duration = Duration::from_millis(8);
const OUTPUT_RESYNC_RETRY_DELAY: Duration = Duration::from_millis(16);
const DURABLE_OUTPUT_BATCH_DELAY: Duration = Duration::from_millis(100);
const OUTPUT_PERSISTENCE_BARRIER_TIMEOUT: Duration = Duration::from_secs(2);
const TERMINAL_INPUT_BACKPRESSURE_CODE: &str = "terminal_input_backpressure";
/// Cap coalesced PTY→client batches so a verbose agent/build cannot grow an
/// unbounded `output_batch` between timer flushes (early flush when exceeded).
const OUTPUT_BATCH_MAX_BYTES: usize = 64 * 1024;
const ORCHESTRATION_ACTIVITY_WRITE_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ClientKind {
    Local,
    Mobile,
}

struct ClientState {
    handle: ClientHandle,
    authenticated: bool,
    binary_frames: bool,
    supports_mobile_emulator_tab_kind: bool,
    supports_codex_tab_kind: bool,
    kind: ClientKind,
    local_role: client_delivery::LocalClientRole,
    mobile_device_id: Option<String>,
    mobile_device_name: Option<String>,
    cloud_device_id: Option<String>,
}

struct SshBootstrapJobState {
    job_id: String,
    target_id: String,
    status: SshBootstrapStatus,
    handle: JoinHandle<()>,
}

pub use server_runner::{run_terminal_host_server, TerminalHostExit};

struct ServerActor {
    runtime_dir: PathBuf,
    control_file_path: PathBuf,
    token: String,
    config: TerminalHostConfig,
    store: TerminalHostHistoryStore,
    runtime_store: RuntimeStore,
    automation_wake: Arc<Notify>,
    automations_active: bool,
    sessions: HashMap<String, Session>,
    ssh_bootstrap_jobs: HashMap<String, SshBootstrapJobState>,
    project_clone_jobs: HashMap<String, tokio::sync::oneshot::Sender<()>>,
    managed_workspace_jobs: usize,
    emulator_requests: emulator_request_queue::EmulatorRequestQueue,
    agent_quota_cache: Option<(Instant, u64, Value)>,
    account_push: account_push_state::AccountPushState,
    clients: HashMap<u64, ClientState>,
    mobile_prompt_file_uploads: HashMap<u64, HashSet<String>>,
    pending_output_writes: HashMap<String, Vec<JoinHandle<()>>>,
    agent_presence: AgentPresenceRegistry,
    orchestration_waiters: MessageWaiterRegistry,
    orchestration_delivery_in_flight: HashSet<String>,
    orchestration_delivery_backpressured: HashSet<String>,
    orchestration_activity_last_recorded: HashMap<String, Instant>,
    coordinators: HashMap<String, CoordinatorHandle>,
    resources: ResourceMonitorState,
    terminal_pulses: terminal_pulse::TerminalPulseManager,
    browser: BrowserBroker,
    emulators: Option<Arc<Mutex<EmulatorManager>>>,
    codex: Option<codex_app_server::CodexAppServer>,
    codex_presence: HashMap<String, Value>,
    codex_presence_scheduled: bool,
    codex_pending_messages: HashMap<String, Vec<Value>>,
    codex_flush_scheduled: HashSet<String>,
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
                        binary_frames: false,
                        supports_mobile_emulator_tab_kind: false,
                        supports_codex_tab_kind: false,
                        kind,
                        local_role: client_delivery::LocalClientRole::Cli,
                        mobile_device_id: None,
                        mobile_device_name: None,
                        cloud_device_id: None,
                    },
                );
            }
            ServerCommand::ClientLine { id, line } => self.handle_line(id, line).await,
            ServerCommand::ClientDisconnected { id } => self.dispose_client(id).await,
            ServerCommand::EmulatorPointerTimeout {
                tab_id,
                client_id,
                generation,
            } => self.handle_emulator_pointer_timeout(&tab_id, client_id, generation),
            ServerCommand::Pty {
                session_id,
                event,
                handled,
            } => {
                self.handle_pty_event(session_id, event).await;
                let _ = handled.send(());
            }
            ServerCommand::OutputBatchTick {
                session_id,
                generation,
            } => self.handle_output_batch_tick(session_id, generation),
            ServerCommand::OutputResyncTick {
                session_id,
                client_id,
            } => self.handle_output_resync_tick(session_id, client_id),
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
            ServerCommand::RequestedShutdown => self.dispose().await,
            ServerCommand::RequestedRestart => self.dispose().await,
            ServerCommand::AgentHookEvent { event } => self.handle_agent_hook_event(event).await,
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
            ServerCommand::WorkspaceSetupFinished {
                client_id,
                request_id,
                result,
            } => {
                self.handle_workspace_setup_finished(client_id, request_id, result)
                    .await
            }
            ServerCommand::AiTextGenerationFinished {
                client_id,
                request_id,
                result,
            } => self.handle_ai_text_generation_finished(client_id, request_id, result),
            ServerCommand::MobileWorkspaceFileFinished {
                client_id,
                request_id,
                request_type,
                result,
            } => self.handle_mobile_workspace_file_finished(
                client_id,
                request_id,
                &request_type,
                result,
            ),
            ServerCommand::MobilePromptFileFinished {
                client_id,
                request_id,
                request_type,
                upload_id,
                result,
            } => self.handle_mobile_prompt_file_finished(
                client_id,
                request_id,
                &request_type,
                upload_id.as_deref(),
                result,
            ),
            ServerCommand::AgentQuotaFinished {
                client_id,
                request_id,
                environment_signature,
                result,
            } => self.handle_agent_quota_finished(
                client_id,
                request_id,
                environment_signature,
                result,
            ),
            ServerCommand::AgentQuotaClaudeTuiFinished {
                client_id,
                request_id,
                environment_signature,
                result,
            } => self.handle_agent_quota_claude_tui_finished(
                client_id,
                request_id,
                environment_signature,
                result,
            ),
            ServerCommand::AgentQuotaCodexResetFinished {
                client_id,
                request_id,
                environment_signature,
                result,
            } => self.handle_agent_quota_codex_reset_finished(
                client_id,
                request_id,
                environment_signature,
                result,
            ),
            ServerCommand::HostToolFinished {
                client_id,
                request_id,
                result,
                operation_id,
                skill,
            } => self.handle_host_tool_finished(client_id, request_id, result, operation_id, skill),
            ServerCommand::EmulatorRequestFinished {
                client_id,
                request_id,
                completion,
            } => {
                self.handle_emulator_request_finished(client_id, request_id, completion);
            }
            ServerCommand::EmulatorMaintenanceFinished(completion) => {
                self.handle_emulator_maintenance_finished(completion)
            }
            ServerCommand::RuntimeMutationFinished(finished) => {
                self.handle_runtime_mutation_finished(finished).await
            }
            ServerCommand::OrchestrationWaitTimeout {
                waiter_id,
                effective_timeout_ms,
            } => {
                self.handle_orchestration_wait_timeout(waiter_id, effective_timeout_ms)
                    .await
            }
            ServerCommand::OrchestrationStateWaitPoll(waiter_id) => {
                self.handle_orchestration_state_wait_poll(waiter_id).await
            }
            ServerCommand::OrchestrationDeferredEnter {
                session_id,
                session_instance_id,
                message_ids,
                force_submit,
            } => {
                self.handle_orchestration_deferred_enter(
                    session_id,
                    session_instance_id,
                    message_ids,
                    force_submit,
                )
                .await
            }
            ServerCommand::TerminalStartupInput {
                session_id,
                session_instance_id,
                interactive_shell,
                command,
            } => self.handle_terminal_startup_input(
                session_id,
                session_instance_id,
                interactive_shell,
                command,
            ),
            ServerCommand::TerminalStartupSubmit {
                session_id,
                session_instance_id,
            } => self.handle_terminal_startup_submit(session_id, session_instance_id),
            ServerCommand::TerminalPulseFileChanged {
                workspace_id,
                watcher_generation,
                event_sequence,
            } => self.handle_terminal_pulse_file_changed(
                &workspace_id,
                watcher_generation,
                event_sequence,
            ),
            ServerCommand::TerminalPulseWatcherStarted {
                workspace_id,
                generation,
                result,
            } => {
                self.handle_terminal_pulse_watcher_started(workspace_id, generation, result)
                    .await
            }
            ServerCommand::TerminalPulseWatcherFailed {
                workspace_id,
                watcher_generation,
                error,
            } => {
                self.handle_terminal_pulse_watcher_failed(&workspace_id, watcher_generation, &error)
            }
            ServerCommand::TerminalPulseDue {
                session_id,
                session_instance_id,
                generation,
            } => self.handle_terminal_pulse_due(session_id, session_instance_id, generation),
            ServerCommand::ProjectCloneChanged { job_id } => {
                self.handle_project_clone_changed(job_id)
            }
            ServerCommand::ProjectCloneFinished { job_id } => {
                self.handle_project_clone_finished(job_id).await
            }
            ServerCommand::CoordinatorTick { run_id } => self.handle_coordinator_tick(run_id).await,
            ServerCommand::ResourceSampleTick => self.handle_resource_sample_tick(),
            ServerCommand::ResourceSampleReady { snapshot } => {
                self.handle_resource_sample_ready(snapshot)
            }
            ServerCommand::AutomationTick => self.handle_automation_tick().await,
            ServerCommand::BrowserRequestTimeout { correlation_id } => {
                self.handle_browser_timeout(&correlation_id)
            }
            ServerCommand::CodexMessage { message } => self.handle_codex_message(message).await,
            ServerCommand::CodexProcessExited { reason } => {
                self.handle_codex_process_exited(reason).await
            }
            ServerCommand::CodexMalformed { reason } => self.handle_codex_malformed(reason),
            ServerCommand::CodexPresenceTick => self.handle_codex_presence_tick(),
            ServerCommand::CodexFlush { tab_id } => self.handle_codex_flush(&tab_id).await,
            ServerCommand::CodexAutoResolve {
                tab_id,
                thread_id,
                request_id,
                server_instance,
            } => {
                self.handle_codex_auto_resolve(&tab_id, &thread_id, request_id, server_instance)
                    .await
            }
            ServerCommand::Account(command) => self.handle_account_command(command).await,
            ServerCommand::Push(command) => self.handle_push_command(command),
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
                force_submit: false,
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
        self.coordinators
            .values()
            .any(|coordinator| coordinator.config.coordinator_handle.as_deref() == Some(handle))
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
        force_submit: bool,
    ) {
        let skip_auto_enter = message_ids.is_empty()
            && !force_submit
            && skips_auto_enter(self.agent_presence.agent_type(&session_id));
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
                self.schedule_orchestration_enter(
                    session_id,
                    session_instance_id,
                    message_ids,
                    force_submit,
                );
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
        force_submit: bool,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(DEFERRED_ENTER_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::OrchestrationDeferredEnter {
                session_id,
                session_instance_id,
                message_ids,
                force_submit,
            });
        });
    }

    pub(super) fn queue_orchestration_paste(
        &mut self,
        session_id: &str,
        prompt: &str,
        message_ids: Vec<String>,
        force_submit: bool,
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
                force_submit,
            },
            &paste,
        )
    }

    pub(super) fn queue_orchestration_control(
        &mut self,
        session_id: &str,
        bytes: &[u8],
    ) -> HostResult<()> {
        let session = self
            .sessions
            .get_mut(session_id)
            .filter(|session| session.running())
            .ok_or_else(|| HostError::state(format!("terminal is not running: {session_id}")))?;
        let session_instance_id = session.instance_id();
        session.queue_write(
            PtyWriteCompletion::OrchestrationEnter {
                session_instance_id,
                message_ids: Vec::new(),
            },
            bytes,
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

    async fn dispose(&mut self) {
        if self.disposed {
            return;
        }
        self.disposed = true;
        self.cancel_shutdown_timer();
        self.codex = None;
        if let Some(handle) = self.mobile_gateway.take() {
            handle.abort();
        }
        if let Some(emulators) = self.emulators.as_ref() {
            emulators.lock().await.dispose().await;
        }
        // Closing client handles ends their connection loops.
        self.browser = BrowserBroker::default();
        self.clients.clear();
        let store = self.store.clone();
        let session_ids: Vec<String> = self.sessions.keys().cloned().collect();
        for session_id in session_ids {
            self.terminal_pulses.disarm(&session_id);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::history_store::TerminalHostCheckpoint;
    use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
    use alera_core::runtime::{
        NewOrchestrationTask, OrchestrationDispatchStatus, OrchestrationTaskStatus,
    };
    use std::net::Ipv6Addr;

    async fn account_push_for_test(
        dir: &tempfile::TempDir,
        runtime_store: &RuntimeStore,
    ) -> account_push_state::AccountPushState {
        account_push_state::AccountPushState::new(dir.path().to_path_buf(), runtime_store.clone())
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn stale_ssh_bootstrap_progress_is_not_broadcast() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let (handle, mut out_rx) = ClientHandle::test_channels();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
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
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::from([(1, ClientState::local(handle, true))]),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::new(),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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
        let actor = actor_test_harness::test_actor(&dir, HashMap::new(), HashMap::new()).await;
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
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::new(),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
            inbox,
            next_client_id: Arc::new(AtomicU64::new(1)),
            mobile_gateway: None,
            shutdown_gen: 0,
            disposed: false,
        };

        let response = actor
            .orchestration_run_stop(&json!({
                "id": run.id,
                "actor": "coord",
                "reason": "maintenance"
            }))
            .await
            .unwrap();
        assert_eq!(response["runId"], json!(run.id));
        assert_eq!(response["status"], json!("stopped"));
        assert!(actor
            .runtime_store
            .active_orchestration_coordinator_run()
            .await
            .unwrap()
            .is_none());
        let stopped = actor
            .runtime_store
            .orchestration_coordinator_run_by_id(&run.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(stopped.stop_reason.as_deref(), Some("maintenance"));
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
                run_id: None,
                workspace_id: "workspace-1".to_string(),
                coordinator_handle: "coord".to_string(),
                result_schema: None,
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
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::new(),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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
                run_id: None,
                workspace_id: "workspace-1".to_string(),
                coordinator_handle: "coord".to_string(),
                result_schema: None,
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
                output_stream_bytes: 0,
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
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::from([("term-1".to_string(), session)]),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::new(),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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
                run_id: None,
                workspace_id: "workspace-1".to_string(),
                coordinator_handle: "coord".to_string(),
                result_schema: None,
            })
            .await
            .unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let (handle, _control_out_rx) = ClientHandle::test_channels();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::from([(1, ClientState::local(handle, false))]),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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
    async fn last_app_client_disconnect_preserves_host_agent_presence() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel();
        let (first_app_handle, _first_app_rx) = ClientHandle::test_channels();
        let (second_app_handle, _second_app_rx) = ClientHandle::test_channels();
        let (cli_handle, _cli_rx) = ClientHandle::test_channels();
        let mut actor = ServerActor {
            runtime_dir: dir.path().to_path_buf(),
            control_file_path: dir.path().join("runtime-host.json"),
            token: "token".to_string(),
            config: TerminalHostConfig::default(),
            store,
            runtime_store: runtime_store.clone(),
            automation_wake: Arc::new(Notify::new()),
            automations_active: false,
            sessions: HashMap::new(),
            ssh_bootstrap_jobs: HashMap::new(),
            project_clone_jobs: HashMap::new(),
            managed_workspace_jobs: 0,
            emulator_requests: Default::default(),
            agent_quota_cache: None,
            account_push: account_push_for_test(&dir, &runtime_store).await,
            clients: HashMap::from([
                (1, ClientState::local(first_app_handle, true)),
                (2, ClientState::local(second_app_handle, true)),
                (3, ClientState::local(cli_handle, false)),
            ]),
            mobile_prompt_file_uploads: HashMap::new(),
            pending_output_writes: HashMap::new(),
            agent_presence: AgentPresenceRegistry::default(),
            orchestration_waiters: MessageWaiterRegistry::default(),
            orchestration_delivery_in_flight: HashSet::new(),
            orchestration_delivery_backpressured: HashSet::new(),
            orchestration_activity_last_recorded: HashMap::new(),
            coordinators: HashMap::new(),
            resources: ResourceMonitorState::default(),
            terminal_pulses: Default::default(),
            browser: BrowserBroker::default(),
            emulators: None,
            codex: None,
            codex_presence: HashMap::new(),
            codex_presence_scheduled: false,
            codex_pending_messages: HashMap::new(),
            codex_flush_scheduled: HashSet::new(),
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

        assert!(actor.agent_presence.is_injection_ready("term-1"));
    }
}
