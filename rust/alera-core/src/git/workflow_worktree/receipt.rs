use std::path::{Path, PathBuf};

use git2::{ErrorCode, Oid, Repository};
use serde::{Deserialize, Serialize};

use super::{canonical, invalid, GitError};

const MAX_RECEIPT_BYTES: usize = 64 * 1024;

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct WorkflowWorktreeReceipt {
    version: u32,
    id: String,
    repository: PathBuf,
    destination: PathBuf,
    branch: String,
    base_sha: String,
}

impl WorkflowWorktreeReceipt {
    pub(super) fn new(
        repo: &Repository,
        path: &str,
        base_sha: &str,
        id: &str,
    ) -> Result<Self, GitError> {
        if !Path::new(path).is_absolute() {
            return Err(invalid("workflow destination must be absolute"));
        }
        Ok(Self {
            version: 1,
            id: id.into(),
            repository: canonical(repo.commondir())?,
            destination: PathBuf::from(path),
            branch: format!("refs/heads/alera/workflows/{id}"),
            base_sha: base_sha.into(),
        })
    }

    fn reference_name(&self) -> String {
        format!("refs/alera/workflow-resources/{}", self.id)
    }

    pub(super) fn exists(&self, repo: &Repository) -> Result<bool, GitError> {
        let reference = match repo.find_reference(&self.reference_name()) {
            Ok(reference) => reference,
            Err(error) if error.code() == ErrorCode::NotFound => return Ok(false),
            Err(error) => return Err(GitError::from_git2(error)),
        };
        let oid = reference
            .target()
            .ok_or_else(|| invalid("workflow ownership receipt must be a direct reference"))?;
        let blob = repo.find_blob(oid).map_err(GitError::from_git2)?;
        if blob.size() > MAX_RECEIPT_BYTES {
            return Err(invalid("workflow ownership receipt exceeds its size limit"));
        }
        let stored: Self = serde_json::from_slice(blob.content())
            .map_err(|_| invalid("invalid workflow ownership receipt"))?;
        if stored != *self {
            return Err(invalid("workflow ownership receipt identity changed"));
        }
        Ok(true)
    }

    pub(super) fn verify(&self, repo: &Repository) -> Result<(), GitError> {
        if self.exists(repo)? {
            return Ok(());
        }
        // Ref creation and its reflog are atomic. This proof recovers the
        // interruption before promotion to the non-expiring receipt below.
        let log = repo.reflog(&self.branch).map_err(GitError::from_git2)?;
        let first = log
            .len()
            .checked_sub(1)
            .and_then(|index| log.get(index))
            .ok_or_else(|| invalid("workflow branch has no ownership receipt"))?;
        let message = format!("alera workflow {} at {}", self.id, self.base_sha);
        if first.id_old() != Oid::ZERO_SHA1
            || first.id_new() != Oid::from_str(&self.base_sha).map_err(GitError::from_git2)?
            || first.message().map_err(GitError::from_git2)? != Some(message.as_str())
        {
            return Err(invalid("workflow branch belongs to another resource"));
        }
        Ok(())
    }

    pub(super) fn persist(&self, repo: &Repository) -> Result<(), GitError> {
        if self.exists(repo)? {
            return Ok(());
        }
        self.verify(repo)?;
        let bytes = serde_json::to_vec(self).map_err(|error| invalid(error.to_string()))?;
        if bytes.len() > MAX_RECEIPT_BYTES {
            return Err(invalid("workflow ownership receipt exceeds its size limit"));
        }
        let oid = repo.blob(&bytes).map_err(GitError::from_git2)?;
        // A direct ref keeps the immutable blob reachable through reflog
        // expiry and GC. Never force a ref or replace another identity.
        match repo.reference(
            &self.reference_name(),
            oid,
            false,
            "workflow ownership receipt",
        ) {
            Ok(_) => Ok(()),
            Err(error) if error.code() == ErrorCode::Exists => {
                if self.exists(repo)? {
                    Ok(())
                } else {
                    Err(invalid(
                        "workflow ownership receipt disappeared during creation",
                    ))
                }
            }
            Err(error) => Err(GitError::from_git2(error)),
        }
    }
}
