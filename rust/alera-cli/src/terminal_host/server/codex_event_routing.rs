use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_state::{
    active_turn_id, is_codex_tab, snapshot, tab_thread_id, turn_id_from_message,
};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn find_codex_tab_for_thread(
        &self,
        thread_id: &str,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
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
    ) -> HostResult<Option<WorkspaceTabRecord>> {
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

    pub(super) async fn reject_unroutable_codex_request(&self, id: Value) {
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

    pub(super) async fn find_codex_tab_for_message(
        &self,
        message: &Value,
        thread_id: Option<&str>,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        if let Some(thread_id) = thread_id {
            if let Some(tab) = self.find_codex_tab_for_thread(thread_id).await? {
                return Ok(Some(tab));
            }
            return Ok(None);
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
                            turn_id_from_message(event).as_deref() == Some(turn_id.as_str())
                        })
                    })
        })
        .await
    }

    pub(super) async fn find_codex_tab_by_id(
        &self,
        tab_id: &str,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        self.find_codex_tab_matching(|tab| tab.id == tab_id).await
    }

    async fn find_latest_codex_tab(&self) -> HostResult<Option<WorkspaceTabRecord>> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let mut candidates = Vec::new();
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
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

    async fn find_codex_tab_matching<F>(&self, matches: F) -> HostResult<Option<WorkspaceTabRecord>>
    where
        F: Fn(&WorkspaceTabRecord) -> bool,
    {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
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
