use alera_core::git as core_git;

use super::GitError;

pub fn list_branches(path: String) -> Result<Vec<String>, GitError> {
    core_git::list_branches(&path).map_err(Into::into)
}

pub fn current_branch(path: String) -> Result<String, GitError> {
    core_git::current_branch(&path).map_err(Into::into)
}

pub fn create_and_checkout_branch(
    path: String,
    branch: String,
    expected_head: Option<String>,
    expected_oid: Option<String>,
) -> Result<(), GitError> {
    core_git::create_and_checkout_branch_from(
        &path,
        &branch,
        expected_head.as_deref(),
        expected_oid.as_deref(),
    )
    .map_err(Into::into)
}

pub fn reset_branch_to_ref(
    path: String,
    branch: String,
    target_ref: String,
    expected_oid: Option<String>,
) -> Result<(), GitError> {
    core_git::reset_branch_to_ref_from(&path, &branch, &target_ref, expected_oid.as_deref())
        .map_err(Into::into)
}

pub fn checkout_branch(path: String, branch: String) -> Result<(), GitError> {
    core_git::checkout_branch(&path, &branch).map_err(Into::into)
}

pub fn branch_exists(repo_path: String, branch: String) -> Result<bool, GitError> {
    core_git::branch_exists(&repo_path, &branch).map_err(Into::into)
}

pub fn is_valid_branch_name(name: String) -> Result<bool, GitError> {
    core_git::is_valid_branch_name(&name).map_err(Into::into)
}

pub fn refresh_source_branch(repo_path: String, source_branch: String) -> Result<(), GitError> {
    core_git::refresh_source_branch(&repo_path, &source_branch).map_err(Into::into)
}
pub fn default_branch(path: String) -> Result<String, super::GitError> {
    alera_core::git::default_branch(&path).map_err(super::GitError::from)
}
