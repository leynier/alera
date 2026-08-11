//! Reduction and fan-out of Codex app-server notifications.

use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::protocol::event;

use super::codex_nonblocking_questions::is_nonblocking_user_input_request;
use super::codex_state::{
    active_turn_id, append_message_with_normalized, is_codex_tab, snapshot, snapshot_delta,
    tab_thread_id, thread_id_from_message,
};
use super::codex_tab_lifecycle::active_cwd;
use super::ServerActor;

// The current Codex protocol requires isBlocking and deprecates autoResolutionMs.
// Match the Codex TUI's fixed 60-second grace plus 60-second countdown.
const CODEX_NONBLOCKING_QUESTION_GRACE: std::time::Duration = std::time::Duration::from_secs(120);

fn pending_auto_resolution_request(
    tab: &alera_core::runtime::WorkspaceTabRecord,
    thread_id: &str,
    request_id: &Value,
) -> Option<Value> {
    if tab_thread_id(tab).as_deref() != Some(thread_id) {
        return None;
    }
    snapshot(tab)
        .get("pendingRequests")
        .and_then(Value::as_array)
        .and_then(|requests| {
            requests
                .iter()
                .find(|request| request.get("id") == Some(request_id))
                .cloned()
        })
}

#[path = "codex_stream_collector.rs"]
mod codex_stream_collector;

fn is_streaming_codex_message(message: &Value) -> bool {
    let method = message
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    method.contains("delta") || method == "turn/diff/updated"
}

fn catalogue_invalidations(method: Option<&str>) -> &'static [&'static str] {
    match method {
        Some("skills/changed") => &["skills:"],
        Some("app/list/updated") => &["apps:"],
        Some("account/updated" | "account/login/completed" | "account/logout") => {
            &["models", "collaborationModes"]
        }
        _ => &[],
    }
}

fn catalogue_change(method: Option<&str>) -> Option<&'static str> {
    match method {
        Some("skills/changed") => Some("skills"),
        Some("app/list/updated") => Some("apps"),
        Some("account/updated" | "account/login/completed" | "account/logout") => Some("account"),
        _ => None,
    }
}

fn retained_timeline_window(previous: &Value, next: &Value) -> bool {
    let next_cells = next
        .get("timelineCells")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    previous
        .get("timelineCells")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .all(|previous_cell| {
            previous_cell.get("id").and_then(Value::as_str).map_or_else(
                || next_cells.contains(previous_cell),
                |id| {
                    next_cells
                        .iter()
                        .any(|cell| cell.get("id").and_then(Value::as_str) == Some(id))
                },
            )
        })
}

