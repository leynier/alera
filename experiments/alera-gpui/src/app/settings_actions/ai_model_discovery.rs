use std::time::Duration;

impl AleraApp {
    pub(super) fn auto_discover_configured_ai_models(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.settings_state.ai_text_enabled {
            return;
        }
        let agents = std::iter::once(self.settings_state.ai_text_agent.clone())
            .chain(
                self.settings_state
                    .ai_text_prompt_settings_by_operation
                    .values()
                    .filter_map(|prompt| prompt.agent.clone()),
            )
            .filter(|agent| supports_ai_model_discovery(agent))
            .collect::<std::collections::BTreeSet<_>>();
        for agent in agents {
            if self.ai_model_auto_discovered.insert(agent.clone()) {
                self.discover_ai_text_models(agent, window, cx);
            }
        }
    }

    pub(super) fn discover_ai_text_models(
        &mut self,
        agent: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !supports_ai_model_discovery(&agent)
            || !self.ai_model_discovery_busy.insert(agent.clone())
        {
            return;
        }
        self.ai_model_discovery_errors.remove(&agent);
        cx.notify();
        let bridge = self.bridge.clone();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "aiText.models.discover",
                    json!({"agent": agent}),
                    Duration::from_secs(65),
                )
                .await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.ai_model_discovery_busy.remove(&agent);
                match result {
                    Ok(value) if value.get("success").and_then(Value::as_bool) == Some(true) => {
                        let models = value
                            .get("models")
                            .cloned()
                            .and_then(|models| serde_json::from_value(models).ok())
                            .unwrap_or_default();
                        let default_model = value
                            .get("defaultModelId")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .to_string();
                        this.settings_state
                            .ai_text_discovered_models_by_agent
                            .insert(agent.clone(), models);
                        if !default_model.is_empty() {
                            this.settings_state
                                .ai_text_discovered_default_model_by_agent
                                .insert(agent.clone(), default_model);
                        }
                        this.ai_model_discovery_errors.remove(&agent);
                        this.settings_store.save(&this.settings_state);
                        this.sync_ai_text_selects(window, cx);
                        cx.notify();
                    }
                    Ok(value) => {
                        let error = value
                            .get("error")
                            .and_then(Value::as_str)
                            .unwrap_or("Model Discovery Failed.")
                            .to_string();
                        this.ai_model_discovery_errors
                            .insert(agent.clone(), error.into());
                        cx.notify();
                    }
                    Err(error) => {
                        this.ai_model_discovery_errors
                            .insert(agent.clone(), error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }
}

pub(super) fn supports_ai_model_discovery(agent: &str) -> bool {
    matches!(agent, "codex" | "cursor" | "agy" | "opencode" | "opencode2" | "pi" | "grok")
}
