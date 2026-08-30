use gpui::Context;
use serde_json::Value;

use super::AleraApp;

#[derive(Debug, PartialEq, Eq)]
pub(super) struct AddedProject {
    pub id: String,
}

impl AddedProject {
    pub fn registered(value: &Value) -> Result<Self, String> {
        Self::from_id(value.get("project").and_then(|project| project.get("id")))
    }

    pub fn cloned(value: &Value) -> Result<Self, String> {
        Self::from_id(value.get("projectId"))
    }

    fn from_id(value: Option<&Value>) -> Result<Self, String> {
        value.and_then(Value::as_str).filter(|id| !id.is_empty())
            .map(|id| Self { id: id.to_owned() })
            .ok_or_else(|| "Project operation did not return a project ID.".to_owned())
    }
}

impl AleraApp {
    pub(super) fn activate_added_project(&mut self, project: AddedProject, cx: &mut Context<Self>) {
        if self.collapsed_project_ids.remove(&project.id) {
            self.persist_sidebar_view_prefs(cx);
        }
        // A selected-project set is a positive filter, not the current context.
        // Preserve it while activating the added project, just like Flutter.
        self.active_project_id = Some(project.id);
        self.selected_workspace_id = None;
        self.selected_tab_id = None;
        self.pending_workspace_terminal_id = None;
        self.pending_workspace_tab_id = None;
        self.reset_local_workspace(cx);
        self.error = None;
        self.refresh(cx);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn project_activation_uses_project_identity_not_main_workspace_or_job() {
        let added = AddedProject::registered(&json!({
            "project": {"id": "project"}, "mainWorkspace": {"id": "main"}, "created": false
        })).unwrap();
        assert_eq!(added.id, "project");
        assert_eq!(AddedProject::cloned(&json!({"id": "job", "projectId": "project", "workspaceId": "main"})).unwrap(), added);
        assert!(AddedProject::cloned(&json!({"id": "job", "projectId": null})).is_err());
        assert!(AddedProject::registered(&json!({"project": {"id": ""}})).is_err());
    }
}
