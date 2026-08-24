use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;

use crate::runtime_bridge::RuntimeBridge;

const SNAPSHOT_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, Debug, Default)]
pub struct WorkbenchSnapshot {
    pub projects: Vec<Project>,
    pub tabs: Vec<WorkspaceTab>,
    pub layout: Option<WorkbenchLayout>,
    pub tags: Vec<WorkspaceTag>,
    pub relations: Vec<WorkspaceRelation>,
    /// Workspace scope used for the tab/layout request. `None` identifies the
    /// sidebar-only snapshot and must never be applied to a mounted workbench.
    pub selected_workspace_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub repo_path: String,
    pub kind: String,
    pub updated_at: String,
    pub workspaces: Vec<Workspace>,
}

#[derive(Clone, Debug)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub path: String,
    pub branch: Option<String>,
    pub source_branch: Option<String>,
    pub kind: String,
    pub status: String,
    pub updated_at: String,
    pub host_id: String,
    pub reuses_existing_branch: bool,
    pub is_pinned: bool,
    pub tag_ids: Vec<String>,
    pub tag_names: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct WorkspaceTag {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Debug)]
pub struct WorkspaceRelation {
    pub parent_workspace_id: String,
    pub child_workspace_id: String,
}

#[derive(Clone, Debug)]
pub struct WorkspaceTab {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub kind: String,
    pub payload: Value,
}

#[derive(Clone, Debug)]
pub struct WorkbenchLayout {
    pub workspace_id: String,
    pub root: WorkbenchLayoutNode,
    pub groups: BTreeMap<String, WorkbenchPaneGroup>,
    pub active_group_id: String,
}

