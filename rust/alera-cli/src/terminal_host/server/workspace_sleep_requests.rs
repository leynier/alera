use std::collections::{BTreeMap, BTreeSet};

use alera_core::runtime::WorkspaceTabRecord;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::ServerActor;

impl ServerActor {
    /// Terminal tabs a workspace sleep stopped, by workspace. Clients show them
    /// as closed until the workspace wakes.
    pub(super) async fn slept_workspace_tabs(&self, client_id: u64) -> HostResult<Value> {
        self.require_auth(client_id)?;
        serde_json::to_value(self.slept_workspace_tab_ids().await?)
            .map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn slept_workspace_tab_ids(
        &self,
    ) -> HostResult<BTreeMap<String, Vec<String>>> {
        self.runtime_store
            .list_slept_workspace_tabs()
            .await
            .map_err(|error| HostError::state(error.to_string()))
    }

    /// A session starting for one of a workspace's slept terminals wakes the
    /// whole workspace, which is what opening it from any client does.
    pub(super) async fn wake_workspace_for_tab(&mut self, workspace_id: &str, tab_id: &str) {
        match self
            .runtime_store
            .wake_workspace_for_tab(workspace_id, tab_id)
            .await
        {
            Ok(true) => self.broadcast_workspace_sleep_changed(workspace_id),
            Ok(false) => {}
            Err(error) => tracing::warn!("could not wake workspace {workspace_id}: {error}"),
        }
    }

    pub(super) fn broadcast_workspace_sleep_changed(&self, workspace_id: &str) {
        self.broadcast_authenticated(event(
            "workspaceSleepChanged",
            json!({"workspaceId": workspace_id}),
        ));
    }
}

/// Drops slept terminals from the sidebar counts and agent presence so a slept
/// workspace lists like one whose terminals were closed.
/// A slept tab closed later no longer counts, so only live records subtract.
pub(super) fn hide_slept_terminals(
    slept: &BTreeMap<String, Vec<String>>,
    tabs: &[WorkspaceTabRecord],
    terminal_tab_counts: &mut BTreeMap<String, i64>,
    agent_presence: &mut Value,
) {
    let slept_tab_ids = slept.values().flatten().collect::<BTreeSet<_>>();
    for tab in tabs {
        if tab.kind != "terminal" || !slept_tab_ids.contains(&tab.id) {
            continue;
        }
        if let Some(count) = terminal_tab_counts.get_mut(&tab.workspace_id) {
            *count -= 1;
            if *count <= 0 {
                terminal_tab_counts.remove(&tab.workspace_id);
            }
        }
    }
    if let Value::Array(items) = agent_presence {
        items.retain(|item| {
            !item
                .get("tabId")
                .and_then(Value::as_str)
                .is_some_and(|tab_id| slept_tab_ids.contains(&tab_id.to_string()))
        });
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use alera_core::runtime::WorkspaceTabRecord;
    use chrono::Utc;
    use serde_json::json;

    use super::hide_slept_terminals;

    fn terminal(id: &str, workspace_id: &str) -> WorkspaceTabRecord {
        WorkspaceTabRecord {
            id: id.to_string(),
            workspace_id: workspace_id.to_string(),
            kind: "terminal".to_string(),
            title: id.to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({}),
        }
    }

    #[test]
    fn slept_terminals_leave_the_counts_and_presence() {
        let slept = BTreeMap::from([("w-slept".to_string(), vec!["t-slept".to_string()])]);
        let tabs = [
            terminal("t-slept", "w-slept"),
            terminal("t-spawned", "w-slept"),
            terminal("t-live", "w-live"),
        ];
        let mut counts = BTreeMap::from([("w-slept".to_string(), 2), ("w-live".to_string(), 1)]);
        let mut presence = json!([
            {"workspaceId": "w-slept", "tabId": "t-slept"},
            {"workspaceId": "w-slept", "tabId": "t-spawned"},
            {"workspaceId": "w-live", "tabId": "t-live"},
        ]);

        hide_slept_terminals(&slept, &tabs, &mut counts, &mut presence);

        assert_eq!(counts["w-slept"], 1);
        assert_eq!(counts["w-live"], 1);
        assert_eq!(
            presence,
            json!([
                {"workspaceId": "w-slept", "tabId": "t-spawned"},
                {"workspaceId": "w-live", "tabId": "t-live"},
            ])
        );
    }

    #[test]
    fn a_slept_tab_closed_later_does_not_hide_a_new_terminal() {
        let slept = BTreeMap::from([(
            "w".to_string(),
            vec!["t-slept".to_string(), "t-closed".to_string()],
        )]);
        let tabs = [terminal("t-slept", "w"), terminal("t-new", "w")];
        let mut counts = BTreeMap::from([("w".to_string(), 2)]);
        let mut presence = json!([]);

        hide_slept_terminals(&slept, &tabs, &mut counts, &mut presence);

        assert_eq!(counts["w"], 1);
    }

    #[test]
    fn a_fully_slept_workspace_has_no_terminal_count() {
        let slept = BTreeMap::from([("w".to_string(), vec!["t-1".to_string(), "t-2".to_string()])]);
        let tabs = [terminal("t-1", "w"), terminal("t-2", "w")];
        let mut counts = BTreeMap::from([("w".to_string(), 2)]);
        let mut presence = json!([]);

        hide_slept_terminals(&slept, &tabs, &mut counts, &mut presence);

        assert!(counts.is_empty());
    }
}
