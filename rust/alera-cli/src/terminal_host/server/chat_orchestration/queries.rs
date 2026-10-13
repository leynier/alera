use alera_core::runtime::{
    chat_orchestration_request_digest, ChatOrchestrationReceipt, ChatOrchestrationReceiptCheck,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::{ChatOp, ReceiptKey};

use super::authorization::OrchestrationCaller;
use super::models::ListInput;
use super::service::ChatOrchestrationService;
use super::tasks::list_tasks;

pub(super) fn runtime_receipt_key(
    scope: &str,
    verb: &str,
    request_id: &str,
    chat_id: &str,
    operation: &ChatOp,
) -> ReceiptKey {
    ReceiptKey {
        verb: format!("chatOrchestration.{verb}"),
        request_id: chat_orchestration_request_digest(
            "runtime_identity",
            &json!({"scope":scope, "verb":verb, "id":request_id}),
        ),
        digest: chat_orchestration_request_digest(
            verb,
            &json!({"chatId":chat_id, "operation":operation}),
        ),
    }
}

impl ChatOrchestrationService {
    pub(super) async fn tasks_list(
        &self,
        input: ListInput,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let mut value = list_tasks(&self.store, &input).await?;
        if caller.bound.is_some() {
            if let Some(tasks) = value.get_mut("tasks").and_then(Value::as_array_mut) {
                for task in tasks {
                    let mutable = if let (Some(bound), Some(task_id)) =
                        (&caller.bound, task["taskId"].as_str())
                    {
                        self.store
                            .is_chat_orchestration_task_in_lineage(&bound.chat_id, task_id)
                            .await
                            .map_err(|error| HostError::state(error.to_string()))?
                    } else {
                        false
                    };
                    task["readOnly"] = json!(!mutable);
                }
            }
        }
        Ok(value)
    }

    pub(super) async fn read(&self, chat_id: String, limit: usize) -> HostResult<Value> {
        let snapshot = self.runtime.snapshot(&chat_id).await?;
        let mut chat = json!({
            "chatId": snapshot["chatId"],
            "workspaceId": snapshot["workspaceId"],
            "tabId": snapshot["tabId"],
            "title": snapshot["title"],
            "provider": snapshot["provider"],
            "providerInstanceId": snapshot["providerInstanceId"],
            "archived": snapshot["archived"],
            "status": snapshot["session"]["status"],
            "model": snapshot["session"]["model"],
            "runtimeMode": snapshot["session"]["runtimeMode"],
        });
        self.project_chat_context(&mut chat).await?;
        let items = snapshot
            .get("items")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let visible = items
            .iter()
            .filter(|item| item["type"] == "user_message" || item["type"] == "assistant_message")
            .collect::<Vec<_>>();
        let mut messages = visible
            .iter()
            .rev()
            .take(limit)
            .map(|item| {
                json!({
                    "itemId": item["itemId"],
                    "role": if item["type"] == "user_message" { "user" } else { "assistant" },
                    "text": item["text"],
                    "createdAt": item["createdAt"],
                    "origin": {
                        "kind":item["normalized"]["origin"]["kind"],
                        "senderChatId":item["normalized"]["origin"]["senderChatId"],
                        "taskIds":item["normalized"]["origin"]["taskIds"],
                    },
                })
            })
            .collect::<Vec<_>>();
        messages.reverse();
        let plans = items
            .iter()
            .filter(|item| item["type"] == "plan")
            .map(|item| {
                json!({
                    "itemId": item["itemId"],
                    "explanation": item["normalized"]["explanation"],
                    "steps": item["normalized"]["planSteps"].as_array().into_iter().flatten()
                        .map(|step| json!({"step":step["step"], "status":step["status"]})).collect::<Vec<_>>(),
                })
            })
            .collect::<Vec<_>>();
        Ok(json!({
            "chat": chat,
            "messages": messages,
            "plans": plans,
            "truncated": visible.len() > limit || snapshot.get("historyBefore").is_some_and(|value| !value.is_null()),
        }))
    }

    pub(super) async fn list_chats(
        &self,
        workspace_id: Option<String>,
        project_id: Option<String>,
        host_id: Option<String>,
        include_archived: bool,
    ) -> HostResult<Value> {
        let mut chats = Vec::new();
        for mut chat in self
            .runtime
            .list(workspace_id.as_deref(), include_archived)
            .await?
        {
            self.project_chat_context(&mut chat).await?;
            if project_id
                .as_deref()
                .is_some_and(|id| chat["projectId"].as_str() != Some(id))
                || host_id
                    .as_deref()
                    .is_some_and(|id| chat["hostId"].as_str() != Some(id))
            {
                continue;
            }
            chats.push(chat);
        }
        Ok(json!({"chats": chats}))
    }

    async fn project_chat_context(&self, chat: &mut Value) -> HostResult<()> {
        if let Some(workspace_id) = chat["workspaceId"].as_str() {
            if let Some(workspace) = self
                .store
                .find_workspace(workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                chat["projectId"] = json!(workspace.project_id);
                chat["hostId"] = json!(workspace.host_id);
            }
        }
        if let Some(chat_id) = chat["chatId"].as_str() {
            if let Some(record) = self
                .store
                .agent_chat(chat_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                chat["runtimeMode"] = record.snapshot["session"]["runtimeMode"].clone();
                if let Some(metadata) = record.metadata {
                    chat["lineage"] = json!({"parentChatId":metadata["parentChatId"],
                        "taskId":metadata["taskId"], "role":metadata["role"]});
                }
            }
        }
        Ok(())
    }

    pub(super) async fn check_receipt(
        &self,
        caller: &OrchestrationCaller,
        verb: &str,
        request_id: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let digest = chat_orchestration_request_digest(verb, payload);
        match self
            .store
            .check_chat_orchestration_receipt(&caller.ctx.scope, verb, request_id, &digest)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            ChatOrchestrationReceiptCheck::New => Ok(None),
            ChatOrchestrationReceiptCheck::Replay(response) => Ok(Some(response)),
            ChatOrchestrationReceiptCheck::Conflict => Err(HostError::conflict(
                "request_conflict",
                "This requestId was already used for a different request.",
                json!({}),
            )),
        }
    }

    pub(super) async fn record_receipt(
        &self,
        caller: &OrchestrationCaller,
        verb: &str,
        request_id: &str,
        payload: &Value,
        response: Value,
    ) -> HostResult<()> {
        let digest = chat_orchestration_request_digest(verb, payload);
        match self
            .store
            .record_chat_orchestration_receipt(
                None,
                &ChatOrchestrationReceipt {
                    scope: caller.ctx.scope.clone(),
                    verb: verb.into(),
                    request_id: request_id.into(),
                    digest,
                    response,
                },
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            ChatOrchestrationReceiptCheck::Conflict => Err(HostError::conflict(
                "request_conflict",
                "This requestId was already used for a different request.",
                json!({}),
            )),
            _ => Ok(()),
        }
    }
}
