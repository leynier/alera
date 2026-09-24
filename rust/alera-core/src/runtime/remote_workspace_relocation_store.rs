use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

use super::{
    RuntimeStore, Workspace, WorkspaceKind, WorkspaceRelocationIntent, WorkspaceStatus,
    LOCAL_HOST_ID,
};

/// Home's durable choices, recorded before asking the owner to inspect or mutate Git.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteWorkspaceRelocationIntent {
    pub id: String,
    pub source: Workspace,
    pub project_checkout_path: String,
    pub destination_path: Option<String>,
    #[serde(default)]
    pub workspace_root: Option<String>,
    #[serde(default)]
    pub owner_preparation: Option<super::WorkspaceRelocation>,
    #[serde(default)]
    pub setup_config: Option<super::ProjectConfig>,
    pub intent: WorkspaceRelocationIntent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteWorkspaceRelocationRecovery {
    pub intent: RemoteWorkspaceRelocationIntent,
    pub home_committed: bool,
    pub owner_receipt: Option<super::WorkspaceRelocation>,
}

impl RuntimeStore {
    pub async fn list_remote_workspace_relocation_recovery(
        &self,
        workspace: &Workspace,
        limit: u32,
    ) -> Result<Vec<RemoteWorkspaceRelocationRecovery>> {
        let rows: Vec<(String, bool, Option<String>)> = sqlx::query_as("SELECT dataJson, completed, ownerJournalJson FROM remoteWorkspaceRelocationIntents WHERE workspaceId = ? AND projectId = ? AND hostId = ? AND json_extract(dataJson, '$.source.instanceId') = ? ORDER BY rowid DESC LIMIT ?")
            .bind(&workspace.id).bind(&workspace.project_id).bind(&workspace.host_id).bind(&workspace.instance_id).bind(limit.clamp(1, 100)).fetch_all(self.pool()).await?;
        rows.into_iter()
            .map(|(data, home_committed, receipt)| {
                Ok(RemoteWorkspaceRelocationRecovery {
                    intent: serde_json::from_str(&data)?,
                    home_committed,
                    owner_receipt: receipt
                        .map(|value| serde_json::from_str(&value))
                        .transpose()?,
                })
            })
            .collect()
    }

    pub(super) async fn migrate_remote_workspace_relocation_intents(&self) -> Result<()> {
        for statement in [
            "CREATE TABLE IF NOT EXISTS remoteWorkspaceRelocationIntents (id TEXT PRIMARY KEY, workspaceId TEXT NOT NULL, projectId TEXT NOT NULL, hostId TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0, dataJson TEXT NOT NULL, ownerJournalJson TEXT)",
            "CREATE UNIQUE INDEX IF NOT EXISTS remoteRelocationOwnerIdx ON remoteWorkspaceRelocationIntents(projectId, hostId) WHERE completed = 0",
            "CREATE TRIGGER IF NOT EXISTS retainRemoteRelocatingWorkspace BEFORE DELETE ON workspaces WHEN EXISTS (SELECT 1 FROM remoteWorkspaceRelocationIntents WHERE workspaceId = OLD.id AND completed = 0) BEGIN SELECT RAISE(ABORT, 'Workspace has an unfinished SSH relocation; recover it before removal'); END",
            "CREATE TRIGGER IF NOT EXISTS retainRemoteRelocatingWorkspaceIdentity BEFORE UPDATE ON workspaces WHEN EXISTS (SELECT 1 FROM remoteWorkspaceRelocationIntents WHERE workspaceId = OLD.id AND completed = 0) AND (NEW.id IS NOT OLD.id OR NEW.instanceId IS NOT OLD.instanceId OR NEW.projectId IS NOT OLD.projectId OR NEW.hostId IS NOT OLD.hostId OR NEW.status IS NOT OLD.status OR NEW.path IS NOT OLD.path OR NEW.kind IS NOT OLD.kind) BEGIN SELECT RAISE(ABORT, 'Workspace location and identity are reserved by an unfinished SSH relocation'); END",
            "CREATE TRIGGER IF NOT EXISTS reserveRemoteRelocationAgainstLocal BEFORE INSERT ON remoteWorkspaceRelocationIntents WHEN EXISTS (SELECT 1 FROM workspaceRelocations WHERE projectId = NEW.projectId AND hostId = NEW.hostId AND completed = 0) BEGIN SELECT RAISE(ABORT, 'Checkout has an unfinished relocation'); END",
            "CREATE TRIGGER IF NOT EXISTS reserveLocalRelocationAgainstRemote BEFORE INSERT ON workspaceRelocations WHEN EXISTS (SELECT 1 FROM remoteWorkspaceRelocationIntents WHERE projectId = NEW.projectId AND hostId = NEW.hostId AND completed = 0 AND id != NEW.id) BEGIN SELECT RAISE(ABORT, 'Checkout has an unfinished SSH relocation'); END",
        ] {
            sqlx::query(statement).execute(self.pool()).await?;
        }
        Ok(())
    }

