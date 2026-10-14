//! Satellite-owned chats: routing metadata and tab mirrors, never transcripts.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use alera_core::runtime::{RuntimeStore, AGENT_CHAT_TAB_KIND};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::broadcast;

use super::agent_chat_runtime::{CallerCtx, ChatRuntimeEvent};
use super::host_link_routing::mirror_workspace;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

pub(crate) const INTERNAL_CHAT_REQUEST: &str = "agentChat.runtime";
pub(crate) use remote_events::remote_chat_summaries;

fn store_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

/// Only the identity needed to find a chat's owner is retained at the hub.
#[derive(Clone)]
pub(crate) struct RemoteChatDirectory {
    routes: Arc<Mutex<HashMap<String, (String, String)>>>,
    cursors: Arc<Mutex<HashMap<String, i64>>>,
    events: broadcast::Sender<ChatRuntimeEvent>,
}

impl Default for RemoteChatDirectory {
    fn default() -> Self {
        Self {
            routes: Default::default(),
            cursors: Default::default(),
            events: broadcast::channel(1024).0,
        }
    }
}

impl RemoteChatDirectory {
    pub(crate) fn route(&self, chat_id: &str) -> Option<(String, String)> {
        self.routes.lock().unwrap().get(chat_id).cloned()
    }

    pub(crate) fn remember(&self, chat_id: &str, workspace_id: &str, host_id: &str) {
        self.routes
            .lock()
            .unwrap()
            .insert(chat_id.into(), (workspace_id.into(), host_id.into()));
    }
}

#[async_trait]
pub(crate) trait RemoteChatTransport: Send + Sync {
    async fn request(&self, workspace_id: &str, verb: &str, payload: Value) -> HostResult<Value>;
    async fn request_host(
        &self,
        _host_id: &str,
        _verb: &str,
        _payload: Value,
    ) -> HostResult<Value> {
        Err(HostError::conflict(
            "host_unavailable",
            "The remote host is unavailable.",
            json!({}),
        ))
    }
}

#[derive(Clone)]
pub(crate) struct LinkedChatTransport {
    pub(crate) store: RuntimeStore,
    pub(crate) links: HostLinkRegistry,
}

#[async_trait]
impl RemoteChatTransport for LinkedChatTransport {
    async fn request(&self, workspace_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        let (link, _) = mirror_workspace(&self.store, &self.links, workspace_id)
            .await
            .map_err(|_| host_unavailable())?;
        super::agent_chat_attachment_requests::require_remote_upload_capability(
            &payload,
            &link.attachment().runtime_capabilities,
        )?;
        link.request_with_timeout(
            verb,
            payload,
            crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
        )
        .await
        .map_err(remote_transport_error)
    }
    async fn request_host(&self, host_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        let link = self
            .links
            .link(host_id)
            .await
            .map_err(|_| host_unavailable())?;
        super::agent_chat_attachment_requests::require_remote_upload_capability(
            &payload,
            &link.attachment().runtime_capabilities,
        )?;
        link.request_with_timeout(
            verb,
            payload,
            crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
        )
        .await
        .map_err(remote_transport_error)
    }
}

fn host_unavailable() -> HostError {
    HostError::conflict(
        "host_unavailable",
        "The remote chat host is unavailable.",
        json!({}),
    )
}

fn remote_transport_error(error: HostError) -> HostError {
    match &error {
        HostError::State(message)
            if message.starts_with("The link to host ")
                || message.starts_with("The host ") && message.contains("did not answer") =>
        {
            host_unavailable()
        }
        _ => error,
    }
}

#[derive(Clone)]
pub(crate) struct RemoteChatRouter {
    pub(crate) store: RuntimeStore,
    pub(crate) directory: RemoteChatDirectory,
    pub(crate) transport: Arc<dyn RemoteChatTransport>,
}

impl RemoteChatRouter {
    pub(crate) fn new(
        store: RuntimeStore,
        links: HostLinkRegistry,
        directory: RemoteChatDirectory,
    ) -> Self {
        Self {
            transport: Arc::new(LinkedChatTransport {
                store: store.clone(),
                links,
            }),
            store,
            directory,
        }
    }