#[derive(Clone, Debug)]
pub enum WorkbenchLayoutNode {
    Leaf {
        group_id: String,
    },
    Split {
        axis: WorkbenchSplitAxis,
        first: Box<WorkbenchLayoutNode>,
        second: Box<WorkbenchLayoutNode>,
        ratio: f64,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WorkbenchSplitAxis {
    Horizontal,
    Vertical,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WorkbenchSplitDirection {
    Left,
    Right,
    Up,
    Down,
}

/// Drop regions used while a tab is being dragged over a pane.
///
/// `Center` keeps the existing pane and appends/reorders the tab. The four
/// directional regions create a sibling pane, matching Flutter's workbench
/// drag target semantics.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WorkbenchDropZone {
    Center,
    Left,
    Right,
    Up,
    Down,
}

impl WorkbenchDropZone {
    pub fn split_direction(self) -> Option<WorkbenchSplitDirection> {
        match self {
            Self::Center => None,
            Self::Left => Some(WorkbenchSplitDirection::Left),
            Self::Right => Some(WorkbenchSplitDirection::Right),
            Self::Up => Some(WorkbenchSplitDirection::Up),
            Self::Down => Some(WorkbenchSplitDirection::Down),
        }
    }
}

#[derive(Clone, Debug)]
pub struct WorkbenchPaneGroup {
    pub id: String,
    pub tab_ids: Vec<String>,
    pub active_tab_id: Option<String>,
}

#[cfg(any())]
impl WorkbenchLayout {
    pub fn add_tab_to_active_group(&mut self, tab_id: String) {
        let Some(group) = self.groups.get_mut(&self.active_group_id) else {
            return;
        };
        if !group.tab_ids.contains(&tab_id) {
            group.tab_ids.push(tab_id.clone());
        }
        group.active_tab_id = Some(tab_id);
    }

    pub fn remove_tab(&mut self, tab_id: &str) {
        for group in self.groups.values_mut() {
            group.tab_ids.retain(|candidate| candidate != tab_id);
            if group.active_tab_id.as_deref() == Some(tab_id) {
                group.active_tab_id = group.tab_ids.first().cloned();
            }
        }
    }

    pub fn activate_tab(&mut self, tab_id: &str) {
        let Some((group_id, group)) = self
            .groups
            .iter_mut()
            .find(|(_, group)| group.tab_ids.iter().any(|candidate| candidate == tab_id))
        else {
            return;
        };
        self.active_group_id = group_id.clone();
        group.active_tab_id = Some(tab_id.to_string());
    }

    pub fn split_group(
        &mut self,
        target_group_id: &str,
        direction: WorkbenchSplitDirection,
        new_group: WorkbenchPaneGroup,
    ) {
        let axis = match direction {
            WorkbenchSplitDirection::Left | WorkbenchSplitDirection::Right => {
                WorkbenchSplitAxis::Horizontal
            }
            WorkbenchSplitDirection::Up | WorkbenchSplitDirection::Down => {
                WorkbenchSplitAxis::Vertical
            }
        };
        let target = WorkbenchLayoutNode::Leaf {
            group_id: target_group_id.to_string(),
        };
        let added = WorkbenchLayoutNode::Leaf {
            group_id: new_group.id.clone(),
        };
        let (first, second) = match direction {
            WorkbenchSplitDirection::Left | WorkbenchSplitDirection::Up => (added, target),
            WorkbenchSplitDirection::Right | WorkbenchSplitDirection::Down => (target, added),
        };
        if replace_layout_leaf(
            &mut self.root,
            target_group_id,
            WorkbenchLayoutNode::Split {
                axis,
                first: Box::new(first),
                second: Box::new(second),
                ratio: 0.5,
            },
        ) {
            self.active_group_id = new_group.id.clone();
            self.groups.insert(new_group.id.clone(), new_group);
        }
    }

    pub fn merge_group_into_sibling(&mut self, group_id: &str) {
        let Some(sibling_id) = sibling_group_id(&self.root, group_id) else {
            return;
        };
        let Some(source) = self.groups.remove(group_id) else {
            return;
        };
        let Some(target) = self.groups.get_mut(&sibling_id) else {
            self.groups.insert(source.id.clone(), source);
            return;
        };
        target.tab_ids.extend(source.tab_ids);
        target.active_tab_id = source
            .active_tab_id
            .or_else(|| target.active_tab_id.clone());
        if let Some(root) = remove_layout_leaf(self.root.clone(), group_id) {
            self.root = root;
            self.active_group_id = sibling_id;
        }
    }

    pub fn to_value(&self) -> Value {
        json!({
            "workspaceId": self.workspace_id,
            "activeGroupId": self.active_group_id,
            "groups": self.groups.iter().map(|(key, group)| {
                (
                    key.clone(),
                    json!({
                        "id": group.id,
                        "tabIds": group.tab_ids,
                        "activeTabId": group.active_tab_id,
                    }),
                )
            }).collect::<serde_json::Map<_, _>>(),
            "root": layout_node_to_value(&self.root),
        })
    }
}

#[cfg(any())]
fn replace_layout_leaf(
    node: &mut WorkbenchLayoutNode,
    group_id: &str,
    replacement: WorkbenchLayoutNode,
) -> bool {
    match node {
        WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        } if candidate == group_id => {
            *node = replacement;
            true
        }
        WorkbenchLayoutNode::Split { first, second, .. } => {
            replace_layout_leaf(first, group_id, replacement.clone())
                || replace_layout_leaf(second, group_id, replacement)
        }
        _ => false,
    }
}

#[cfg(any())]
fn first_layout_leaf(node: &WorkbenchLayoutNode) -> &str {
    match node {
        WorkbenchLayoutNode::Leaf { group_id } => group_id,
        WorkbenchLayoutNode::Split { first, .. } => first_layout_leaf(first),
    }
}

#[cfg(any())]
fn sibling_group_id(node: &WorkbenchLayoutNode, group_id: &str) -> Option<String> {
    match node {
        WorkbenchLayoutNode::Leaf { .. } => None,
        WorkbenchLayoutNode::Split { first, second, .. } => match (&**first, &**second) {
            (WorkbenchLayoutNode::Leaf { group_id: first_id }, _) if first_id == group_id => {
                Some(first_layout_leaf(second).to_string())
            }
            (
                _,
                WorkbenchLayoutNode::Leaf {
                    group_id: second_id,
                },
            ) if second_id == group_id => Some(first_layout_leaf(first).to_string()),
            _ => sibling_group_id(first, group_id).or_else(|| sibling_group_id(second, group_id)),
        },
    }
}

#[cfg(any())]
fn remove_layout_leaf(node: WorkbenchLayoutNode, group_id: &str) -> Option<WorkbenchLayoutNode> {
    match node {
        WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        } => (candidate != group_id).then_some(WorkbenchLayoutNode::Leaf {
            group_id: candidate,
        }),
        WorkbenchLayoutNode::Split {
            axis,
            first,
            second,
            ratio,
        } => match (
            remove_layout_leaf(*first, group_id),
            remove_layout_leaf(*second, group_id),
        ) {
            (Some(first), Some(second)) => Some(WorkbenchLayoutNode::Split {
                axis,
                first: Box::new(first),
                second: Box::new(second),
                ratio,
            }),
            (Some(node), None) | (None, Some(node)) => Some(node),
            (None, None) => None,
        },
    }
}

