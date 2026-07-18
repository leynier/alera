use std::path::Path;

use git2::{Oid, Repository};

use super::git::git_diff_paths::GitPathContext;
use super::git::{open_repo, GitChangeArea, GitError};

const MAX_DIFF_BLOB_BYTES: u64 = 20 * 1024 * 1024;

/// Raw bytes of one side of a diffed file, used for binary previews such as
/// images. Returns `None` when that side does not exist (added or deleted
/// files), the entry is not a blob, or the content exceeds
/// [`MAX_DIFF_BLOB_BYTES`].
pub fn git_diff_blob_bytes(
    path: String,
    file_path: String,
    old_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    old_side: bool,
) -> Result<Option<Vec<u8>>, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let new_repo_path = paths.to_repo_path(&file_path);
    let old_repo_path = old_path
        .as_deref()
        .map(|old| paths.to_repo_path(old))
        .unwrap_or_else(|| new_repo_path.clone());

    if let Some(commit_oid) = commit_oid {
        let oid = Oid::from_str(&commit_oid).map_err(GitError::from_git2)?;
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        if old_side {
            let parent = match parent_oid {
                Some(parent_oid) => {
                    let parent_oid = Oid::from_str(&parent_oid).map_err(GitError::from_git2)?;
                    Some(repo.find_commit(parent_oid).map_err(GitError::from_git2)?)
                }
                None => commit.parent(0).ok(),
            };
            let Some(parent) = parent else {
                return Ok(None);
            };
            let tree = parent.tree().map_err(GitError::from_git2)?;
            return Ok(tree_blob_bytes(&repo, &tree, &old_repo_path));
        }
        let tree = commit.tree().map_err(GitError::from_git2)?;
        return Ok(tree_blob_bytes(&repo, &tree, &new_repo_path));
    }

    match area {
        Some(GitChangeArea::Staged) => {
            if old_side {
                let Some(tree) = repo.head().ok().and_then(|head| head.peel_to_tree().ok()) else {
                    return Ok(None);
                };
                Ok(tree_blob_bytes(&repo, &tree, &old_repo_path))
            } else {
                index_blob_bytes(&repo, &new_repo_path)
            }
        }
        Some(GitChangeArea::Unstaged) => {
            if old_side {
                index_blob_bytes(&repo, &old_repo_path)
            } else {
                Ok(workdir_file_bytes(&repo, &new_repo_path))
            }
        }
        Some(GitChangeArea::Untracked) => {
            if old_side {
                Ok(None)
            } else {
                Ok(workdir_file_bytes(&repo, &new_repo_path))
            }
        }
        None => Ok(None),
    }
}

fn tree_blob_bytes(repo: &Repository, tree: &git2::Tree<'_>, repo_path: &str) -> Option<Vec<u8>> {
    let entry = tree.get_path(Path::new(repo_path)).ok()?;
    blob_bytes(repo, entry.id())
}

fn index_blob_bytes(repo: &Repository, repo_path: &str) -> Result<Option<Vec<u8>>, GitError> {
    let index = repo.index().map_err(GitError::from_git2)?;
    let Some(entry) = index.get_path(Path::new(repo_path), 0) else {
        return Ok(None);
    };
    Ok(blob_bytes(repo, entry.id))
}

fn blob_bytes(repo: &Repository, oid: Oid) -> Option<Vec<u8>> {
    let blob = repo.find_blob(oid).ok()?;
    if blob.size() as u64 > MAX_DIFF_BLOB_BYTES {
        return None;
    }
    Some(blob.content().to_vec())
}

fn workdir_file_bytes(repo: &Repository, repo_path: &str) -> Option<Vec<u8>> {
    let full_path = repo.workdir()?.join(repo_path);
    let metadata = std::fs::metadata(&full_path).ok()?;
    if !metadata.is_file() || metadata.len() > MAX_DIFF_BLOB_BYTES {
        return None;
    }
    std::fs::read(&full_path).ok()
}
