use super::git_commit_state_impl::{current_head_commit, repository_has_conflicts};
use super::{head_branch_name, open_repo, GitError, GitRepositoryState};
use git2::BranchType;

pub fn git_repository_state(path: String) -> Result<GitRepositoryState, GitError> {
    let repo = open_repo(&path)?;
    let branch = head_branch_name(&repo);
    let mut upstream = None;
    let mut ahead = 0;
    let mut behind = 0;

    if branch != "HEAD" {
        if let Ok(local) = repo.find_branch(&branch, BranchType::Local) {
            if let Ok(upstream_branch) = local.upstream() {
                upstream = upstream_branch
                    .name()
                    .map_err(GitError::from_git2)?
                    .map(ToString::to_string);
                if let (Some(local_oid), Some(upstream_oid)) =
                    (local.get().target(), upstream_branch.get().target())
                {
                    let counts = repo
                        .graph_ahead_behind(local_oid, upstream_oid)
                        .map_err(GitError::from_git2)?;
                    ahead = counts.0 as u32;
                    behind = counts.1 as u32;
                }
            }
        }
    }

    let head_message = current_head_commit(&repo)?.and_then(|commit| {
        commit
            .message()
            .ok()
            .map(|message| message.trim_end_matches(['\r', '\n']).to_string())
    });

    Ok(GitRepositoryState {
        branch,
        upstream,
        ahead,
        behind,
        has_conflicts: repository_has_conflicts(&repo)?,
        head_message,
    })
}
