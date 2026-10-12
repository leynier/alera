use super::{GitChangeEntry, GitDiffResult, GitError};
use alera_core::source_control;
pub use alera_core::source_control::GitWorkspaceComparison;
use flutter_rust_bridge::frb;

#[frb(mirror(GitWorkspaceComparison))]
pub struct _GitWorkspaceComparison {
    pub base_ref: Option<String>,
    pub base_oid: String,
    pub head_oid: Option<String>,
    pub head_ref: String,
    pub tree_oid: String,
    pub index_oid: String,
    pub entries: Vec<GitChangeEntry>,
    pub added: u32,
    pub removed: u32,
}

pub fn git_workspace_default_branch(path: String) -> Result<String, GitError> {
    source_control::git_workspace_default_branch(path)
}

pub fn git_workspace_comparison(
    path: String,
    base_ref: Option<String>,
) -> Result<GitWorkspaceComparison, GitError> {
    source_control::git_workspace_comparison(path, base_ref)
}

pub fn git_workspace_comparison_diff(
    path: String,
    snapshot: GitWorkspaceComparison,
    file_path: String,
) -> Result<GitDiffResult, GitError> {
    source_control::git_workspace_comparison_diff(path, snapshot, file_path)
}

pub fn git_commit_selected(
    path: String,
    snapshot: GitWorkspaceComparison,
    file_paths: Vec<String>,
    message: String,
) -> Result<String, GitError> {
    source_control::git_commit_selected(path, snapshot, file_paths, message)
}
