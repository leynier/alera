//! Hub-led orchestration over the satellite's existing chat actors.

use std::sync::Arc;

use alera_core::runtime::ChatOrchestrationChildTurn;
use async_trait::async_trait;
use serde::de::DeserializeOwned;
use serde_json::{json, Value};
use tokio::sync::broadcast;

use super::agent_chat_remote::{RemoteChatRouter, INTERNAL_CHAT_REQUEST};
use super::agent_chat_runtime::{
    AgentChatRuntime, CallerCtx, ChatOp, ChatRuntimeEvent, CreateChatInput, ReceiptKey, SendInput,
};
use super::chat_orchestration::{
    BoundChat, ChatOrchestrationRuntime, ChatOrchestrationService, LocalChatOrchestrationRuntime,
    OrchestrationCaller,
};
use crate::terminal_host::host_error::{HostError, HostResult};

use super::chat_orchestration::operation_wire;

struct MergedChatEvents {
    sender: broadcast::Sender<ChatRuntimeEvent>,
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

impl Drop for MergedChatEvents {
    fn drop(&mut self) {
        for task in &self.tasks {
            task.abort();
        }
    }
}

pub(crate) struct RoutedChatRuntime {
    local: Arc<dyn ChatOrchestrationRuntime>,
    router: RemoteChatRouter,
    events: MergedChatEvents,
}

impl RoutedChatRuntime {
    pub(crate) fn new(local: AgentChatRuntime, router: RemoteChatRouter) -> Arc<Self> {
        let local: Arc<dyn ChatOrchestrationRuntime> =
            LocalChatOrchestrationRuntime::new(router.store.clone(), local);
        let sender = broadcast::channel(1024).0;
        let mut tasks = Vec::new();
        for mut source in [local.subscribe(), router.directory.subscribe()] {
            let sender = sender.clone();
            tasks.push(tokio::spawn(async move {
                loop {
                    let event = match source.recv().await {
                        Ok(event) => event,
                        Err(broadcast::error::RecvError::Lagged(_)) => {
                            ChatRuntimeEvent::ChatsChanged { workspace_id: None }
                        }
                        Err(broadcast::error::RecvError::Closed) => break,
                    };
                    let _ = sender.send(event);
                }
            }));
        }
        Arc::new(Self {
            local,
            router,
            events: MergedChatEvents { sender, tasks },
        })
    }

    async fn remote_chat_workspace(&self, chat_id: &str) -> HostResult<Option<String>> {
        let Some(workspace_id) = self.router.chat_workspace(chat_id).await? else {
            return Err(HostError::conflict(
                "chat_not_found",
                "Chat not found.",
                json!({}),
            ));
        };
        Ok(self
            .router
            .remote_workspace(&workspace_id)
            .await?
            .map(|_| workspace_id))
    }

    async fn remote_command(&self, workspace_id: &str, payload: Value) -> HostResult<Value> {
        self.router
            .transport
            .request(workspace_id, INTERNAL_CHAT_REQUEST, payload)
            .await
    }
}

#[async_trait]
impl ChatOrchestrationRuntime for RoutedChatRuntime {
    async fn create(
        &self,
        input: CreateChatInput,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(host_id) = self.router.remote_workspace(&input.workspace_id).await? {
            let workspace_id = input.workspace_id.clone();
            let value = self.remote_command(&workspace_id, json!({"operation": "create", "input": input, "caller": caller, "receipt": receipt})).await?;
            if let Some(chat_id) = value["chatId"].as_str() {
                self.router
                    .directory
                    .remember(chat_id, &workspace_id, &host_id);
            }
            if let Err(error) = self.router.sync_workspace(&workspace_id).await {
                tracing::warn!(target: "host_link", %workspace_id, "chat committed before its tab mirror synchronized: {}", error.wire_message());
            }
            return Ok(value);
        }
        self.local.create(input, caller, receipt).await
    }

