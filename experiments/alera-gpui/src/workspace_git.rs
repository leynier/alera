#[derive(Clone, Debug, Default)]
pub struct GitSnapshot {
    pub branch: String,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    pub has_conflicts: bool,
    pub head_message: Option<String>,
    pub changes: Vec<GitChange>,
    pub history: Vec<GitHistoryItem>,
    pub history_metadata: GitHistoryMetadata,
    pub stashes: Vec<GitStash>,
}

#[derive(Clone, Debug, Default)]
pub struct GitHistoryMetadata {
    pub current_ref: Option<GitHistoryRef>,
    pub remote_ref: Option<GitHistoryRef>,
    pub base_ref: Option<GitHistoryRef>,
    pub merge_base: Option<String>,
    pub has_incoming_changes: bool,
    pub has_outgoing_changes: bool,
    pub has_more: bool,
    pub limit: u32,
}

#[derive(Clone, Debug)]
pub struct GitChange {
    pub path: String,
    pub area: String,
    pub status: String,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

#[derive(Clone, Debug)]
pub struct GitHistoryItem {
    pub full_id: String,
    pub id: String,
    pub parent_ids: Vec<String>,
    pub subject: String,
    pub message: String,
    pub author: Option<String>,
    pub timestamp_millis: Option<i64>,
    pub references: Vec<GitHistoryRef>,
}

#[derive(Clone, Debug)]
pub struct GitHistoryRef {
    pub id: String,
    pub name: String,
    pub revision: Option<String>,
    pub category: String,
    pub color: Option<GitHistoryColor>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GitHistoryColor {
    Reference,
    RemoteReference,
    BaseReference,
    Lane1,
    Lane2,
    Lane3,
    Lane4,
    Lane5,
}

#[derive(Clone, Debug)]
pub struct GitStash {
    pub index: u32,
    pub reference: String,
    pub message: String,
}

#[derive(Clone, Debug)]
pub struct GitCommitChange {
    pub path: String,
    pub old_path: Option<String>,
    pub status: String,
    pub added: Option<u32>,
    pub removed: Option<u32>,
}

#[derive(Clone, Debug, Default)]
pub struct GitDiffResult {
    pub files: Vec<GitDiffFile>,
    pub truncated: bool,
}

#[derive(Clone, Debug)]
pub struct GitDiffFile {
    pub path: String,
    pub old_path: Option<String>,
    pub area: String,
    pub status: String,
    pub lines: Vec<GitDiffLine>,
    pub added: Option<u32>,
    pub removed: Option<u32>,
    pub is_binary: bool,
    pub is_large: bool,
    pub is_gitlink: bool,
    pub truncated: bool,
    pub line_preview_truncated: bool,
}

#[derive(Clone, Debug)]
pub struct GitDiffLine {
    pub text: String,
    pub kind: String,
}

pub fn complete_history_metadata(
    branch: &str,
    upstream: Option<&str>,
    ahead: u32,
    behind: u32,
    history: &[GitHistoryItem],
    mut metadata: GitHistoryMetadata,
) -> GitHistoryMetadata {
    if metadata.current_ref.is_none() {
        metadata.current_ref = find_history_ref(history, |item_ref| {
            item_ref.name == branch
                || item_ref.id == format!("refs/heads/{branch}")
                || item_ref.id.ends_with(&format!("/{branch}"))
        });
    }
    if metadata.remote_ref.is_none() {
        metadata.remote_ref = upstream.and_then(|upstream| {
            find_history_ref(history, |item_ref| {
                item_ref.name == upstream
                    || item_ref.id == format!("refs/remotes/{upstream}")
                    || item_ref.id.ends_with(&format!("/{upstream}"))
            })
        });
    }
    if metadata.merge_base.is_none() {
        metadata.merge_base = match (
            metadata
                .current_ref
                .as_ref()
                .and_then(|item_ref| item_ref.revision.as_deref()),
            metadata
                .remote_ref
                .as_ref()
                .and_then(|item_ref| item_ref.revision.as_deref()),
        ) {
            (Some(current), Some(remote)) => nearest_common_ancestor(history, current, remote),
            _ => None,
        };
    }
    if ahead > 0 {
        metadata.has_outgoing_changes = true;
    }
    if behind > 0 {
        metadata.has_incoming_changes = true;
    }
    if metadata.limit == 0 {
        metadata.limit = 50;
        metadata.has_more = history.len() >= metadata.limit as usize;
    }
    metadata
}

fn find_history_ref(
    history: &[GitHistoryItem],
    predicate: impl Fn(&GitHistoryRef) -> bool,
) -> Option<GitHistoryRef> {
    history.iter().find_map(|item| {
        item.references.iter().find_map(|item_ref| {
            predicate(item_ref).then(|| {
                let mut item_ref = item_ref.clone();
                item_ref.revision = Some(item.full_id.clone());
                item_ref
            })
        })
    })
}

fn nearest_common_ancestor(
    history: &[GitHistoryItem],
    current: &str,
    remote: &str,
) -> Option<String> {
    let parents = history
        .iter()
        .map(|item| (item.full_id.as_str(), item.parent_ids.as_slice()))
        .collect::<HashMap<_, _>>();
    let current_distances = ancestor_distances(&parents, current);
    let remote_distances = ancestor_distances(&parents, remote);
    current_distances
        .iter()
        .filter_map(|(id, current_distance)| {
            remote_distances
                .get(id)
                .map(|remote_distance| ((*current_distance).max(*remote_distance), id))
        })
        .min_by_key(|(distance, _)| *distance)
        .map(|(_, id)| (*id).to_owned())
}

fn ancestor_distances<'a>(
    parents: &HashMap<&'a str, &'a [String]>,
    revision: &'a str,
) -> HashMap<&'a str, usize> {
    let mut distances = HashMap::new();
    let mut queue = VecDeque::from([(revision, 0usize)]);
    while let Some((id, distance)) = queue.pop_front() {
        if distances
            .get(id)
            .is_some_and(|known_distance| *known_distance <= distance)
        {
            continue;
        }
        distances.insert(id, distance);
        if let Some(parent_ids) = parents.get(id) {
            queue.extend(
                parent_ids
                    .iter()
                    .map(|parent_id| (parent_id.as_str(), distance + 1)),
            );
        }
    }
    distances
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn completes_legacy_history_metadata_from_refs_and_graph() {
        let history = vec![
            item("local", &["base"], &[item_ref("main")]),
            item("remote", &["base"], &[item_ref("origin/main")]),
            item("base", &[], &[]),
        ];

        let metadata = complete_history_metadata(
            "main",
            Some("origin/main"),
            1,
            1,
            &history,
            GitHistoryMetadata::default(),
        );

        assert_eq!(
            metadata.current_ref.unwrap().revision.as_deref(),
            Some("local")
        );
        assert_eq!(
            metadata.remote_ref.unwrap().revision.as_deref(),
            Some("remote")
        );
        assert_eq!(metadata.merge_base.as_deref(), Some("base"));
        assert!(metadata.has_incoming_changes);
        assert!(metadata.has_outgoing_changes);
        assert_eq!(metadata.limit, 50);
    }

    fn item(id: &str, parent_ids: &[&str], references: &[GitHistoryRef]) -> GitHistoryItem {
        GitHistoryItem {
            full_id: id.to_owned(),
            id: id.to_owned(),
            parent_ids: parent_ids
                .iter()
                .map(|parent| (*parent).to_owned())
                .collect(),
            subject: id.to_owned(),
            message: id.to_owned(),
            author: None,
            timestamp_millis: None,
            references: references.to_vec(),
        }
    }

    fn item_ref(name: &str) -> GitHistoryRef {
        GitHistoryRef {
            id: name.to_owned(),
            name: name.to_owned(),
            revision: None,
            category: String::new(),
            color: None,
        }
    }
}

#[derive(Clone, Debug)]
pub enum GitAction {
    StageAll,
    StagePath(String),
    UnstageAll,
    UnstagePath(String),
    DiscardAll,
    DiscardPath(String),
    Commit(String),
    Amend(String),
    Fetch,
    Pull,
    Push,
    Sync,
    Stash,
    StashPop(u32),
}
use std::collections::{HashMap, VecDeque};
