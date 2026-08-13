use git2::{Branch, BranchType, Reference, Repository};
use uuid::Uuid;

use super::{
    configured_remote_for_tracking_branch, git_cli_in_path, open_repo, GitError, GitErrorKind,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitHostedReviewRange {
    pub base_oid: String,
    pub head_oid: String,
    pub retention_id: String,
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
    let retention_id = Uuid::new_v4().simple().to_string();
    let base_source = format!("refs/heads/{base_branch}");
    let base_target = format!("refs/alera/hosted-reviews/operations/{retention_id}/base");
    let head_target = format!("refs/alera/hosted-reviews/operations/{retention_id}/head");
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
        retain_hosted_review_objects(&refreshed, &retention_id, base_oid, head_oid)?;
        Ok(GitHostedReviewRange {
            base_oid: base_oid.to_string(),
            head_oid: head_oid.to_string(),
            retention_id: retention_id.clone(),
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

pub fn release_hosted_review_range(repo_path: &str, retention_id: &str) -> Result<(), GitError> {
    validate_retention_id(retention_id)?;
    let repo = open_repo(repo_path)?;
    for role in ["base", "head"] {
        let name = retained_ref_name(retention_id, role);
        if let Ok(mut reference) = repo.find_reference(&name) {
            reference.delete().map_err(GitError::from_git2)?;
        }
    }
    Ok(())
}

fn retain_hosted_review_objects(
    repo: &Repository,
    retention_id: &str,
    base_oid: git2::Oid,
    head_oid: git2::Oid,
) -> Result<(), GitError> {
    validate_retention_id(retention_id)?;
    for (role, object_id) in [("base", base_oid), ("head", head_oid)] {
        let name = retained_ref_name(retention_id, role);
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

fn validate_retention_id(retention_id: &str) -> Result<(), GitError> {
    if retention_id.len() == 32
        && retention_id
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
    {
        return Ok(());
    }
    Err(GitError::new(
        GitErrorKind::Internal,
        "invalid hosted review retention id",
    ))
}

fn retained_ref_name(retention_id: &str, role: &str) -> String {
    format!("refs/alera/hosted-reviews/tabs/{retention_id}/{role}")
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
