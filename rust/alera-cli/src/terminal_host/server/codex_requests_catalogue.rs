//! Codex thread lifecycle and dynamic catalogue requests.

use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use alera_core::{
    git as core_git,
    runtime::{Workspace, WorkspaceTabRecord},
};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::CODEX_TAB_KIND;

use super::super::codex_state::{
    merge_resume_snapshot, persist_snapshot, set_thread_and_snapshot, snapshot, tab_thread_id,
};
use super::super::codex_tab_lifecycle::{
    active_cwd, append_context_reset_notice, clear_stale_thread_activity, clear_thread_identity,
    configuration, has_materialized_conversation, missing_rollout, normalize_configuration,
    set_active_cwd, set_configuration,
};
use super::super::requests::require_string_key;
use super::super::ServerActor;
use super::codex_thread_sessions::{
    allowed_cwd, ensure_thread_switch_allowed, thread_resume_params,
};

impl ServerActor {
    pub(super) async fn codex_review_branches(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self.codex_tab(&tab_id).await?;
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("Workspace not found: {}", tab.workspace_id))
            })?;
        live_codex_review_branches(&tab, &workspace.path)
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
        let mut tab = WorkspaceTabRecord {
            id: Uuid::new_v4().to_string(),
            workspace_id: workspace.id.clone(),
            kind: CODEX_TAB_KIND.to_string(),
            title: "Codex Chat".to_string(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        };
        if let Some(value) = payload.get("configuration") {
            let normalized = normalize_configuration(value).map_err(HostError::format)?;
            set_configuration(&mut tab, normalized);
        }
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
            params = codex_skills_list_params(params, &tab, &workspace.path);
        }
        let force_reload = params
            .get("forceReload")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let cache_key = catalogue_cache_key("skills:", &params);
        if force_reload {
            let server = self.ensure_codex_server(None).await?;
            server.invalidate_catalogues("skills:").await;
            return self.codex_server_request("skills/list", params).await;
        }
        self.codex_server_cached_request(&cache_key, "skills/list", params)
            .await
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
        let cache_key = catalogue_cache_key("apps:", &params);
        self.codex_server_cached_request(&cache_key, "app/list", params)
            .await
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
        let existing_thread = tab_thread_id(&tab);
        let Some(thread_id) = existing_thread.as_deref() else {
            return Ok(thread_open_response(&tab, None, None, None));
        };
        let supports_missing_rollout_recovery = payload
            .get("supportsMissingRolloutRecovery")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let workspaces = self.codex_workspaces(None).await?;
        let (cwd, cwd_changed) = resumable_codex_cwd(&tab, &workspace, &workspaces)?;
        if cwd_changed {
            set_active_cwd(&mut tab, &cwd);
        }
        if !cwd_changed {
            if let Some(server) = self.codex.as_ref() {
                if let Some(hydration) = server
                    .take_thread_hydration(&tab_id, thread_id, &cwd, tab.updated_at)
                    .await
                {
                    if server
                        .history_cursor_is_reusable(
                            thread_id,
                            hydration.history_next_cursor.as_deref(),
                            20,
                        )
                        .await
                    {
                        return Ok(thread_open_response(
                            &tab,
                            Some(thread_id),
                            None,
                            hydration.history_next_cursor,
                        ));
                    }
                    server.forget_thread_hydration(&tab_id).await;
                }
            }
        }
        let server = self.ensure_codex_server(Some(&cwd)).await?;
        let response = match server
            .request("thread/resume", thread_resume_params(thread_id, &cwd, 20))
            .await
        {
            Ok(response) => response,
            Err(error) if missing_rollout(&error.wire_message(), thread_id) => {
                server.forget_thread_hydration(&tab_id).await;
                let (next_thread_id, recovery) =
                    resolve_missing_rollout(&mut tab, thread_id, supports_missing_rollout_recovery);
                let saved = self
                    .runtime_store
                    .upsert_workspace_tab(tab)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                self.refresh_codex_presence(&saved);
                self.schedule_codex_presence_changed();
                self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
                self.broadcast_authenticated(crate::terminal_host::protocol::event(
                    "codexThreadChanged",
                    json!({
                        "tabId": saved.id,
                        "workspaceId": saved.workspace_id,
                        "threadId": next_thread_id,
                        "snapshot": snapshot(&saved),
                        "configuration": configuration(&saved),
                        "recovery": recovery,
                    }),
                ));
                return Ok(thread_open_response(
                    &saved,
                    next_thread_id.as_deref(),
                    recovery,
                    None,
                ));
            }
            Err(error) => return Err(error),
        };
        let thread_id = response
            .pointer("/thread/id")
            .or_else(|| response.get("threadId"))
            .and_then(Value::as_str)
            .or(existing_thread.as_deref())
            .ok_or_else(|| HostError::state("Codex app-server returned no thread id."))?
            .to_string();
        let stored_snapshot = snapshot(&tab);
        let history_page = server
            .project_resumed_thread_history(&thread_id, &response, 20)
            .await?;
        let history_next_cursor = history_page
            .as_ref()
            .and_then(|page| page.next_cursor.clone());
        let next_snapshot = response
            .get("snapshot")
            .filter(|value| value.is_object())
            .cloned()
            .or_else(|| history_page.as_ref().map(|page| page.snapshot.clone()))
            .map(|resumed| merge_resume_snapshot(&stored_snapshot, resumed))
            .unwrap_or(stored_snapshot);
        let response_cwd = response
            .pointer("/thread/cwd")
            .and_then(Value::as_str)
            .or_else(|| response.get("cwd").and_then(Value::as_str))
            .and_then(|value| allowed_cwd(value, &workspaces))
            .unwrap_or(cwd);
        set_active_cwd(&mut tab, &response_cwd);
        set_thread_and_snapshot(&mut tab, &thread_id, next_snapshot);
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        server
            .record_thread_hydration(
                &saved.id,
                &thread_id,
                &response_cwd,
                saved.updated_at,
                history_next_cursor.clone(),
            )
            .await;
        Ok(thread_open_response(
            &saved,
            Some(&thread_id),
            None,
            history_next_cursor,
        ))
    }

    pub(super) async fn configure_codex_tab(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let value = payload
            .get("configuration")
            .ok_or_else(|| HostError::format("Codex tab configuration is required."))?;
        let normalized = normalize_configuration(value).map_err(HostError::format)?;
        let mut tab = self.codex_tab(&tab_id).await?;
        set_configuration(&mut tab, normalized.clone());
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": tab_thread_id(&saved),
                "snapshot": snapshot(&saved),
                "configuration": normalized,
            }),
        ));
        Ok(json!({
            "tabId": saved.id,
            "configuration": configuration(&saved),
        }))
    }

    pub(super) async fn recover_codex_thread(&mut self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        if let Some(server) = self.codex.as_ref() {
            server.forget_thread_hydration(&tab_id).await;
        }
        let mut tab = self.codex_tab(&tab_id).await?;
        ensure_recovery_matches(payload, &tab)?;
        clear_thread_identity(&mut tab);
        let mut next_snapshot = snapshot(&tab);
        append_context_reset_notice(&mut next_snapshot);
        persist_snapshot(&mut tab, next_snapshot);
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.refresh_codex_presence(&saved);
        self.schedule_codex_presence_changed();
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "codexThreadChanged",
            json!({
                "tabId": saved.id,
                "workspaceId": saved.workspace_id,
                "threadId": null,
                "snapshot": snapshot(&saved),
                "configuration": configuration(&saved),
                "recovery": null,
            }),
        ));
        Ok(thread_open_response(&saved, None, None, None))
    }

    pub(super) async fn codex_thread_snapshot(&self, payload: &Value) -> HostResult<Value> {
        let tab_id = require_string_key(payload, "tabId")?;
        let tab = self.codex_tab(&tab_id).await?;
        Ok(json!({
            "tabId": tab.id,
            "threadId": tab_thread_id(&tab),
            "snapshot": snapshot(&tab),
            "configuration": configuration(&tab),
        }))
    }
}

