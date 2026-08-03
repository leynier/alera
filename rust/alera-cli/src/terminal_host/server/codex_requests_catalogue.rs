//! Codex thread lifecycle and dynamic catalogue requests.

use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use alera_core::runtime::WorkspaceTabRecord;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::CODEX_TAB_KIND;

use super::super::codex_state::{
    active_turn_id, is_codex_tab, set_thread_and_snapshot, snapshot, tab_thread_id,
};
use super::super::requests::require_string_key;
use super::super::ServerActor;

impl ServerActor {
    pub(crate) async fn interrupt_codex_workspace_in_background(&self, workspace_id: String) {
        let Some(server) = self.codex.as_ref().cloned() else {
            return;
        };
        let Ok(tabs) = self.runtime_store.list_workspace_tabs(&workspace_id).await else {
            return;
        };
        for tab in tabs.into_iter().filter(is_codex_tab) {
            let Some(thread_id) = tab_thread_id(&tab) else {
                continue;
            };
            let Some(turn_id) = active_turn_id(&snapshot(&tab)) else {
                continue;
            };
            server.interrupt_in_background(thread_id, turn_id);
        }
    }

    pub(crate) async fn interrupt_codex_project_in_background(&self, project_id: String) {
        let Ok(workspaces) = self.runtime_store.list_workspaces(&project_id).await else {
            return;
        };
        for workspace in workspaces {
            self.interrupt_codex_workspace_in_background(workspace.id)
                .await;
        }
    }

    pub(crate) async fn close_codex_tab_before_removal(&mut self, tab_id: &str) -> HostResult<()> {
        let Some(tab) = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(());
        };
        if !is_codex_tab(&tab) {
            return Ok(());
        }
        let Some(thread_id) = tab_thread_id(&tab) else {
            return Ok(());
        };
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("Codex workspace no longer exists."))?;
        let server = self.ensure_codex_server(Some(&workspace.path)).await?;
        if let Some(turn_id) = active_turn_id(&snapshot(&tab)) {
            let _ = server
                .request(
                    "turn/interrupt",
                    json!({"threadId": thread_id, "turnId": turn_id}),
                )
                .await;
        }
        server
            .request("thread/delete", json!({"threadId": thread_id}))
            .await
            .map(|_| ())
    }

    pub(super) async fn create_codex_tab(&mut self, payload: &Value) -> HostResult<Value> {
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        let now = Utc::now();
        let tab = WorkspaceTabRecord {
            id: Uuid::new_v4().to_string(),
            workspace_id: workspace.id.clone(),
            kind: CODEX_TAB_KIND.to_string(),
            title: "Codex".to_string(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        };
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_workspace_tabs_changed(Some(&workspace.id));
        Ok(json!(tab))
    }

    pub(super) async fn list_codex_skills(&mut self, payload: &Value) -> HostResult<Value> {
        let mut params = payload.clone();
        if let Some(tab_id) = payload.get("tabId").and_then(Value::as_str) {
            let tab = self.codex_tab(tab_id).await?;
            let workspace = self
                .runtime_store
                .find_workspace(&tab.workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| {
                    HostError::state(format!("Workspace not found: {}", tab.workspace_id))
                })?;
            if let Some(object) = params.as_object_mut() {
                object.remove("tabId");
                object
                    .entry("cwds".to_string())
                    .or_insert_with(|| json!([workspace.path]));
                object
                    .entry("forceReload".to_string())
                    .or_insert(json!(false));
            }
        }
        self.codex_server_request("skills/list", params).await
    }

    pub(super) async fn list_codex_apps(&mut self, payload: &Value) -> HostResult<Value> {
        let mut params = payload.clone();
        if let Some(tab_id) = payload.get("tabId").and_then(Value::as_str) {
            let tab = self.codex_tab(tab_id).await?;
            let thread_id = tab_thread_id(&tab);
            if let Some(object) = params.as_object_mut() {
                object.remove("tabId");
                if let Some(thread_id) = thread_id {
                    object
                        .entry("threadId".to_string())
                        .or_insert(Value::String(thread_id));
                }
            }
        }
        self.codex_server_request("app/list", params).await
    }

    pub(super) async fn list_codex_thread_items(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self.codex_tab(&tab_id).await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("The Codex thread has not been opened."))?;
        let mut params = payload.clone();
        if let Some(object) = params.as_object_mut() {
            object.remove("tabId");
            object.insert("threadId".to_string(), Value::String(thread_id));
        }
        self.codex_server_request("thread/items/list", params).await
    }

    pub(super) async fn open_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let mut tab = self.codex_tab(&tab_id).await?;
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        let server = self.ensure_codex_server(Some(&workspace.path)).await?;
        let existing_thread = tab_thread_id(&tab);
        let response = if let Some(thread_id) = existing_thread.as_deref() {
            server
                .request("thread/resume", json!({"threadId": thread_id}))
                .await?
        } else {
            let mut params = json!({"cwd": workspace.path, "approvalPolicy": "on-request"});
            copy_optional(payload, &mut params, "model");
            server.request("thread/start", params).await?
        };
        let thread_id = response
            .pointer("/thread/id")
            .or_else(|| response.get("threadId"))
            .and_then(Value::as_str)
            .or(existing_thread.as_deref())
            .ok_or_else(|| HostError::state("Codex app-server returned no thread id."))?;
        let next_snapshot = response
            .get("snapshot")
            .filter(|value| value.is_object())
            .cloned()
            .unwrap_or_else(|| snapshot(&tab));
        set_thread_and_snapshot(&mut tab, thread_id, next_snapshot);
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        Ok(json!({
            "tab": saved,
            "threadId": thread_id,
            "snapshot": snapshot(&saved),
        }))
    }

    pub(super) async fn codex_thread_snapshot(&self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self.codex_tab(&tab_id).await?;
        Ok(json!({
            "tabId": tab.id,
            "threadId": tab_thread_id(&tab),
            "snapshot": snapshot(&tab),
        }))
    }
}

fn copy_optional(payload: &Value, target: &mut Value, key: &str) {
    if let Some(value) = payload.get(key) {
        if let Some(object) = target.as_object_mut() {
            object.insert(key.to_string(), value.clone());
        }
    }
}