    async fn list(
        &self,
        workspace_id: Option<&str>,
        include_archived: bool,
    ) -> HostResult<Vec<Value>> {
        if let Some(workspace_id) = workspace_id {
            if self.router.remote_workspace(workspace_id).await?.is_some() {
                return self
                    .router
                    .list_remote(workspace_id, include_archived)
                    .await;
            }
            return self.local.list(Some(workspace_id), include_archived).await;
        }
        let mut chats = self.local.list(None, include_archived).await?;
        for workspace in self
            .router
            .store
            .list_all_workspaces()
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            if crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
                chats.extend(
                    self.router
                        .list_remote(&workspace.id, include_archived)
                        .await?,
                );
            }
        }
        Ok(chats)
    }

    async fn providers(&self, workspace_id: Option<&str>, refresh: bool) -> HostResult<Value> {
        if let Some(workspace_id) = workspace_id {
            if self.router.remote_workspace(workspace_id).await?.is_some() {
                return self
                    .router
                    .transport
                    .request(
                        workspace_id,
                        "agentChat.providers",
                        json!({"workspaceId": workspace_id, "refreshModels": refresh}),
                    )
                    .await;
            }
        }
        self.local.providers(workspace_id, refresh).await
    }

    async fn providers_for_host(
        &self,
        workspace_id: Option<&str>,
        host_id: Option<&str>,
        refresh: bool,
    ) -> HostResult<Value> {
        if let Some(workspace_id) = workspace_id {
            let owner = self
                .router
                .store
                .find_workspace(workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| HostError::state("Unknown workspace."))?;
            if host_id.is_some_and(|requested| requested != owner.host_id) {
                return Err(HostError::conflict(
                    "invalid_target",
                    "The workspace belongs to another host.",
                    json!({}),
                ));
            }
            return self.providers(Some(workspace_id), refresh).await;
        }
        match host_id {
            None | Some("local") => self.local.providers(None, refresh).await,
            Some(host_id) => {
                self.router
                    .transport
                    .request_host(
                        host_id,
                        "agentChat.providers",
                        json!({"refreshModels": refresh}),
                    )
                    .await
            }
        }
    }

    async fn command(
        &self,
        chat_id: &str,
        operation: ChatOp,
        caller: CallerCtx,
        receipt: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        if let Some(workspace_id) = self.remote_chat_workspace(chat_id).await? {
            let operation = operation_wire::encode_operation(&operation);
            return self.remote_command(&workspace_id, json!({"operation": "command", "chatId": chat_id, "op": operation, "caller": caller, "receipt": receipt})).await;
        }
        self.local
            .command(chat_id, operation, caller, receipt)
            .await
    }

    async fn send(&self, chat_id: &str, input: SendInput, caller: CallerCtx) -> HostResult<Value> {
        self.command(chat_id, ChatOp::Send(input), caller, None)
            .await
    }

    async fn snapshot(&self, chat_id: &str) -> HostResult<Value> {
        self.command(chat_id, ChatOp::Snapshot, CallerCtx::runtime(), None)
            .await
    }

    async fn validate_binding(&self, binding: &BoundChat) -> HostResult<Value> {
        let Some(origin_host_id) = &binding.origin_host_id else {
            return self.local.validate_binding(binding).await;
        };
        let workspace_id = self
            .remote_chat_workspace(&binding.chat_id)
            .await?
            .ok_or_else(invalid_binding)?;
        if self
            .router
            .remote_workspace(&workspace_id)
            .await?
            .as_deref()
            != Some(origin_host_id)
        {
            return Err(invalid_binding());
        }
        self.remote_command(&workspace_id, json!({"operation": "validateBinding", "chatId": binding.chat_id, "generation": binding.generation, "credentialHash": binding.credential_hash})).await
    }

    async fn turn_for_client_message(
        &self,
        chat_id: &str,
        client_message_id: &str,
    ) -> HostResult<Option<Value>> {
        if let Some(workspace_id) = self.remote_chat_workspace(chat_id).await? {
            let value = self.remote_command(&workspace_id, json!({"operation": "turnForClientMessage", "chatId": chat_id, "clientMessageId": client_message_id})).await?;
            return Ok((!value.is_null()).then_some(value));
        }
        self.local
            .turn_for_client_message(chat_id, client_message_id)
            .await
    }

    async fn child_turn(
        &self,
        chat_id: &str,
        turn_id: &str,
    ) -> HostResult<Option<ChatOrchestrationChildTurn>> {
        if let Some(workspace_id) = self.remote_chat_workspace(chat_id).await? {
            let value = self
                .remote_command(
                    &workspace_id,
                    json!({"operation": "childTurn", "chatId": chat_id, "turnId": turn_id}),
                )
                .await?;
            return Ok((!value.is_null()).then(|| ChatOrchestrationChildTurn {
                turn_status: value["turnStatus"].as_str().map(str::to_owned),
                final_assistant_text: value["finalAssistantText"].as_str().map(str::to_owned),
            }));
        }
        self.local.child_turn(chat_id, turn_id).await
    }

    fn subscribe(&self) -> broadcast::Receiver<ChatRuntimeEvent> {
        self.events.sender.subscribe()
    }
}

