//! Satellite-owned chats: routing metadata and tab mirrors, never transcripts.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use alera_core::runtime::{RuntimeStore, AGENT_CHAT_TAB_KIND};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::broadcast;

use super::agent_chat_runtime::{CallerCtx, ChatRuntimeEvent};
use super::host_link_routing::mirror_workspace;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

pub(crate) const INTERNAL_CHAT_REQUEST: &str = "agentChat.runtime";
pub(crate) use remote_events::remote_chat_summaries;

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
        link.request_with_timeout(
            verb,
            payload,
            crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
        )
        .await
        .map_err(remote_transport_error)
    }
    async fn request_host(&self, host_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        self.links
            .link(host_id)
            .await
            .map_err(|_| host_unavailable())?
            .request_with_timeout(
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

impl ServerActor {
    pub(super) fn remote_chat_router(&self) -> RemoteChatRouter {
        RemoteChatRouter::new(
            self.runtime_store.clone(),
            self.host_links.clone(),
            self.remote_agent_chats.clone(),
        )
    }

    pub(super) async fn try_start_agent_chat_remote_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !verb.starts_with("agentChat.") {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, verb)?;
        if verb == INTERNAL_CHAT_REQUEST {
            if !self.is_hub_link_client(client_id) {
                return Err(HostError::conflict(
                    "chat_scope_denied",
                    "Only the registered hub link may drive an internal chat request.",
                    json!({}),
                ));
            }
            if payload["operation"] != "wire" {
                let runtime = self
                    .agent_chat_runtime()
                    .ok_or_else(|| HostError::state("Agent chats are unavailable."))?;
                let payload = payload.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    super::chat_orchestration_remote::handle_internal_runtime(&runtime, &payload)
                        .await
                });
                return Ok(true);
            }
            let caller: CallerCtx = super::chat_orchestration_remote::decode(payload, "caller")?;
            let verb = super::chat_orchestration_remote::text(payload, "verb")?;
            if verb == INTERNAL_CHAT_REQUEST || !verb.starts_with("agentChat.") {
                return Err(HostError::format("Invalid internal chat verb."));
            }
            let runtime = self
                .agent_chat_runtime()
                .ok_or_else(|| HostError::state("Agent chats are unavailable."))?;
            let request_payload = payload["payload"].clone();
            let attachments = if verb == "agentChat.send" {
                let chat_id = super::agent_chat_runtime::commands::required_string(
                    &request_payload,
                    "chatId",
                )?;
                Some(
                    self.validated_agent_chat_attachments(
                        client_id,
                        caller.mobile,
                        &chat_id,
                        &request_payload,
                    )
                    .await?,
                )
            } else {
                None
            };
            self.spawn_agent_chat_request(client_id, request_id, async move {
                super::agent_chat_deferred::dispatch(
                    runtime,
                    &verb,
                    &request_payload,
                    caller,
                    attachments,
                )
                .await
            });
            return Ok(true);
        }
        // Mirrored satellite workspaces have local host ids and stay on their owner.
        let router = self.remote_chat_router();
        let workspace_id = match payload.get("chatId").and_then(Value::as_str) {
            Some(chat_id) => {
                if self
                    .runtime_store
                    .agent_chat(chat_id)
                    .await
                    .map_err(store_error)?
                    .is_some()
                {
                    return Ok(false);
                }
                router.directory.route(chat_id).map(|route| route.0)
            }
            None => payload
                .get("workspaceId")
                .and_then(Value::as_str)
                .map(str::to_owned),
        };
        let unscoped_list = verb == "agentChat.list" && workspace_id.is_none();
        if !unscoped_list
            && payload.get("chatId").is_none()
            && match &workspace_id {
                Some(id) => router.remote_workspace(id).await?.is_none(),
                None => true,
            }
        {
            return Ok(false);
        }
        let caller = self.agent_chat_caller(client_id);
        let payload = payload.clone();
        let verb = verb.to_owned();
        self.spawn_deferred_request(client_id, request_id, async move {
            router
                .forward_wire(&verb, &payload, caller)
                .await?
                .ok_or_else(|| HostError::conflict("chat_not_found", "Chat not found.", json!({})))
        });
        Ok(true)
    }
}

fn store_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
#[path = "agent_chat_remote_tests.rs"]
pub(crate) mod tests;

#[path = "agent_chat_remote_events.rs"]
mod remote_events;
