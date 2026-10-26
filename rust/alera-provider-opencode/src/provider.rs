use crate::config::OpenCodeProviderConfig;
use crate::events;
use alera_provider_protocol::{
    EventKind, InterruptInput, Provider, ProviderCapabilities, ProviderError, ProviderEvent,
    ProviderKind, ProviderSession, RequestKind, RuntimeResponse, SessionStartInput, SessionStatus,
    TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use opencode_agent_sdk::{
    ClientConfig, HttpTransport, OpenCodeClient, OpenCodeEvent, SessionRequest,
};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet, VecDeque};
use std::future::Future;
use std::time::Duration;

pub(crate) struct PendingRequest {
    pub native_id: String,
    pub kind: RequestKind,
    pub thread_id: String,
    pub native_session_id: String,
    pub turn_id: Option<String>,
    pub questions: Vec<alera_provider_protocol::UserInputQuestion>,
    pub is_form: bool,
}

pub(crate) fn opencode_kind() -> ProviderKind {
    ProviderKind::Other("opencode".into())
}

pub(crate) async fn timed<T, F>(
    timeout: Duration,
    operation: &str,
    future: F,
) -> Result<T, ProviderError>
where
    F: Future<Output = Result<T, opencode_agent_sdk::OpenCodeError>>,
{
    tokio::time::timeout(timeout, future)
        .await
        .map_err(|_| ProviderError::Timeout {
            operation: operation.into(),
        })?
        .map_err(crate::config::map_open_code_error)
}

#[derive(Debug, Clone)]
pub(crate) struct ActiveTurn {
    pub id: String,
    pub native_message_id: Option<String>,
    pub interrupted: bool,
}

/// OpenCode HTTP/SSE provider adapter.
pub struct OpenCodeProvider<T: HttpTransport> {
    pub(crate) client: OpenCodeClient<T>,
    pub(crate) config: OpenCodeProviderConfig,
    pub(crate) initialized: bool,
    pub(crate) closed: bool,
    pub(crate) session: Option<ProviderSession>,
    pub(crate) active_turn: Option<ActiveTurn>,
    pub(crate) pending: HashMap<String, PendingRequest>,
    pub(crate) queued_events: VecDeque<ProviderEvent>,
    pub(crate) next_turn: u64,
    pub(crate) scoped_mcp_servers: Vec<String>,
    pub(crate) mcp_tool_ids: HashSet<String>,
    pub(crate) native_parts: crate::native_parts::NativeParts,
}

impl<T: HttpTransport> OpenCodeProvider<T> {
    pub fn new(transport: T, config: OpenCodeProviderConfig) -> Self {
        let client_config: ClientConfig = config.client_config();
        Self {
            client: OpenCodeClient::new(transport, client_config),
            config,
            initialized: false,
            closed: false,
            session: None,
            active_turn: None,
            pending: HashMap::new(),
            queued_events: VecDeque::new(),
            next_turn: 0,
            scoped_mcp_servers: Vec::new(),
            mcp_tool_ids: HashSet::new(),
            native_parts: Default::default(),
        }
    }

    pub fn config(&self) -> &OpenCodeProviderConfig {
        &self.config
    }

    pub fn config_mut(&mut self) -> &mut OpenCodeProviderConfig {
        &mut self.config
    }

    pub fn client(&self) -> &OpenCodeClient<T> {
        &self.client
    }

    pub fn client_mut(&mut self) -> &mut OpenCodeClient<T> {
        &mut self.client
    }

    pub fn into_transport(self) -> T {
        self.client.into_transport()
    }

    pub(crate) fn provider_kind() -> ProviderKind {
        opencode_kind()
    }

    pub(crate) fn thread_id(&self) -> Result<String, ProviderError> {
        self.session
            .as_ref()
            .map(|session| session.thread_id.clone())
            .ok_or_else(|| ProviderError::InvalidState("start an OpenCode session first".into()))
    }

    pub(crate) fn event_from_sdk(
        &mut self,
        event: OpenCodeEvent,
    ) -> Result<ProviderEvent, ProviderError> {
        events::map_event(self, event)
    }

    pub(crate) fn ensure_open(&self) -> Result<(), ProviderError> {
        if self.closed {
            Err(ProviderError::Closed)
        } else {
            Ok(())
        }
    }

