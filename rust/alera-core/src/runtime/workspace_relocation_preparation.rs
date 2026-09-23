use std::path::{Component, Path, PathBuf};

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

use super::{
    RuntimeStore, WorkspaceKind, WorkspaceRelocation, WorkspaceRelocationPhase, WorkspaceStatus,
    LOCAL_HOST_ID,
};
use crate::git;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRelocationIntent {
    pub workspace_id: String,
    pub to_project_checkout: bool,
    pub destination_path: Option<String>,
    pub branch: Option<String>,
    pub replacement_branch: Option<String>,
    pub move_changes: bool,
    pub shared_impact_confirmed: bool,
}

impl RuntimeStore {
    pub async fn prepare_local_workspace_relocation(
        &self,
        intent: WorkspaceRelocationIntent,
    ) -> Result<WorkspaceRelocation> {
        self.prepare_local_workspace_relocation_with_id(intent, None)
            .await
    }

    pub async fn prepare_local_workspace_relocation_with_id(
        &self,
        intent: WorkspaceRelocationIntent,
        relocation_id: Option<String>,
    ) -> Result<WorkspaceRelocation> {
        if let Some(id) = &relocation_id {
            uuid::Uuid::parse_str(id).map_err(|_| anyhow!("Relocation ID must be a UUID"))?;
        }
        if !intent.shared_impact_confirmed {
            bail!("Confirm the shared checkout impact before relocating this workspace");
        }
        let source = self
            .find_workspace(&intent.workspace_id)
            .await?
            .ok_or_else(|| anyhow!("Workspace not found: {}", intent.workspace_id))?;
        if source.host_id != LOCAL_HOST_ID || source.status != WorkspaceStatus::Active {
            bail!("Local relocation requires an active workspace on this host");
        }
        let intent = tokio::task::spawn_blocking(move || normalize_intent(intent)).await??;
        if let Some(id) = &relocation_id {
            if let Some(previous) = self.find_workspace_relocation(id).await? {
                let expected = if matches!(
                    previous.phase,
                    WorkspaceRelocationPhase::Committed
                        | WorkspaceRelocationPhase::RemovingSource
                        | WorkspaceRelocationPhase::Completed
                ) {
                    &previous.destination
                } else {
                    &previous.source
                };
                let latest: Option<String> = sqlx::query_scalar("SELECT id FROM workspaceRelocations WHERE workspaceId = ? ORDER BY rowid DESC LIMIT 1")
                    .bind(&source.id).fetch_optional(self.pool()).await?;
                if latest.as_deref() != Some(id)
                    || previous.source.instance_id != source.instance_id
                    || previous.source.host_id != source.host_id
                    || previous.source.project_id != source.project_id
                    || !matches_intent(&previous, &intent)
                    || source.path != expected.path
                    || source.kind != expected.kind
                {
                    bail!("Relocation ID belongs to different choices or a superseded task location; no effects were repeated");
                }
                return Ok(previous);
            }
        }
        if let Some(pending) = self
            .active_workspace_relocation(&source.project_id, &source.host_id)
            .await?
        {
            if relocation_id.as_ref().is_some_and(|id| id != &pending.id)
                || !matches_intent(&pending, &intent)
            {
                bail!("This checkout has unfinished relocation {}; resume its original choices before starting another operation", pending.id);
            }
            return Ok(pending);
        }
        let expected_kind = if intent.to_project_checkout {
            WorkspaceKind::Linked
        } else {
            WorkspaceKind::Main
        };
        if source.kind != expected_kind {
            bail!("Workspace is already at the requested checkout type");
        }
        let checkout = self
            .find_project_checkout(&source.project_id, &source.host_id)
            .await?
            .ok_or_else(|| {
                anyhow!("Register the project checkout on this host before relocating")
            })?;
        let journal = tokio::task::spawn_blocking(move || -> Result<WorkspaceRelocation> {
            let mut destination = source.clone();
            destination.kind = if intent.to_project_checkout { WorkspaceKind::Main } else { WorkspaceKind::Linked };
            destination.path = if intent.to_project_checkout {
                if intent.destination_path.is_some() || intent.branch.is_some() || intent.replacement_branch.is_some() {
                    bail!("Hand On uses the registered project checkout and the source's current branch");
                }
                checkout.path.clone()
            } else {
                intent.destination_path.ok_or_else(|| anyhow!("A new worktree destination is required"))?
            };
            let original_branch = git::current_branch(&source.path)?;
            let source_commit = git::checkout_commit(&source.path)?;
            destination.branch = Some(if intent.to_project_checkout { original_branch.clone() } else {
                intent.branch.ok_or_else(|| anyhow!("A destination branch is required"))?
            });
            destination.source_branch = if intent.to_project_checkout { None } else { Some(original_branch.clone()) };
            destination.reuses_existing_branch = intent.replacement_branch.is_some();
            let replacement_commit = intent.replacement_branch.as_ref().map(|branch| git::local_branch_commit(&checkout.path, branch)).transpose()?;
            let destination_original_branch = if intent.to_project_checkout { Some(git::current_branch(&checkout.path)?) } else { None };
            let destination_original_commit = if intent.to_project_checkout { Some(git::checkout_commit(&checkout.path)?) } else { None };
            let journal = WorkspaceRelocation {
                id: relocation_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string()), source, destination, repository_path: checkout.path,
                original_branch, source_commit, replacement_branch: intent.replacement_branch,
                replacement_commit, destination_original_branch, destination_original_commit,
                move_changes: intent.move_changes, recovery_stash_oid: None, phase: WorkspaceRelocationPhase::Prepared,
            };
            if journal.destination.kind == WorkspaceKind::Linked {
                git::validate_workspace_relocation_storage(&journal.repository_path, &journal.id)?;
            }
            super::workspace_relocation_execution::validate_prepared(&journal)?;
            Ok(journal)
        }).await??;
        self.begin_workspace_relocation(&journal).await?;
        Ok(journal)
    }
}

