use alera_core::runtime::{
    RuntimeAiAssistPromptSettings, RuntimeAiAssistSettings, RuntimeTextAction,
};
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_requests::{active_generations, plan_command, run_command};
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) fn start_ai_assist_text_action(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let workspace_path = required_non_blank(payload, "workspacePath")?;
        let action_id = required_non_blank(payload, "actionId")?;
        let selected_text = payload
            .get("selectedText")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::format("selectedText must be a string."))?
            .to_owned();
        let runtime_store = self.runtime_store.clone();
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
                let settings = runtime_store
                    .effective_ai_assist_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let actions = runtime_store
                    .text_actions_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .unwrap_or_default();
                let action = actions
                    .actions
                    .into_iter()
                    .find(|action| action.id == action_id)
                    .ok_or_else(|| HostError::state("Text action was not found."))?;
                generate_text_action(&workspace_path, selected_text, action, settings, cancel_rx)
                    .await
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

async fn generate_text_action(
    workspace_path: &str,
    selected_text: String,
    action: RuntimeTextAction,
    settings: RuntimeAiAssistSettings,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<Value> {
    if !settings.enabled {
        return Err(HostError::state("AI Assist is disabled."));
    }
    if !action.enabled {
        return Err(HostError::state("Text action is disabled."));
    }
    let prompt = build_text_action_prompt(&action.prompt, &selected_text);
    let mut action_settings = settings;
    let effective_agent = action
        .agent_override
        .clone()
        .unwrap_or_else(|| action_settings.agent.clone());
    action_settings.prompt_settings_by_operation.insert(
        "textAction".to_string(),
        RuntimeAiAssistPromptSettings {
            agent: Some(effective_agent),
            model: action.model_override.clone(),
        },
    );
    if !action.reasoning_by_model.is_empty() {
        action_settings
            .selected_thinking_by_operation
            .insert("textAction".to_string(), action.reasoning_by_model.clone());
    }
    let plan = plan_command(&action_settings, "textAction", &prompt)?;
    let agent_label = plan.label.clone();
    let raw = run_command(
        plan,
        workspace_path,
        action_settings.timeout_seconds,
        cancel_rx,
    )
    .await?;
    let text = clean_generated_text(&raw);
    if text.trim().is_empty() {
        return Err(HostError::state(format!(
            "{agent_label} returned no replacement text."
        )));
    }
    Ok(json!({"text": text, "agentLabel": agent_label}))
}

fn build_text_action_prompt(instruction: &str, selected_text: &str) -> String {
    [
        instruction.trim(),
        "",
        "Replace only the selected text using the source below.",
        "--- selected text ---",
        selected_text,
        "--- end selected text ---",
        "",
        "Return only the replacement text. Do not include explanations or code fences.",
    ]
    .join("\n")
}

fn clean_generated_text(raw: &str) -> String {
    let mut text = raw.replace("\r\n", "\n").trim().to_string();
    if let Some((first, rest)) = text.split_once('\n') {
        let first = first.trim();
        if first.eq_ignore_ascii_case("generating")
            || first.eq_ignore_ascii_case("thinking")
            || first
                .chars()
                .all(|character| matches!(character, '.' | '…'))
        {
            text = rest.trim().to_string();
        }
    }
    if text.starts_with("```") && text.ends_with("```") {
        if let Some(first_newline) = text.find('\n') {
            text = text[first_newline + 1..text.len() - 3].trim().to_string();
        }
    }
    text
}

#[cfg(test)]
mod tests {
    use super::{build_text_action_prompt, clean_generated_text};

    #[test]
    fn builds_prompt_with_selected_text_boundaries() {
        assert_eq!(
            build_text_action_prompt("Make it concise.", "Hello"),
            "Make it concise.\n\nReplace only the selected text using the source below.\n--- selected text ---\nHello\n--- end selected text ---\n\nReturn only the replacement text. Do not include explanations or code fences."
        );
    }

    #[test]
    fn removes_agent_preamble_and_fences() {
        assert_eq!(
            clean_generated_text("thinking\n```text\nHello\n```"),
            "Hello"
        );
    }
}
