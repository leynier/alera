//! `chatOrchestration.requestSecret` and `agentChat.secret.provide`
//! (`agentChatSecretRequestsV1`): an agent asks for a secret in a masked
//! card; only a person answers it, from desktop or mobile. The value goes
//! straight from the provide verb to its delivery (a one-use ref or an
//! owner-only file) and never passes through the chat actor, its history,
//! its snapshots or a receipt.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{json, Value};
use tokio::sync::watch;

use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, ChatOp};
use crate::terminal_host::server::agent_chat_runtime::session_runtime_requests::{
    RuntimeRequestInput, SECRET_INPUT_KIND,
};

use super::authorization::OrchestrationCaller;
use super::secret_store::{SecretDelivery, SecretVault};
use super::service::ChatOrchestrationService;

/// How long one `requestSecret` call waits before it answers `pending`;
/// below the 50 s MCP call cap.
pub(crate) const SECRET_WAIT: Duration = Duration::from_secs(45);

const MAX_LABEL_CHARS: usize = 200;
const MAX_REASON_CHARS: usize = 2_000;
/// A secret is a token or key, not a document.
const MAX_SECRET_BYTES: usize = 64 * 1024;

pub(crate) struct ChatSecretBroker {
    pub(super) vault: SecretVault,
    waits: Mutex<HashMap<String, Arc<SecretWait>>>,
    pub(super) wait: Duration,
}

struct SecretWait {
    chat_id: String,
    delivery: SecretDelivery,
    outcome: watch::Sender<Option<Value>>,
}

impl ChatSecretBroker {
    pub(crate) fn new(vault: SecretVault) -> Self {
        Self {
            vault,
            waits: Mutex::default(),
            wait: SECRET_WAIT,
        }
    }

    #[cfg(test)]
    pub(crate) fn with_wait(mut self, wait: Duration) -> Self {
        self.wait = wait;
        self
    }

    fn get(&self, request_id: &str) -> Option<Arc<SecretWait>> {
        self.waits.lock().unwrap().get(request_id).cloned()
    }

    fn forget(&self, request_id: &str) {
        self.waits.lock().unwrap().remove(request_id);
    }
}

fn denied(message: &str) -> HostError {
    HostError::conflict("secret_request_denied", message, json!({}))
}

fn gone() -> HostError {
    HostError::conflict(
        "request_resolved",
        "This secret request no longer exists.",
        json!({}),
    )
}

pub(super) struct SecretAsk {
    pub request_id: Option<String>,
    pub label: Option<String>,
    pub reason: Option<String>,
    pub placeholder: Option<String>,
    pub delivery: Option<String>,
}

impl ChatOrchestrationService {
    fn secret_broker(&self) -> HostResult<&Arc<ChatSecretBroker>> {
        self.secrets.as_ref().ok_or_else(|| {
            HostError::conflict(
                "unsupported",
                "Secret requests are unavailable on this host.",
                json!({}),
            )
        })
    }

    pub(super) async fn request_secret(
        &self,
        ask: SecretAsk,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let broker = self.secret_broker()?.clone();
        let Some(bound) = caller.bound.as_ref() else {
            return Err(denied("Only an agent in a chat asks for a secret."));
        };
        broker.vault.sweep().await;
        let request_id = match ask.request_id {
            Some(request_id) => {
                let wait = broker.get(&request_id).ok_or_else(gone)?;
                if wait.chat_id != bound.chat_id {
                    return Err(gone());
                }
                request_id
            }
            None => self.open_secret_request(&broker, ask, caller).await?,
        };
        let wait = broker.get(&request_id).ok_or_else(gone)?;
        let mut outcome = wait.outcome.subscribe();
        let settled = tokio::time::timeout(broker.wait, async {
            outcome
                .wait_for(|outcome| outcome.is_some())
                .await
                .ok()
                .and_then(|outcome| outcome.clone())
        })
        .await;
        if let Ok(Some(result)) = settled {
            broker.forget(&request_id);
            return Ok(result);
        }
        let state = self
            .runtime
            .command(
                &bound.chat_id,
                ChatOp::RuntimeRequestState {
                    runtime_request_id: request_id.clone(),
                },
                caller.ctx.clone(),
                None,
            )
            .await?;
        if state["pending"] != true {
            broker.forget(&request_id);
            return Ok(json!({"status": "cancelled"}));
        }
        Ok(json!({
            "status": "pending",
            "requestId": request_id,
            "next": "The person has not answered yet. Call request_secret again with this requestId to keep waiting; do not ask again in chat.",
        }))
    }

