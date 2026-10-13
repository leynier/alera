//! Validates satellite events and mirrors only their public tab records.

use alera_core::runtime::{WorkspaceTabRecord, AGENT_CHAT_TAB_KIND};
use serde_json::{json, Value};

use super::{store_error, RemoteChatDirectory, RemoteChatRouter};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::AgentChatRuntime;
use crate::terminal_host::server::agent_chat_runtime::ChatRuntimeEvent;

pub(crate) async fn remote_chat_summaries(
    runtime: &AgentChatRuntime,
    payload: &Value,
) -> HostResult<Value> {
    let mut chats = runtime
        .list(
            payload["workspaceId"].as_str(),
            payload["includeArchived"].as_bool().unwrap_or(false),
        )
        .await?;
    for chat in &mut chats {
        if let Some(record) = runtime
            .store()
            .agent_chat(chat["chatId"].as_str().unwrap_or_default())
            .await
            .map_err(store_error)?
        {
            chat["runtimeMode"] = record.snapshot["session"]["runtimeMode"].clone();
            if let Some(metadata) = record.metadata {
                let mut lineage = serde_json::Map::new();
                for field in ["parentChatId", "taskId", "role"] {
                    if let Some(value) = metadata[field].as_str() {
                        lineage.insert(field.into(), json!(value));
                    }
                }
                chat["lineage"] = Value::Object(lineage);
            }
        }
    }
    Ok(json!({"chats":chats}))
}
use crate::terminal_host::server::{ServerActor, ServerCommand};

impl RemoteChatDirectory {
    pub(crate) fn publish(&self, change: ChatRuntimeEvent) {
        let _ = self.events.send(change);
    }

    fn accepts_cursor(&self, chat_id: &str, cursor: i64) -> bool {
        let mut cursors = self.cursors.lock().unwrap();
        if cursors.get(chat_id).is_some_and(|known| *known >= cursor) {
            return false;
        }
        cursors.insert(chat_id.into(), cursor);
        true
    }

    pub(crate) fn subscribe(&self) -> tokio::sync::broadcast::Receiver<ChatRuntimeEvent> {
        self.events.subscribe()
    }
}

impl RemoteChatRouter {
    pub(crate) async fn sync_workspace(&self, workspace_id: &str) -> HostResult<()> {
        let chats = self.list_remote(workspace_id, true).await?;
        let answer = self
            .transport
            .request(
                workspace_id,
                "tab.list",
                json!({"workspaceId": workspace_id}),
            )
            .await?;
        let tabs: Vec<WorkspaceTabRecord> = serde_json::from_value(answer)
            .map_err(|error| HostError::format(format!("Invalid remote tabs: {error}")))?;
        let mut kept = std::collections::HashSet::new();
        for mut tab in tabs {
            if tab.kind != AGENT_CHAT_TAB_KIND || tab.workspace_id != workspace_id {
                continue;
            }
            let Some(chat_id) = tab.payload["chatId"].as_str() else {
                continue;
            };
            if !chats.iter().any(|chat| {
                chat["chatId"].as_str() == Some(chat_id)
                    && chat["tabId"].as_str() == Some(tab.id.as_str())
                    && chat["archived"].as_bool() == Some(false)
            }) {
                continue;
            }
            let previous = self
                .store
                .find_workspace_tab(&tab.id)
                .await
                .map_err(store_error)?;
            if previous.is_some_and(|previous| {
                previous.workspace_id != workspace_id
                    || previous.kind != AGENT_CHAT_TAB_KIND
                    || previous.payload["chatId"] != tab.payload["chatId"]
            }) {
                continue;
            }
            kept.insert(tab.id.clone());
            let mut payload = serde_json::Map::new();
            for key in ["chatId", "provider", "providerInstanceId", "model"] {
                if let Some(value) = tab.payload[key].as_str() {
                    payload.insert(key.into(), json!(value));
                }
            }
            tab.payload = Value::Object(payload);
            tab.title = tab.title.chars().take(200).collect();
            self.store
                .upsert_workspace_tab(tab)
                .await
                .map_err(store_error)?;
        }
        for tab in self
            .store
            .list_workspace_tabs(workspace_id)
            .await
            .map_err(store_error)?
        {
            if tab.kind == AGENT_CHAT_TAB_KIND && !kept.contains(&tab.id) {
                self.store
                    .remove_workspace_tab(&tab.id)
                    .await
                    .map_err(store_error)?;
            }
        }
        Ok(())
    }

