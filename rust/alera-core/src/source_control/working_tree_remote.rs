//! Fetch, pull and push through the git CLI so the credential helper applies.

use super::*;

pub fn git_fetch(path: String) -> Result<(), GitError> {
    git_cli_in_path(&path, &["fetch", "--all", "--prune"])
}

pub fn git_pull(path: String) -> Result<(), GitError> {
    git_pull_with_progress(path, &|_| {})
}

pub fn git_push(path: String) -> Result<(), GitError> {
    git_push_with_progress(path, &|_| {})
}

pub fn git_pull_with_progress(
    path: String,
    output: &(dyn Fn(String) + Send + Sync),
) -> Result<(), GitError> {
    git_cli_progress(&path, &["pull", "--progress"], output)
}

pub fn git_push_with_progress(
    path: String,
    output: &(dyn Fn(String) + Send + Sync),
) -> Result<(), GitError> {
    let repo = open_repo(&path)?;
    let state = git_repository_state(path.clone())?;
    if state.branch == "HEAD" {
        return Err(GitError::new(
            GitErrorKind::DetachedHead,
            "cannot push detached HEAD",
        ));
    }
    if state.tracks_same_named_upstream() {
        return git_cli_progress(&path, &["push", "--progress"], output);
    }
    if repo.find_remote("origin").is_err() {
        return Err(GitError::new(
            GitErrorKind::RemoteNotFound,
            "remote origin not found",
        ));
    }
    git_cli_progress(
        &path,
        &["push", "--progress", "-u", "origin", &state.branch],
        output,
    )
}

fn git_cli_in_path(path: &str, args: &[&str]) -> Result<(), GitError> {
    git_in_dir(Path::new(path), args)
        .map(|_| ())
        .map_err(|error| GitError::new(GitErrorKind::GitCli, error.message))
}

fn git_cli_progress(
    path: &str,
    args: &[&str],
    output: &(dyn Fn(String) + Send + Sync),
) -> Result<(), GitError> {
    crate::git_cli::git_in_dir_with_progress(Path::new(path), args, output)
        .map(|_| ())
        .map_err(|error| GitError::new(GitErrorKind::GitCli, error.message))
}
