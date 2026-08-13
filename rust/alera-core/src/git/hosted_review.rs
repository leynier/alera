use git2::{Branch, BranchType, Reference, Repository};
use uuid::Uuid;

use super::{
    configured_remote_for_tracking_branch, git_cli_in_path, open_repo, GitError, GitErrorKind,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitHostedReviewRange {
    pub base_oid: String,
    pub head_oid: String,
}

pub fn fetch_hosted_review_range(
    repo_path: &str,
    base_branch: &str,
    head_sha: &str,
    review_ref: Option<&str>,
) -> Result<GitHostedReviewRange, GitError> {
    let repo = open_repo(repo_path)?;
    if !Branch::name_is_valid(base_branch).map_err(GitError::from_git2)? {
        return Err(GitError::new(GitErrorKind::InvalidBranchName, base_branch));
    }
    if !matches!(head_sha.len(), 40 | 64) || !head_sha.bytes().all(|byte| byte.is_ascii_hexdigit())
    {
        return Err(GitError::new(
            GitErrorKind::Internal,
            "invalid hosted head SHA",
        ));
    }
    if review_ref.is_some_and(|value| !Reference::is_valid_name(value)) {
        return Err(GitError::new(
            GitErrorKind::InvalidBranchName,
            "invalid hosted review ref",
        ));
    }
    let remote = hosted_review_remote(&repo, base_branch)?;
    let namespace = Uuid::new_v4().simple().to_string();
    let base_source = format!("refs/heads/{base_branch}");
    let base_target = format!("refs/alera/hosted-reviews/{namespace}/base");
    let head_target = format!("refs/alera/hosted-reviews/{namespace}/head");
    let result = (|| {
        fetch_ref(repo_path, &remote, &base_source, &base_target)?;

        let primary_head = review_ref.unwrap_or(head_sha);
        if let Err(primary_error) = fetch_ref(repo_path, &remote, primary_head, &head_target) {
            if review_ref.is_none()
                || fetch_ref(repo_path, &remote, head_sha, &head_target).is_err()
            {
                return Err(primary_error);
            }
        }

        let refreshed = open_repo(repo_path)?;
        let base_oid = refreshed
            .refname_to_id(&base_target)
            .map_err(GitError::from_git2)?;
        let head_oid = refreshed
            .refname_to_id(&head_target)
            .map_err(GitError::from_git2)?;
        if head_oid.to_string() != head_sha.to_ascii_lowercase() {
            return Err(GitError::new(
                GitErrorKind::Conflict,
                "the hosted review changed while its diff was opening",
            ));
        }
        retain_hosted_review_objects(&refreshed, [base_oid, head_oid])?;
        Ok(GitHostedReviewRange {
            base_oid: base_oid.to_string(),
            head_oid: head_oid.to_string(),
        })
    })();
    cleanup_temporary_refs(repo_path, [&base_target, &head_target]);
    result
}

fn fetch_ref(path: &str, remote: &str, source: &str, target: &str) -> Result<(), GitError> {
    let refspec = format!("+{source}:{target}");
    git_cli_in_path(
        path,
        &[
            "fetch",
            "--no-tags",
            "--no-write-fetch-head",
            remote,
            &refspec,
        ],
    )
}

fn retain_hosted_review_objects<const N: usize>(
    repo: &Repository,
    object_ids: [git2::Oid; N],
) -> Result<(), GitError> {
    for object_id in object_ids {
        let name = format!("refs/alera/hosted-reviews/objects/{object_id}");
        repo.reference(
            &name,
            object_id,
            true,
            "alera: retain object for a persisted hosted review tab",
        )
        .map_err(GitError::from_git2)?;
    }
    Ok(())
}

fn cleanup_temporary_refs<const N: usize>(path: &str, names: [&str; N]) {
    let Ok(repo) = open_repo(path) else {
        return;
    };
    for name in names {
        if let Ok(mut reference) = repo.find_reference(name) {
            let _ = reference.delete();
        }
    }
}

fn hosted_review_remote(repo: &Repository, base_branch: &str) -> Result<String, GitError> {
    if let Ok(branch) = repo.find_branch(base_branch, BranchType::Local) {
        if let Ok(upstream) = branch.upstream() {
            if let Some(name) = upstream.name().map_err(GitError::from_git2)? {
                if let Some(remote) = configured_remote_for_tracking_branch(repo, name)? {
                    return Ok(remote);
                }
            }
        }
    }
    if repo.find_remote("origin").is_ok() {
        return Ok("origin".to_string());
    }
    let remotes = repo.remotes().map_err(GitError::from_git2)?;
    let names = remotes
        .iter()
        .filter_map(Result::ok)
        .flatten()
        .collect::<Vec<_>>();
    match names.as_slice() {
        [remote] => Ok((*remote).to_string()),
        _ => Err(GitError::new(
            GitErrorKind::RemoteNotFound,
            "could not determine the hosted review remote",
        )),
    }
}

#[cfg(test)]
#[path = "../git_hosted_review_tests.rs"]
mod tests;