#[cfg(any())]
fn layout_node_to_value(node: &WorkbenchLayoutNode) -> Value {
    match node {
        WorkbenchLayoutNode::Leaf { group_id } => {
            json!({"type": "leaf", "groupId": group_id})
        }
        WorkbenchLayoutNode::Split {
            axis,
            first,
            second,
            ratio,
        } => json!({
            "type": "split",
            "axis": match axis {
                WorkbenchSplitAxis::Horizontal => "horizontal",
                WorkbenchSplitAxis::Vertical => "vertical",
            },
            "first": layout_node_to_value(first),
            "second": layout_node_to_value(second),
            "ratio": ratio,
        }),
    }
}

impl WorkbenchSnapshot {
    pub async fn load(
        bridge: &RuntimeBridge,
        selected_workspace_id: Option<&str>,
    ) -> Result<Self, String> {
        let (projects_value, tags_value, relations_value) = tokio::join!(
            bridge.request_with_timeout("project.list", json!({}), SNAPSHOT_REQUEST_TIMEOUT,),
            bridge.request_with_timeout("workspaceTag.list", json!({}), SNAPSHOT_REQUEST_TIMEOUT,),
            bridge.request_with_timeout(
                "workspaceRelation.list",
                json!({}),
                SNAPSHOT_REQUEST_TIMEOUT,
            ),
        );
        let project_values = as_array(projects_value?);
        let tags = as_array(tags_value?)
            .into_iter()
            .map(parse_tag)
            .collect::<Result<Vec<_>, _>>()?;
        let relations = as_array(relations_value?)
            .into_iter()
            .map(parse_relation)
            .collect::<Result<Vec<_>, _>>()?;
        let mut projects = Vec::with_capacity(project_values.len());
        for value in project_values {
            let id = required_string(&value, "id")?;
            let workspaces = as_array(
                bridge
                    .request_with_timeout(
                        "workspace.list",
                        json!({ "projectId": id }),
                        SNAPSHOT_REQUEST_TIMEOUT,
                    )
                    .await?,
            )
            .into_iter()
            .map(parse_workspace)
            .collect::<Result<Vec<_>, _>>()?;
            projects.push(Project {
                id,
                name: required_string(&value, "name")?,
                repo_path: required_string(&value, "repoPath")?,
                kind: string_or(&value, "kind", "gitRepository"),
                updated_at: string_or(&value, "updatedAt", ""),
                workspaces,
            });
        }

        let mut tabs = Vec::new();
        let mut layout = None;
        if let Some(workspace_id) = selected_workspace_id {
            tabs = as_array(
                bridge
                    .request_with_timeout(
                        "tab.list",
                        json!({ "workspaceId": workspace_id }),
                        SNAPSHOT_REQUEST_TIMEOUT,
                    )
                    .await?,
            )
            .into_iter()
            .map(parse_tab)
            .collect::<Result<Vec<_>, _>>()?;
            layout = bridge
                .request_with_timeout(
                    "layout.find",
                    json!({ "workspaceId": workspace_id }),
                    SNAPSHOT_REQUEST_TIMEOUT,
                )
                .await?
                .as_object()
                .and_then(|record| record.get("data"))
                .cloned()
                .map(parse_layout)
                .transpose()?;
            if let Some(layout) = layout.as_mut() {
                normalize_layout_tab_ids(layout, &tabs);
                let tab_ids = tabs.iter().map(|tab| tab.id.clone()).collect::<Vec<_>>();
                layout.reconcile_tabs(&tab_ids);
            }
        }

        Ok(Self {
            projects,
            tabs,
            layout,
            tags,
            relations,
            selected_workspace_id: selected_workspace_id.map(str::to_string),
        })
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

/// Older GPUI builds persisted temporary numeric tab ids while the runtime
/// stores UUIDs.  Translate those positional ids before reconciliation so a
/// stale layout keeps its split topology and ratios instead of collapsing all
/// tabs into the active group.
fn normalize_layout_tab_ids(layout: &mut WorkbenchLayout, tabs: &[WorkspaceTab]) {
    let valid = tabs
        .iter()
        .map(|tab| tab.id.as_str())
        .collect::<BTreeSet<_>>();
    let resolve = |tab_id: &str| {
        if valid.contains(tab_id) {
            return Some(tab_id.to_string());
        }
        tab_id
            .parse::<usize>()
            .ok()
            .and_then(|index| index.checked_sub(1))
            .and_then(|index| tabs.get(index))
            .map(|tab| tab.id.clone())
    };
    for group in layout.groups.values_mut() {
        group.tab_ids = group
            .tab_ids
            .iter()
            .filter_map(|tab_id| resolve(tab_id))
            .collect();
        group.active_tab_id = group.active_tab_id.as_deref().and_then(resolve);
    }
}

fn parse_workspace(value: Value) -> Result<Workspace, String> {
    Ok(Workspace {
        id: required_string(&value, "id")?,
        name: required_string(&value, "name")?,
        path: required_string(&value, "path")?,
        branch: optional_string(&value, "branch"),
        source_branch: optional_string(&value, "sourceBranch"),
        kind: string_or(&value, "kind", "linked"),
        status: string_or(&value, "status", "active"),
        updated_at: string_or(&value, "updatedAt", ""),
        host_id: string_or(&value, "hostId", "local"),
        reuses_existing_branch: value.get("reusesExistingBranch").and_then(Value::as_bool)
            == Some(true),
        is_pinned: value.get("isPinned").and_then(Value::as_bool) == Some(true),
        tag_ids: value
            .get("tagIds")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
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

fn parse_tag(value: Value) -> Result<WorkspaceTag, String> {
    Ok(WorkspaceTag {
        id: required_string(&value, "id")?,
        name: required_string(&value, "name")?,
    })
}

fn parse_relation(value: Value) -> Result<WorkspaceRelation, String> {
    Ok(WorkspaceRelation {
        parent_workspace_id: required_string(&value, "parentWorkspaceId")?,
        child_workspace_id: required_string(&value, "childWorkspaceId")?,
    })
}

fn parse_tab(value: Value) -> Result<WorkspaceTab, String> {
    Ok(WorkspaceTab {
        id: required_string(&value, "id")?,
        workspace_id: required_string(&value, "workspaceId")?,
        title: required_string(&value, "title")?,
        kind: string_or(&value, "kind", "terminal"),
        payload: value.get("payload").cloned().unwrap_or_else(|| json!({})),
    })
}

fn parse_layout(value: Value) -> Result<WorkbenchLayout, String> {
    let groups_value = value
        .get("groups")
        .and_then(Value::as_object)
        .ok_or_else(|| "Workbench layout omitted groups.".to_string())?;
    let mut groups = BTreeMap::new();
    for (key, value) in groups_value {
        let id = required_string(value, "id")?;
        let tab_ids = value
            .get("tabIds")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect();
        groups.insert(
            key.clone(),
            WorkbenchPaneGroup {
                id,
                tab_ids,
                active_tab_id: optional_string(value, "activeTabId"),
            },
        );
    }
    Ok(WorkbenchLayout {
        workspace_id: required_string(&value, "workspaceId")?,
        root: parse_layout_node(
            value
                .get("root")
                .ok_or_else(|| "Workbench layout omitted root.".to_string())?,
        )?,
        groups,
        active_group_id: required_string(&value, "activeGroupId")?,
    })
}

fn parse_layout_node(value: &Value) -> Result<WorkbenchLayoutNode, String> {
    match value.get("type").and_then(Value::as_str) {
        Some("leaf") => Ok(WorkbenchLayoutNode::Leaf {
            group_id: required_string(value, "groupId")?,
        }),
        Some("split") => {
            let axis = match value.get("axis").and_then(Value::as_str) {
                Some("horizontal") => WorkbenchSplitAxis::Horizontal,
                Some("vertical") => WorkbenchSplitAxis::Vertical,
                _ => return Err("Workbench layout has an invalid split axis.".to_string()),
            };
            let first = value
                .get("first")
                .ok_or_else(|| "Workbench split omitted first child.".to_string())?;
            let second = value
                .get("second")
                .ok_or_else(|| "Workbench split omitted second child.".to_string())?;
            Ok(WorkbenchLayoutNode::Split {
                axis,
                first: Box::new(parse_layout_node(first)?),
                second: Box::new(parse_layout_node(second)?),
                ratio: value
                    .get("ratio")
                    .and_then(Value::as_f64)
                    .unwrap_or(0.5)
                    .clamp(0.15, 0.85),
            })
        }
        _ => Err("Workbench layout has an unknown node type.".to_string()),
    }
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

    #[test]
    fn layout_parser_preserves_groups_and_split_geometry() {
        let layout = parse_layout(json!({
            "workspaceId": "w1",
            "activeGroupId": "left",
            "groups": {
                "left": {"id": "left", "tabIds": ["t1"], "activeTabId": "t1"},
                "right": {"id": "right", "tabIds": ["t2"], "activeTabId": "t2"}
            },
            "root": {
                "type": "split",
                "axis": "horizontal",
                "ratio": 0.6,
                "first": {"type": "leaf", "groupId": "left"},
                "second": {"type": "leaf", "groupId": "right"}
            }
        }))
        .unwrap();
        assert_eq!(layout.groups.len(), 2);
        assert!(matches!(
            layout.root,
            WorkbenchLayoutNode::Split {
                axis: WorkbenchSplitAxis::Horizontal,
                ..
            }
        ));
    }

    #[test]
    fn numeric_legacy_tab_ids_are_mapped_before_reconciliation() {
        let mut layout = parse_layout(json!({
            "workspaceId": "w1",
            "activeGroupId": "right",
            "groups": {
                "left": {"id": "left", "tabIds": ["1"], "activeTabId": "1"},
                "right": {"id": "right", "tabIds": ["2", "3"], "activeTabId": "3"}
            },
            "root": {
                "type": "split",
                "axis": "horizontal",
                "ratio": 0.5,
                "first": {"type": "leaf", "groupId": "left"},
                "second": {"type": "leaf", "groupId": "right"}
            }
        }))
        .unwrap();
        let tabs = [
            WorkspaceTab {
                id: "uuid-1".to_string(),
                workspace_id: "w1".to_string(),
                title: "One".to_string(),
                kind: "terminal".to_string(),
                payload: json!({}),
            },
            WorkspaceTab {
                id: "uuid-2".to_string(),
                workspace_id: "w1".to_string(),
                title: "Two".to_string(),
                kind: "terminal".to_string(),
                payload: json!({}),
            },
            WorkspaceTab {
                id: "uuid-3".to_string(),
                workspace_id: "w1".to_string(),
                title: "Three".to_string(),
                kind: "terminal".to_string(),
                payload: json!({}),
            },
        ];
        normalize_layout_tab_ids(&mut layout, &tabs);
        layout.reconcile_tabs(&tabs.iter().map(|tab| tab.id.clone()).collect::<Vec<_>>());
        assert_eq!(layout.groups["left"].tab_ids, ["uuid-1"]);
        assert_eq!(layout.groups["right"].tab_ids, ["uuid-2", "uuid-3"]);
        assert!(matches!(layout.root, WorkbenchLayoutNode::Split { .. }));
    }
}
