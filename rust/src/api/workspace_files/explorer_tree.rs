use std::collections::{HashMap, HashSet};

use super::{
    WorkspaceExplorerDirectoryChildren, WorkspaceExplorerEntryBinding, WorkspaceExplorerTreeNode,
    WorkspaceExplorerTreeNodeKind, WorkspaceExplorerTreeProjection, WorkspaceFileEntry,
    WorkspaceFileKind,
};

const ROOT_ID: &str = "workspace-root";
const PLACEHOLDER_PREFIX: &str = "__alera_placeholder__:";

pub(super) fn project_tree(
    workspace_name: String,
    workspace_path: String,
    directories: Vec<WorkspaceExplorerDirectoryChildren>,
    replacement: Option<WorkspaceExplorerDirectoryChildren>,
) -> WorkspaceExplorerTreeProjection {
    let mut directories_by_path = directories
        .into_iter()
        .map(|directory| {
            (
                normalize_relative_path(&directory.relative_path),
                directory.children,
            )
        })
        .collect::<HashMap<_, _>>();

    if let Some(replacement) = replacement {
        replace_directory_children(
            &mut directories_by_path,
            normalize_relative_path(&replacement.relative_path),
            replacement.children,
        );
    }
    prune_unreachable_directories(&mut directories_by_path);

    let (nodes, entry_bindings) =
        build_nodes(&workspace_name, &workspace_path, &directories_by_path);
    let directories = sorted_directories(directories_by_path);

    WorkspaceExplorerTreeProjection {
        directories,
        nodes,
        entry_bindings,
    }
}

fn replace_directory_children(
    directories_by_path: &mut HashMap<String, Vec<WorkspaceFileEntry>>,
    relative_path: String,
    children: Vec<WorkspaceFileEntry>,
) {
    if let Some(previous) = directories_by_path.get(&relative_path) {
        let next_paths = children
            .iter()
            .map(|entry| entry.relative_path.as_str())
            .collect::<HashSet<_>>();
        let removed_paths = previous
            .iter()
            .filter_map(|entry| {
                (!next_paths.contains(entry.relative_path.as_str()))
                    .then_some(entry.relative_path.clone())
            })
            .collect::<Vec<_>>();
        for removed_path in removed_paths {
            remove_cached_subtree(directories_by_path, &removed_path);
        }
    }
    directories_by_path.insert(relative_path, children);
}

fn remove_cached_subtree(
    directories_by_path: &mut HashMap<String, Vec<WorkspaceFileEntry>>,
    relative_path: &str,
) {
    directories_by_path.remove(relative_path);
    let prefix = format!("{relative_path}/");
    directories_by_path.retain(|path, _| path != relative_path && !path.starts_with(&prefix));
    for children in directories_by_path.values_mut() {
        children.retain(|child| {
            child.relative_path != relative_path && !child.relative_path.starts_with(&prefix)
        });
    }
}

fn prune_unreachable_directories(
    directories_by_path: &mut HashMap<String, Vec<WorkspaceFileEntry>>,
) {
    let known_paths = directories_by_path
        .values()
        .flat_map(|children| children.iter().map(|entry| entry.relative_path.clone()))
        .collect::<HashSet<_>>();
    directories_by_path.retain(|path, _| path.is_empty() || known_paths.contains(path));
}

fn build_nodes(
    workspace_name: &str,
    workspace_path: &str,
    directories_by_path: &HashMap<String, Vec<WorkspaceFileEntry>>,
) -> (
    Vec<WorkspaceExplorerTreeNode>,
    Vec<WorkspaceExplorerEntryBinding>,
) {
    let mut nodes = HashMap::<String, WorkspaceExplorerTreeNode>::new();
    let mut entry_bindings = Vec::<WorkspaceExplorerEntryBinding>::new();
    nodes.insert(
        ROOT_ID.to_string(),
        WorkspaceExplorerTreeNode {
            id: ROOT_ID.to_string(),
            name: workspace_name.to_string(),
            kind: WorkspaceExplorerTreeNodeKind::Root,
            parent_id: String::new(),
            virtual_path: "/".to_string(),
            source_path: workspace_path.to_string(),
            entry_id: None,
            child_ids: Vec::new(),
            is_expanded: true,
            is_virtual: false,
        },
    );

    let mut directory_paths = directories_by_path.keys().cloned().collect::<Vec<_>>();
    directory_paths.sort_by(|left, right| {
        left.matches('/')
            .count()
            .cmp(&right.matches('/').count())
            .then_with(|| left.cmp(right))
    });
    for directory_path in directory_paths {
        if let Some(entries) = directories_by_path.get(&directory_path) {
            for entry in entries {
                add_entry_node(&mut nodes, &mut entry_bindings, entry);
                if matches!(entry.kind, WorkspaceFileKind::Directory)
                    && entry.has_children_hint
                    && !directories_by_path.contains_key(&entry.relative_path)
                {
                    add_placeholder(&mut nodes, &entry.relative_path);
                }
            }
        }
    }

    let mut nodes = nodes.into_values().collect::<Vec<_>>();
    nodes.sort_by(|left, right| {
        if left.id == ROOT_ID {
            return std::cmp::Ordering::Less;
        }
        if right.id == ROOT_ID {
            return std::cmp::Ordering::Greater;
        }
        left.virtual_path.cmp(&right.virtual_path)
    });
    entry_bindings.sort_by(|left, right| left.node_id.cmp(&right.node_id));
    (nodes, entry_bindings)
}