    pub async fn find_remote_workspace_relocation_intent(
        &self,
        id: &str,
    ) -> Result<Option<RemoteWorkspaceRelocationIntent>> {
        let data: Option<String> = sqlx::query_scalar(
            "SELECT dataJson FROM remoteWorkspaceRelocationIntents WHERE id = ?",
        )
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        data.map(|data| serde_json::from_str(&data).map_err(Into::into))
            .transpose()
    }

    pub async fn pending_remote_workspace_relocation(
        &self,
        project_id: &str,
        host_id: &str,
    ) -> Result<Option<RemoteWorkspaceRelocationIntent>> {
        let data: Option<String> = sqlx::query_scalar("SELECT dataJson FROM remoteWorkspaceRelocationIntents WHERE projectId = ? AND hostId = ? AND completed = 0")
            .bind(project_id).bind(host_id).fetch_optional(self.pool()).await?;
        data.map(|data| serde_json::from_str(&data).map_err(Into::into))
            .transpose()
    }

    pub async fn begin_remote_workspace_relocation(
        &self,
        id: &str,
        source: &Workspace,
        intent: WorkspaceRelocationIntent,
    ) -> Result<RemoteWorkspaceRelocationIntent> {
        self.begin_remote_workspace_relocation_with_root(id, source, intent, None)
            .await
    }

    pub async fn begin_remote_workspace_relocation_with_root(
        &self,
        id: &str,
        source: &Workspace,
        intent: WorkspaceRelocationIntent,
        workspace_root: Option<String>,
    ) -> Result<RemoteWorkspaceRelocationIntent> {
        self.begin_remote_workspace_relocation_with_config(id, source, intent, workspace_root, None)
            .await
    }

