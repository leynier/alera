use crate::config::MuseProviderConfig;
use crate::events::{map_frame, MappedFrame, PendingRequest};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::*;
use muse_agent_sdk::{MuseClient, MuseClientOptions, MuseFrame, MuseSdkError};
use serde_json::{Map, Value};
use std::collections::{HashMap, VecDeque};

pub struct MuseProvider {
    pub(crate) config: MuseProviderConfig,
    pub(crate) transport: Option<Box<dyn JsonTransport>>,
    pub(crate) client: Option<MuseClient>,
    pub(crate) initialized: bool,
    pub(crate) granted_capabilities: Vec<String>,
    pub(crate) closed: bool,
    pub(crate) session: Option<ProviderSession>,
    pub(crate) pending: HashMap<RequestId, PendingRequest>,
    pub(crate) queued_events: VecDeque<ProviderEvent>,
}

impl MuseProvider {
    pub fn new(config: MuseProviderConfig) -> Result<Self, ProviderError> {
        Ok(Self {
            config,
            transport: None,
            client: None,
            initialized: false,
            granted_capabilities: Vec::new(),
            closed: false,
            session: None,
            pending: HashMap::new(),
            queued_events: VecDeque::new(),
        })
    }

    pub fn with_transport<T: JsonTransport + 'static>(
        transport: T,
        config: MuseProviderConfig,
    ) -> Result<Self, ProviderError> {
        let mut provider = Self::new(config)?;
        provider.transport = Some(Box::new(transport));
        Ok(provider)
    }

    pub fn with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        config: MuseProviderConfig,
    ) -> Result<Self, ProviderError> {
        let mut provider = Self::new(config)?;
        provider.transport = Some(transport);
        Ok(provider)
    }

    pub(crate) fn sdk_error(error: MuseSdkError) -> ProviderError {
        match error {
            MuseSdkError::Transport(error) => ProviderError::Protocol(error.to_string()),
            MuseSdkError::Protocol(message) => ProviderError::Protocol(message),
            MuseSdkError::Rpc {
                code,
                message,
                data,
            } => ProviderError::Rpc {
                code,
                message,
                data,
            },
            MuseSdkError::Timeout { operation } => ProviderError::Timeout { operation },
            MuseSdkError::Closed => ProviderError::Closed,
            MuseSdkError::InvalidState(message) => ProviderError::InvalidState(message),
            MuseSdkError::Unsupported(message) => ProviderError::Unsupported(message),
        }
    }

    pub(crate) fn options(&self) -> MuseClientOptions {
        self.config.options.clone()
    }

    pub(crate) fn has_granted_capability(&self, capability: &str) -> bool {
        self.granted_capabilities
            .iter()
            .any(|granted| granted == capability)
    }

    pub(crate) fn session_ref(&self) -> Result<&ProviderSession, ProviderError> {
        self.session
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("Muse session has not started".into()))
    }

    pub(crate) fn queue_event(&mut self, event: ProviderEvent) -> Result<(), ProviderError> {
        event.validate()?;
        self.queued_events.push_back(event);
        Ok(())
    }

    pub(crate) fn event_session_started(&self, session: &ProviderSession) -> ProviderEvent {
        let mut event = ProviderEvent::new(
            ProviderKind::Other("muse".into()),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::SessionStarted,
            serde_json::json!({"resume": session.native_thread_id}),
            Some(RawEvent {
                source: "muse.msp".into(),
                method: Some("session/start".into()),
                message_type: Some("session".into()),
                payload: serde_json::json!({"sessionId": session.native_thread_id}),
            }),
        );
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: None,
        });
        event
    }

    pub(crate) fn event_thread_started(&self, session: &ProviderSession) -> ProviderEvent {
        let mut event = ProviderEvent::new(
            ProviderKind::Other("muse".into()),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::ThreadStarted,
            serde_json::json!({"providerThreadId": session.native_thread_id}),
            Some(RawEvent {
                source: "muse.msp".into(),
                method: Some("session/start".into()),
                message_type: Some("thread".into()),
                payload: serde_json::json!({"sessionId": session.native_thread_id}),
            }),
        );
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: None,
        });
        event
    }

    pub(crate) fn approval_mode(
        input: &SessionStartInput,
    ) -> Result<Option<&'static str>, ProviderError> {
        match input.sandbox_mode {
            None | Some(SandboxMode::WorkspaceWrite) => {}
            Some(SandboxMode::ReadOnly) => {
                return Err(ProviderError::Unsupported(
                    "Muse does not expose a read-only MSP sandbox".into(),
                ))
            }
            Some(SandboxMode::DangerFullAccess) => {
                return Err(ProviderError::Unsupported(
                    "Muse MSP does not expose a danger-full-access sandbox".into(),
                ))
            }
        }
        if input.approval_policy.is_some() && input.runtime_mode != RuntimeMode::ApprovalRequired {
            return Err(ProviderError::Validation(
                "approvalPolicy conflicts with runtimeMode".into(),
            ));
        }
        if let Some(policy) = input.approval_policy {
            return Ok(Some(match policy {
                ApprovalPolicy::Untrusted => "denyUnmatched",
                ApprovalPolicy::OnFailure | ApprovalPolicy::OnRequest => "promptUnmatched",
                ApprovalPolicy::Never => "allowAll",
            }));
        }
        Ok(Some(match input.runtime_mode {
            RuntimeMode::ApprovalRequired => "promptUnmatched",
            RuntimeMode::Auto => "promptUnmatched",
            RuntimeMode::FullAccess => "allowAll",
            RuntimeMode::AutoAcceptEdits => {
                return Err(ProviderError::Unsupported(
                    "Muse MSP has no accept-edits-only approval mode".into(),
                ))
            }
        }))
    }

    pub(crate) async fn handle_frame(
        &mut self,
        frame: MuseFrame,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let session = self.session_ref()?.clone();
        let mapped = map_frame(
            frame,
            &self.config.provider_instance_id,
            &session.thread_id,
            session.active_turn_id.as_deref(),
        );
        let Some(mapped) = mapped else {
            return Ok(None);
        };
        match mapped {
            MappedFrame::Event(event) => {
                if matches!(event.kind, EventKind::RequestResolved) {
                    if let Some(id) = event.payload.get("requestId") {
                        let request_id = match id {
                            Value::String(value) => RequestId::String(value.clone()),
                            Value::Number(value) => value
                                .as_i64()
                                .map(RequestId::Integer)
                                .unwrap_or_else(|| RequestId::String(value.to_string())),
                            _ => RequestId::String(id.to_string()),
                        };
                        self.pending.remove(&request_id);
                    }
                }
                match &event.kind {
                    EventKind::SessionExited => {
                        if let Some(session) = &mut self.session {
                            session.status = SessionStatus::Stopped;
                            session.active_turn_id = None;
                        }
                        self.pending.clear();
                    }
                    EventKind::SessionStateChanged | EventKind::ThreadStateChanged => {
                        if let Some(session) = &mut self.session {
                            match event.payload.get("state").and_then(Value::as_str) {
                                Some("active" | "running") => {
                                    session.status = SessionStatus::Running;
                                }
                                Some("idle" | "ready") => {
                                    session.status = SessionStatus::Ready;
                                }
                                Some("error") => {
                                    session.status = SessionStatus::Error;
                                }
                                Some("closed" | "stopped") => {
                                    session.status = SessionStatus::Stopped;
                                    session.active_turn_id = None;
                                }
                                _ => {}
                            }
                        }
                    }
                    _ => {}
                }
                if event.kind == EventKind::TurnCompleted {
                    let ended_turn = event.turn_id.as_deref();
                    let active_turn = self
                        .session
                        .as_ref()
                        .and_then(|session| session.active_turn_id.as_deref());
                    if ended_turn.is_some() && ended_turn == active_turn {
                        if let Some(session) = &mut self.session {
                            session.status = SessionStatus::Ready;
                            session.active_turn_id = None;
                        }
                        if let Some(ended_turn) = ended_turn {
                            self.pending.retain(|_, pending| {
                                pending.turn_id.as_deref() != Some(ended_turn)
                                    || pending_survives_terminal(pending)
                            });
                        }
                    }
                }
                event.validate()?;
                Ok(Some(event))
            }
            MappedFrame::RuntimeRequest { mut event, pending } => {
                if let Some(wire_id) = pending.wire_id.clone() {
                    self.client
                        .as_ref()
                        .ok_or_else(|| {
                            ProviderError::InvalidState("Muse client unavailable".into())
                        })?
                        .respond_server_request(wire_id, Value::Object(Map::new()))
                        .await
                        .map_err(Self::sdk_error)?;
                }
                event
                    .provider_refs
                    .get_or_insert_with(ProviderRefs::default)
                    .provider_request_id = Some(pending.logical_id.to_string());
                event.validate()?;
                self.pending.insert(pending.logical_id.clone(), pending);
                Ok(Some(event))
            }
        }
    }
}

fn pending_survives_terminal(pending: &PendingRequest) -> bool {
    pending.params.get("subagentOrigin").is_some()
        || pending
            .params
            .get("subject")
            .and_then(|subject| subject.get("kind"))
            .and_then(Value::as_str)
            == Some("workflow")
        || pending.params.get("workflow").is_some()
}
