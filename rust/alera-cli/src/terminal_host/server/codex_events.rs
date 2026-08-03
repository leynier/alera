//! Reduction and fan-out of Codex app-server notifications.

use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::event;

use super::codex_state::{
    active_turn_id, append_message, is_codex_tab, snapshot, tab_thread_id, thread_id_from_message,
    turn_id_from_message,
};
use super::ServerActor;

fn is_streaming_codex_message(message: &Value) -> bool {
    let method = message
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    method.contains("delta") || method == "turn/diff/updated"
}

impl ServerActor {
    pub(super) async fn handle_codex_message(&mut self, message: Value) {
        if message.get("method").and_then(Value::as_str) == Some("currentTime/read") {
            let Some(id) = message.get("id").cloned() else {
                return;
            };
            let Some(server) = self.codex.as_ref().cloned() else {
                return;
            };
            if let Err(error) = server
                .respond(
                    id,
                    Some(json!({"currentTimeAt": Utc::now().timestamp()})),
                    None,
                )
                .await
            {
                self.broadcast_codex_server_error(error.wire_message());
            }
            return;
        }
        let thread_id = thread_id_from_message(&message);
        let tab = match self
            .find_codex_tab_for_message(&message, thread_id.as_deref())
            .await
        {
            Ok(Some(tab)) => tab,
            Ok(None) => {
                if let Some(id) = message.get("id").cloned() {
                    self.reject_unroutable_codex_request(id).await;
                } else {
                    self.broadcast_authenticated(event(
                        "codexThreadChanged",
                        json!({"message": message}),
                    ));
                }
                return;
            }
            Err(error) => {
                self.broadcast_codex_server_error(error.to_string());
                return;
            }
        };
        if is_streaming_codex_message(&message) {
            self.queue_codex_message(&tab.id, message).await;
            return;
        }
        self.handle_codex_flush(&tab.id).await;
        self.persist_codex_messages(tab, vec![message]).await;
    }

    pub(super) async fn handle_codex_flush(&mut self, tab_id: &str) {
        self.codex_flush_scheduled.remove(tab_id);
        let Some(messages) = self.codex_pending_messages.remove(tab_id) else {
            return;
        };
        if messages.is_empty() {
            return;
        }
        let tab = match self.find_codex_tab_by_id(tab_id).await {
            Ok(Some(tab)) => tab,
            Ok(None) => return,
            Err(error) => {
                self.broadcast_codex_server_error(error.to_string());
                return;
            }
        };
        self.persist_codex_messages(tab, messages).await;
    }

