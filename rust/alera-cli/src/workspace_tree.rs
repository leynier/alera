//! Workspace trees: a workspace and every workspace below it through parent
//! links, which is what the sidebar's Tree actions (Pin Workspace Tree, Set
//! Section Tree) apply to.

use std::collections::{BTreeMap, HashSet, VecDeque};
use std::path::Path;

use alera_core::runtime::{RuntimeStore, Workspace};
use anyhow::Result;
use serde_json::json;

use crate::runtime_host_client::RuntimeHostRpcClient;

/// `root` first, then its descendants breadth first. A stale relation cycle
/// cannot loop: each workspace is visited once.
pub(crate) fn tree_ids(workspaces: &[Workspace], root: &str) -> Vec<String> {
    let mut children: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for workspace in workspaces {
        if let Some(parent) = workspace.parent_workspace_id.as_deref() {
            children.entry(parent).or_default().push(&workspace.id);
        }
    }
    let mut seen = HashSet::from([root.to_string()]);
    let mut ordered = vec![root.to_string()];
    let mut pending = VecDeque::from([root.to_string()]);
    while let Some(id) = pending.pop_front() {
        for child in children.get(id.as_str()).into_iter().flatten() {
            if seen.insert((*child).to_string()) {
                ordered.push((*child).to_string());
                pending.push_back((*child).to_string());
            }
        }
    }
    ordered
}

/// Every workspace with its parent link, from the running host when there is
/// one so the answer matches what the apps show.
pub(crate) async fn all_workspaces(runtime_dir: &Path) -> Result<Vec<Workspace>> {
    if let Some(mut client) = RuntimeHostRpcClient::connect(runtime_dir).await? {
        return client.request("workspace.listAll", &json!({})).await;
    }
    RuntimeStore::open(runtime_dir)
        .await?
        .list_all_workspaces()
        .await
}

#[cfg(test)]
mod tests {
    use alera_core::runtime::{WorkspaceKind, WorkspaceStatus};
    use chrono::Utc;

    use super::*;

    fn workspace(id: &str, parent: Option<&str>) -> Workspace {
        Workspace {
            id: id.into(),
            instance_id: id.into(),
            host_id: "local".into(),
            project_id: "p".into(),
            name: id.into(),
            branch: None,
            path: format!("/{id}"),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: vec![],
            tag_names: vec![],
            section_id: None,
            parent_workspace_id: parent.map(str::to_string),
            child_count: 0,
        }
    }

    #[test]
    fn a_tree_is_the_root_and_every_descendant_once() {
        let workspaces = [
            workspace("root", Some("grandchild")),
            workspace("child", Some("root")),
            workspace("other", None),
            workspace("grandchild", Some("child")),
            workspace("sibling", Some("root")),
        ];
        assert_eq!(
            tree_ids(&workspaces, "root"),
            ["root", "child", "sibling", "grandchild"]
        );
        assert_eq!(tree_ids(&workspaces, "other"), ["other"]);
        assert_eq!(tree_ids(&workspaces, "missing"), ["missing"]);
    }
}
