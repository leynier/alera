//! Provider process lifecycle: start or resume off the actor's critical path,
//! adopt the result, and account for a process that stops or dies.

use std::path::PathBuf;

use alera_provider_protocol::{NativeForkInput, SessionStartInput};
use tokio::sync::oneshot;

use super::ids::process_epoch;
use super::provider_factory::ProviderLaunch;
use super::provider_traits::{parse_runtime_mode, provider_traits};
use super::session::{ChatSession, StartupResult, CLOSE_TIMEOUT, STARTUP_TIMEOUT};
use super::wire::{json, Recovery};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StartMode {
    Resume,
    Fresh,
}

impl ChatSession {
    pub(super) fn set_status(&mut self, status: &str) {
        self.header.session.status = status.to_string();
    }

    pub(super) fn set_recovery(&mut self, recovery: Option<Recovery>) {
        self.header.recovery = recovery.map(|recovery| json(&recovery));
    }

    fn recovery_kind(&self) -> Option<&str> {
        self.header.recovery.as_ref()?.get("kind")?.as_str()
    }

    pub(super) fn can_resume(&self) -> bool {
        self.native_thread.is_some()
            && self.recovery_kind() != Some("notResumable")
            && provider_traits(&self.header.provider).is_some_and(|t| t.capabilities.resume)
    }

    pub(super) async fn start_provider(&mut self, mode: Option<StartMode>) {
        if self.provider.is_some() || self.startup.is_some() {
            return;
        }
        let resume = self.plan_start(mode);
        self.spawn_startup(resume).await;
    }

    /// Decides between resuming the native session and a fresh one, before
    /// any turn text is built from that decision. A fresh session of a chat
    /// with history gets the transcript with its first turn.
    pub(super) fn plan_start(&mut self, mode: Option<StartMode>) -> Option<String> {
        let resume = mode != Some(StartMode::Fresh) && self.can_resume();
        if !resume && self.has_items {
            self.handoff_pending =
                !self.native_fork_pending() || self.native_fork_has_local_history();
        }
        resume.then(|| self.native_thread.clone()).flatten()
    }

    pub(super) async fn spawn_startup(&mut self, resume_thread_id: Option<String>) {
        let native_fork = (resume_thread_id.is_none() && self.native_fork_pending())
            .then(|| self.native_fork.clone())
            .flatten();
        self.startup_forking = native_fork.is_some();
        self.startup_resume = resume_thread_id.is_some();
        self.process_epoch = process_epoch();
        self.native_ids.clear();
        self.set_status("starting");
        self.header.session.error_message = None;
        self.set_recovery(None);

        let model = self.header.session.model.clone().or_else(|| {
            self.deps
                .instances
                .find(&self.header.provider_instance_id)
                .and_then(|instance| instance.default_model)
        });
        if self.header.session.model.is_none() && model.is_some() {
            self.header.session.model = model.clone();
            self.pending.session();
        }
        let _ = self.flush().await;

        let mut launch = ProviderLaunch {
            chat_id: self.header.chat_id.clone(),
            generation: self.generation,
            provider: self.header.provider.clone(),
            provider_instance_id: self.header.provider_instance_id.clone(),
            cwd: self.header.session.cwd.as_ref().map(PathBuf::from),
            model,
            runtime_mode: parse_runtime_mode(&self.header.session.runtime_mode).unwrap_or_default(),
            instance: self.deps.instances.find(&self.header.provider_instance_id),
            mcp_servers: Vec::new(),
            env: Default::default(),
        };
        let hooks = self
            .deps
            .hooks
            .read()
            .map(|hooks| hooks.clone())
            .unwrap_or_default();
        let mut options = super::session_effort::session_effort_options(
            &self.header.provider,
            self.header.session.reasoning_effort.as_deref(),
        );
        if self.header.provider == "claudeAgent" {
            options.insert(
                "enableFileCheckpointing".into(),
                serde_json::json!(self.file_checkpointing_enabled()),
            );
        }
        let factory = self.deps.factory.clone();
        let instances = self.deps.instances.clone();
        let (tx, rx) = oneshot::channel::<StartupResult>();
        self.startup = Some(rx);
        self.startup_task = Some(tokio::spawn(async move {
            let attempt = async {
                if instances
                    .provider_of(&launch.provider_instance_id, Some(&launch.provider))
                    .is_none()
                {
                    return Err("The selected agent instance was not found or is disabled.".into());
                }
                for hook in hooks {
                    hook.prepare(&mut launch).await?;
                }
                if instances
                    .provider_of(&launch.provider_instance_id, Some(&launch.provider))
                    .is_none()
                {
                    return Err("The selected agent instance was not found or is disabled.".into());
                }
                let mut provider = factory
                    .spawn(&launch)
                    .await
                    .map_err(|error| error.to_string())?;
                let started = async {
                    provider.initialize().await?;
                    if options.contains_key("reasoningEffort") {
                        let effort = provider.reasoning_effort_capabilities();
                        if !effort.session || !effort.turn {
                            return Err(alera_provider_protocol::ProviderError::Unsupported("This agent cannot honor reasoning effort for the session and turns.".into()));
                        }
                    }
                    let injection = provider.capabilities().mcp_injection;
                    if let Some(server) = launch
                        .mcp_servers
                        .iter()
                        .find(|server| !injection.supports(server))
                    {
                        return Err(alera_provider_protocol::ProviderError::Unsupported(
                            format!(
                                "{} cannot attach the MCP server {}",
                                launch.provider, server.name
                            ),
                        ));
                    }
                    let input = SessionStartInput {
                        thread_id: launch.chat_id.clone(),
                        resume_thread_id,
                        cwd: launch.cwd.clone(),
                        model: launch.model.clone(),
                        runtime_mode: launch.runtime_mode,
                        approval_policy: None,
                        sandbox_mode: None,
                        options,
                        mcp_servers: launch.mcp_servers.clone(),
                    };
                    input.validate()?;
                    if let Some(plan) = native_fork {
                        let capabilities = provider.native_history_capabilities();
                        let supported = match &plan.boundary {
                            alera_provider_protocol::NativeForkBoundary::Turn(_) => {
                                capabilities.fork_at_turn
                            }
                            alera_provider_protocol::NativeForkBoundary::Message(_) => {
                                capabilities.fork_at_message
                            }
                        };
                        if !supported {
                            return Err(alera_provider_protocol::ProviderError::Unsupported(
                                "The agent cannot fork at the selected native boundary.".into(),
                            ));
                        }
                        let fork_input = NativeForkInput {
                            source_native_thread_id: plan.source_native_thread_id,
                            boundary: Some(plan.boundary),
                            session: input,
                        };
                        fork_input.validate()?;
                        provider
                            .fork_session(fork_input)
                            .await
                            .map(|fork| fork.session)
                    } else {
                        provider.start_session(input).await
                    }
                }
                .await;
                match started {
                    Ok(session) => Ok((provider, session)),
                    Err(error) => {
                        let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
                        Err(error.to_string())
                    }
                }
            };
            let result = tokio::time::timeout(STARTUP_TIMEOUT, attempt)
                .await
                .unwrap_or_else(|_| Err("The provider did not start in time.".into()));
            if let Err(Ok((mut provider, _))) = tx.send(result) {
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
            }
        }));
    }