    pub(crate) async fn validated_change(
        &self,
        host_id: &str,
        payload: &Value,
    ) -> HostResult<Option<ChatRuntimeEvent>> {
        let (Some(workspace_id), Some(chat_id), Some(cursor), Some(delta)) = (
            payload["workspaceId"].as_str(),
            payload["chatId"].as_str(),
            payload["cursor"].as_i64(),
            payload.get("delta").filter(|delta| delta.is_object()),
        ) else {
            return Ok(None);
        };
        if cursor < 0 || self.remote_workspace(workspace_id).await?.as_deref() != Some(host_id) {
            return Ok(None);
        }
        if self.directory.route(chat_id).is_none() {
            self.list_remote(workspace_id, true).await?;
        }
        if self.directory.route(chat_id) != Some((workspace_id.into(), host_id.into())) {
            return Ok(None);
        }
        if !self.directory.accepts_cursor(chat_id, cursor) {
            return Ok(None);
        }
        Ok(Some(ChatRuntimeEvent::Changed {
            chat_id: chat_id.into(),
            workspace_id: workspace_id.into(),
            cursor,
            delta: delta.clone(),
        }))
    }
}

impl ServerActor {
    pub(crate) fn start_remote_agent_chat_sync(&self, host_id: &str) {
        let supported = match self.host_links.state(host_id) {
            crate::terminal_host::host_link::HostLinkState::Attached { attachment } => attachment
                .runtime_capabilities
                .iter()
                .any(|capability| capability == "agentChatV1"),
            _ => false,
        };
        if !supported {
            return;
        }
        self.relay_remote_agent_chat_event(host_id, "agentChatsChanged", &json!({}));
    }

    pub(crate) fn relay_remote_agent_chat_event(&self, host_id: &str, name: &str, payload: &Value) {
        let router = self.remote_chat_router();
        let inbox = self.inbox.clone();
        let host_id = host_id.to_owned();
        let name = name.to_owned();
        let payload = payload.clone();
        tokio::spawn(async move {
            let result: HostResult<()> = async {
                if name == "agentChatChanged" {
                    if let Some(change) = router.validated_change(&host_id, &payload).await? {
                        router.directory.publish(change.clone());
                        let _ = inbox.send(ServerCommand::AgentChatRuntimeEvent { event: change });
                    }
                } else {
                    for workspace in router
                        .store
                        .list_all_workspaces()
                        .await
                        .map_err(store_error)?
                    {
                        if workspace.host_id != host_id
                            || payload["workspaceId"]
                                .as_str()
                                .is_some_and(|id| id != workspace.id)
                        {
                            continue;
                        }
                        router.sync_workspace(&workspace.id).await?;
                        for change in [
                            ChatRuntimeEvent::ChatsChanged {
                                workspace_id: Some(workspace.id.clone()),
                            },
                            ChatRuntimeEvent::TabsChanged {
                                workspace_id: workspace.id.clone(),
                            },
                        ] {
                            router.directory.publish(change.clone());
                            let _ =
                                inbox.send(ServerCommand::AgentChatRuntimeEvent { event: change });
                        }
                    }
                }
                Ok(())
            }
            .await;
            if let Err(error) = result {
                tracing::warn!(target: "host_link", %host_id, "remote chat relay failed: {}", error.wire_message());
            }
        });
    }
}