fn resolve_missing_rollout(
    tab: &mut WorkspaceTabRecord,
    thread_id: &str,
    supports_explicit_recovery: bool,
) -> (Option<String>, Option<Value>) {
    let mut next_snapshot = snapshot(tab);
    if has_materialized_conversation(&next_snapshot) && supports_explicit_recovery {
        clear_stale_thread_activity(&mut next_snapshot);
        persist_snapshot(tab, next_snapshot);
        return (
            Some(thread_id.to_string()),
            Some(json!({
                "kind": "missingRollout",
                "threadId": thread_id,
                "message": "The saved Codex context is no longer available.",
            })),
        );
    }

    let had_materialized_conversation = has_materialized_conversation(&next_snapshot);
    clear_thread_identity(tab);
    if had_materialized_conversation {
        append_context_reset_notice(&mut next_snapshot);
        persist_snapshot(tab, next_snapshot);
    }
    (None, None)
}

fn ensure_recovery_matches(payload: &Value, tab: &WorkspaceTabRecord) -> HostResult<()> {
    let current_thread_id = tab_thread_id(tab)
        .ok_or_else(|| HostError::state("The Codex conversation no longer needs recovery."))?;
    if let Some(expected_thread_id) = payload
        .get("expectedThreadId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        if current_thread_id != expected_thread_id {
            return Err(HostError::state(
                "The Codex conversation changed before recovery. Review the current conversation and try again.",
            ));
        }
    }
    ensure_thread_switch_allowed(tab)
}