    async fn open_secret_request(
        &self,
        broker: &ChatSecretBroker,
        ask: SecretAsk,
        caller: &OrchestrationCaller,
    ) -> HostResult<String> {
        let bound = caller.bound.as_ref().expect("bound secret caller");
        let label = bounded(ask.label, "label", MAX_LABEL_CHARS)?;
        let reason = bounded(ask.reason, "reason", MAX_REASON_CHARS)?;
        let delivery = SecretDelivery::parse(ask.delivery.as_deref())?;
        let mut question = json!({
            "id": "value",
            "header": label,
            "question": reason,
            "masked": true,
        });
        if let Some(placeholder) = ask.placeholder.filter(|text| !text.trim().is_empty()) {
            question["placeholder"] = json!(placeholder);
        }
        let opened = self
            .runtime
            .command(
                &bound.chat_id,
                ChatOp::OpenRuntimeRequest(RuntimeRequestInput {
                    kind: SECRET_INPUT_KIND.into(),
                    title: label,
                    detail: Some(reason),
                    question,
                }),
                caller.ctx.clone(),
                None,
            )
            .await?;
        let request_id = opened["runtimeRequestId"]
            .as_str()
            .ok_or_else(|| HostError::state("The secret request did not open."))?
            .to_owned();
        let (outcome, _) = watch::channel(None);
        broker.waits.lock().unwrap().insert(
            request_id.clone(),
            Arc::new(SecretWait {
                chat_id: bound.chat_id.clone(),
                delivery,
                outcome,
            }),
        );
        Ok(request_id)
    }

    /// `agentChat.secret.provide {chatId, runtimeRequestId, action, value?}`
    /// from a person. `action` is `save` (with `value`) or `decline`.
    pub(crate) async fn provide_secret(
        &self,
        payload: &Value,
        ctx: CallerCtx,
    ) -> HostResult<Value> {
        let broker = self.secret_broker()?.clone();
        let chat_id = text(payload, "chatId")?;
        let request_id = text(payload, "runtimeRequestId")?;
        let action = payload["action"].as_str().unwrap_or("save");
        let value = match action {
            "save" => {
                let value = payload["value"]
                    .as_str()
                    .filter(|value| !value.is_empty())
                    .ok_or_else(|| HostError::format("value is required"))?;
                if value.len() > MAX_SECRET_BYTES {
                    return Err(HostError::format("value is too long"));
                }
                register_secret(value);
                Some(value)
            }
            "decline" => None,
            _ => return Err(HostError::format("action must be save or decline")),
        };
        let wait = broker.get(&request_id).ok_or_else(gone)?;
        if wait.chat_id != chat_id {
            return Err(gone());
        }
        broker.vault.sweep().await;
        let saved = match value {
            Some(value) => Some(broker.vault.deliver(&chat_id, wait.delivery, value).await?),
            None => None,
        };
        let outcome = if saved.is_some() {
            "resolved"
        } else {
            "declined"
        };
        let resolved = self
            .runtime
            .command(
                &chat_id,
                ChatOp::ResolveRuntimeRequest {
                    runtime_request_id: request_id.clone(),
                    outcome: outcome.into(),
                },
                ctx,
                None,
            )
            .await;
        if let Err(error) = resolved {
            if let Some(saved) = &saved {
                broker.vault.discard(saved).await;
            }
            broker.forget(&request_id);
            return Err(error);
        }
        let result = saved.unwrap_or_else(|| json!({"status": "declined"}));
        wait.outcome.send_replace(Some(result.clone()));
        Ok(json!({"status": result["status"]}))
    }

    /// `chatOrchestration.readSecret {secretRef}` from `alera chat secret
    /// read`: a bound agent reads only refs saved for its own chat.
    pub(super) async fn read_secret(
        &self,
        secret_ref: &str,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let broker = self.secret_broker()?.clone();
        if caller.ctx.mobile {
            return Err(denied("A secret is read only on the host."));
        }
        let chat_id = caller.bound.as_ref().map(|bound| bound.chat_id.as_str());
        let value = broker.vault.consume(secret_ref, chat_id).await?;
        register_secret(&value);
        Ok(json!({"value": value}))
    }
}

fn text(payload: &Value, key: &str) -> HostResult<String> {
    payload[key]
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}

fn bounded(value: Option<String>, key: &str, max: usize) -> HostResult<String> {
    let value = value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::format(format!("{key} is required")))?;
    if value.chars().count() > max {
        return Err(HostError::format(format!("{key} is too long")));
    }
    Ok(value)
}