    fn next_turn_id(&mut self) -> String {
        self.next_turn = self.next_turn.saturating_add(1);
        format!("turn:opencode:{}", self.next_turn)
    }
}

#[async_trait]
impl<T: HttpTransport> Provider for OpenCodeProvider<T> {
    fn kind(&self) -> ProviderKind {
        Self::provider_kind()
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            mcp_injection: if self.config.server_url.is_none() {
                alera_provider_protocol::McpInjectionCapabilities {
                    stdio: true,
                    http: true,
                }
            } else {
                Default::default()
            },
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: false,
            streaming: true,
            native_turn_ids: false,
            multiple_threads: false,
            model_switch: true,
            steer: false,
            snapshot: false,
            rollback: false,
            fork: false,
        }
    }

    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.ensure_open()?;
        self.initialized = true;
        Ok(())
    }

    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        self.ensure_open()?;
        input.validate()?;
        crate::config::validate_session_options(&input)?;
        crate::mcp::validate_input(
            self.config.server_url.as_deref(),
            self.config.support_table(),
            &input,
        )?;
        if !self.initialized {
            return Err(ProviderError::InvalidState(
                "initialize must be called before start_session".into(),
            ));
        }
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "OpenCode provider supports one session per connection".into(),
            ));
        }
        let timeout = self.config.request_timeout;
        if !input.mcp_servers.is_empty() {
            let directory = input
                .cwd
                .as_ref()
                .map(|path| path.to_string_lossy().into_owned())
                .or_else(|| self.client.config().directory.clone());
            self.client.set_directory(directory);
        }
        crate::mcp::preflight(self, &input.mcp_servers).await?;
        let permission_rules = crate::mcp::permission_rules(&input.mcp_servers);
        let native = if let Some(resume) = input.resume_thread_id.as_deref() {
            let native = timed(
                timeout,
                "session.resume",
                self.client.resume_session(resume),
            )
            .await?;
            if self.config.generation == crate::config::OpenCodeGeneration::V2
                && !permission_rules.is_empty()
            {
                timed(
                    timeout,
                    "session.permissions",
                    self.client
                        .update_session_permissions(&native.id, permission_rules.clone()),
                )
                .await?;
            }
            native
        } else {
            timed(
                timeout,
                "session.create",
                self.client.create_session(SessionRequest {
                    title: Some(input.thread_id.clone()),
                    directory: input
                        .cwd
                        .as_ref()
                        .map(|path| path.to_string_lossy().into_owned()),
                    parent_id: None,
                    permissions: if self.config.generation == crate::config::OpenCodeGeneration::V2
                        && !permission_rules.is_empty()
                    {
                        Some(permission_rules)
                    } else {
                        None
                    },
                }),
            )
            .await?
        };
        if let Some(cwd) = input.cwd.as_ref() {
            self.client
                .set_directory(Some(cwd.to_string_lossy().into_owned()));
        }
        let scoped_mcp_servers = crate::mcp::install(self, &input.mcp_servers).await?;
        if let Err(error) = timed(timeout, "event.subscribe", self.client.start_events()).await {
            let mut cleanup = scoped_mcp_servers.clone();
            let cleanup_error = crate::mcp::cleanup(self, &mut cleanup).await;
            return Err(crate::mcp::combine_errors(error, cleanup_error));
        }
        let session = ProviderSession {
            provider: Self::provider_kind(),
            provider_instance_id: self.config.provider_instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id: native.id,
            status: SessionStatus::Ready,
            model: input.model.or_else(|| self.config.model.clone()),
            cwd: input.cwd.or_else(|| self.config.cwd.clone()),
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        self.scoped_mcp_servers = scoped_mcp_servers;
        let mut started = ProviderEvent::new(
            Self::provider_kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::ThreadStarted,
            json!({ "providerThreadId": session.native_thread_id }),
            None,
        );
        started.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: None,
        });
        started.validate()?;
        self.queued_events.push_back(started);
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        self.ensure_open()?;
        input.validate()?;
        crate::config::validate_turn_options(&input)?;
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start an OpenCode session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::InvalidState(
                "turn threadId does not match the active OpenCode session".into(),
            ));
        }
        if self.active_turn.is_some() {
            return Err(ProviderError::InvalidState(
                "cannot start an OpenCode turn while another turn is active".into(),
            ));
        }
        let parts = crate::config::prompt_parts(&input)?;
        let skills = self.mentioned_skills(&input.input).await;
        let turn_id = self.next_turn_id();
        let model = input.model.clone().or_else(|| session.model.clone());
        let mut started = ProviderEvent::new(
            Self::provider_kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::TurnStarted,
            model
                .as_ref()
                .map(|model| json!({ "model": model }))
                .unwrap_or_else(|| json!({})),
            None,
        );
        let requested_message_id = crate::native_message_id::native_message_id(&started);
        self.active_turn = Some(ActiveTurn {
            id: turn_id.clone(),
            native_message_id: Some(requested_message_id.clone()),
            interrupted: false,
        });
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Running;
            session.active_turn_id = Some(turn_id.clone());
        }
        let response = match timed(
            self.config.request_timeout,
            "session.prompt",
            self.client.prompt_parts_with_skills(
                &session.native_thread_id,
                parts,
                model.as_deref(),
                Some(&requested_message_id),
                &skills,
            ),
        )
        .await
        {
            Ok(response) => response,
            Err(error) => {
                self.active_turn = None;
                if let Some(session) = self.session.as_mut() {
                    session.status = SessionStatus::Ready;
                    session.active_turn_id = None;
                }
                return Err(error);
            }
        };
        let native_message_id = response
            .get("id")
            .or_else(|| response.get("messageID"))
            .and_then(Value::as_str)
            .map(str::to_owned)
            .or(Some(requested_message_id));
        self.native_parts.start_turn(native_message_id.clone());
        if let Some(active) = self.active_turn.as_mut() {
            active.native_message_id = native_message_id.clone();
        }
        started.turn_id = Some(turn_id.clone());
        started.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: native_message_id.clone(),
            provider_item_id: native_message_id.clone(),
            provider_request_id: None,
        });
        started.validate()?;
        self.queued_events.push_back(started);
        Ok(TurnStartResult {
            thread_id: session.thread_id,
            turn_id,
            native_turn_id: native_message_id,
        })
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start an OpenCode session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::InvalidState(
                "interrupt threadId does not match the active OpenCode session".into(),
            ));
        }
        let active = self
            .active_turn
            .as_mut()
            .ok_or_else(|| ProviderError::InvalidState("no active OpenCode turn".into()))?;
        if let Some(turn_id) = input.turn_id {
            if turn_id != active.id {
                return Err(ProviderError::InvalidState(
                    "interrupt turnId does not match the active turn".into(),
                ));
            }
        }
        timed(
            self.config.request_timeout,
            "session.abort",
            self.client.abort(&session.native_thread_id),
        )
        .await?;
        active.interrupted = true;
        let mut deferred = std::mem::take(&mut self.queued_events);
        if deferred.iter().any(|event| {
            matches!(
                event.kind,
                EventKind::TurnCompleted | EventKind::TurnAborted
            )
        }) {
            self.queued_events.extend(deferred);
            return Ok(());
        }
        loop {
            let next = match timed(
                self.config.request_timeout,
                "event.next_after_abort",
                self.client.next_event(),
            )
            .await
            {
                Ok(next) => next,
                Err(error) => {
                    self.queued_events.extend(deferred);
                    return Err(error);
                }
            };
            let Some(event) = next else {
                self.queued_events.extend(deferred);
                return Err(ProviderError::Protocol(
                    "OpenCode event stream closed before interruption completed".into(),
                ));
            };
            let mapped = match self.event_from_sdk(event) {
                Ok(mapped) => mapped,
                Err(error) => {
                    self.queued_events.extend(deferred);
                    return Err(error);
                }
            };
            let terminal = matches!(
                mapped.kind,
                EventKind::TurnCompleted | EventKind::TurnAborted
            );
            deferred.push_back(mapped);
            if terminal {
                self.queued_events.extend(deferred);
                return Ok(());
            }
        }
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        crate::runtime_response::respond(self, response).await
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.ensure_open()?;
        if let Some(event) = self.queued_events.pop_front() {
            return Ok(Some(event));
        }
        let Some(event) = self
            .client
            .next_event()
            .await
            .map_err(crate::config::map_open_code_error)?
        else {
            return Ok(None);
        };
        Ok(Some(self.event_from_sdk(event)?))
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        crate::mcp::close(self, self.config.request_timeout).await
    }
}
