use super::*;
use alera_agent_transport::TransportError;

/// Hands an injected transport to the SDK client, which owns it by value.
pub(super) struct BoxedTransport(pub(super) Box<dyn JsonTransport>);

#[async_trait]
impl JsonTransport for BoxedTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        self.0.send(message).await
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        self.0.recv().await
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.0.close().await
    }
}

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
        // The CLI inherits the configured env over the process env.
        let context_usage = super::context_usage::ContextUsage::from_env(|key| {
            config
                .options
                .env
                .get(key)
                .cloned()
                .or_else(|| std::env::var(key).ok())
        });
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
            session_effort: None,
            permission: Default::default(),
            plan_interaction: Arc::new(AtomicBool::new(false)),
            file_checkpointing: false,
            fork_source_native_thread_id: None,
            pending_user_prompt: None,
            turn_failure: Default::default(),
            described_commands: false,
            background_tasks: Default::default(),
            workflow_tasks: Default::default(),
            turn_signals: Default::default(),
            task_tools: Default::default(),
            command_output: Default::default(),
            attachment_budget: Default::default(),
            context_usage,
        })
    }

    #[cfg(test)]
    pub(super) fn build_options(
        &self,
        input: &SessionStartInput,
    ) -> Result<ClaudeAgentOptions, ProviderError> {
        self.launch_options(input).map(|(options, _)| options)
    }

    /// The launch options, and whether Full Access stepped down because
    /// Claude's settings disable bypass.
    pub(super) fn launch_options(
        &self,
        input: &SessionStartInput,
    ) -> Result<(ClaudeAgentOptions, bool), ProviderError> {
        if matches!(input.sandbox_mode, Some(SandboxMode::ReadOnly)) {
            return Err(ProviderError::Unsupported(
                "Claude Code does not expose a read-only filesystem sandbox".into(),
            ));
        }
        if let Some(unsupported) = input.options.keys().find(|key| {
            !matches!(
                key.as_str(),
                "permissionMode"
                    | "interactionMode"
                    | "reasoningEffort"
                    | "enableFileCheckpointing"
            )
        }) {
            return Err(ProviderError::Unsupported(format!(
                "unsupported Claude session option: {unsupported}"
            )));
        }
        let mut options = self.config.options.clone();
        if let Some(effort) = alera_provider_protocol::reasoning_effort(&input.options)? {
            reasoning_effort::validate(
                effort,
                input.model.as_deref().or(options.model.as_deref()),
            )?;
            options.effort = Some(effort.into());
        }
        if let Some(value) = input.options.get("enableFileCheckpointing") {
            options.enable_file_checkpointing = value.as_bool().ok_or_else(|| {
                ProviderError::Validation("enableFileCheckpointing must be a boolean".into())
            })?;
        }
        if options.enable_file_checkpointing {
            if options
                .extra_args
                .get("replay-user-messages")
                .is_some_and(Option::is_some)
            {
                return Err(ProviderError::Validation(
                    "Claude replay-user-messages checkpoint flag cannot have a value".into(),
                ));
            }
            options
                .extra_args
                .insert("replay-user-messages".into(), None);
        }
        if input.cwd.is_some() {
            options.cwd = input.cwd.clone();
        }
        if input.model.is_some() {
            options.model = input.model.clone();
        }
        if input.resume_thread_id.is_some() {
            options.resume = input.resume_thread_id.clone();
        }
        let has_injected_mcp = mcp::merge_options(&mut options, &input.mcp_servers)?;
        if has_injected_mcp
            && input
                .mcp_servers
                .iter()
                .any(|server| server.name == "alera")
            && !options
                .allowed_tools
                .iter()
                .any(|tool| tool == "mcp__alera__*")
        {
            options.allowed_tools.push("mcp__alera__*".into());
        }
        if has_injected_mcp
            && input
                .mcp_servers
                .iter()
                .any(|server| server.name == "alera")
        {
            background_wait::append_background_wait_instructions(&mut options);
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
        // Base64 image and document blocks need frames above the default.
        options.max_buffer_size = options
            .max_buffer_size
            .max(super::attachments::MAX_FRAME_BYTES);
        let stepped_down = super::permission_mode::step_down_bypass(&mut options);
        install_callbacks(
            &mut options,
            &self.request_tx,
            &self.pending,
            &self.next_request,
            &self.thread_id,
            &self.active_turn_id,
            &self.plan_interaction,
        );
        Ok((options, stepped_down))
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
        if self.fork_source_native_thread_id.as_deref() == Some(native) {
            return;
        }
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
        if self.fork_source_native_thread_id.is_some() && native_thread_id.starts_with("pending:") {
            return;
        }
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
#[path = "lifecycle_tests.rs"]
mod tests;
