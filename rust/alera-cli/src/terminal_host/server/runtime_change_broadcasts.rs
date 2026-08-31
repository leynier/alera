use serde_json::{json, Value};

use crate::terminal_host::protocol::event;

use super::ServerActor;

/// Scoped runtime change broadcasts.
///
/// Every app-side watcher listens to the same event stream, so an unscoped
/// event makes all of them refetch: spawning one terminal used to cost one
/// round-trip per registered workspace. Carrying the id lets a watcher skip an
/// event that is not about it.
///
/// The scope is optional on purpose. An older host broadcasts an empty payload
/// and the app treats an absent scope as a wildcard, which keeps a new app
/// correct against a host that is already running and a new host correct
/// against an older app. For that reason this is an additive payload change
/// and must not bump the protocol version. Pass `None` whenever the mutation
/// really is broader than one workspace or project: the wildcard is the safe
/// value, never guess a scope.
impl ServerActor {
    pub(super) fn broadcast_workflow_catalog_changed(
        &self,
        source: &alera_core::runtime::WorkflowRecipeSource,
        catalog_revision: i64,
    ) {
        self.broadcast_authenticated_local(event(
            "workflowCatalogChanged",
            json!({"source": source, "catalogRevision": catalog_revision}),
        ));
    }

    pub(super) fn broadcast_workspace_tabs_changed(&self, workspace_id: Option<&str>) {
        self.broadcast_authenticated(event(
            "workspaceTabsChanged",
            scope_payload("workspaceId", workspace_id),
        ));
    }

    pub(super) fn broadcast_workspaces_changed(&self, project_id: Option<&str>) {
        self.broadcast_authenticated(event(
            "workspacesChanged",
            scope_payload("projectId", project_id),
        ));
    }

    pub(super) fn broadcast_mobile_emulator_changed(
        &self,
        tab_id: Option<&str>,
        workspace_id: Option<&str>,
        reason: &str,
    ) {
        let mut payload = scope_payload("workspaceId", workspace_id);
        if let Some(tab_id) = tab_id.filter(|value| !value.is_empty()) {
            payload["tabId"] = Value::String(tab_id.to_string());
        }
        payload["reason"] = Value::String(reason.to_string());
        self.broadcast_authenticated(event("mobileEmulatorChanged", payload));
    }

    pub(super) fn broadcast_agent_canvas_changed(
        &self,
        workspace_id: &str,
        canvas_id: &str,
        revision: i64,
        reason: &str,
    ) {
        self.broadcast_authenticated(event(
            "agentCanvasChanged",
            json!({
                "workspaceId": workspace_id,
                "canvasId": canvas_id,
                "revision": revision,
                "reason": reason,
            }),
        ));
    }
}

/// Pulls a scope id out of a record payload that is about to be handed back.
pub(super) fn string_scope(payload: &Value, key: &str) -> Option<String> {
    payload.get(key).and_then(Value::as_str).map(str::to_string)
}

fn scope_payload(field: &str, id: Option<&str>) -> Value {
    match id.filter(|value| !value.is_empty()) {
        Some(value) => json!({ field: value }),
        None => json!({}),
    }
}

#[cfg(test)]
mod tests {
    use super::scope_payload;
    use serde_json::json;

    #[test]
    fn scope_payload_carries_the_id_when_known() {
        assert_eq!(
            scope_payload("workspaceId", Some("workspace-1")),
            json!({ "workspaceId": "workspace-1" })
        );
    }

    #[test]
    fn scope_payload_is_a_wildcard_without_an_id() {
        assert_eq!(scope_payload("workspaceId", None), json!({}));
    }

    #[test]
    fn scope_payload_treats_an_empty_id_as_a_wildcard() {
        assert_eq!(scope_payload("projectId", Some("")), json!({}));
    }

    #[test]
    fn emulator_change_payload_can_carry_both_scopes() {
        let mut payload = scope_payload("workspaceId", Some("workspace-1"));
        payload["tabId"] = serde_json::Value::String("tab-1".into());
        payload["reason"] = serde_json::Value::String("attached".into());
        assert_eq!(
            payload,
            json!({
                "workspaceId": "workspace-1",
                "tabId": "tab-1",
                "reason": "attached",
            })
        );
    }
}
