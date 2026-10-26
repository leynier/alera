//! Provider configuration, recovery and archive lifecycle for one chat.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, turn_active, unsupported, ConfigureInput};
use super::ids::process_epoch;
use super::provider_traits::provider_traits;
use super::session::{ChatSession, CLOSE_TIMEOUT};
use super::session_provider::StartMode;
use super::tab_directory::{chat_tab_payload, chat_tab_record};

impl ChatSession {
    pub(super) fn require_idle(&self, what: &str) -> HostResult<()> {
        if let Some(op) = self
            .native_operation
            .as_ref()
            .filter(|op| super::session_native_history_recovery::native_operation_freezes(op))
        {
            return Err(super::session_native_history::native_pending_error(
                op,
                op.state == "uncertain",
            ));
        }
        if self.header.session.active_turn_id.is_some()
            || !self.header.pending_requests.is_empty()
            || !self.header.queue.is_empty()
            || self.startup.is_some()
            || self.deferred_turn.is_some()
        {
            return Err(turn_active(format!(
                "Wait for the running turn, open requests and queued messages before {what}."
            )));
        }
        Ok(())
    }

    pub(super) async fn configure(&mut self, input: ConfigureInput) -> HostResult<Value> {
        let instance_id = input
            .provider_instance_id
            .clone()
            .or_else(|| input.provider.clone())
            .unwrap_or_else(|| self.header.provider_instance_id.clone());
        let switching = instance_id != self.header.provider_instance_id;
        let provider = if switching {
            self.deps
                .instances
                .provider_of(&instance_id, input.provider.as_deref())
                .ok_or_else(|| {
                    conflict(
                        "providerUnavailable",
                        format!("Unknown provider instance {instance_id}"),
                    )
                })?
        } else {
            self.header.provider.clone()
        };
        let default_model = self
            .deps
            .instances
            .find(&instance_id)
            .and_then(|instance| instance.default_model);
        let model = match &input.model {
            Some(model) => model.clone().or(default_model),
            None if switching => default_model,
            None => self.header.session.model.clone(),
        };
        let effort = match &input.reasoning_effort {
            Some(effort) => effort.clone(),
            None if switching || model != self.header.session.model => None,
            None => self.header.session.reasoning_effort.clone(),
        };
        if provider == alera_core::runtime::AGENT_CHAT_UNSELECTED_PROVIDER {
            return Err(conflict(
                "providerRequired",
                "Choose an agent before configuring this chat.",
            ));
        }
        let traits = provider_traits(&provider)
            .ok_or_else(|| conflict("providerUnavailable", "Unknown provider"))?;
        let runtime_mode = input.runtime_mode.clone().unwrap_or_else(|| {
            if traits
                .runtime_modes
                .contains(&self.header.session.runtime_mode.as_str())
            {
                self.header.session.runtime_mode.clone()
            } else {
                "approval-required".into()
            }
        });
        let interaction_mode = input.interaction_mode.clone().unwrap_or_else(|| {
            if traits
                .interaction_modes
                .contains(&self.header.session.interaction_mode.as_str())
            {
                self.header.session.interaction_mode.clone()
            } else {
                "default".into()
            }
        });
        if !traits.runtime_modes.contains(&runtime_mode.as_str())
            || !traits
                .interaction_modes
                .contains(&interaction_mode.as_str())
        {
            return Err(unsupported(
                "This agent does not support the requested runtime or interaction mode.",
            ));
        }
        self.validate_effort(&provider, &instance_id, model.as_deref(), effort.as_deref())
            .await?;
        let restart = !switching
            && (self.provider.is_some() || self.startup.is_some())
            && ((model != self.header.session.model
                && (!traits.per_turn_model || model.is_none()))
                || runtime_mode != self.header.session.runtime_mode);
        if switching || restart {
            self.require_idle("changing the agent settings")?;
        }
        if switching {
            self.switch_provider(provider, instance_id, model.clone())
                .await?;
        } else if restart {
            self.stop_provider(
                "reconfigured",
                "The next message starts the session with the new settings.",
            )
            .await;
            self.native_thread = None;
            self.deps
                .store
                .bind_agent_chat_native_thread(&self.header.chat_id, self.generation, None)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            self.handoff_pending = self.has_items;
            self.header.recovery = None;
        }
        self.header.session.model = model;
        self.header.session.reasoning_effort = effort;
        self.set_runtime_mode(&runtime_mode)?;
        self.set_interaction_mode(&interaction_mode)?;
        self.update_tab_payload().await;
        self.snapshot().await
    }

    fn set_runtime_mode(&mut self, mode: &str) -> HostResult<()> {
        if !provider_traits(&self.header.provider)
            .is_some_and(|traits| traits.runtime_modes.contains(&mode))
        {
            return Err(unsupported(format!(
                "{} does not support the {mode} runtime mode.",
                self.header.provider
            )));
        }
        self.header.session.runtime_mode = mode.to_string();
        self.pending.session();
        Ok(())
    }

    fn set_interaction_mode(&mut self, mode: &str) -> HostResult<()> {
        if !provider_traits(&self.header.provider)
            .is_some_and(|traits| traits.interaction_modes.contains(&mode))
        {
            return Err(unsupported(format!(
                "{} does not support the {mode} interaction mode.",
                self.header.provider
            )));
        }
        self.header.session.interaction_mode = mode.to_string();
        self.pending.session();
        Ok(())
    }

