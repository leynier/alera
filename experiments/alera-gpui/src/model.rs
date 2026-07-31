use serde_json::{json, Value};

use crate::runtime_bridge::RuntimeBridge;

#[derive(Clone, Debug, Default)]
pub struct WorkbenchSnapshot {
    pub projects: Vec<Project>,
    pub tabs: Vec<WorkspaceTab>,
    pub layout: Option<Value>,
}

#[derive(Clone, Debug)]
pub struct Project {
    pub name: String,
    pub repo_path: String,
    pub kind: String,
    pub workspaces: Vec<Workspace>,
}

#[derive(Clone, Debug)]
pub struct Workspace {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub path: String,
    pub branch: Option<String>,
    pub kind: String,
    pub status: String,
    pub is_pinned: bool,
    pub tag_names: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct WorkspaceTab {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub payload: Value,
}

impl WorkbenchSnapshot {
    pub async fn load(
        bridge: &RuntimeBridge,
        selected_workspace_id: Option<&str>,
    ) -> Result<Self, String> {
        let project_values = as_array(bridge.request("project.list", json!({})).await?);
        let mut projects = Vec::with_capacity(project_values.len());
        for value in project_values {
            let id = required_string(&value, "id")?;
            let workspaces = as_array(
                bridge
                    .request("workspace.list", json!({ "projectId": id }))
                    .await?,
            )
            .into_iter()
            .map(parse_workspace)
            .collect::<Result<Vec<_>, _>>()?;
            projects.push(Project {
                name: required_string(&value, "name")?,
                repo_path: required_string(&value, "repoPath")?,
                kind: string_or(&value, "kind", "gitRepository"),
                workspaces,
            });
        }

        let mut tabs = Vec::new();
        let mut layout = None;
        if let Some(workspace_id) = selected_workspace_id {
            tabs = as_array(
                bridge
                    .request("tab.list", json!({ "workspaceId": workspace_id }))
                    .await?,
            )
            .into_iter()
            .map(parse_tab)
            .collect::<Result<Vec<_>, _>>()?;
            layout = bridge
                .request("layout.find", json!({ "workspaceId": workspace_id }))
                .await?
                .as_object()
                .and_then(|record| record.get("data"))
                .cloned();
        }

        Ok(Self {
            projects,
            tabs,
            layout,
        })
    }

    pub fn first_workspace_id(&self) -> Option<&str> {
        self.projects
            .iter()
            .flat_map(|project| &project.workspaces)
            .next()
            .map(|workspace| workspace.id.as_str())
    }

    pub fn project_for_workspace(&self, workspace_id: &str) -> Option<&Project> {
        self.projects.iter().find(|project| {
            project
                .workspaces
                .iter()
                .any(|item| item.id == workspace_id)
        })
    }

    pub fn workspace(&self, workspace_id: &str) -> Option<&Workspace> {
        self.projects
            .iter()
            .flat_map(|project| &project.workspaces)
            .find(|workspace| workspace.id == workspace_id)
    }
}

fn parse_workspace(value: Value) -> Result<Workspace, String> {
    Ok(Workspace {
        id: required_string(&value, "id")?,
        project_id: required_string(&value, "projectId")?,
        name: required_string(&value, "name")?,
        path: required_string(&value, "path")?,
        branch: optional_string(&value, "branch"),
        kind: string_or(&value, "kind", "linked"),
        status: string_or(&value, "status", "active"),
        is_pinned: value.get("isPinned").and_then(Value::as_bool) == Some(true),
        tag_names: value
            .get("tagNames")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
    })
}

fn parse_tab(value: Value) -> Result<WorkspaceTab, String> {
    Ok(WorkspaceTab {
        id: required_string(&value, "id")?,
        title: required_string(&value, "title")?,
        kind: string_or(&value, "kind", "terminal"),
        payload: value.get("payload").cloned().unwrap_or_else(|| json!({})),
    })
}

fn as_array(value: Value) -> Vec<Value> {
    value.as_array().cloned().unwrap_or_default()
}

fn required_string(value: &Value, key: &str) -> Result<String, String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| format!("Runtime payload omitted {key}."))
}

fn optional_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .map(str::to_string)
}

fn string_or(value: &Value, key: &str, fallback: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_parser_preserves_runtime_identity_and_tags() {
        let workspace = parse_workspace(json!({
            "id": "w1",
            "projectId": "p1",
            "name": "GPUI",
            "path": "/tmp/gpui",
            "branch": "feat/gpui",
            "kind": "linked",
            "status": "active",
            "isPinned": true,
            "tagNames": ["POC", "Rust"],
        }))
        .unwrap();
        assert_eq!(workspace.id, "w1");
        assert_eq!(workspace.branch.as_deref(), Some("feat/gpui"));
        assert_eq!(workspace.tag_names, ["POC", "Rust"]);
        assert!(workspace.is_pinned);
    }
}
