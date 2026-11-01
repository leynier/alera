#[path = "background_wait.rs"]
mod background_wait;
#[path = "callbacks.rs"]
mod callbacks;
#[path = "canonical_payload.rs"]
mod canonical_payload;
#[path = "compaction.rs"]
mod compaction;
#[path = "context_usage.rs"]
mod context_usage;
#[path = "failure.rs"]
mod failure;
#[path = "history.rs"]
mod history;
#[path = "lifecycle.rs"]
mod lifecycle;
#[path = "lineage.rs"]
mod lineage;
#[path = "mapping.rs"]
mod mapping;
#[path = "mapping_stream.rs"]
mod mapping_stream;
#[path = "mcp.rs"]
mod mcp;
#[path = "permission_mode.rs"]
mod permission_mode;
#[path = "progress_text.rs"]
mod progress_text;
#[path = "reasoning_effort.rs"]
mod reasoning_effort;
#[path = "request_events.rs"]
mod request_events;
#[path = "runtime_response.rs"]
mod runtime_response;
#[path = "slash_commands.rs"]
mod slash_commands;
#[path = "system_notices.rs"]
mod system_notices;
#[path = "task_list.rs"]
mod task_list;
#[path = "turn_signals.rs"]
mod turn_signals;
#[path = "turns.rs"]
mod turns;
#[path = "user_messages.rs"]
mod user_messages;
#[path = "workflow.rs"]
mod workflow;

use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    ApprovalPolicy, EventKind, InteractionMode, InterruptInput, Provider, ProviderCapabilities,
    ProviderError, ProviderEvent, ProviderKind, ProviderSession, RawEvent, RequestKind,
    RuntimeMode, RuntimeRequest, RuntimeResponse, SandboxMode, SessionStartInput, SessionStatus,
    StreamKind, TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use callbacks::{install_callbacks, PendingResponse, RequestNotice};
use claude_agent_sdk::{ClaudeAgentOptions, ClaudeClient, ClaudeSdkError};
use failure::sdk_error;
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};

const EMPTY_SESSION_NOTICE: &str =
    "The earlier Claude session never saved a message, so a new session continues this chat.";
const MESSAGE_SOURCE: &str = "claude.sdk.message";
const PERMISSION_SOURCE: &str = "claude.sdk.permission";
// SDK MCP control frames share the SDK message source.
const MCP_SOURCE: &str = MESSAGE_SOURCE;

/// Configuration shared by process-backed and injected-transport providers.
#[derive(Clone)]
pub struct ClaudeProviderConfig {
    pub provider_instance_id: String,
    pub options: ClaudeAgentOptions,
}

impl Default for ClaudeProviderConfig {
    fn default() -> Self {
        Self {
            provider_instance_id: "claude".into(),
            options: ClaudeAgentOptions::default(),
        }
    }
}

/// A provider adapter backed by Claude Code's stream-json SDK.
pub struct ClaudeProvider {
    config: ClaudeProviderConfig,
    transport: Option<Box<dyn JsonTransport>>,
    client: Option<ClaudeClient>,
    initialized: bool,
    closed: bool,
    session: Option<ProviderSession>,
    active_turn_id: Arc<Mutex<Option<String>>>,
    thread_id: Arc<Mutex<Option<String>>>,
    request_tx: mpsc::Sender<RequestNotice>,
    request_rx: mpsc::Receiver<RequestNotice>,
    pending: Arc<Mutex<HashMap<String, PendingResponse>>>,
    next_request: Arc<AtomicU64>,
    next_turn: u64,
    queued_events: VecDeque<ProviderEvent>,
    streamed_text_message_ids: std::collections::HashSet<String>,
    streamed_thinking_message_ids: std::collections::HashSet<String>,
    streamed_text_unscoped: bool,
    streamed_thinking_unscoped: bool,
    stream_message_id: Option<String>,
    open_items: HashMap<String, String>,
    stream_items: HashMap<String, String>,
    session_effort: Option<String>,
    // Launch permission mode, its Full Access step-down and the mode plan turns return to.
    permission: permission_mode::LaunchPermission,
    plan_interaction: Arc<AtomicBool>,
    file_checkpointing: bool,
    fork_source_native_thread_id: Option<String>,
    pending_user_prompt: Option<user_messages::UserPromptCorrelation>,
    turn_failure: failure::TurnFailureEvidence,
    // `initialize` described the commands, so `system/init` names are ignored.
    described_commands: bool,
    background_tasks: background_wait::BackgroundTasks,
    workflow_tasks: workflow::WorkflowTasks,
    turn_signals: turn_signals::TurnSignals,
    task_tools: task_list::TaskTools,
    context_usage: context_usage::ContextUsage,
}