impl ServerActor {
    pub(super) async fn handle_codex_message(&mut self, message: Value) {
        let method = message.get("method").and_then(Value::as_str);
        if let Some(server) = self.codex.as_ref() {
            for prefix in catalogue_invalidations(method) {
                server.invalidate_catalogues(prefix).await;
            }
        }
        if let Some(catalog) = catalogue_change(method) {
            self.broadcast_authenticated(event("codexCatalogChanged", json!({"catalog": catalog})));
            return;
        }
        if method == Some("currentTime/read") {
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
        self.schedule_nonblocking_question_auto_resolution(&tab, &message);
        if is_streaming_codex_message(&message) {
            self.queue_codex_message(&tab.id, message).await;
            return;
        }
        self.handle_codex_force_flush(&tab.id).await;
        self.persist_codex_messages(tab, vec![message]).await;
    }

    fn schedule_nonblocking_question_auto_resolution(
        &self,
        tab: &alera_core::runtime::WorkspaceTabRecord,
        message: &Value,
    ) {
        if !is_nonblocking_user_input_request(message) {
            return;
        }
        let Some(request_id) = message.get("id").cloned() else {
            return;
        };
        let Some(thread_id) = tab_thread_id(tab) else {
            return;
        };
        let Some(server_instance) = self
            .codex
            .as_ref()
            .map(super::codex_app_server::CodexAppServer::instance_token)
        else {
            return;
        };
        let inbox = self.inbox.clone();
        let tab_id = tab.id.clone();
        tokio::spawn(async move {
            tokio::time::sleep(CODEX_NONBLOCKING_QUESTION_GRACE).await;
            let _ = inbox.send(super::ServerCommand::CodexAutoResolve {
                tab_id,
                thread_id,
                request_id,
                server_instance,
            });
        });
    }

    pub(super) async fn handle_codex_auto_resolve(
        &mut self,
        tab_id: &str,
        thread_id: &str,
        request_id: Value,
        server_instance: std::sync::Arc<()>,
    ) {
        if !self
            .codex
            .as_ref()
            .is_some_and(|server| server.matches_instance(&server_instance))
        {
            return;
        }
        let pending = match self.find_codex_tab_by_id(tab_id).await {
            Ok(Some(tab)) => pending_auto_resolution_request(&tab, thread_id, &request_id),
            Ok(None) => None,
            Err(error) => {
                self.broadcast_codex_server_error(error.to_string());
                return;
            }
        };
        if pending.as_ref().is_none_or(|request| {
            !is_nonblocking_user_input_request(request)
                || request
                    .get("autoResolutionSnoozed")
                    .and_then(Value::as_bool)
                    == Some(true)
        }) {
            return;
        }
        if let Err(error) = self
            .respond_to_codex_request_for_tab(
                &json!({
                    "requestId": request_id,
                    "result": {"answers": {}},
                }),
                tab_id,
            )
            .await
        {
            self.broadcast_codex_server_error(error.to_string());
        }
    }

    pub(super) async fn handle_codex_force_flush(&mut self, tab_id: &str) {
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

    pub(super) async fn handle_codex_flush(&mut self, tab_id: &str) {
        self.codex_flush_scheduled.remove(tab_id);
        let Some(messages) = self.codex_pending_messages.get(tab_id) else {
            return;
        };
        if !codex_stream_collector::safe_boundary(messages) {
            return;
        }
        self.handle_codex_force_flush(tab_id).await;
    }

    fn schedule_codex_flush(&mut self, tab_id: &str, delay: std::time::Duration) {
        if !self.codex_flush_scheduled.insert(tab_id.to_string()) {
            return;
        }
        let inbox = self.inbox.clone();
        let tab_id = tab_id.to_string();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = inbox.send(super::ServerCommand::CodexFlush { tab_id });
        });
    }

    async fn queue_codex_message(&mut self, tab_id: &str, message: Value) {
        let pending = self
            .codex_pending_messages
            .entry(tab_id.to_string())
            .or_default();
        pending.push(message);
        let should_flush_now = codex_stream_collector::should_force_flush(pending);
        let delay = codex_stream_collector::batch_delay(pending);
        self.schedule_codex_flush(tab_id, delay);
        if should_flush_now {
            self.handle_codex_force_flush(tab_id).await;
        }
    }

    async fn persist_codex_messages(
        &mut self,
        tab: alera_core::runtime::WorkspaceTabRecord,
        messages: Vec<Value>,
    ) {
        let previous_snapshot = snapshot(&tab);
        let mut next = tab.clone();
        let mut title_changed = false;
        let mut normalized_messages = Vec::with_capacity(messages.len());
        for message in &messages {
            let (_, normalized_message) =
                append_message_with_normalized(&mut next, message.clone());
            normalized_messages.push(normalized_message);
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
        let retained_history_window = retained_timeline_window(&previous_snapshot, &next_snapshot);
        let delta = snapshot_delta(&previous_snapshot, &next_snapshot, &normalized_messages);
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
        if let (Some(server), Some(thread_id), Some(cwd)) = (
            self.codex.as_ref(),
            thread_id.as_deref(),
            active_cwd(&saved),
        ) {
            server
                .refresh_thread_hydration_revision(
                    &saved.id,
                    thread_id,
                    &cwd,
                    saved.updated_at,
                    retained_history_window,
                )
                .await;
        }
        self.broadcast_authenticated(event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": thread_id,
                "message": message,
                "coalescedMessages": messages.len(),
                "snapshot": snapshot(&saved),
                "snapshotDelta": delta,
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
            self.handle_codex_force_flush(&tab_id).await;
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
}

#[cfg(test)]
#[path = "codex_events_tests.rs"]
mod tests;