    pub(crate) async fn remote_workspace(&self, workspace_id: &str) -> HostResult<Option<String>> {
        let workspace = self
            .store
            .find_workspace(workspace_id)
            .await
            .map_err(store_error)?;
        Ok(workspace
            .filter(|workspace| crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)))
            .map(|workspace| workspace.host_id))
    }

    pub(crate) async fn chat_workspace(&self, chat_id: &str) -> HostResult<Option<String>> {
        if let Some(chat) = self.store.agent_chat(chat_id).await.map_err(store_error)? {
            return Ok(Some(chat.workspace_id));
        }
        if let Some((workspace_id, host_id)) = self.directory.route(chat_id) {
            if self.remote_workspace(&workspace_id).await?.as_deref() == Some(&host_id) {
                return Ok(Some(workspace_id));
            }
        }
        for tab in self
            .store
            .list_all_workspace_tabs()
            .await
            .map_err(store_error)?
        {
            if tab.kind == AGENT_CHAT_TAB_KIND && tab.payload["chatId"].as_str() == Some(chat_id) {
                return Ok(Some(tab.workspace_id));
            }
        }
        // An archived chat has no tab, and the directory is empty after restart.
        // Ask owners for summaries so reopen can still carry only chatId.
        let mut unavailable = None;
        for workspace in self
            .store
            .list_all_workspaces()
            .await
            .map_err(store_error)?
        {
            if !crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
                continue;
            }
            match self.list_remote(&workspace.id, true).await {
                Ok(chats)
                    if chats
                        .iter()
                        .any(|chat| chat["chatId"].as_str() == Some(chat_id)) =>
                {
                    return Ok(Some(workspace.id))
                }
                Ok(_) => {}
                Err(error) => unavailable = Some(error),
            }
        }
        if let Some(error) = unavailable {
            return Err(error);
        }
        Ok(None)
    }

    pub(crate) async fn list_remote(
        &self,
        workspace_id: &str,
        include_archived: bool,
    ) -> HostResult<Vec<Value>> {
        let host_id = self
            .remote_workspace(workspace_id)
            .await?
            .ok_or_else(|| HostError::state("The chat workspace is not remote."))?;
        let answer = self
            .transport
            .request(
                workspace_id,
                INTERNAL_CHAT_REQUEST,
                json!({"operation":"summaries", "workspaceId": workspace_id, "includeArchived": include_archived}),
            )
            .await?;
        let chats = answer["chats"]
            .as_array()
            .ok_or_else(|| HostError::format("Invalid remote chat list."))?;
        let mut owned = Vec::new();
        for chat in chats {
            if chat["workspaceId"].as_str() != Some(workspace_id) {
                continue;
            }
            let Some(chat_id) = chat["chatId"].as_str().filter(|id| !id.is_empty()) else {
                continue;
            };
            if self
                .store
                .agent_chat(chat_id)
                .await
                .map_err(store_error)?
                .is_some()
                || self
                    .directory
                    .route(chat_id)
                    .is_some_and(|route| route.0 != workspace_id)
            {
                continue;
            }
            self.directory.remember(chat_id, workspace_id, &host_id);
            // Project only public summary fields, even if a satellite over-reports.
            let mut summary = serde_json::Map::new();
            for key in [
                "chatId",
                "workspaceId",
                "tabId",
                "title",
                "provider",
                "providerInstanceId",
                "model",
                "status",
                "archived",
                "cursor",
                "updatedAt",
                "runtimeMode",
                "lineage",
            ] {
                if let Some(value) = chat.get(key) {
                    summary.insert(key.into(), value.clone());
                }
            }
            if let Some(lineage) = summary.get_mut("lineage") {
                let mut projected = serde_json::Map::new();
                for key in ["parentChatId", "taskId", "role"] {
                    if let Some(value) = lineage[key].as_str() {
                        projected.insert(key.into(), json!(value));
                    }
                }
                *lineage = Value::Object(projected);
            }
            owned.push(Value::Object(summary));
        }
        Ok(owned)
    }

    pub(crate) async fn forward_wire(
        &self,
        verb: &str,
        payload: &Value,
        caller: CallerCtx,
    ) -> HostResult<Option<Value>> {
        if !verb.starts_with("agentChat.") || verb == INTERNAL_CHAT_REQUEST {
            return Ok(None);
        }
        if let Some(host_id) = payload
            .get("hostId")
            .and_then(Value::as_str)
            .filter(|id| *id != "local")
        {
            return self
                .transport
                .request_host(
                    host_id,
                    INTERNAL_CHAT_REQUEST,
                    json!({"operation":"wire", "verb":verb, "payload":payload, "caller":caller}),
                )
                .await
                .map(Some);
        }
        if verb == "agentChat.list" && payload.get("workspaceId").is_none_or(Value::is_null) {
            let archived = payload["includeArchived"].as_bool().unwrap_or(false);
            let mut chats: Vec<Value> = self
                .store
                .list_all_agent_chats(archived)
                .await
                .map_err(store_error)?
                .iter()
                .map(super::agent_chat_runtime::runtime_handle::chat_summary)
                .collect();
            for workspace in self
                .store
                .list_all_workspaces()
                .await
                .map_err(store_error)?
            {
                if crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
                    chats.extend(self.list_remote(&workspace.id, archived).await?);
                }
            }
            return Ok(Some(json!({"chats": chats})));
        }
        let workspace_id = match payload.get("chatId").and_then(Value::as_str) {
            Some(chat_id) => self.chat_workspace(chat_id).await?,
            None => payload
                .get("workspaceId")
                .and_then(Value::as_str)
                .map(str::to_owned),
        };
        let Some(workspace_id) = workspace_id else {
            return Ok(None);
        };
        let Some(host_id) = self.remote_workspace(&workspace_id).await? else {
            return Ok(None);
        };
        let value = self
            .transport
            .request(
                &workspace_id,
                INTERNAL_CHAT_REQUEST,
                json!({"operation": "wire", "verb": verb, "payload": payload, "caller": caller}),
            )
            .await?;
        let snapshot = value.get("snapshot").unwrap_or(&value);
        if snapshot["workspaceId"].as_str() == Some(workspace_id.as_str()) {
            if let Some(chat_id) = snapshot["chatId"].as_str() {
                self.directory.remember(chat_id, &workspace_id, &host_id);
            }
        }
        if matches!(
            verb,
            "agentChat.create"
                | "agentChat.reopen"
                | "agentChat.close"
                | "agentChat.rename"
                | "agentChat.configure"
        ) {
            if let Err(error) = self.sync_workspace(&workspace_id).await {
                tracing::warn!(target: "host_link", %workspace_id, "chat committed before its tab mirror synchronized: {}", error.wire_message());
            }
        }
        Ok(Some(value))
    }
}

#[path = "agent_chat_remote_requests.rs"]
mod remote_requests;

#[cfg(test)]
#[path = "agent_chat_remote_tests.rs"]
pub(crate) mod tests;

#[path = "agent_chat_remote_events.rs"]
mod remote_events;