fn resumable_codex_cwd(
    tab: &WorkspaceTabRecord,
    workspace: &Workspace,
    workspaces: &[Workspace],
) -> HostResult<(String, bool)> {
    let stored_cwd = active_cwd(tab);
    let cwd = stored_cwd
        .as_deref()
        .and_then(|value| allowed_cwd(value, workspaces))
        .or_else(|| allowed_cwd(&workspace.path, workspaces))
        .ok_or_else(|| HostError::format("Codex cwd must be inside a known workspace."))?;
    let changed = stored_cwd.as_deref() != Some(cwd.as_str());
    Ok((cwd, changed))
}

fn thread_open_response(
    tab: &WorkspaceTabRecord,
    thread_id: Option<&str>,
    recovery: Option<Value>,
    history_next_cursor: Option<String>,
) -> Value {
    let mut public_tab = tab.clone();
    super::super::tab_compatibility::redact_private_tab_payload(&mut public_tab);
    json!({
        "tab": public_tab,
        "threadId": thread_id,
        "cwd": active_cwd(tab),
        "snapshot": snapshot(tab),
        "configuration": configuration(tab),
        "recovery": recovery,
        "historyNextCursor": history_next_cursor,
    })
}

fn codex_skills_list_params(
    mut params: Value,
    tab: &WorkspaceTabRecord,
    workspace_path: &str,
) -> Value {
    if let Some(object) = params.as_object_mut() {
        object.remove("tabId");
        let cwd = active_cwd(tab).unwrap_or_else(|| workspace_path.to_string());
        object
            .entry("cwds".to_string())
            .or_insert_with(|| json!([cwd]));
        object
            .entry("forceReload".to_string())
            .or_insert(json!(false));
    }
    params
}

fn catalogue_cache_key(prefix: &str, params: &Value) -> String {
    let encoded = serde_json::to_string(params).unwrap_or_else(|_| "{}".to_string());
    format!("{prefix}{encoded}")
}

fn live_codex_review_branches(tab: &WorkspaceTabRecord, workspace_path: &str) -> HostResult<Value> {
    let cwd = active_cwd(tab).unwrap_or_else(|| workspace_path.to_string());
    let branches =
        core_git::list_branches(&cwd).map_err(|error| HostError::state(error.to_string()))?;
    let current_branch =
        core_git::current_branch(&cwd).map_err(|error| HostError::state(error.to_string()))?;
    Ok(json!({
        "branches": branches,
        "currentBranch": current_branch,
        "cwd": cwd,
    }))
}

#[cfg(test)]
#[path = "codex_requests_catalogue_tests.rs"]
mod tests;
