use super::*;

impl ClaudeProvider {
    /// Construct a process-backed provider. The Claude CLI is spawned when its
    /// first session starts, through the SDK's shared JsonLineProcess.
    pub fn new(config: ClaudeProviderConfig) -> Result<Self, ProviderError> {
        config.options.validate().map_err(sdk_error)?;
        Self::empty(config, None)
    }

    /// Construct a provider using a scripted or otherwise injected transport.
    pub fn with_transport<T: JsonTransport + 'static>(
        transport: T,
        config: ClaudeProviderConfig,
    ) -> Result<Self, ProviderError> {
        config.options.validate().map_err(sdk_error)?;
        Self::empty(config, Some(Box::new(transport)))
    }

    /// Construct with an already boxed shared transport.
    pub fn with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        config: ClaudeProviderConfig,
    ) -> Result<Self, ProviderError> {
        config.options.validate().map_err(sdk_error)?;
        Self::empty(config, Some(transport))
    }

    fn empty(
        config: ClaudeProviderConfig,
        transport: Option<Box<dyn JsonTransport>>,
    ) -> Result<Self, ProviderError> {
        let (request_tx, request_rx) = mpsc::channel(32);
        Ok(Self {
            config,
            transport,
            client: None,
            initialized: false,
            closed: false,
            session: None,
            active_turn_id: Arc::new(Mutex::new(None)),
            thread_id: Arc::new(Mutex::new(None)),
            request_tx,
            request_rx,
            pending: Arc::new(Mutex::new(HashMap::new())),
            next_request: Arc::new(AtomicU64::new(0)),
            next_turn: 0,
            queued_events: VecDeque::new(),
            streamed_text_message_ids: std::collections::HashSet::new(),
            streamed_thinking_message_ids: std::collections::HashSet::new(),
            streamed_text_unscoped: false,
            streamed_thinking_unscoped: false,
            stream_message_id: None,
            open_items: HashMap::new(),
            stream_items: HashMap::new(),
        })
    }

    pub(super) fn build_options(
        &self,
        input: &SessionStartInput,
    ) -> Result<ClaudeAgentOptions, ProviderError> {
        if matches!(input.sandbox_mode, Some(SandboxMode::ReadOnly)) {
            return Err(ProviderError::Unsupported(
                "Claude Code does not expose a read-only filesystem sandbox".into(),
            ));
        }
        if let Some(unsupported) = input
            .options
            .keys()
            .find(|key| !matches!(key.as_str(), "permissionMode" | "interactionMode"))
        {
            return Err(ProviderError::Unsupported(format!(
                "unsupported Claude session option: {unsupported}"
            )));
        }
        let mut options = self.config.options.clone();
        if input.cwd.is_some() {
            options.cwd = input.cwd.clone();
        }
        if input.model.is_some() {
            options.model = input.model.clone();
        }
        if input.resume_thread_id.is_some() {
            options.resume = input.resume_thread_id.clone();
        }
        let interaction_plan =
            input.options.get("interactionMode").and_then(Value::as_str) == Some("plan");
        let requested_danger = matches!(input.sandbox_mode, Some(SandboxMode::DangerFullAccess));
        let requested_full_access = matches!(input.runtime_mode, RuntimeMode::FullAccess);
        if interaction_plan && (requested_danger || requested_full_access) {
            return Err(ProviderError::Unsupported(
                "Claude plan mode conflicts with full filesystem access".into(),
            ));
        }
        if let Some(value) = input.options.get("permissionMode") {
            let permission_mode = value.as_str().ok_or_else(|| {
                ProviderError::Validation("permissionMode must be a string".into())
            })?;
            if (requested_danger || requested_full_access) && permission_mode != "bypassPermissions"
            {
                return Err(ProviderError::Unsupported(
                    "explicit permissionMode conflicts with full filesystem access".into(),
                ));
            }
            options.permission_mode = Some(permission_mode.to_owned());
        } else {
            let derived_mode = if requested_danger || requested_full_access {
                Some("bypassPermissions")
            } else if interaction_plan {
                Some("plan")
            } else {
                match input.approval_policy {
                    Some(ApprovalPolicy::Untrusted) => Some("plan"),
                    Some(ApprovalPolicy::OnFailure | ApprovalPolicy::OnRequest) => Some("default"),
                    Some(ApprovalPolicy::Never) => Some("dontAsk"),
                    None => match input.runtime_mode {
                        RuntimeMode::ApprovalRequired if options.permission_mode.is_some() => None,
                        RuntimeMode::ApprovalRequired => Some("default"),
                        RuntimeMode::AutoAcceptEdits => Some("acceptEdits"),
                        RuntimeMode::Auto => Some("dontAsk"),
                        RuntimeMode::FullAccess => Some("bypassPermissions"),
                    },
                }
            };
            if let Some(mode) = derived_mode {
                options.permission_mode = Some(mode.into());
            }
        }
        install_callbacks(
            &mut options,
            &self.request_tx,
            &self.pending,
            &self.next_request,
            &self.thread_id,
            &self.active_turn_id,
        );
        Ok(options)
    }

    pub(super) fn raw(&self, message_type: impl Into<String>, payload: Value) -> RawEvent {
        self.raw_from(MESSAGE_SOURCE, message_type, payload)
    }

    pub(super) fn raw_from(
        &self,
        source: &str,
        message_type: impl Into<String>,
        payload: Value,
    ) -> RawEvent {
        RawEvent {
            source: source.into(),
            method: None,
            message_type: Some(message_type.into()),
            payload,
        }
    }

    pub(super) fn event(&self, kind: EventKind, payload: Value, raw: RawEvent) -> ProviderEvent {
        let thread_id = self
            .session
            .as_ref()
            .map_or_else(String::new, |session| session.thread_id.clone());
        let mut event = ProviderEvent::new(
            ProviderKind::Claude,
            self.config.provider_instance_id.clone(),
            thread_id,
            kind,
            payload,
            Some(raw),
        );
        event.turn_id = self
            .active_turn_id
            .try_lock()
            .ok()
            .and_then(|value| value.clone());
        event
    }

    pub(super) fn event_for_turn(
        &self,
        kind: EventKind,
        turn_id: Option<String>,
        payload: Value,
        raw: RawEvent,
    ) -> ProviderEvent {
        let mut event = self.event(kind, payload, raw);
        event.turn_id = turn_id;
        event
    }

    pub(super) fn queue(&mut self, event: ProviderEvent) {
        self.queued_events.push_back(event);
    }

    pub(super) fn pop_validated(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        let Some(event) = self.queued_events.pop_front() else {
            return Ok(None);
        };
        event.validate()?;
        Ok(Some(event))
    }

    pub(super) fn set_native_thread(&mut self, native: &str) {
        if let Some(session) = &mut self.session {
            if !native.is_empty() {
                session.native_thread_id = native.to_owned();
            }
        }
    }

    pub(super) fn queue_session_events(&mut self) {
        let (thread_id, native_thread_id) = match &self.session {
            Some(session) => (session.thread_id.clone(), session.native_thread_id.clone()),
            None => return,
        };
        self.queue(self.event(
            EventKind::SessionStarted,
            session_started_payload(&native_thread_id),
            self.raw("session", json!({ "status": "ready" })),
        ));
        self.queue(self.event(
            EventKind::ThreadStarted,
            json!({ "providerThreadId": native_thread_id.clone() }),
            self.raw(
                "thread",
                json!({ "threadId": thread_id, "nativeThreadId": native_thread_id }),
            ),
        ));
    }
}

fn session_started_payload(native_thread_id: &str) -> Value {
    let mut payload = json!({ "message": "Claude session started" });
    if !native_thread_id.starts_with("pending:") {
        payload["resume"] = Value::String(native_thread_id.to_owned());
    }
    payload
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_access_overrides_configured_default_permission_mode() {
        let mut config = ClaudeProviderConfig::default();
        config.options.permission_mode = Some("default".into());
        let provider = ClaudeProvider::new(config).unwrap();
        let input = SessionStartInput {
            runtime_mode: RuntimeMode::FullAccess,
            ..SessionStartInput::new("app-thread")
        };

        let options = provider.build_options(&input).unwrap();

        assert_eq!(
            options.permission_mode.as_deref(),
            Some("bypassPermissions")
        );
    }
}