#[async_trait]
impl Provider for ClaudeProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Claude
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            mcp_injection: alera_provider_protocol::McpInjectionCapabilities {
                stdio: true,
                http: true,
            },
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: false,
            streaming: true,
            native_turn_ids: false,
            multiple_threads: false,
            model_switch: false,
            steer: false,
            snapshot: false,
            rollback: false,
            fork: true,
        }
    }

    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }

    fn reasoning_effort_capabilities(
        &self,
    ) -> alera_provider_protocol::ReasoningEffortCapabilities {
        reasoning_effort::capabilities()
    }

    fn native_history_capabilities(&self) -> alera_provider_protocol::NativeHistoryCapabilities {
        alera_provider_protocol::NativeHistoryCapabilities {
            file_checkpointing: true,
            fork_at_message: true,
            rewind_files: self.file_checkpointing && self.session.is_some() && !self.closed,
            ..Default::default()
        }
    }

    async fn fork_session(
        &mut self,
        input: alera_provider_protocol::NativeForkInput,
    ) -> Result<alera_provider_protocol::NativeForkResult, ProviderError> {
        self.fork_native(input).await
    }

    async fn rewind_files(
        &mut self,
        input: alera_provider_protocol::NativeRewindFilesInput,
    ) -> Result<alera_provider_protocol::NativeRewindFilesResult, ProviderError> {
        self.rewind_native_files(input).await
    }

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Err(ProviderError::Closed);
        }
        self.initialized = true;
        Ok(())
    }

    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        if !self.initialized {
            return Err(ProviderError::InvalidState(
                "initialize must be called before start_session".into(),
            ));
        }
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Claude provider supports one session at a time".into(),
            ));
        }
        let (mut options, stepped_down) = self.launch_options(&input)?;
        // A session that never saved a message cannot be resumed, so a fresh
        // one continues the chat; its id binds at init.
        let replaced = self.fork_source_native_thread_id.is_none()
            && options.resume.as_deref().is_some_and(|id| {
                crate::claude_session_has_no_conversation(&options.env, options.cwd.as_deref(), id)
            });
        if replaced {
            options.resume = None;
        }
        self.session_effort = options.effort.clone();
        let plan_at_start = options.permission_mode.as_deref() == Some("plan")
            && input.options.get("interactionMode").and_then(Value::as_str) == Some("plan");
        self.plan_interaction.store(plan_at_start, Ordering::SeqCst);
        self.permission =
            permission_mode::LaunchPermission::new(&options, plan_at_start, stepped_down);
        self.file_checkpointing = options.enable_file_checkpointing;
        *self.thread_id.lock().await = Some(input.thread_id.clone());
        let client = if let Some(transport) = self.transport.take() {
            let client =
                ClaudeClient::with_transport(lifecycle::BoxedTransport(transport), options)
                    .map_err(sdk_error)?;
            client.initialize().await.map_err(sdk_error)?;
            client
        } else {
            ClaudeClient::connect(options).await.map_err(sdk_error)?
        };
        self.client = Some(client);
        let native_thread_id = if self.fork_source_native_thread_id.is_some() || replaced {
            format!("pending:{}", input.thread_id)
        } else {
            input
                .resume_thread_id
                .clone()
                .unwrap_or_else(|| format!("pending:{}", input.thread_id))
        };
        let session = ProviderSession {
            provider: ProviderKind::Claude,
            provider_instance_id: self.config.provider_instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id,
            status: SessionStatus::Ready,
            model: input.model.or_else(|| self.config.options.model.clone()),
            cwd: input.cwd.or_else(|| self.config.options.cwd.clone()),
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        self.queue_session_events();
        if replaced {
            let notice = json!({ "message": EMPTY_SESSION_NOTICE });
            self.queue(self.event(
                EventKind::RuntimeWarning,
                notice.clone(),
                self.raw("session", notice),
            ));
        }
        self.queue_initialize_commands();
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        self.send_native_turn(input).await
    }

    async fn await_background_tasks(
        &mut self,
        task_ids: &[String],
        _awaited: bool,
    ) -> Result<Vec<String>, ProviderError> {
        if self.session.is_none() || self.closed {
            return Err(ProviderError::InvalidState(
                "session has not started".into(),
            ));
        }
        // The runtime holds the marks; Claude itself never needs them.
        Ok(self.background_tasks.matching(task_ids))
    }

    async fn stop_subagent(&mut self, task_id: &str) -> Result<(), ProviderError> {
        if self.session.is_none() || self.closed {
            return Err(ProviderError::InvalidState(
                "session has not started".into(),
            ));
        }
        if !self.background_tasks.running_subagent(task_id) {
            return Err(ProviderError::InvalidState(
                "the sub-agent is not running".into(),
            ));
        }
        self.client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("session client is unavailable".into()))?
            .stop_task(task_id)
            .await
            .map_err(sdk_error)
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        let session = self
            .session
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("session has not started".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "interrupt threadId does not match session".into(),
            ));
        }
        let active = self.active_turn_id.lock().await.clone();
        if let Some(turn_id) = &input.turn_id {
            if active.as_deref() != Some(turn_id.as_str()) {
                return Err(ProviderError::Validation(
                    "interrupt turnId does not match active turn".into(),
                ));
            }
        }
        if active.is_none() {
            return Err(ProviderError::InvalidState(
                "no active turn to interrupt".into(),
            ));
        }
        self.client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("session client is unavailable".into()))?
            .interrupt()
            .await
            .map_err(sdk_error)
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.respond_runtime(response).await
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.pending
            .lock()
            .await
            .retain(|_, response| !response.is_closed());
        loop {
            if let Some(event) = self.pop_validated()? {
                return Ok(Some(event));
            }
            if self.closed {
                return Ok(None);
            }
            let message = {
                let client = self
                    .client
                    .as_ref()
                    .ok_or_else(|| ProviderError::InvalidState("session has not started".into()))?;
                let message_future = client.next_message();
                tokio::select! {
                    notice = self.request_rx.recv() => {
                        let Some(notice) = notice else {
                            return Ok(None);
                        };
                        match self.request_opened_event(notice).await? {
                            Some(event) => return Ok(Some(event)),
                            None => continue,
                        }
                    }
                    result = message_future => result.map_err(sdk_error)?,
                }
            };
            if let Some(message) = message {
                let events = self.map_message(message);
                self.queued_events.extend(events);
            } else {
                return Ok(None);
            }
        }
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        self.pending.lock().await.clear();
        self.pending_user_prompt = None;
        self.background_tasks.clear();
        if let Some(client) = &self.client {
            client.close().await.map_err(sdk_error)?;
        } else if let Some(mut transport) = self.transport.take() {
            transport.close().await.map_err(ProviderError::Transport)?;
        }
        if self.session.is_some() {
            self.queue(self.event(
                EventKind::SessionExited,
                json!({
                    "reason": "provider closed",
                    "recoverable": false,
                    "exitKind": "graceful"
                }),
                self.raw("session", json!({ "status": "stopped" })),
            ));
            if let Some(session) = &mut self.session {
                session.status = SessionStatus::Stopped;
                session.active_turn_id = None;
            }
        }
        self.closed = true;
        Ok(())
    }
}
