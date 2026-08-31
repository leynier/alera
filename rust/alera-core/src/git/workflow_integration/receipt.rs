use git2::{ErrorCode, Repository, Signature};

use super::{
    artifact_digest, invalid, oid, GitError, WorkflowIntegrationReceipt, WorkflowIntegrationRequest,
};

const MAX_BYTES: usize = 256 * 1024;

fn reference(request: &WorkflowIntegrationRequest) -> String {
    format!("refs/alera/workflow-integrations/{}", request.id)
}

pub(super) fn load(
    repo: &Repository,
    request: &WorkflowIntegrationRequest,
) -> Result<Option<WorkflowIntegrationReceipt>, GitError> {
    let reference = match repo.find_reference(&reference(request)) {
        Ok(reference) => reference,
        Err(error) if error.code() == ErrorCode::NotFound => return Ok(None),
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let commit = repo
        .find_commit(
            reference
                .target()
                .ok_or_else(|| invalid("receipt must be a direct reference"))?,
        )
        .map_err(GitError::from_git2)?;
    let tree = commit.tree().map_err(GitError::from_git2)?;
    let entry = tree
        .get_name("receipt.json")
        .ok_or_else(|| invalid("receipt metadata missing"))?;
    let blob = repo.find_blob(entry.id()).map_err(GitError::from_git2)?;
    if blob.size() > MAX_BYTES {
        return Err(invalid("integration receipt exceeds its size limit"));
    }
    let receipt: WorkflowIntegrationReceipt = serde_json::from_slice(blob.content())
        .map_err(|_| invalid("invalid integration receipt"))?;
    if receipt.version != 1
        || &receipt.request != request
        || commit.parent_count() != 2
        || commit.parent_id(0).map_err(GitError::from_git2)? != oid(&receipt.integrated_sha)?
        || commit.parent_id(1).map_err(GitError::from_git2)? != oid(&request.source_sha)?
    {
        return Err(invalid("integration receipt identity changed"));
    }
    let candidate = repo
        .find_commit(oid(&receipt.integrated_sha)?)
        .map_err(GitError::from_git2)?;
    if candidate.id() != oid(&request.expected_sha)?
        && (candidate.parent_count() != 1
            || candidate.parent_id(0).map_err(GitError::from_git2)? != oid(&request.expected_sha)?)
    {
        return Err(invalid("integration receipt has an unexpected parent"));
    }
    let source = commit.parent(1).map_err(GitError::from_git2)?;
    artifact_digest(
        &source.tree().map_err(GitError::from_git2)?,
        &request.artifacts,
    )?;
    if artifact_digest(
        &candidate.tree().map_err(GitError::from_git2)?,
        &request.artifacts,
    )? != receipt.artifact_digest
    {
        return Err(invalid("integration artifact evidence changed"));
    }
    Ok(Some(receipt))
}

pub(super) fn persist(
    repo: &Repository,
    receipt: &WorkflowIntegrationReceipt,
    signature: &Signature<'_>,
) -> Result<WorkflowIntegrationReceipt, GitError> {
    let bytes = serde_json::to_vec(receipt).map_err(|error| invalid(error.to_string()))?;
    if bytes.len() > MAX_BYTES {
        return Err(invalid("integration receipt exceeds its size limit"));
    }
    let blob = repo.blob(&bytes).map_err(GitError::from_git2)?;
    let mut builder = repo.treebuilder(None).map_err(GitError::from_git2)?;
    builder
        .insert("receipt.json", blob, 0o100644)
        .map_err(GitError::from_git2)?;
    let tree = repo
        .find_tree(builder.write().map_err(GitError::from_git2)?)
        .map_err(GitError::from_git2)?;
    let candidate = repo
        .find_commit(oid(&receipt.integrated_sha)?)
        .map_err(GitError::from_git2)?;
    let source = repo
        .find_commit(oid(&receipt.request.source_sha)?)
        .map_err(GitError::from_git2)?;
    // Parents make both trees reachable even before the integration ref moves.
    let id = repo
        .commit(
            None,
            signature,
            signature,
            "workflow integration receipt",
            &tree,
            &[&candidate, &source],
        )
        .map_err(GitError::from_git2)?;
    match repo.reference(
        &reference(&receipt.request),
        id,
        false,
        "workflow integration receipt",
    ) {
        Ok(_) => Ok(receipt.clone()),
        Err(error) if error.code() == ErrorCode::Exists => load(repo, &receipt.request)?
            .ok_or_else(|| invalid("integration receipt disappeared during creation")),
        Err(error) => Err(GitError::from_git2(error)),
    }
}
