use std::time::Duration;

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_opencode_go::{
    complete_opencode_go, list_opencode_go_models, OPENCODE_GO_DEFAULT_MODEL, OPENCODE_GO_LABEL,
};
use super::ai_assist_operation_registry::active_generations;
use super::chatgpt_request_options::parse_thinking_context;
use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

const MODELS_TIMEOUT: Duration = Duration::from_secs(60);

impl ServerActor {
    pub(super) fn start_ai_assist_complete(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let operation_id = required_non_blank(payload, "operationId")?;
        let prompt = required_non_blank(payload, "prompt")?;
        let session_id = required_non_blank(payload, "sessionId")?;
        let agent =
            optional_non_blank(payload, "agent").unwrap_or_else(|| "opencode-go".to_string());
        if !matches!(agent.as_str(), "opencode-go" | "chatgpt") {
            return Err(HostError::format("Unsupported direct AI Assist provider."));
        }
        let model = optional_non_blank(payload, "model").unwrap_or_else(|| {
            if agent == "chatgpt" {
                String::new()
            } else {
                OPENCODE_GO_DEFAULT_MODEL.to_string()
            }
        });
        let thinking_level = optional_non_blank(payload, "thinkingLevel");
        let service_tier = optional_non_blank(payload, "serviceTier");
        let thinking_context = if agent == "chatgpt" {
            parse_thinking_context(payload.get("thinkingContext"))?
        } else {
            None
        };
        let timeout_seconds = payload
            .get("timeoutSeconds")
            .and_then(Value::as_u64)
            .filter(|value| *value > 0)
            .unwrap_or(120);
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let (registration, cancel_rx) = active_generations().register(operation_id, None)?;
        tokio::spawn(async move {
            let result = async {
                let settings = store
                    .effective_ai_assist_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if !settings.enabled {
                    return Err(HostError::state("AI Assist is disabled."));
                }
                let text = if agent == "chatgpt" {
                    let service_tier = service_tier
                        .as_deref()
                        .or(Some(settings.chat_gpt_service_tier.as_str()));
                    super::chatgpt_inference::complete_with_options(
                        &prompt,
                        &model,
                        thinking_level.as_deref(),
                        service_tier,
                        thinking_context,
                        Duration::from_secs(timeout_seconds),
                        cancel_rx,
                    )
                    .await?
                } else {
                    complete_opencode_go(
                        &prompt,
                        &model,
                        &session_id,
                        Duration::from_secs(timeout_seconds),
                        cancel_rx,
                    )
                    .await?
                };
                Ok(json!({
                    "text": text,
                    "agentLabel": if agent == "chatgpt" { "ChatGPT" } else { OPENCODE_GO_LABEL },
                }))
            }
            .await;
            drop(registration);
            let _ = inbox.send(ServerCommand::AiAssistFinished {
                client_id,
                request_id,
                result,
            });
        });
        Ok(())
    }

    pub(super) fn start_opencode_go_models(
        &mut self,
        client_id: u64,
        request_id: i64,
    ) -> HostResult<()> {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = list_opencode_go_models(MODELS_TIMEOUT).await.map(|models| {
                let default_model_id = if models
                    .iter()
                    .any(|model| model.id == OPENCODE_GO_DEFAULT_MODEL)
                {
                    OPENCODE_GO_DEFAULT_MODEL
                } else {
                    models[0].id.as_str()
                };
                json!({
                    "models": models
                        .iter()
                        .map(|model| json!({"id": model.id, "label": model.label}))
                        .collect::<Vec<_>>(),
                    "defaultModelId": default_model_id,
                })
            });
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
