use std::path::PathBuf;

use serde_json::{Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{unsupported, SendInput};
use super::session::ChatSession;

impl ChatSession {
    pub(super) async fn remember_first_send(&mut self) {
        if self.header.turns.len() != 1 {
            return;
        }
        let selection = serde_json::json!({"providerInstanceId":self.header.provider_instance_id,
            "model":self.header.session.model,"runtimeMode":self.header.session.runtime_mode,
            "interactionMode":self.header.session.interaction_mode});
        let receipt = alera_core::runtime::AgentChatReceipt {
            caller_scope: "runtime:rememberedSelection".into(),
            request_id: format!("first-send:{}", self.header.chat_id),
            digest: super::ids::payload_digest(&selection),
            receipt: Value::Null,
        };
        match self
            .deps
            .store
            .remember_agent_chat_selection(&selection, &receipt)
            .await
        {
            Ok(alera_core::runtime::AgentChatSettingsOutcome::Applied(response)) => {
                if let Some(revision) = response["revision"].as_i64() {
                    self.deps
                        .sink
                        .emit(super::events::ChatRuntimeEvent::PreferencesChanged { revision })
                        .await;
                }
            }
            Ok(_) => {}
            Err(error) => {
                tracing::warn!(chat_id=%self.header.chat_id,error=%error,"could not remember first chat selection")
            }
        }
    }

    pub(super) async fn apply_turn_configuration(&mut self, input: &SendInput) -> HostResult<bool> {
        let model = input
            .model
            .clone()
            .or_else(|| self.header.session.model.clone());
        let model_changed = model != self.header.session.model;
        let effort = input.reasoning_effort.clone().or_else(|| {
            (!model_changed)
                .then(|| self.header.session.reasoning_effort.clone())
                .flatten()
        });
        let provider = self.header.provider.clone();
        let instance_id = self.header.provider_instance_id.clone();
        self.validate_effort(&provider, &instance_id, model.as_deref(), effort.as_deref())
            .await?;
        if effort.is_some()
            && self
                .provider
                .as_ref()
                .is_some_and(|provider| !provider.reasoning_effort_capabilities().turn)
        {
            return Err(unsupported(
                "This agent cannot honor reasoning effort on a turn.",
            ));
        }
        let per_turn = self
            .live_caps
            .as_ref()
            .map(|caps| caps.model_switch)
            .unwrap_or_else(|| {
                super::provider_traits::provider_traits(&self.header.provider)
                    .is_some_and(|traits| traits.per_turn_model)
            });
        if model_changed && !per_turn {
            self.stop_provider("reconfigured", "The next turn uses the selected model.")
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
        if model_changed {
            self.update_tab_payload().await;
        }
        Ok(per_turn)
    }

    pub(super) async fn validate_effort(
        &mut self,
        provider: &str,
        instance_id: &str,
        model: Option<&str>,
        effort: Option<&str>,
    ) -> HostResult<()> {
        let Some(effort) = effort else {
            return Ok(());
        };
        let instance = self.deps.instances.find(instance_id);
        self.deps
            .factory
            .validate_reasoning_effort(
                provider,
                instance.as_ref(),
                self.header.session.cwd.as_ref().map(PathBuf::from),
                model,
                effort,
            )
            .await
            .map_err(unsupported)
    }
}

pub(super) fn session_effort_options(provider: &str, effort: Option<&str>) -> Map<String, Value> {
    let mut options = Map::new();
    if provider == "codex" {
        if let Some(effort) = effort {
            options.insert("reasoningEffort".into(), Value::String(effort.into()));
        }
    }
    options
}

pub(super) fn turn_effort_options(provider: &str, effort: Option<&str>) -> Map<String, Value> {
    let mut options = Map::new();
    if provider == "codex" {
        if let Some(effort) = effort {
            options.insert("reasoningEffort".into(), Value::String(effort.into()));
        }
    }
    options
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn effort_maps_to_native_fields_only_for_supported_adapter() {
        assert_eq!(
            session_effort_options("codex", Some("high"))["reasoningEffort"],
            "high"
        );
        assert_eq!(
            turn_effort_options("codex", Some("high"))["reasoningEffort"],
            "high"
        );
        assert!(session_effort_options("pi", Some("high")).is_empty());
        assert!(turn_effort_options("pi", Some("high")).is_empty());
        assert!(turn_effort_options("codex", None).is_empty());
    }
}