    /// Waits for the startup task after its result reached the actor. The
    /// task can still be unwinding the provider close path when the oneshot is
    /// delivered, so do not leave it detached before adopting the result.
    pub(super) async fn join_startup_task(&mut self) {
        if let Some(task) = self.startup_task.take() {
            let _ = task.await;
        }
    }

    /// Cancels hook preparation or provider startup and waits for the task to
    /// disappear before any generation credential is revoked. Dropping the
    /// task also drops a partially spawned provider, whose process boundary
    /// performs its own kill-on-drop cleanup.
    pub(super) async fn cancel_startup(&mut self) {
        self.startup.take();
        if let Some(task) = self.startup_task.take() {
            task.abort();
            let _ = task.await;
        }
    }

    pub(super) async fn finish_startup(&mut self, result: StartupResult) {
        match result {
            Ok((provider, session)) => {
                self.live_caps = Some(provider.capabilities());
                self.provider = Some(provider);
                // Task ids of an earlier process name nothing in this one.
                self.awaited_tasks.clear();
                self.events_armed = true;
                self.record_native_session(&session.native_thread_id).await;
                if self.startup_forking {
                    if let Err(error) = self.complete_native_fork().await {
                        self.provider_failed(error).await;
                        return;
                    }
                }
                if self.header.session.model.is_none() {
                    self.header.session.model = session.model;
                }
                let running = self.header.session.active_turn_id.is_some();
                self.set_status(if running { "running" } else { "ready" });
                let _ = self.flush().await;
                if let Some(deferred) = self.deferred_turn.take() {
                    self.submit_turn(deferred.input).await;
                    let _ = self.flush().await;
                } else {
                    self.drain_queue().await;
                }
            }
            Err(message) => {
                let kind = if self.startup_resume {
                    "notResumable"
                } else if looks_missing(&message) {
                    "providerMissing"
                } else {
                    "providerExited"
                };
                self.deferred_turn = None;
                self.revoke_launch_credentials("providerStartFailed").await;
                self.finish_turn(
                    "failed",
                    Some(message.clone()),
                    Some("providerStartFailed".into()),
                )
                .await;
                self.set_status("error");
                self.header.session.error_message = Some(message.clone());
                self.set_recovery(Some(Recovery {
                    kind: kind.into(),
                    message,
                    can_resume: false,
                    can_restart: kind != "providerMissing",
                }));
                let _ = self.flush().await;
            }
        }
    }

