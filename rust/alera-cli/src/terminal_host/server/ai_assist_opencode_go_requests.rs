use std::time::Duration;

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_opencode_go::{
    complete_opencode_go, list_opencode_go_models, OPENCODE_GO_DEFAULT_MODEL, OPENCODE_GO_LABEL,
};
use super::ai_assist_operation_registry::active_generations;
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
        let model = optional_non_blank(payload, "model")
            .unwrap_or_else(|| OPENCODE_GO_DEFAULT_MODEL.to_string());
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
                let text = complete_opencode_go(
                    &prompt,
                    &model,
                    &session_id,
                    Duration::from_secs(timeout_seconds),
                    cancel_rx,
                )
                .await?;
                Ok(json!({
                    "text": text,
                    "agentLabel": OPENCODE_GO_LABEL,
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
                let default_model_id = models
                    .iter()
                    .any(|model| model.id == OPENCODE_GO_DEFAULT_MODEL)
                    .then_some(OPENCODE_GO_DEFAULT_MODEL)
                    .unwrap_or(models[0].id.as_str());
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
