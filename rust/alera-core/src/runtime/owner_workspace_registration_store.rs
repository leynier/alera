use anyhow::{anyhow, bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::{Project, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID};

impl RuntimeStore {
    /// Register an inspected local owner checkout and task together, preserving equivalent retries.
    pub async fn register_owner_workspace(
        &self,
        project: &Project,
        workspace: &Workspace,
        repository_path: Option<&str>,
    ) -> Result<Workspace> {
        if project.id.trim().is_empty()
            || project.repo_path.trim().is_empty()
            || workspace.id.trim().is_empty()
            || workspace.instance_id.trim().is_empty()
            || workspace.project_id != project.id
            || workspace.host_id != LOCAL_HOST_ID
            || workspace.status != WorkspaceStatus::Active
            || (workspace.kind == WorkspaceKind::Main
                && (!same_owner_path(&workspace.path, &project.repo_path)
                    || repository_path.is_some()))
            || (workspace.kind == WorkspaceKind::Linked
                && repository_path.is_none_or(|path| path.trim().is_empty()))
        {
            bail!(
                "An active task with stable project, workspace and instance identities is required"
            );
        }
        let paths = (project.repo_path.clone(), workspace.path.clone());
        let (project_path, checkout_path) = tokio::task::spawn_blocking(move || {
            (
                super::checkout_store::canonical_local_path_or_original(&paths.0),
                super::checkout_store::canonical_local_path_or_original(&paths.1),
            )
        })
        .await?;
        // Startup mirroring and a first request can arrive together. Lock before the
        // identity read so the second registration validates the committed winner.
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let existing = sqlx::query(
            "SELECT instanceId, projectId, hostId, path, kind, status FROM workspaces WHERE id = ?",
        )
        .bind(&workspace.id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(existing) = existing {
            if existing.try_get::<String, _>("instanceId")? != workspace.instance_id
                || existing.try_get::<String, _>("projectId")? != project.id
                || existing.try_get::<String, _>("hostId")? != LOCAL_HOST_ID
                || !same_owner_path(existing.try_get("path")?, &workspace.path)
                || existing.try_get::<String, _>("kind")? != workspace.kind.as_str()
                || existing.try_get::<String, _>("status")? != WorkspaceStatus::Active.as_str()
            {
                bail!("Remote task identity already belongs to another workspace; no state was replaced");
            }
            validate_existing_owner(&mut tx, project, workspace, repository_path).await?;
        } else {
            super::checkout_store::register_owner_project_checkout_in(
                &mut tx,
                project,
                &project_path,
            )
            .await?;
            super::checkout_store::bind_workspace_checkout(&mut tx, workspace, &checkout_path)
                .await?;
            if let Some(repository_path) = repository_path {
                let result = sqlx::query("UPDATE repositoryCheckouts SET repositoryPath = ? WHERE id = (SELECT checkoutId FROM workspaceCheckoutBindings WHERE workspaceId = ?) AND (repositoryPath IS NULL OR repositoryPath = ?)")
                    .bind(repository_path).bind(&workspace.id).bind(repository_path).execute(&mut *tx).await?;
                if result.rows_affected() != 1 {
                    bail!("The linked checkout already belongs to a different repository");
                }
            }
            super::workspace_record_write::write_workspace_record(&mut tx, workspace, false)
                .await?;
        }
        tx.commit().await?;
        self.find_workspace(&workspace.id)
            .await?
            .ok_or_else(|| anyhow!("Remote task not found after registration"))
    }
}

async fn validate_existing_owner(
    tx: &mut Transaction<'_, Sqlite>,
    project: &Project,
    workspace: &Workspace,
    repository_path: Option<&str>,
) -> Result<()> {
    let owner = sqlx::query("SELECT repoPath, kind FROM projects WHERE id = ?")
        .bind(&project.id)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| anyhow!("Remote task project is unavailable"))?;
    if !same_owner_path(owner.try_get("repoPath")?, &project.repo_path)
        || owner.try_get::<String, _>("kind")? != project.kind.as_str()
    {
        bail!("Remote task repository ownership changed");
    }
    if workspace.kind == WorkspaceKind::Linked {
        let stored: Option<Option<String>> = sqlx::query_scalar(
            "SELECT c.repositoryPath FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b
             ON c.id = b.checkoutId WHERE b.workspaceId = ?",
        )
        .bind(&workspace.id)
        .fetch_optional(&mut **tx)
        .await?;
        if stored.flatten().as_deref() != repository_path {
            bail!("Remote linked task repository origin changed; no state was replaced");
        }
    }
    Ok(())
}

fn same_owner_path(left: &str, right: &str) -> bool {
    fn plain(path: &str) -> std::borrow::Cow<'_, str> {
        if let Some(rest) = path.strip_prefix(r"\\?\UNC\") {
            return std::borrow::Cow::Owned(format!(r"\\{rest}"));
        }
        path.strip_prefix(r"\\?\").unwrap_or(path).into()
    }
    left == right || plain(left) == plain(right)
}

#[cfg(test)]
#[path = "owner_workspace_registration_store_tests.rs"]
mod tests;
