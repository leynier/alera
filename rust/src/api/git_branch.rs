use alera_core::git as core_git;

use super::GitError;

pub fn list_branches(path: String) -> Result<Vec<String>, GitError> {
    core_git::list_branches(&path).map_err(Into::into)
}

pub fn current_branch(path: String) -> Result<String, GitError> {
    core_git::current_branch(&path).map_err(Into::into)
}

pub fn create_and_checkout_branch(path: String, branch: String) -> Result<(), GitError> {
    core_git::create_and_checkout_branch(&path, &branch).map_err(Into::into)
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