    async fn switch_provider(
        &mut self,
        provider: String,
        instance_id: String,
        model: Option<String>,
    ) -> HostResult<()> {
        self.cancel_startup().await;
        self.revoke_launch_credentials("providerSwitch").await;
        if let Some(mut process) = self.provider.take() {
            let _ = tokio::time::timeout(CLOSE_TIMEOUT, process.close()).await;
        }
        self.live_caps = None;
        self.events_armed = false;
        // Another agent has its own commands; it reports them once it starts.
        self.header.session.commands.clear();
        self.header.provider = provider;
        self.header.provider_instance_id = instance_id.clone();
        self.header.session.model = model.or_else(|| {
            self.deps
                .instances
                .find(&instance_id)
                .and_then(|instance| instance.default_model)
        });
        let traits = provider_traits(&self.header.provider);
        if !traits.as_ref().is_some_and(|traits| {
            traits
                .runtime_modes
                .contains(&self.header.session.runtime_mode.as_str())
        }) {
            self.header.session.runtime_mode = "approval-required".into();
        }
        if !traits.as_ref().is_some_and(|traits| {
            traits
                .interaction_modes
                .contains(&self.header.session.interaction_mode.as_str())
        }) {
            self.header.session.interaction_mode = "default".into();
        }
        self.generation += 1;
        self.header.session.generation = self.generation;
        self.native_thread = None;
        self.native_fork = None;
        self.fork_source_turn_id = None;
        self.header.session.extra.remove("historyOperation");
        self.header.session.extra.remove("fileCheckpointing");
        self.process_epoch = process_epoch();
        self.native_ids.clear();
        self.handoff_pending = self.has_items;
        self.header.recovery = None;
        self.set_status("stopped");
        self.header.session.error_message = None;
        self.header.session.reasoning_effort = None;
        if !self.has_items && self.header.title_source == "default" {
            self.header.title = self
                .deps
                .instances
                .find(&instance_id)
                .and_then(|instance| instance.label)
                .unwrap_or_else(|| {
                    traits
                        .map(|traits| traits.label)
                        .unwrap_or("Agent Chat")
                        .into()
                });
            if let Ok(Some(workspace_id)) = self
                .deps
                .tabs
                .rename_tab(&self.header.tab_id, &self.header.title)
                .await
            {
                self.notify_tabs(workspace_id);
            }
        }
        self.pending.session();
        self.pending.recovery();
        self.update_tab_payload().await;
        self.notify_chats();
        Ok(())
    }

    pub(super) async fn update_tab_payload(&mut self) {
        let payload = chat_tab_payload(
            &self.header.chat_id,
            &self.header.provider,
            &self.header.provider_instance_id,
            self.header.session.model.as_deref(),
        );
        if let Ok(Some(workspace_id)) = self
            .deps
            .tabs
            .update_tab(&self.header.tab_id, None, Some(payload))
            .await
        {
            self.notify_tabs(workspace_id);
        }
    }

    pub(super) async fn recover(&mut self, mode: Option<&str>) -> HostResult<Value> {
        if self.never_sent() {
            return self.snapshot().await;
        }
        if self.provider.is_some() || self.startup.is_some() {
            return self.snapshot().await;
        }
        if mode == Some("restart") && self.native_fork_pending() {
            self.clear_native_fork("transcriptFork")
                .await
                .map_err(HostError::state)?;
            self.handoff_pending = self.has_items;
        }
        let mode = match mode {
            Some("resume") if !self.can_resume() => {
                return Err(unsupported(
                    "This chat's provider session cannot be resumed.",
                ));
            }
            Some("resume") => StartMode::Resume,
            Some("restart") => StartMode::Fresh,
            None => {
                if self.can_resume() {
                    StartMode::Resume
                } else {
                    StartMode::Fresh
                }
            }
            Some(other) => return Err(HostError::format(format!("Unknown recovery mode {other}"))),
        };
        self.start_provider(Some(mode)).await;
        self.snapshot().await
    }

    pub(super) async fn close_chat(&mut self) -> HostResult<Value> {
        if !self.header.archived {
            self.stop_provider("closed", "The chat was closed.").await;
            self.header.queue.clear();
            self.header.archived = true;
            self.header.recovery = None;
            self.pending.archived();
            self.pending.recovery();
            self.pending.queue();
            let _ = self.flush().await;
            self.deps
                .store
                .archive_agent_chat(&self.header.chat_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            self.notify_chats();
            self.notify_tabs(self.header.workspace_id.clone());
        }
        self.closed = true;
        Ok(json!({"archived": true}))
    }

    pub(super) async fn reopen(&mut self, tab_id: String) -> HostResult<Value> {
        if !self.header.archived {
            return Err(conflict("chatNotArchived", "This chat is already open."));
        }
        let tab = chat_tab_record(
            &tab_id,
            &self.header.workspace_id,
            &self.header.title,
            chat_tab_payload(
                &self.header.chat_id,
                &self.header.provider,
                &self.header.provider_instance_id,
                self.header.session.model.as_deref(),
            ),
        );
        let record = self
            .deps
            .store
            .restore_agent_chat(&self.header.chat_id, &tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.header = super::header::Header::from_snapshot(record.snapshot.clone())
            .map_err(HostError::state)?;
        self.committed = self.header.clone();
        self.generation = record.generation;
        self.native_thread = record.native_thread_id;
        self.pending = Default::default();
        self.closed = false;
        self.notify_chats();
        self.notify_tabs(self.header.workspace_id.clone());
        self.snapshot().await
    }
}
