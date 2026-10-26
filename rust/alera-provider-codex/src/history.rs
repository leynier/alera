use crate::provider::CodexProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::*;
use serde_json::{json, Value};

impl<T: JsonTransport> CodexProvider<T> {
    pub(crate) async fn start_native_session(
        &mut self,
        input: SessionStartInput,
        method: &str,
        native_source: Option<&str>,
        last_turn_id: Option<&str>,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Codex provider supports one session per connection".into(),
            ));
        }
        // Validate options before startup or publishing a pending identity.
        let mut params = self.thread_params(&input)?;
        if method == "thread/fork" {
            params.remove("lastTurnId");
            params.remove("path");
        }
        if let Some(source) = native_source {
            params.insert("threadId".into(), Value::String(source.into()));
        }
        if let Some(id) = last_turn_id {
            params.insert("lastTurnId".into(), Value::String(id.into()));
        }
        self.pending_thread_id = Some(input.thread_id.clone());
        let response = async {
            self.initialize().await?;
            self.call(method, Value::Object(params)).await
        }
        .await;
        self.pending_thread_id = None;
        let response = response?;
        let native_thread_id = Self::decode_thread_id(&response)?;
        if method == "thread/fork" && native_source == Some(native_thread_id.as_str()) {
            return Err(ProviderError::Protocol(
                "Codex fork returned its source thread id".into(),
            ));
        }
        self.history_mode = response
            .get("thread")
            .and_then(|thread| thread.get("historyMode"))
            .and_then(Value::as_str)
            .map(str::to_owned);
        self.session_effort = reasoning_effort(&input.options)?
            .map(str::to_owned)
            .or_else(|| {
                response
                    .get("reasoningEffort")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
            });
        let defaults = crate::policy::runtime_defaults(input.runtime_mode);
        self.runtime_mode = input.runtime_mode;
        self.approval_policy = Some(
            input
                .approval_policy
                .or(self.config.approval_policy)
                .unwrap_or(defaults.approval_policy),
        );
        self.sandbox_mode = Some(
            input
                .sandbox_mode
                .or(self.config.sandbox_mode)
                .unwrap_or(defaults.sandbox_mode),
        );
        let session = ProviderSession {
            provider: ProviderKind::Codex,
            provider_instance_id: self.config.instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id,
            status: if self.pending_requests.is_empty() {
                SessionStatus::Ready
            } else {
                SessionStatus::Waiting
            },
            model: input.model.or_else(|| self.config.model.clone()),
            cwd: input.cwd.or_else(|| self.config.cwd.clone()),
            active_turn_id: None,
        };
        self.session = Some(session);
        self.queue_session_skills().await;
        Ok(self.session.clone().expect("the session was just started"))
    }

    pub(crate) async fn fork_native(
        &mut self,
        input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        input.validate()?;
        let last_turn = match &input.boundary {
            Some(NativeForkBoundary::Message(_)) => {
                return Err(ProviderError::Unsupported(
                    "Codex forks require a native turn boundary".into(),
                ))
            }
            Some(NativeForkBoundary::Turn(id)) => Some(id.as_str()),
            None => None,
        };
        let session = self
            .start_native_session(
                input.session,
                "thread/fork",
                Some(&input.source_native_thread_id),
                last_turn,
            )
            .await?;
        Ok(NativeForkResult {
            native_thread_id: Some(session.native_thread_id.clone()),
            session,
            source_native_thread_id: input.source_native_thread_id,
            boundary: input.boundary,
        })
    }

    pub(crate) async fn rollback_native(
        &mut self,
        input: NativeRollbackInput,
    ) -> Result<NativeRollbackResult, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        let session = self.idle_history_session(&input.thread_id)?;
        let (method, params) = match &input.boundary {
            NativeRollbackBoundary::RemoveTurns(count) => {
                if self.history_mode.as_deref() == Some("paginated") {
                    return Err(ProviderError::Unsupported(
                        "paginated Codex history requires a native BeforeTurn boundary".into(),
                    ));
                }
                (
                    "thread/rollback",
                    json!({"threadId":session.native_thread_id,"numTurns":count}),
                )
            }
            NativeRollbackBoundary::BeforeTurn(id) => {
                if self.history_mode.as_deref() != Some("paginated") {
                    return Err(ProviderError::Unsupported(
                        "BeforeTurn requires advertised paginated Codex history".into(),
                    ));
                }
                (
                    "thread/revert",
                    json!({"threadId":session.native_thread_id,"beforeTurnId":id}),
                )
            }
        };
        let response = self.call(method, params).await?;
        if Self::decode_thread_id(&response)? != session.native_thread_id {
            return Err(ProviderError::Protocol(
                "Codex rollback returned a different native thread".into(),
            ));
        }
        Ok(NativeRollbackResult {
            thread_id: input.thread_id,
            native_thread_id: session.native_thread_id,
            boundary: input.boundary,
            native_response: response,
        })
    }

    fn idle_history_session(&self, thread_id: &str) -> Result<ProviderSession, ProviderError> {
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start a Codex session first".into()))?;
        if session.thread_id != thread_id {
            return Err(ProviderError::Validation(
                "history threadId does not match session".into(),
            ));
        }
        if session.active_turn_id.is_some()
            || session.status != SessionStatus::Ready
            || self.terminal_event_pending
            || !self.pending_requests.is_empty()
        {
            return Err(ProviderError::InvalidState(
                "native history operations require a settled Codex session".into(),
            ));
        }
        Ok(session)
    }

    pub(crate) async fn steer_native(
        &mut self,
        input: TurnInput,
        expected_turn_id: &str,
    ) -> Result<(), ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start a Codex session first".into()))?;
        if session.thread_id != input.thread_id
            || expected_turn_id.trim().is_empty()
            || session.active_turn_id.as_deref() != Some(expected_turn_id)
            || self.terminal_event_pending
        {
            return Err(ProviderError::InvalidState(
                "steering requires the exact active native Codex turn".into(),
            ));
        }
        if input.model.is_some()
            || input.interaction_mode != InteractionMode::Default
            || input.options.keys().any(|key| key != "clientUserMessageId")
        {
            return Err(ProviderError::Unsupported(
                "Codex steering cannot change active turn settings".into(),
            ));
        }
        let values = crate::rpc::native_input(&input)?;
        let mut params = json!({"threadId":session.native_thread_id,"expectedTurnId":expected_turn_id,"input":values});
        if let Some(id) = input.options.get("clientUserMessageId") {
            if !id.as_str().is_some_and(|id| !id.trim().is_empty()) {
                return Err(ProviderError::Validation(
                    "clientUserMessageId must be a nonempty string".into(),
                ));
            }
            params["clientUserMessageId"] = id.clone();
        }
        let response = self.call("turn/steer", params).await?;
        if response.get("turnId").and_then(Value::as_str) != Some(expected_turn_id) {
            return Err(ProviderError::Protocol(
                "Codex steer acknowledgement does not match expectedTurnId".into(),
            ));
        }
        Ok(())
    }
}
