//! Prepared squash integration. The caller serializes a run and persists its
//! intent before invoking Git; the Git receipt bridges Git and database commits.

use std::collections::BTreeSet;
use std::path::{Component, Path};

use git2::{Oid, Repository, RepositoryState};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::{is_worktree_clean, verify_workflow_worktree_tip, GitError, GitErrorKind};

mod checkout;
mod receipt;
#[cfg(test)]
mod tests;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkflowGitResource {
    pub id: String,
    pub path: String,
    pub base_sha: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkflowIntegrationRequest {
    pub id: String,
    pub repo_path: String,
    pub run_id: String,
    pub revision: i64,
    pub task_id: String,
    pub dispatch_id: String,
    pub integration: WorkflowGitResource,
    pub source: WorkflowGitResource,
    pub expected_sha: String,
    pub source_sha: String,
    pub result_digest: String,
    pub artifacts: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorkflowIntegrationReceipt {
    pub version: u32,
    pub request: WorkflowIntegrationRequest,
    pub integrated_sha: String,
    pub artifact_digest: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum WorkflowGitPreparation {
    Ready {
        receipt: Box<WorkflowIntegrationReceipt>,
    },
    Conflict {
        paths: Vec<String>,
        truncated: bool,
    },
}

pub fn prepare_workflow_integration(
    request: &WorkflowIntegrationRequest,
) -> Result<WorkflowGitPreparation, GitError> {
    request.validate()?;
    let repo = Repository::open(&request.integration.path).map_err(GitError::from_git2)?;
    request.verify_resources()?;
    if !is_worktree_clean(&request.source.path)? {
        return Err(invalid(
            "commit or inspect pending changes before integrating",
        ));
    }
    if let Some(receipt) = receipt::load(&repo, request)? {
        return Ok(WorkflowGitPreparation::Ready {
            receipt: Box::new(receipt),
        });
    }
    if head_oid(&repo)? != oid(&request.expected_sha)? {
        return Err(invalid("integration head differs from its reserved SHA"));
    }
    if repo.state() != RepositoryState::Clean || !is_worktree_clean(&request.integration.path)? {
        return Err(invalid(
            "commit or inspect pending changes before integrating",
        ));
    }
    let base = repo
        .find_commit(oid(&request.source.base_sha)?)
        .map_err(GitError::from_git2)?;
    let ours = repo
        .find_commit(oid(&request.expected_sha)?)
        .map_err(GitError::from_git2)?;
    let theirs = repo
        .find_commit(oid(&request.source_sha)?)
        .map_err(GitError::from_git2)?;
    if ours.id() != base.id()
        && !repo
            .graph_descendant_of(ours.id(), base.id())
            .map_err(GitError::from_git2)?
    {
        return Err(invalid(
            "task base is not an ancestor of the integration head",
        ));
    }
    let source_tree = theirs.tree().map_err(GitError::from_git2)?;
    artifact_digest(&source_tree, &request.artifacts)?;
    let mut index = repo
        .merge_trees(
            &base.tree().map_err(GitError::from_git2)?,
            &ours.tree().map_err(GitError::from_git2)?,
            &source_tree,
            None,
        )
        .map_err(GitError::from_git2)?;
    if index.has_conflicts() {
        let mut paths = BTreeSet::new();
        for conflict in index.conflicts().map_err(GitError::from_git2)? {
            let conflict = conflict.map_err(GitError::from_git2)?;
            for entry in [conflict.ancestor, conflict.our, conflict.their]
                .into_iter()
                .flatten()
            {
                paths.insert(
                    String::from_utf8_lossy(&entry.path)
                        .chars()
                        .take(1024)
                        .collect(),
                );
            }
            if paths.len() > 128 {
                break;
            }
        }
        return Ok(WorkflowGitPreparation::Conflict {
            truncated: paths.len() > 128,
            paths: paths.into_iter().take(128).collect(),
        });
    }
    let tree_id = index.write_tree_to(&repo).map_err(GitError::from_git2)?;
    let tree = repo.find_tree(tree_id).map_err(GitError::from_git2)?;
    let artifact_digest = artifact_digest(&tree, &request.artifacts)?;
    // A submodule has its own checkout lifecycle; never claim to have updated it.
    let delta = repo
        .diff_tree_to_tree(
            Some(&ours.tree().map_err(GitError::from_git2)?),
            Some(&tree),
            None,
        )
        .map_err(GitError::from_git2)?;
    if delta.deltas().any(|delta| {
        delta.old_file().mode() == git2::FileMode::Commit
            || delta.new_file().mode() == git2::FileMode::Commit
    }) {
        return Err(invalid(
            "submodule changes require explicit integration outside this workflow",
        ));
    }
    let signature = repo.signature().map_err(GitError::from_git2)?;
    let integrated_sha = if tree_id == ours.tree_id() {
        ours.id()
    } else {
        repo.commit(
            None,
            &signature,
            &signature,
            &format!("chore: integrate workflow task {}", request.task_id),
            &tree,
            &[&ours],
        )
        .map_err(GitError::from_git2)?
    };
    let receipt = WorkflowIntegrationReceipt {
        version: 1,
        request: request.clone(),
        integrated_sha: integrated_sha.to_string(),
        artifact_digest,
    };
    let receipt = receipt::persist(&repo, &receipt, &signature)?;
    Ok(WorkflowGitPreparation::Ready {
        receipt: Box::new(receipt),
    })
}

pub fn apply_workflow_integration(
    request: &WorkflowIntegrationRequest,
) -> Result<WorkflowIntegrationReceipt, GitError> {
    request.validate()?;
    request.verify_resources()?;
    if !is_worktree_clean(&request.source.path)? {
        return Err(invalid(
            "commit or inspect pending changes before integrating",
        ));
    }
    let repo = Repository::open(&request.integration.path).map_err(GitError::from_git2)?;
    let receipt = receipt::load(&repo, request)?
        .ok_or_else(|| invalid("integration has no durable Git receipt"))?;
    checkout::apply(&repo, &receipt)?;
    Ok(receipt)
}

impl WorkflowIntegrationRequest {
    fn validate(&self) -> Result<(), GitError> {
        for id in [&self.id, &self.integration.id, &self.source.id] {
            uuid::Uuid::parse_str(id).map_err(|_| invalid("invalid integration identity"))?;
        }
        for id in [&self.run_id, &self.task_id, &self.dispatch_id] {
            if id.trim().is_empty() || id.len() > 160 || id.chars().any(char::is_control) {
                return Err(invalid("invalid workflow task or dispatch identity"));
            }
        }
        for sha in [
            &self.expected_sha,
            &self.source_sha,
            &self.integration.base_sha,
            &self.source.base_sha,
        ] {
            oid(sha)?;
        }
        if self.revision < 1
            || self.source.id == self.integration.id
            || self.result_digest.len() != 64
            || !self
                .result_digest
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
            || self.artifacts.len() > 128
        {
            return Err(invalid("invalid integration revision, digest or resource"));
        }
        for path in [&self.repo_path, &self.integration.path, &self.source.path] {
            if !Path::new(path).is_absolute() || path.len() > 16384 {
                return Err(invalid(
                    "integration resource path must be absolute and bounded",
                ));
            }
        }
        let mut paths = BTreeSet::new();
        for path in &self.artifacts {
            if path.is_empty()
                || path.len() > 1024
                || path.contains(['\\', ':', '\0'])
                || !Path::new(path)
                    .components()
                    .all(|c| matches!(c, Component::Normal(_)))
                || path
                    .split('/')
                    .any(|part| part.is_empty() || part == "." || part == ".git")
                || !paths.insert(path)
            {
                return Err(invalid(
                    "artifact paths must be unique repository-relative files",
                ));
            }
        }
        Ok(())
    }

    fn verify_resources(&self) -> Result<(), GitError> {
        for resource in [&self.integration, &self.source] {
            let tip = verify_workflow_worktree_tip(
                &self.repo_path,
                &resource.path,
                &resource.base_sha,
                &resource.id,
            )?;
            if resource.id == self.source.id && tip != self.source_sha {
                return Err(invalid("task branch changed after result capture"));
            }
        }
        Ok(())
    }
}

fn artifact_digest(tree: &git2::Tree<'_>, paths: &[String]) -> Result<String, GitError> {
    let mut digest = Sha256::new();
    for path in paths.iter().collect::<BTreeSet<_>>() {
        let entry = tree
            .get_path(Path::new(path))
            .map_err(|_| invalid(format!("artifact is not committed: {path}")))?;
        if !matches!(entry.filemode(), 0o100644 | 0o100755) {
            return Err(invalid(
                "artifacts must be committed regular files, not links or directories",
            ));
        }
        digest.update((path.len() as u64).to_be_bytes());
        digest.update(path.as_bytes());
        digest.update(entry.filemode().to_be_bytes());
        digest.update(entry.id().as_bytes());
    }
    Ok(format!("{:x}", digest.finalize()))
}

fn oid(value: &str) -> Result<Oid, GitError> {
    if value.len() != 40
        || !value
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    {
        return Err(invalid("integration requires a full lowercase commit SHA"));
    }
    Oid::from_str(value).map_err(GitError::from_git2)
}

fn head_oid(repo: &Repository) -> Result<Oid, GitError> {
    repo.head()
        .map_err(GitError::from_git2)?
        .target()
        .ok_or_else(|| invalid("integration HEAD has no commit"))
}

fn invalid(message: impl Into<String>) -> GitError {
    GitError::new(GitErrorKind::Conflict, message)
}