    /// Stores the native session id once the provider has a real one.
    pub(super) async fn record_native_session(&mut self, native: &str) {
        if native.is_empty()
            || native.starts_with("pending:")
            || self.native_thread.as_deref() == Some(native)
        {
            return;
        }
        match self
            .deps
            .store
            .bind_agent_chat_native_thread(&self.header.chat_id, self.generation, Some(native))
            .await
        {
            Ok(()) => self.native_thread = Some(native.to_string()),
            Err(error) => {
                tracing::warn!(chat_id = %self.header.chat_id, error = %error, "agent chat native thread was not recorded")
            }
        }
    }

    pub(super) async fn provider_went_quiet(&mut self) {
        self.events_armed = false;
        let turn_running =
            self.header.session.active_turn_id.is_some() && self.deferred_turn.is_none();
        if turn_running || !self.header.pending_requests.is_empty() {
            self.provider_failed("The provider stopped reporting events.".into())
                .await;
        }
    }

    pub(super) async fn provider_failed(&mut self, message: String) {
        let Some(mut provider) = self.provider.take() else {
            return;
        };
        self.awaited_tasks.clear();
        let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
        self.revoke_launch_credentials("providerExited").await;
        self.live_caps = None;
        self.events_armed = false;
        self.finish_turn(
            "failed",
            Some(message.clone()),
            Some("providerExited".into()),
        )
        .await;
        self.expire_requests_of_turn(None);
        self.set_status("error");
        self.header.session.error_message = Some(message.clone());
        let can_resume = self.can_resume();
        self.set_recovery(Some(Recovery {
            kind: "providerExited".into(),
            message,
            can_resume,
            can_restart: true,
        }));
        let _ = self.flush().await;
    }

    pub(super) async fn revoke_launch_credentials(&mut self, reason: &str) {
        let hooks = self
            .deps
            .hooks
            .read()
            .map(|hooks| hooks.clone())
            .unwrap_or_default();
        for hook in hooks {
            if let Err(error) = hook
                .revoke(&self.header.chat_id, self.generation, reason)
                .await
            {
                tracing::warn!(
                    chat_id = %self.header.chat_id,
                    reason,
                    error,
                    "could not revoke agent chat launch credential"
                );
            }
        }
    }

    /// Stops the provider and leaves the chat resumable. Used for workspace
    /// sleep, reconfiguration and as the first half of closing a chat.
    pub(super) async fn stop_provider(&mut self, reason: &str, message: &str) {
        if self
            .native_operation
            .as_ref()
            .is_some_and(super::session_native_history_recovery::native_operation_freezes)
        {
            // The operation owns recovery until reconciliation. Normal stop
            // would poison that frozen header and block the final store commit.
            self.quiesce_native_history().await;
            return;
        }
        self.cancel_startup().await;
        self.revoke_launch_credentials(reason).await;
        self.deferred_turn = None;
        if let Some(mut provider) = self.provider.take() {
            if self.header.session.active_turn_id.is_some() {
                let _ = tokio::time::timeout(
                    CLOSE_TIMEOUT,
                    provider.interrupt(alera_provider_protocol::InterruptInput {
                        thread_id: self.header.chat_id.clone(),
                        turn_id: self.provider_turn_id.clone(),
                    }),
                )
                .await;
            }
            let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
        }
        self.live_caps = None;
        self.events_armed = false;
        self.finish_turn("interrupted", None, Some(reason.into()))
            .await;
        self.expire_requests_of_turn(None);
        self.set_status("stopped");
        let recovery = self.stopped_recovery(message);
        self.set_recovery(recovery);
    }

    pub(super) fn stopped_recovery(&self, message: &str) -> Option<Recovery> {
        self.has_items.then(|| {
            let resumable = self.can_resume();
            Recovery {
                kind: if resumable {
                    "resumable"
                } else {
                    "notResumable"
                }
                .into(),
                message: message.into(),
                can_resume: resumable,
                can_restart: true,
            }
        })
    }

    /// Graceful host shutdown: commit, close the process, end the actor.
    pub(super) async fn shutdown(&mut self) {
        let _ = self.flush().await;
        self.cancel_startup().await;
        self.revoke_launch_credentials("shutdown").await;
        if let Some(mut provider) = self.provider.take() {
            let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
        }
        self.closed = true;
    }
}

fn looks_missing(message: &str) -> bool {
    let lower = message.to_ascii_lowercase();
    lower.contains("no such file")
        || lower.contains("not found")
        || lower.contains("cannot find")
        || lower.contains("os error 2")
}
