use git2::{BranchType, ErrorCode, Oid, Repository};

use super::{open_repo, GitError, GitErrorKind};

pub fn validate_branch_deletion(
    repo_path: &str,
    branch: &str,
    force: bool,
    removing_path: Option<&str>,
) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;
    if let Some(occupied) = super::branch_checkout_path(repo_path, branch)? {
        let allowed = removing_path.is_some_and(|path| {
            super::repository::canonical(path) == super::repository::canonical(&occupied)
        });
        if !allowed {
            return Err(GitError::new(
                GitErrorKind::Conflict,
                "Branch is checked out in another worktree",
            ));
        }
    }
    let home = super::default_branch(repo_path)?;
    if branch == home {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "The default branch cannot be deleted",
        ));
    }
    let target = repo
        .find_branch(branch, BranchType::Local)
        .map_err(|error| match error.code() {
            ErrorCode::NotFound => GitError::new(GitErrorKind::BranchNotFound, branch),
            _ => GitError::from_git2(error),
        })?;
    if !force {
        let tip = target
            .get()
            .peel_to_commit()
            .map_err(GitError::from_git2)?
            .id();
        if !is_integrated_into_default(&repo, tip, &home)? {
            return Err(GitError::new(
                GitErrorKind::Conflict,
                "Branch has commits not merged into the default branch; keep it or explicitly confirm their loss separately",
            ));
        }
    }
    Ok(())
}

fn is_integrated_into_default(repo: &Repository, tip: Oid, home: &str) -> Result<bool, GitError> {
    for into in default_integration_tips(repo, home)? {
        if commit_is_integrated(repo, tip, into)? {
            return Ok(true);
        }
    }
    Ok(false)
}

fn default_integration_tips(repo: &Repository, home: &str) -> Result<Vec<Oid>, GitError> {
    let mut tips = Vec::new();
    if let Some(oid) = peel_branch_oid(repo, home, BranchType::Local)? {
        tips.push(oid);
    }
    if let Some(oid) = peel_branch_oid(repo, &format!("origin/{home}"), BranchType::Remote)? {
        if !tips.contains(&oid) {
            tips.push(oid);
        }
    }
    if tips.is_empty() {
        return Err(GitError::new(
            GitErrorKind::BranchNotFound,
            format!("Default branch {home} is not available locally"),
        ));
    }
    Ok(tips)
}

fn peel_branch_oid(
    repo: &Repository,
    name: &str,
    kind: BranchType,
) -> Result<Option<Oid>, GitError> {
    match repo.find_branch(name, kind) {
        Ok(branch) => Ok(Some(
            branch
                .get()
                .peel_to_commit()
                .map_err(GitError::from_git2)?
                .id(),
        )),
        Err(error) if error.code() == ErrorCode::NotFound => Ok(None),
        Err(error) => Err(GitError::from_git2(error)),
    }
}

fn commit_is_integrated(repo: &Repository, tip: Oid, into: Oid) -> Result<bool, GitError> {
    if tip == into {
        return Ok(true);
    }
    if repo
        .graph_descendant_of(into, tip)
        .map_err(GitError::from_git2)?
    {
        return Ok(true);
    }
    content_already_in(repo, tip, into)
}

fn content_already_in(repo: &Repository, tip: Oid, into: Oid) -> Result<bool, GitError> {
    let tip_commit = repo.find_commit(tip).map_err(GitError::from_git2)?;
    let into_commit = repo.find_commit(into).map_err(GitError::from_git2)?;
    let mut index = match repo.merge_commits(&into_commit, &tip_commit, None) {
        Ok(index) => index,
        Err(_) => return Ok(false),
    };
    if index.has_conflicts() {
        return Ok(false);
    }
    let merged_tree = match index.write_tree_to(repo) {
        Ok(oid) => oid,
        Err(_) => return Ok(false),
    };
    Ok(merged_tree == into_commit.tree_id())
}
