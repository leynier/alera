use alera_core::runtime::RuntimeAiAssistSettings;
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_model_defaults::default_model;
use super::ai_assist_requests::{active_generations, plan_command, run_command, SUPPORTED_AGENTS};
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) fn start_ai_assist_speech_message(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let text = required_non_blank(payload, "text")?;
        let mode = required_non_blank(payload, "mode")?;
        if !matches!(mode.as_str(), "cleanUp" | "summarize") {
            return Err(HostError::format("Speech processing mode is unsupported."));
        }
        let workspace_id = optional_non_blank(payload, "workspaceId");
        let tab_id = optional_non_blank(payload, "tabId");
        if workspace_id.is_none() && tab_id.is_none() {
            return Err(HostError::format("workspaceId or tabId is required."));
        }
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let (cancel_tx, cancel_rx) = oneshot::channel();
        let mut active = active_generations()
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))?;
        if active.contains_key(&operation_id) {
            return Err(HostError::state(
                "AI Assist is already running for this operation.",
            ));
        }
        active.insert(operation_id.clone(), cancel_tx);
        drop(active);
        tokio::spawn(async move {
            let result = async {
                let resolved_workspace_id = if let Some(workspace_id) = workspace_id {
                    workspace_id
                } else {
                    let tab_id = tab_id.expect("validated tab id");
                    store
                        .find_workspace_tab(&tab_id)
                        .await
                        .map_err(|error| HostError::state(error.to_string()))?
                        .ok_or_else(|| {
                            HostError::state(format!("Workspace tab not found: {tab_id}"))
                        })?
                        .workspace_id
                };
                let workspace = store
                    .find_workspace(&resolved_workspace_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| {
                        HostError::state(format!("Workspace not found: {resolved_workspace_id}"))
                    })?;
                let settings = store
                    .effective_ai_assist_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                generate_speech_message(&workspace.path, &text, &mode, settings, cancel_rx).await
            }
            .await;
            if let Ok(mut active) = active_generations().lock() {
                active.remove(&operation_id);
            }
            let _ = inbox.send(ServerCommand::AiAssistFinished {
                client_id,
                request_id,
                result,
            });
        });
        Ok(())
    }
}

fn optional_non_blank(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

async fn generate_speech_message(
    working_directory: &str,
    text: &str,
    mode: &str,
    settings: RuntimeAiAssistSettings,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<Value> {
    if !settings.enabled {
        return Err(HostError::state("AI Assist is disabled."));
    }
    let (agent, model) = selected_agent_and_model(&settings, "speechMessage");
    if agent == "custom" || !SUPPORTED_AGENTS.contains(&agent.as_str()) {
        return Err(HostError::format(
            "Select a supported agent subscription for speech processing.",
        ));
    }
    let instructions = settings
        .instructions_by_operation
        .get("speechMessage")
        .map(String::as_str)
        .unwrap_or_default();
    let prompt = speech_message_prompt(text, mode, instructions);
    let plan = plan_command(&settings, "speechMessage", &prompt)?;
    let label = plan.label.clone();
    let timeout_seconds = settings.timeout_seconds;
    let output = run_command(plan, working_directory, timeout_seconds, cancel_rx).await?;
    let cleaned = output.trim();
    if cleaned.is_empty() {
        return Err(HostError::state(
            "The speech processing agent returned no text.",
        ));
    }
    Ok(json!({"text": cleaned, "agentLabel": label, "model": model}))
}

fn selected_agent_and_model(
    settings: &RuntimeAiAssistSettings,
    operation: &str,
) -> (String, String) {
    let prompt_settings = settings.prompt_settings_by_operation.get(operation);
    let agent = prompt_settings
        .and_then(|value| value.agent.as_deref())
        .unwrap_or(&settings.agent)
        .to_string();
    let model = prompt_settings
        .and_then(|value| value.model.as_deref())
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            settings
                .selected_model_by_agent
                .get(&agent)
                .map(String::as_str)
        })
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| default_model(&agent))
        .to_string();
    (agent, model)
}

fn speech_message_prompt(text: &str, mode: &str, instructions: &str) -> String {
    let task = if mode == "summarize" {
        "Turn the transcript into a concise, actionable message. Preserve every request, constraint, technical identifier, name, number, and decision. Remove repetition."
    } else {
        "Clean up the transcript without summarizing it. Preserve its meaning and details while fixing punctuation, grammar, filler words, false starts, and accidental repetition."
    };
    let custom = if instructions.trim().is_empty() {
        String::new()
    } else {
        format!("\nAdditional instructions:\n{}\n", instructions.trim())
    };
    format!(
        "{task}\nDo not answer the speaker, add facts, or include a preamble. Return only the final message.{custom}\nTranscript:\n{text}"
    )
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use alera_core::runtime::{RuntimeAiAssistPromptSettings, RuntimeAiAssistSettings};

    use super::{selected_agent_and_model, speech_message_prompt};

    #[test]
    fn speech_prompt_preserves_mode_and_instructions() {
        let prompt = speech_message_prompt("say this", "summarize", "Keep ticket IDs.");
        assert!(prompt.contains("concise, actionable message"));
        assert!(prompt.contains("Keep ticket IDs."));
        assert!(prompt.ends_with("Transcript:\nsay this"));
    }

    #[test]
    fn speech_selection_uses_operation_agent_and_model() {
        let settings = RuntimeAiAssistSettings {
            enabled: true,
            agent: "codex".to_string(),
            selected_model_by_agent: HashMap::from([(
                "claude".to_string(),
                "claude-sonnet-4-5".to_string(),
            )]),
            prompt_settings_by_operation: HashMap::from([(
                "speechMessage".to_string(),
                RuntimeAiAssistPromptSettings {
                    agent: Some("claude".to_string()),
                    model: None,
                },
            )]),
            ..RuntimeAiAssistSettings::default()
        };
        assert_eq!(
            selected_agent_and_model(&settings, "speechMessage"),
            ("claude".to_string(), "claude-sonnet-4-5".to_string())
        );
    }
}
