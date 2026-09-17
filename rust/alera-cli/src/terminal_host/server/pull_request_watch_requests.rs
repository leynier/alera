use alera_core::runtime::{PullRequestWatch, PullRequestWatchDispatchMark, WorkspaceStatus};
use serde_json::{json, Value};

use super::requests::{optional_string_key, require_string_key, terminal_session_id_from_tab};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    pub(super) async fn pull_request_watch_request(
        &mut self,
        client_id: u64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        match verb {
            "pullRequestWatch.list" => {
                let items = self
                    .runtime_store
                    .list_pull_request_watches()
                    .await
                    .map_err(state_error)?;
                Ok(json!({ "items": items }))
            }
            "pullRequestWatch.find" => {
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let watch = self
                    .runtime_store
                    .find_pull_request_watch(&workspace_id)
                    .await
                    .map_err(state_error)?;
                serde_json::to_value(watch).map_err(state_error)
            }
            "pullRequestWatch.start" => {
                let watch = self.resolve_watch(payload).await?;
                let stored = self
                    .runtime_store
                    .upsert_pull_request_watch(watch)
                    .await
                    .map_err(state_error)?;
                self.broadcast_pull_request_watch_changed(Some(&stored.workspace_id));
                serde_json::to_value(stored).map_err(state_error)
            }
            "pullRequestWatch.stop" => {
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let removed = self
                    .runtime_store
                    .remove_pull_request_watch(&workspace_id)
                    .await
                    .map_err(state_error)?;
                if removed {
                    self.broadcast_pull_request_watch_changed(Some(&workspace_id));
                }
                Ok(json!({ "removed": removed }))
            }
            _ => Err(HostError::format("Unknown pull request watch request.")),
        }
    }

    async fn resolve_watch(&self, payload: &Value) -> HostResult<PullRequestWatch> {
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::format("Workspace not found."))?;
        if workspace.status != WorkspaceStatus::Active {
            return Err(HostError::format("Workspace is not active."));
        }
        let review_number = match optional_i64(payload, "reviewNumber")? {
            Some(number) => number,
            None => linked_review_number(
                self.runtime_store
                    .find_linked_review(&workspace_id)
                    .await
                    .map_err(state_error)?,
            )?,
        };
        let tab_id = self.resolve_tab_id(&workspace_id, payload).await?;
        let profile_id = optional_string_key(payload, "profileId");
        let profile = match profile_id.as_deref() {
            Some(id) => Some(
                self.runtime_store
                    .find_agent_profile(id)
                    .await
                    .map_err(state_error)?
                    .ok_or_else(|| HostError::format(format!("agent profile not found: {id}")))?,
            ),
            None => None,
        };
        let label = optional_string_key(payload, "label").or_else(|| {
            profile
                .as_ref()
                .map(|profile| profile.name.clone())
                .filter(|name| !name.trim().is_empty())
        });
        Ok(PullRequestWatch {
            workspace_id,
            review_number,
            mode: mode_key(payload)?,
            checks: bool_key(payload, "checks", true)?,
            comments: bool_key(payload, "comments", true)?,
            conflicts: bool_key(payload, "conflicts", true)?,
            tab_id,
            profile_id,
            label,
            last_dispatch: last_dispatch(payload)?,
            last_merged_head_sha: optional_string_key(payload, "lastMergedHeadSha"),
        })
    }

    async fn resolve_tab_id(
        &self,
        workspace_id: &str,
        payload: &Value,
    ) -> HostResult<Option<String>> {
        if let Some(tab_id) = optional_string_key(payload, "tabId") {
            let tab = self
                .runtime_store
                .find_workspace_tab(&tab_id)
                .await
                .map_err(state_error)?
                .ok_or_else(|| HostError::format("Terminal tab not found."))?;
            if tab.workspace_id != workspace_id {
                return Err(HostError::format(
                    "Terminal tab does not belong to this workspace.",
                ));
            }
            return Ok(Some(tab_id));
        }
        let Some(handle) = optional_string_key(payload, "handle") else {
            return Ok(None);
        };
        if let Some(session) = self.sessions.get(&handle) {
            if session.workspace_id != workspace_id {
                return Err(HostError::format(
                    "Terminal handle does not belong to this workspace.",
                ));
            }
            return Ok(Some(session.tab_id.clone()));
        }
        let tabs = self
            .runtime_store
            .list_workspace_tabs(workspace_id)
            .await
            .map_err(state_error)?;
        for tab in tabs {
            if terminal_session_id_from_tab(&tab).as_deref() == Some(handle.as_str()) {
                return Ok(Some(tab.id));
            }
        }
        Err(HostError::format("Terminal handle not found."))
    }
}

fn linked_review_number(linked: Option<alera_core::runtime::LinkedReview>) -> HostResult<i64> {
    match linked {
        Some(review) if !review.dismissed => {
            review.number.filter(|number| *number > 0).ok_or_else(|| {
                HostError::format("Link or open a pull request for this workspace first.")
            })
        }
        _ => Err(HostError::format(
            "Link or open a pull request for this workspace first.",
        )),
    }
}

fn mode_key(payload: &Value) -> HostResult<String> {
    match payload.get("mode") {
        None | Some(Value::Null) => Ok("fix".to_string()),
        Some(Value::String(value)) if value == "fix" || value == "fixAndMerge" => Ok(value.clone()),
        _ => Err(HostError::format("mode must be fix or fixAndMerge.")),
    }
}

fn bool_key(payload: &Value, key: &str, default: bool) -> HostResult<bool> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(default),
        Some(Value::Bool(value)) => Ok(*value),
        _ => Err(HostError::format(format!("{key} must be a boolean."))),
    }
}

fn optional_i64(payload: &Value, key: &str) -> HostResult<Option<i64>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Number(value)) => value
            .as_i64()
            .map(Some)
            .ok_or_else(|| HostError::format(format!("{key} must be an integer."))),
        _ => Err(HostError::format(format!("{key} must be an integer."))),
    }
}

fn last_dispatch(payload: &Value) -> HostResult<Option<PullRequestWatchDispatchMark>> {
    match payload.get("lastDispatch") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => serde_json::from_value(value.clone()).map_err(state_error),
    }
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