fn add_entry_node(
    nodes: &mut HashMap<String, WorkspaceExplorerTreeNode>,
    entry_bindings: &mut Vec<WorkspaceExplorerEntryBinding>,
    entry: &WorkspaceFileEntry,
) {
    let parts = entry
        .relative_path
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let mut parent_id = ROOT_ID.to_string();
    let mut current_path = String::new();
    for (index, part) in parts.iter().enumerate() {
        current_path = if current_path.is_empty() {
            (*part).to_string()
        } else {
            format!("{current_path}/{part}")
        };
        let is_leaf = index == parts.len() - 1;
        let node_id = node_id_for_path(&current_path);
        if !nodes.contains_key(&node_id) {
            nodes.insert(
                node_id.clone(),
                WorkspaceExplorerTreeNode {
                    id: node_id.clone(),
                    name: (*part).to_string(),
                    kind: if is_leaf && !matches!(entry.kind, WorkspaceFileKind::Directory) {
                        WorkspaceExplorerTreeNodeKind::File
                    } else {
                        WorkspaceExplorerTreeNodeKind::Folder
                    },
                    parent_id: parent_id.clone(),
                    virtual_path: format!("/{current_path}"),
                    source_path: current_path.clone(),
                    entry_id: is_leaf.then_some(entry.relative_path.clone()),
                    child_ids: Vec::new(),
                    is_expanded: false,
                    is_virtual: false,
                },
            );
            append_child(nodes, &parent_id, &node_id);
        }
        if is_leaf {
            entry_bindings.push(WorkspaceExplorerEntryBinding {
                node_id: node_id.clone(),
                relative_path: entry.relative_path.clone(),
            });
        }
        parent_id = node_id;
    }
}

fn add_placeholder(nodes: &mut HashMap<String, WorkspaceExplorerTreeNode>, parent_path: &str) {
    let parent_id = node_id_for_path(parent_path);
    let node_id = format!("{PLACEHOLDER_PREFIX}{parent_path}");
    if nodes.contains_key(&node_id) || !nodes.contains_key(&parent_id) {
        return;
    }
    nodes.insert(
        node_id.clone(),
        WorkspaceExplorerTreeNode {
            id: node_id.clone(),
            name: String::new(),
            kind: WorkspaceExplorerTreeNodeKind::File,
            parent_id: parent_id.clone(),
            virtual_path: format!("/{parent_path}/.alera-placeholder"),
            source_path: String::new(),
            entry_id: None,
            child_ids: Vec::new(),
            is_expanded: false,
            is_virtual: true,
        },
    );
    append_child(nodes, &parent_id, &node_id);
}

fn append_child(
    nodes: &mut HashMap<String, WorkspaceExplorerTreeNode>,
    parent_id: &str,
    child_id: &str,
) {
    let Some(parent) = nodes.get_mut(parent_id) else {
        return;
    };
    if !parent.child_ids.iter().any(|id| id == child_id) {
        parent.child_ids.push(child_id.to_string());
    }
}

fn sorted_directories(
    directories_by_path: HashMap<String, Vec<WorkspaceFileEntry>>,
) -> Vec<WorkspaceExplorerDirectoryChildren> {
    let mut directories = directories_by_path
        .into_iter()
        .map(
            |(relative_path, children)| WorkspaceExplorerDirectoryChildren {
                relative_path,
                children,
            },
        )
        .collect::<Vec<_>>();
    directories.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    directories
}

fn node_id_for_path(relative_path: &str) -> String {
    format!("path:{relative_path}")
}

fn normalize_relative_path(relative_path: &str) -> String {
    relative_path.trim_matches('/').to_string()
}
