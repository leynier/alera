//! Codex thread discovery, resume, history, and same-tab session commands.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;

use alera_core::runtime::{Workspace, WorkspaceTabRecord};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::super::codex_state::{
    active_turn_id, is_codex_tab, set_thread_and_snapshot, snapshot, tab_thread_id,
};
use super::super::codex_tab_lifecycle::{
    active_cwd, configuration, set_active_cwd, set_thread_owned_by_alera,
};
use super::super::requests::require_string_key;
use super::ServerActor;

type ThreadBindings = HashMap<String, (String, String)>;

impl ServerActor {
    pub(super) async fn list_codex_threads(&mut self, payload: &Value) -> HostResult<Value> {
        let workspace_id = payload
            .get("workspaceId")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string);
        let workspaces = self.codex_workspaces(workspace_id.as_deref()).await?;
        let limit = request_limit(payload);
        let mut base_params = json!({"archived": false});
        copy_optional(payload, &mut base_params, "searchTerm");
        copy_optional(payload, &mut base_params, "sortKey");
        copy_optional(payload, &mut base_params, "sortDirection");
        let server = self
            .ensure_codex_server(workspaces.first().map(|item| item.path.as_str()))
            .await?;
        let bindings = self.codex_thread_bindings().await?;
        let mut cursor = string_value(payload, "cursor");
        let mut seen_cursors = cursor.iter().cloned().collect::<HashSet<_>>();
        let mut items = Vec::new();
        let mut response;
        let mut scanned_pages = 0;
        loop {
            scanned_pages += 1;
            let remaining = limit.saturating_sub(items.len() as u64).max(1);
            let mut params = base_params.clone();
            params["limit"] = Value::Number(remaining.into());
            if let Some(cursor) = cursor.as_ref() {
                params["cursor"] = Value::String(cursor.clone());
            }
            response = server.request("thread/list", params).await?;
            let source = response
                .get("data")
                .or_else(|| response.get("items"))
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            items.extend(
                source
                    .iter()
                    .filter(|thread| eligible_thread(thread))
                    .filter(|thread| {
                        workspace_id.is_none() || thread_belongs_to_workspaces(thread, &workspaces)
                    })
                    .map(|thread| self.thread_summary(thread, &workspaces, &bindings))
                    .take(remaining as usize),
            );
            let next_cursor = response_cursor(&response);
            let cursor_is_new = next_cursor
                .as_ref()
                .is_some_and(|value| seen_cursors.insert(value.clone()));
            if !should_continue_thread_scan(
                workspace_id.is_some(),
                items.len(),
                limit,
                next_cursor.is_some(),
                cursor_is_new,
                scanned_pages,
            ) {
                break;
            }
            cursor = next_cursor;
        }
        let mut result = response.as_object().cloned().unwrap_or_default();
        result.insert("data".to_string(), Value::Array(items.clone()));
        result.insert("items".to_string(), Value::Array(items.clone()));
        result.insert("threads".to_string(), Value::Array(items));
        result.insert("cwdOptions".to_string(), cwd_options(&workspaces));
        Ok(Value::Object(result))
    }

    pub(super) async fn resume_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let thread_id = require_string_key(payload, "threadId")?;
        let bindings = self.codex_thread_bindings().await?;
        if let Some(response) = existing_thread_binding_response(&bindings, &thread_id) {
            return Ok(response);
        }
        let mut tab = self.codex_tab_for_thread_switch(&tab_id).await?;
        let workspaces = self.codex_workspaces(None).await?;
        let workspace = workspaces
            .iter()
            .find(|item| item.id == tab.workspace_id)
            .ok_or_else(|| HostError::state("Codex workspace no longer exists."))?;
        let cwd = requested_cwd(payload)
            .or_else(|| active_cwd(&tab))
            .unwrap_or_else(|| workspace.path.clone());
        let cwd = allowed_cwd(&cwd, &workspaces)
            .ok_or_else(|| HostError::format("Codex cwd must be inside a known workspace."))?;
        let server = self.ensure_codex_server(Some(&cwd)).await?;
        let history_limit = request_limit(payload) as usize;
        let response = server
            .request(
                "thread/resume",
                thread_resume_params(&thread_id, &cwd, history_limit),
            )
            .await?;
        let history_page = server
            .project_resumed_thread_history(&thread_id, &response, history_limit)
            .await;
        let next_snapshot = response
            .get("snapshot")
            .filter(|value| value.is_object())
            .cloned()
            .or_else(|| history_page.as_ref().map(|page| page.snapshot.clone()))
            .unwrap_or_else(|| snapshot(&tab));
        let next_snapshot = resumed_snapshot_with_thread_title(next_snapshot, &response);
        let response_cwd = response
            .pointer("/thread/cwd")
            .and_then(Value::as_str)
            .or_else(|| response.get("cwd").and_then(Value::as_str))
            .and_then(|value| allowed_cwd(value, &workspaces))
            .unwrap_or(cwd);
        set_active_cwd(&mut tab, &response_cwd);
        set_thread_and_snapshot(&mut tab, &thread_id, next_snapshot);
        set_thread_owned_by_alera(&mut tab, false);
        sync_resumed_thread_title(&mut tab);
        let history_next_cursor = history_page.and_then(|page| page.next_cursor);
        let saved = self
            .save_codex_session_tab(tab, history_next_cursor.clone())
            .await?;
        Ok(session_response(&saved, false, None, history_next_cursor))
    }

    pub(super) async fn list_codex_thread_history(&mut self, payload: &Value) -> HostResult<Value> {
        let tab = self
            .codex_tab(&require_string_key(payload, "tabId")?)
            .await?;
        let thread_id = tab_thread_id(&tab)
            .ok_or_else(|| HostError::state("The Codex thread has not been opened."))?;
        let server = self
            .ensure_codex_server(active_cwd(&tab).as_deref())
            .await?;
        let cursor = string_value(payload, "cursor")
            .ok_or_else(|| HostError::format("Codex history cursor is required."))?;
        let limit = request_limit(payload) as usize;
        let page = server
            .load_thread_history_page(&thread_id, &cursor, limit)
            .await?;
        let mut result = serde_json::Map::new();
        result.insert("data".to_string(), Value::Array(page.turns.clone()));
        result.insert("items".to_string(), Value::Array(page.turns));
        result.insert("snapshot".to_string(), page.snapshot);
        result.insert(
            "nextCursor".to_string(),
            page.next_cursor.map_or(Value::Null, Value::String),
        );
        result.insert("threadId".to_string(), Value::String(thread_id));
        result.insert(
            "cwd".to_string(),
            active_cwd(&tab).map_or(Value::Null, Value::String),
        );
        Ok(Value::Object(result))
    }

    pub(super) async fn new_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
        self.start_same_tab_codex_thread(payload, false).await
    }

    pub(super) async fn clear_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
        self.start_same_tab_codex_thread(payload, true).await
    }

    async fn start_same_tab_codex_thread(
        &mut self,
        payload: &Value,
        clear_history: bool,
    ) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let mut tab = self.codex_tab_for_thread_switch(&tab_id).await?;
        let workspaces = self.codex_workspaces(None).await?;
        let workspace = workspaces
            .iter()
            .find(|item| item.id == tab.workspace_id)
            .ok_or_else(|| HostError::state("Codex workspace no longer exists."))?;
        let cwd = requested_cwd(payload)
            .or_else(|| active_cwd(&tab))
            .unwrap_or_else(|| workspace.path.clone());
        let cwd = allowed_cwd(&cwd, &workspaces)
            .ok_or_else(|| HostError::format("Codex cwd must be inside a known workspace."))?;
        let server = self.ensure_codex_server(Some(&cwd)).await?;
        let mut params = json!({
            "cwd": cwd,
            "approvalPolicy": payload.get("approvalPolicy").cloned().unwrap_or(json!("on-request")),
            "runtimeWorkspaceRoots": workspaces.iter().map(|item| item.path.clone()).collect::<Vec<_>>(),
        });
        copy_optional(payload, &mut params, "model");
        let response = server.request("thread/start", params).await?;
        let thread_id = response
            .pointer("/thread/id")
            .or_else(|| response.get("threadId"))
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string)
            .ok_or_else(|| HostError::state("Codex app-server returned no thread id."))?;
        let mut next_snapshot = if clear_history {
            empty_snapshot()
        } else {
            snapshot(&tab)
        };
        reset_snapshot_for_new_thread(&mut next_snapshot, &thread_id, !clear_history);
        set_active_cwd(&mut tab, &cwd);
        set_thread_and_snapshot(&mut tab, &thread_id, next_snapshot);
        set_thread_owned_by_alera(&mut tab, true);
        reset_new_thread_title(&mut tab);
        let saved = self.save_codex_session_tab(tab, None).await?;
        Ok(session_response(
            &saved,
            false,
            Some(if clear_history { "cleared" } else { "new" }),
            None,
        ))
    }

    async fn codex_tab_for_thread_switch(
        &mut self,
        tab_id: &str,
    ) -> HostResult<WorkspaceTabRecord> {
        self.handle_codex_force_flush(tab_id).await;
        let tab = self.codex_tab(tab_id).await?;
        ensure_thread_switch_allowed(&tab)?;
        Ok(tab)
    }

    async fn save_codex_session_tab(
        &mut self,
        tab: WorkspaceTabRecord,
        history_next_cursor: Option<String>,
    ) -> HostResult<WorkspaceTabRecord> {
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.refresh_codex_presence(&saved);
        self.schedule_codex_presence_changed();
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        self.broadcast_authenticated(event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": tab_thread_id(&saved),
                "cwd": active_cwd(&saved),
                "snapshot": snapshot(&saved),
                "historyNextCursor": history_next_cursor,
            }),
        ));
        Ok(saved)
    }

    pub(super) async fn codex_workspaces(
        &self,
        workspace_id: Option<&str>,
    ) -> HostResult<Vec<Workspace>> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let Some(workspace_id) = workspace_id else {
            return Ok(workspaces);
        };
        let workspace = workspaces
            .into_iter()
            .find(|workspace| workspace.id == workspace_id)
            .ok_or_else(|| HostError::state("Codex workspace no longer exists."))?;
        Ok(vec![workspace])
    }

    async fn codex_thread_bindings(&self) -> HostResult<ThreadBindings> {
        let workspaces = self.codex_workspaces(None).await?;
        let mut bindings = HashMap::new();
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            for tab in tabs.into_iter().filter(is_codex_tab) {
                if let Some(thread_id) = tab_thread_id(&tab) {
                    bindings.insert(thread_id, (tab.id, workspace.id.clone()));
                }
            }
        }
        Ok(bindings)
    }

    fn thread_summary(
        &self,
        thread: &Value,
        workspaces: &[Workspace],
        bindings: &ThreadBindings,
    ) -> Value {
        let id = thread_id(thread).unwrap_or_default();
        let cwd = string_value(thread, "cwd");
        let workspace = cwd
            .as_deref()
            .and_then(|value| most_specific_workspace(value, workspaces));
        let binding = bindings.get(&id);
        json!({
            "id": id,
            "threadId": id,
            "title": thread_title(thread),
            "name": thread.get("name").cloned().unwrap_or(Value::Null),
            "preview": thread.get("preview").cloned().unwrap_or(Value::Null),
            "cwd": cwd,
            "workspaceId": workspace.map(|item| item.id.clone()),
            "workspaceName": workspace.map(|item| item.name.clone()),
            "source": thread.get("source").cloned().unwrap_or(Value::Null),
            "sourceKind": source_kind(thread),
            "status": thread.get("status").cloned().unwrap_or(Value::Null),
            "createdAt": thread.get("createdAt").cloned().unwrap_or(Value::Null),
            "updatedAt": thread.get("updatedAt").cloned().unwrap_or(Value::Null),
            "recencyAt": thread.get("recencyAt").cloned().unwrap_or(Value::Null),
            "isPinned": thread.get("isPinned").and_then(Value::as_bool).unwrap_or(false),
            "boundTabId": binding.map(|value| value.0.clone()),
            "boundWorkspaceId": binding.map(|value| value.1.clone()),
            "canResume": binding.is_none(),
        })
    }
}

fn sync_resumed_thread_title(tab: &mut WorkspaceTabRecord) {
    if let Some(title) = snapshot(tab)
        .get("title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        tab.title = title.to_string();
    } else {
        tab.title = "Codex Chat".to_string();
    }
    if let Some(payload) = tab.payload.as_object_mut() {
        payload.remove("manualTitle");
    }
}

fn reset_new_thread_title(tab: &mut WorkspaceTabRecord) {
    tab.title = "Codex Chat".to_string();
    if let Some(payload) = tab.payload.as_object_mut() {
        payload.remove("manualTitle");
    }
}

#[cfg(test)]
#[path = "codex_thread_sessions_tests.rs"]
mod resumed_title_tests;

#[path = "codex_thread_session_support.rs"]
mod support;
pub(in crate::terminal_host::server) use support::*;
