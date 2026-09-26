use alera_core::source_control as core;

use super::git::GitError;

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
    let snapshot = core::git_explorer_status_snapshot(path)?;
    Ok(GitExplorerStatusSnapshot {
        entries: snapshot
            .entries
            .into_iter()
            .map(|entry| GitExplorerStatusEntry {
                path: entry.path,
                status: match entry.status {
                    core::GitExplorerStatus::Untracked => GitExplorerStatus::Untracked,
                    core::GitExplorerStatus::Added => GitExplorerStatus::Added,
                    core::GitExplorerStatus::Modified => GitExplorerStatus::Modified,
                },
            })
            .collect(),
    })
}