pub(crate) async fn handle_internal_runtime(
    runtime: &AgentChatRuntime,
    payload: &Value,
) -> HostResult<Value> {
    let store = runtime.store();
    let local = LocalChatOrchestrationRuntime::new(store.clone(), runtime.clone());
    match payload["operation"].as_str().unwrap_or_default() {
        "summaries" => super::agent_chat_remote::remote_chat_summaries(runtime, payload).await,
        "create" => runtime.create(decode(payload, "input")?, decode(payload, "caller")?, decode_optional(payload, "receipt")?).await,
        "command" => runtime.command(&text(payload, "chatId")?, operation_wire::decode_operation(payload)?, decode(payload, "caller")?, decode_optional(payload, "receipt")?).await,
        "validateBinding" => local.validate_binding(&BoundChat { chat_id: text(payload, "chatId")?, generation: payload["generation"].as_i64().filter(|generation| *generation > 0).ok_or_else(invalid_binding)?, credential_hash: text(payload, "credentialHash")?, runtime_mode: "approval-required".into(), origin_host_id: None }).await,
        "turnForClientMessage" => Ok(local.turn_for_client_message(&text(payload, "chatId")?, &text(payload, "clientMessageId")?).await?.unwrap_or(Value::Null)),
        "childTurn" => Ok(local.child_turn(&text(payload, "chatId")?, &text(payload, "turnId")?).await?.map(|turn| json!({"turnStatus": turn.turn_status, "finalAssistantText": turn.final_assistant_text})).unwrap_or(Value::Null)),
        _ => Err(HostError::format("Unknown internal chat operation.")),
    }
}

pub(super) fn is_chat_orchestration_verb(verb: &str) -> bool {
    matches!(
        verb.strip_prefix("chatOrchestration."),
        Some(
            "capabilities"
                | "delegate"
                | "send"
                | "task"
                | "tasks.list"
                | "wait"
                | "cancel"
                | "interrupt"
                | "backgroundWait"
                | "requests"
                | "respond"
                | "configure"
                | "read"
                | "transfers"
                | "list"
        )
    )
}

/// This envelope is stamped from the authenticated satellite connection.
pub(super) fn forwarded_binding(binding: &BoundChat) -> Value {
    json!({"originChatId": binding.chat_id, "generation": binding.generation, "credentialHash": binding.credential_hash})
}

pub(super) async fn answer_remote_orchestration(
    service: Option<ChatOrchestrationService>,
    router: RemoteChatRouter,
    host_id: &str,
    verb: &str,
    payload: &Value,
    authority: Option<&Value>,
) -> HostResult<Value> {
    if !is_chat_orchestration_verb(verb) {
        return Err(HostError::conflict(
            "chat_scope_denied",
            "The remote chat verb is not allowed.",
            json!({}),
        ));
    }
    let service = service.ok_or_else(|| HostError::state("Chat orchestration is unavailable."))?;
    let caller = if let Some(authority) = authority {
        let chat_id = text(authority, "originChatId").map_err(|_| invalid_binding())?;
        let workspace_id = router
            .chat_workspace(&chat_id)
            .await?
            .ok_or_else(invalid_binding)?;
        if router.remote_workspace(&workspace_id).await?.as_deref() != Some(host_id) {
            return Err(invalid_binding());
        }
        let credential_hash = text(authority, "credentialHash").map_err(|_| invalid_binding())?;
        if credential_hash.len() != 64
            || !credential_hash.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(invalid_binding());
        }
        OrchestrationCaller::agent(
            CallerCtx {
                scope: format!("chat:{chat_id}"),
                actor: format!("agent:{chat_id}"),
                mobile: false,
            },
            BoundChat {
                chat_id,
                generation: authority["generation"]
                    .as_i64()
                    .filter(|generation| *generation > 0)
                    .ok_or_else(invalid_binding)?,
                credential_hash,
                runtime_mode: "approval-required".into(),
                origin_host_id: Some(host_id.into()),
            },
        )
    } else {
        OrchestrationCaller::human(CallerCtx {
            scope: format!("remote-cli:{host_id}"),
            actor: format!("remote-cli:{host_id}"),
            mobile: false,
        })
    };
    let payload = super::hub_reverse_policy::apply_origin(verb, payload.clone(), host_id);
    service
        .handle(
            verb.strip_prefix("chatOrchestration.").unwrap(),
            &payload,
            &caller,
        )
        .await
}

pub(super) fn decode<T: DeserializeOwned>(payload: &Value, field: &str) -> HostResult<T> {
    serde_json::from_value(
        payload
            .get(field)
            .cloned()
            .ok_or_else(|| HostError::format(format!("{field} is required")))?,
    )
    .map_err(|error| HostError::format(format!("Invalid {field}: {error}")))
}

fn decode_optional<T: DeserializeOwned>(payload: &Value, field: &str) -> HostResult<Option<T>> {
    match payload.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(_) => decode(payload, field).map(Some),
    }
}

pub(super) fn text(payload: &Value, field: &str) -> HostResult<String> {
    payload[field]
        .as_str()
        .filter(|value| !value.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| HostError::format(format!("{field} is required")))
}

fn invalid_binding() -> HostError {
    HostError::conflict(
        "chat_credential_invalid",
        "The chat credential is invalid or expired.",
        json!({}),
    )
}

#[cfg(test)]
#[path = "chat_orchestration_remote_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "chat_orchestration_remote_parent_tests.rs"]
mod parent_tests;
