use std::collections::HashSet;

use git2::{BranchType, ErrorCode, Oid, Repository};

use super::{open_repo, GitError, GitErrorKind};

pub(super) fn is_ancestor(
    path: String,
    ancestor_ref: String,
    descendant_ref: String,
) -> Result<bool, GitError> {
    let repo = open_repo(&path)?;
    let ancestor_oid = resolve_comparison_ref_oid(&repo, &ancestor_ref, "ancestor")?;
    let descendant_oid = resolve_comparison_ref_oid(&repo, &descendant_ref, "descendant")?;
    if ancestor_oid == descendant_oid {
        return Ok(true);
    }
    repo.graph_descendant_of(descendant_oid, ancestor_oid)
        .map_err(GitError::from_git2)
}

fn resolve_comparison_ref_oid(
    repo: &Repository,
    raw_name: &str,
    role: &str,
) -> Result<Oid, GitError> {
    let name = raw_name.trim();
    if name.is_empty() || name.starts_with('-') {
        return Err(GitError::new(
            GitErrorKind::InvalidBranchName,
            format!("{role} ref is invalid"),
        ));
    }

    let candidates = if name.starts_with("refs/") {
        vec![name.to_string()]
    } else {
        vec![
            format!("refs/heads/{name}"),
            format!("refs/remotes/origin/{name}"),
        ]
    };
    for candidate in candidates {
        match repo.revparse_single(&candidate) {
            Ok(object) => {
                return object
                    .peel_to_commit()
                    .map(|commit| commit.id())
                    .map_err(GitError::from_git2);
            }
            Err(error) if error.code() == ErrorCode::Ambiguous => {
                return Err(GitError::new(
                    GitErrorKind::BranchNotFound,
                    format!("{role} ref '{name}' is ambiguous"),
                ));
            }
            Err(error) if matches!(error.code(), ErrorCode::NotFound | ErrorCode::InvalidSpec) => {}
            Err(error) => return Err(GitError::from_git2(error)),
        }
    }

    let mut remote_matches = HashSet::new();
    let branches = repo
        .branches(Some(BranchType::Remote))
        .map_err(GitError::from_git2)?;
    for branch_result in branches {
        let (branch, _) = branch_result.map_err(GitError::from_git2)?;
        let Some(branch_name) = branch.name().map_err(GitError::from_git2)? else {
            continue;
        };
        let Some((_, short_name)) = branch_name.split_once('/') else {
            continue;
        };
        if short_name != name {
            continue;
        }
        let oid = branch
            .get()
            .peel_to_commit()
            .map_err(GitError::from_git2)?
            .id();
        remote_matches.insert(oid);
    }
    if remote_matches.len() == 1 {
        if let Some(oid) = remote_matches.iter().next().copied() {
            return Ok(oid);
        }
    }
    if remote_matches.len() > 1 {
        return Err(GitError::new(
            GitErrorKind::BranchNotFound,
            format!("{role} ref '{name}' is ambiguous across remotes"),
        ));
    }

    if !name.starts_with("refs/") {
        match repo.revparse_single(name) {
            Ok(object) => {
                return object
                    .peel_to_commit()
                    .map(|commit| commit.id())
                    .map_err(GitError::from_git2);
            }
            Err(error) if error.code() == ErrorCode::Ambiguous => {
                return Err(GitError::new(
                    GitErrorKind::BranchNotFound,
                    format!("{role} ref '{name}' is ambiguous"),
                ));
            }
            Err(error) if matches!(error.code(), ErrorCode::NotFound | ErrorCode::InvalidSpec) => {}
            Err(error) => return Err(GitError::from_git2(error)),
        }
    }

    Err(GitError::new(
        GitErrorKind::BranchNotFound,
        format!("{role} ref '{name}' was not found"),
    ))
}
