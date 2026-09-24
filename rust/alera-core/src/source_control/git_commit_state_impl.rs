use git2::{ErrorCode, Oid, Repository, RepositoryState};

use super::{GitError, GitErrorKind};

pub(super) fn repository_has_conflicts(repo: &Repository) -> Result<bool, GitError> {
    let index = repo.index().map_err(GitError::from_git2)?;
    Ok(index.has_conflicts())
}

pub(super) fn commit_parent_commits(
    repo: &Repository,
) -> Result<(Vec<git2::Commit<'_>>, bool), GitError> {
    let head = current_head_commit(repo)?;
    match repo.state() {
        RepositoryState::Clean => Ok((head.into_iter().collect(), false)),
        RepositoryState::Merge => {
            let head = head.ok_or_else(|| {
                GitError::new(GitErrorKind::Conflict, "merge state has no HEAD commit")
            })?;
            let mut parents = vec![head];
            for oid in merge_head_oids(repo)? {
                parents.push(repo.find_commit(oid).map_err(GitError::from_git2)?);
            }
            Ok((parents, true))
        }
        RepositoryState::CherryPick | RepositoryState::Revert => {
            let head = head.ok_or_else(|| {
                GitError::new(GitErrorKind::Conflict, "operation state has no HEAD commit")
            })?;
            Ok((vec![head], true))
        }
        _ => Err(GitError::new(
            GitErrorKind::Conflict,
            "finish or abort the in-progress git operation before committing",
        )),
    }
}

pub(super) fn current_head_commit(repo: &Repository) -> Result<Option<git2::Commit<'_>>, GitError> {
    match repo.head() {
        Ok(head) => head.peel_to_commit().map(Some).map_err(GitError::from_git2),
        Err(error) if matches!(error.code(), ErrorCode::UnbornBranch | ErrorCode::NotFound) => {
            Ok(None)
        }
        Err(error) => Err(GitError::from_git2(error)),
    }
}

fn merge_head_oids(repo: &Repository) -> Result<Vec<Oid>, GitError> {
    let path = repo.path().join("MERGE_HEAD");
    let contents = std::fs::read_to_string(path).map_err(GitError::from_io)?;
    contents
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| Oid::from_str(line.trim()).map_err(GitError::from_git2))
        .collect()
}