    async fn queue_codex_message(&mut self, tab_id: &str, message: Value) {
        let pending = self
            .codex_pending_messages
            .entry(tab_id.to_string())
            .or_default();
        pending.push(message);
        let should_flush_now = pending.len() >= 128;
        if self.codex_flush_scheduled.insert(tab_id.to_string()) {
            let inbox = self.inbox.clone();
            let tab_id = tab_id.to_string();
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_millis(32)).await;
                let _ = inbox.send(super::ServerCommand::CodexFlush { tab_id });
            });
        }
        if should_flush_now {
            self.handle_codex_flush(tab_id).await;
        }
    }

    async fn persist_codex_messages(
        &mut self,
        tab: alera_core::runtime::WorkspaceTabRecord,
        messages: Vec<Value>,
    ) {
        let mut next = tab.clone();
        let mut title_changed = false;
        for message in &messages {
            append_message(&mut next, message.clone());
            if let Some(title) = super::codex_state::thread_title_from_message(message) {
                if !next
                    .payload
                    .get("manualTitle")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    title_changed |= next.title != title;
                    next.title = title;
                }
            }
        }
        let next_snapshot = snapshot(&next);
        let next_active_turn_id = active_turn_id(&next_snapshot);
        if let Some(payload) = next.payload.as_object_mut() {
            payload.insert("codexSnapshot".to_string(), next_snapshot);
            match next_active_turn_id {
                Some(turn_id) => {
                    payload.insert("codexActiveTurnId".to_string(), Value::String(turn_id));
                }
                None => {
                    payload.remove("codexActiveTurnId");
                }
            }
        }
        next.updated_at = Utc::now();
        let saved = match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => saved,
            Err(error) => {
                self.broadcast_codex_server_error(error.to_string());
                return;
            }
        };
        self.refresh_codex_presence(&saved);
        if title_changed {
            self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        }
        self.schedule_codex_presence_changed();
        let message = messages.last().cloned().unwrap_or(Value::Null);
        let thread_id = messages
            .iter()
            .rev()
            .find_map(thread_id_from_message)
            .or_else(|| tab_thread_id(&saved));
        self.broadcast_authenticated(event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": thread_id,
                "message": message,
                "coalescedMessages": messages.len(),
                "snapshot": snapshot(&saved),
            }),
        ));
    }

    pub(super) async fn handle_codex_process_exited(&mut self, reason: String) {
        let pending_ids = self
            .codex_pending_messages
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        for tab_id in pending_ids {
            self.handle_codex_flush(&tab_id).await;
        }
        self.codex = None;
        let workspaces = match self.runtime_store.list_all_workspaces().await {
            Ok(workspaces) => workspaces,
            Err(error) => {
                self.broadcast_codex_server_error(format!(
                    "{reason} Workspace state could not be reconciled: {error}"
                ));
                return;
            }
        };
        for workspace in workspaces {
            let tabs = match self.runtime_store.list_workspace_tabs(&workspace.id).await {
                Ok(tabs) => tabs,
                Err(_) => continue,
            };
            for tab in tabs.into_iter().filter(is_codex_tab) {
                let mut failed = tab;
                let next_snapshot = super::codex_state::mark_server_failure(&mut failed, &reason);
                if let Ok(saved) = self.runtime_store.upsert_workspace_tab(failed).await {
                    self.refresh_codex_presence(&saved);
                    self.broadcast_authenticated(event(
                        "codexThreadChanged",
                        json!({
                            "tabId": saved.id,
                            "workspaceId": saved.workspace_id,
                            "threadId": tab_thread_id(&saved),
                            "snapshot": next_snapshot,
                        }),
                    ));
                }
            }
        }
        self.schedule_codex_presence_changed();
        self.broadcast_codex_server_error(reason);
    }

    pub(super) fn handle_codex_malformed(&self, reason: String) {
        self.broadcast_codex_server_error(reason);
    }

    pub(super) fn broadcast_codex_server_error(&self, reason: String) {
        self.broadcast_authenticated(event(
            "codexServerChanged",
            json!({"status": "error", "error": reason}),
        ));
    }

    pub(super) async fn find_codex_tab_for_thread(
        &self,
        thread_id: &str,
    ) -> HostResult<Option<alera_core::runtime::WorkspaceTabRecord>> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| {
                crate::terminal_host::host_error::HostError::state(error.to_string())
            })?;
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| {
                    crate::terminal_host::host_error::HostError::state(error.to_string())
                })?;
            if let Some(tab) = tabs
                .into_iter()
                .find(|tab| is_codex_tab(tab) && tab_thread_id(tab).as_deref() == Some(thread_id))
            {
                return Ok(Some(tab));
            }
        }
        Ok(None)
    }

    pub(super) async fn find_codex_tab_for_request(
        &self,
        request_id: &Value,
    ) -> HostResult<Option<alera_core::runtime::WorkspaceTabRecord>> {
        self.find_codex_tab_matching(|tab| {
            snapshot(tab)
                .pointer("/pendingRequests")
                .and_then(Value::as_array)
                .is_some_and(|requests| {
                    requests
                        .iter()
                        .any(|request| request.get("id") == Some(request_id))
                })
        })
        .await
    }

    async fn reject_unroutable_codex_request(&self, id: Value) {
        let Some(server) = self.codex.as_ref().cloned() else {
            return;
        };
        let error = json!({
            "code": -32601,
            "message": "Alera could not associate this Codex request with an open tab.",
        });
        if let Err(error) = server.respond(id, None, Some(error)).await {
            self.broadcast_codex_server_error(error.wire_message());
        }
    }

    async fn find_codex_tab_for_message(
        &self,
        message: &Value,
        thread_id: Option<&str>,
    ) -> HostResult<Option<alera_core::runtime::WorkspaceTabRecord>> {
        if let Some(thread_id) = thread_id {
            if let Some(tab) = self.find_codex_tab_for_thread(thread_id).await? {
                return Ok(Some(tab));
            }
        }
        let Some(turn_id) = turn_id_from_message(message) else {
            if message.get("id").is_some() {
                return self.find_latest_codex_tab().await;
            }
            return Ok(None);
        };
        self.find_codex_tab_matching(|tab| {
            active_turn_id(&snapshot(tab)).as_deref() == Some(turn_id.as_str())
                || snapshot(tab)
                    .pointer("/events")
                    .and_then(Value::as_array)
                    .is_some_and(|events| {
                        events.iter().any(|event| {
                            super::codex_state::turn_id_from_message(event).as_deref()
                                == Some(turn_id.as_str())
                        })
                    })
        })
        .await
    }

    async fn find_latest_codex_tab(
        &self,
    ) -> HostResult<Option<alera_core::runtime::WorkspaceTabRecord>> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| {
                crate::terminal_host::host_error::HostError::state(error.to_string())
            })?;
        let mut candidates = Vec::new();
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| {
                    crate::terminal_host::host_error::HostError::state(error.to_string())
                })?;
            candidates.extend(
                tabs.into_iter()
                    .filter(|tab| is_codex_tab(tab) && tab_thread_id(tab).is_some()),
            );
        }
        let active = candidates
            .iter()
            .filter(|tab| active_turn_id(&snapshot(tab)).is_some())
            .max_by(|left, right| {
                left.updated_at
                    .cmp(&right.updated_at)
                    .then_with(|| left.id.cmp(&right.id))
            })
            .cloned();
        Ok(active.or_else(|| {
            candidates.into_iter().max_by(|left, right| {
                left.updated_at
                    .cmp(&right.updated_at)
                    .then_with(|| left.id.cmp(&right.id))
            })
        }))
    }

    async fn find_codex_tab_by_id(
        &self,
        tab_id: &str,
    ) -> HostResult<Option<alera_core::runtime::WorkspaceTabRecord>> {
        self.find_codex_tab_matching(|tab| tab.id == tab_id).await
    }

    async fn find_codex_tab_matching<F>(
        &self,
        matches: F,
    ) -> HostResult<Option<alera_core::runtime::WorkspaceTabRecord>>
    where
        F: Fn(&alera_core::runtime::WorkspaceTabRecord) -> bool,
    {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| {
                crate::terminal_host::host_error::HostError::state(error.to_string())
            })?;
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| {
                    crate::terminal_host::host_error::HostError::state(error.to_string())
                })?;
            if let Some(tab) = tabs
                .into_iter()
                .find(|tab| is_codex_tab(tab) && matches(tab))
            {
                return Ok(Some(tab));
            }
        }
        Ok(None)
    }
}
