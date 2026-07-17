use std::collections::HashMap;
use std::path::Path;

use super::git::{git_status, GitChangeStatus, GitError, GitErrorKind};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GitExplorerStatus {
    Untracked,
    Added,
    Modified,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitExplorerStatusEntry {
    pub path: String,
    pub status: GitExplorerStatus,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitExplorerStatusSnapshot {
    pub entries: Vec<GitExplorerStatusEntry>,
}

pub fn git_explorer_status_snapshot(path: String) -> Result<GitExplorerStatusSnapshot, GitError> {
    let result = match git_status(path) {
        Ok(result) => result,
        Err(error) if error.kind == GitErrorKind::NotARepository => {
            return Ok(GitExplorerStatusSnapshot {
                entries: Vec::new(),
            });
        }
        Err(error) => return Err(error),
    };
    let mut statuses = HashMap::<String, GitExplorerStatus>::new();
    for entry in result.entries {
        let status = match entry.status {
            GitChangeStatus::Untracked => GitExplorerStatus::Untracked,
            GitChangeStatus::Added => GitExplorerStatus::Added,
            GitChangeStatus::Modified
            | GitChangeStatus::Deleted
            | GitChangeStatus::Renamed
            | GitChangeStatus::Copied => GitExplorerStatus::Modified,
        };
        merge_explorer_status(&mut statuses, entry.path.clone(), status);
        let mut parent = Path::new(&entry.path).parent();
        while let Some(path) = parent {
            if path.as_os_str().is_empty() {
                break;
            }
            merge_explorer_status(
                &mut statuses,
                path.to_string_lossy().replace('\\', "/"),
                status,
            );
            parent = path.parent();
        }
    }
    let mut entries = statuses
        .into_iter()
        .map(|(path, status)| GitExplorerStatusEntry { path, status })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| left.path.cmp(&right.path));
    Ok(GitExplorerStatusSnapshot { entries })
}

fn merge_explorer_status(
    statuses: &mut HashMap<String, GitExplorerStatus>,
    path: String,
    status: GitExplorerStatus,
) {
    let priority = |status| match status {
        GitExplorerStatus::Untracked => 1,
        GitExplorerStatus::Added => 2,
        GitExplorerStatus::Modified => 3,
    };
    if statuses
        .get(&path)
        .is_some_and(|existing| priority(*existing) >= priority(status))
    {
        return;
    }
    statuses.insert(path, status);
}