fn matches_intent(relocation: &WorkspaceRelocation, intent: &WorkspaceRelocationIntent) -> bool {
    relocation.source.id == intent.workspace_id
        && (relocation.destination.kind == WorkspaceKind::Main) == intent.to_project_checkout
        && relocation.move_changes == intent.move_changes
        && relocation.replacement_branch == intent.replacement_branch
        && if intent.to_project_checkout {
            intent.destination_path.is_none() && intent.branch.is_none()
        } else {
            intent.destination_path.as_ref() == Some(&relocation.destination.path)
                && intent.branch.is_some()
                && intent.branch == relocation.destination.branch
        }
}

fn normalize_intent(mut intent: WorkspaceRelocationIntent) -> Result<WorkspaceRelocationIntent> {
    intent.branch = trimmed(intent.branch);
    intent.replacement_branch = trimmed(intent.replacement_branch);
    intent.destination_path = trimmed(intent.destination_path)
        .map(|path| canonical_destination(&path))
        .transpose()?;
    Ok(intent)
}

fn trimmed(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn canonical_destination(value: &str) -> Result<String> {
    let path = Path::new(value);
    if !path.is_absolute()
        || path
            .components()
            .any(|component| component == Component::ParentDir)
    {
        bail!("Use an absolute worktree destination without parent-directory components");
    }
    let mut ancestor = path;
    let mut suffix = Vec::new();
    loop {
        match std::fs::canonicalize(ancestor) {
            Ok(mut canonical) => {
                for component in suffix.iter().rev() {
                    canonical.push(component);
                }
                return Ok(canonical.to_string_lossy().to_string());
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                if std::fs::symlink_metadata(ancestor).is_ok() {
                    bail!("The destination contains a dangling symbolic link");
                }
                suffix.push(PathBuf::from(
                    ancestor
                        .file_name()
                        .ok_or_else(|| anyhow!("Invalid destination path"))?,
                ));
                ancestor = ancestor
                    .parent()
                    .ok_or_else(|| anyhow!("Destination has no accessible ancestor"))?;
            }
            Err(error) => return Err(error.into()),
        }
    }
}