    pub async fn begin_remote_workspace_relocation_with_config(
        &self,
        id: &str,
        source: &Workspace,
        intent: WorkspaceRelocationIntent,
        workspace_root: Option<String>,
        setup_config: Option<super::ProjectConfig>,
    ) -> Result<RemoteWorkspaceRelocationIntent> {
        if intent.to_project_checkout && setup_config.is_some() {
            bail!("Setup configuration applies only to Hand Off");
        }
        if workspace_root
            .as_ref()
            .is_some_and(|root| root.trim().is_empty())
            || (workspace_root.is_some()
                && (intent.to_project_checkout || intent.destination_path.is_some()))
            || intent
                .destination_path
                .as_ref()
                .is_some_and(|path| path.trim().is_empty())
        {
            bail!("Choose either a destination or a storage root for Hand Off");
        }
        uuid::Uuid::parse_str(id).map_err(|_| anyhow!("Relocation ID must be a UUID"))?;
        if source.host_id == LOCAL_HOST_ID
            || source.status != WorkspaceStatus::Active
            || source.id != intent.workspace_id
            || !intent.shared_impact_confirmed
            || source.instance_id.trim().is_empty()
        {
            bail!("SSH relocation requires an active remote task, exact identity and shared-impact confirmation");
        }
        if self
            .find_project(&source.project_id)
            .await?
            .is_none_or(|project| project.kind != super::ProjectKind::GitRepository)
        {
            bail!("Relocation requires a Git project on the owning host");
        }
        let checkout = self
            .find_project_checkout(&source.project_id, &source.host_id)
            .await?
            .ok_or_else(|| {
                anyhow!("Register the project checkout on the owning host before relocation")
            })?;
        let destination_path = if intent.to_project_checkout {
            if source.kind != WorkspaceKind::Linked
                || intent.destination_path.is_some()
                || intent.branch.is_some()
                || intent.replacement_branch.is_some()
                || !intent.move_changes
            {
                bail!("Hand On requires a linked task and transfers its changes to the registered checkout");
            }
            Some(checkout.path.clone())
        } else {
            if source.kind != WorkspaceKind::Main
                || source.path != checkout.path
                || intent
                    .branch
                    .as_deref()
                    .is_none_or(|branch| branch.trim().is_empty())
                || (intent.replacement_branch.is_some() && !intent.move_changes)
            {
                bail!(
                    "Hand Off requires the shared project task and explicit branch/change choices"
                );
            }
            intent.destination_path.clone()
        };
        if destination_path.as_deref() == Some(source.path.as_str()) {
            bail!("Relocation requires a different checkout path");
        }
        let requested = RemoteWorkspaceRelocationIntent {
            id: id.into(),
            source: source.clone(),
            project_checkout_path: checkout.path,
            destination_path,
            workspace_root,
            owner_preparation: None,
            setup_config,
            intent,
        };
        let data = serde_json::to_string(&requested)?;
        let mut tx = self.pool().begin().await?;
        let current: Option<(String, String, String)> = sqlx::query_as("SELECT instanceId, path, kind FROM workspaces WHERE id = ? AND projectId = ? AND hostId = ? AND status = 'active'")
            .bind(&source.id).bind(&source.project_id).bind(&source.host_id).fetch_optional(&mut *tx).await?;
        if current
            != Some((
                source.instance_id.clone(),
                source.path.clone(),
                source.kind.as_str().into(),
            ))
        {
            bail!("Workspace identity or location changed before SSH relocation");
        }
        // The same UUID is a retry only when its persisted choices and source agree.
        let prior: Option<String> = sqlx::query_scalar(
            "SELECT dataJson FROM remoteWorkspaceRelocationIntents WHERE id = ?",
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(prior) = prior {
            let prior: RemoteWorkspaceRelocationIntent = serde_json::from_str(&prior)?;
            if prior.source.id != source.id
                || prior.source.instance_id != source.instance_id
                || prior.source.host_id != source.host_id
                || prior.source.project_id != source.project_id
                || prior.source.path != source.path
                || prior.source.kind != source.kind
                || prior.project_checkout_path != requested.project_checkout_path
                || prior.workspace_root != requested.workspace_root
                || serde_json::to_value(&prior.setup_config)?
                    != serde_json::to_value(&requested.setup_config)?
                || serde_json::to_value(&prior.intent)? != serde_json::to_value(&requested.intent)?
            {
                bail!("Relocation ID belongs to different choices or another task instance");
            }
            return Ok(prior);
        }
        sqlx::query("INSERT INTO remoteWorkspaceRelocationIntents(id, workspaceId, projectId, hostId, dataJson) VALUES (?, ?, ?, ?, ?)")
            .bind(id).bind(&source.id).bind(&source.project_id).bind(&source.host_id).bind(data).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(requested)
    }
}

#[cfg(test)]
#[path = "remote_workspace_relocation_store_tests.rs"]
mod tests;
