use alera_core::git as core_git;

use super::GitError;

pub struct GitHostedReviewRange {
    pub base_oid: String,
    pub head_oid: String,
    pub retention_id: String,
}

pub fn git_fetch_hosted_review_range(
    path: String,
    remote_name: String,
    base_branch: String,
    head_sha: String,
    review_ref: Option<String>,
) -> Result<GitHostedReviewRange, GitError> {
    let range = core_git::hosted_review::fetch_hosted_review_range(
        &path,
        &remote_name,
        &base_branch,
        &head_sha,
        review_ref.as_deref(),
    )?;
    Ok(GitHostedReviewRange {
        base_oid: range.base_oid,
        head_oid: range.head_oid,
        retention_id: range.retention_id,
    })
}

pub fn git_release_hosted_review_range(path: String, retention_id: String) -> Result<(), GitError> {
    core_git::hosted_review::release_hosted_review_range(&path, &retention_id)?;
    Ok(())
}

pub fn git_persist_hosted_review_range(path: String, retention_id: String) -> Result<(), GitError> {
    core_git::hosted_review::persist_hosted_review_range(&path, &retention_id)?;
    Ok(())
}
