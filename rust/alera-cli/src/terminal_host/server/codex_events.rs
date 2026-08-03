//! Reduction and fan-out of Codex app-server notifications.

use serde_json::{json, Value};

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::event;

use super::codex_state::{
    active_turn_id, append_message, is_codex_tab, snapshot, tab_thread_id, thread_id_from_message,
    turn_id_from_message,
};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn handle_codex_message(&mut self, message: Value) {
        let thread_id = thread_id_from_message(&message);
        let tab = match self
            .find_codex_tab_for_message(&message, thread_id.as_deref())
            .await
        {
            Ok(Some(tab)) => tab,
            Ok(None) => {
                self.broadcast_authenticated(event(
                    "codexThreadChanged",
                    json!({"message": message}),
                ));
                return;
            }
            Err(error) => {
                self.broadcast_codex_server_error(error.to_string());
                return;
            }
        };
        let mut next = tab.clone();
        let next_snapshot = append_message(&mut next, message.clone());
        let active_turn_id = next_snapshot
            .get("activeTurnId")
            .and_then(Value::as_str)
            .map(str::to_string);
        if let Some(payload) = next.payload.as_object_mut() {
            payload.insert("codexSnapshot".to_string(), next_snapshot.clone());
            match active_turn_id {
                Some(turn_id) => {
                    payload.insert("codexActiveTurnId".to_string(), Value::String(turn_id));
                }
                None => {
                    payload.remove("codexActiveTurnId");
                }
            }
        }
        if let Some(title) = super::codex_state::thread_title_from_message(&message) {
            if !next
                .payload
                .get("manualTitle")
                .and_then(Value::as_bool)
                .unwrap_or(false)
            {
                next.title = title;
            }
        }
        next.updated_at = chrono::Utc::now();
        let saved = match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => saved,
            Err(error) => {
                self.broadcast_codex_server_error(error.to_string());
                return;
            }
        };
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        self.broadcast_authenticated(event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": thread_id.or_else(|| tab_thread_id(&saved)),
                "message": message,
                "snapshot": snapshot(&saved),
            }),
        ));
    }

    pub(super) async fn handle_codex_process_exited(&mut self, reason: String) {
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
                    self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
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
