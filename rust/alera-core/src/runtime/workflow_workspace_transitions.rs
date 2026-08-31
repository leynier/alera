use anyhow::{bail, Result};
use sqlx::{Sqlite, Transaction};

use super::workflow_workspace_eligibility::{approved_plan, eligible_task};
use super::workflow_workspace_store::decode;
use super::{
    RuntimeStore, WorkflowWorkspaceIdentity, WorkflowWorkspacePhase as Phase,
    WorkflowWorkspaceRecord, WorktreeSetupReport,
};

impl RuntimeStore {
    pub async fn validate_workflow_workspace(
        &self,
        id: &str,
        revision: i64,
    ) -> Result<WorkflowWorkspaceRecord> {
        let mut tx = self.pool().begin().await?;
        let record = decode(
            &sqlx::query("SELECT * FROM workflowWorkspaces WHERE id = ?")
                .bind(id)
                .fetch_one(&mut *tx)
                .await?,
        )?;
        validate(&mut tx, &record.identity, revision).await?;
        tx.commit().await?;
        Ok(record)
    }

    pub async fn transition_workflow_workspace(
        &self,
        id: &str,
        revision: i64,
        expected: Phase,
        next: Phase,
        report: Option<&WorktreeSetupReport>,
        error: Option<&str>,
    ) -> Result<WorkflowWorkspaceRecord> {
        if !(next == Phase::Attention
            || matches!(
                (expected, next),
                (Phase::Reserved, Phase::Creating)
                    | (Phase::Creating, Phase::Created)
                    | (Phase::Created, Phase::SetupRunning)
                    | (Phase::Created, Phase::Ready)
                    | (Phase::SetupRunning, Phase::Ready)
            ))
            || expected == Phase::Attention
        {
            bail!("invalid workflow workspace transition");
        }
        let report = report
            .map(super::workflow_setup_report::bounded_report)
            .transpose()?;
        if error.is_some_and(|value| value.len() > 4096) {
            bail!("workflow setup error exceeds the byte limit");
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let record = decode(
            &sqlx::query("SELECT * FROM workflowWorkspaces WHERE id = ?")
                .bind(id)
                .fetch_one(&mut *tx)
                .await?,
        )?;
        if record.phase != expected {
            bail!("workflow workspace phase changed");
        }
        if next != Phase::Attention {
            validate(&mut tx, &record.identity, revision).await?;
        }
        if next == Phase::Created {
            let w = &record.identity.workspace;
            // INSERT, never upsert: an unrelated/replaced identity must not be adopted.
            sqlx::query(
                "INSERT INTO workspaces(id, instanceId, hostId, projectId, name, branch, path,
                createdAt, updatedAt, kind, status, sourceBranch, reusesExistingBranch, isPinned)
                VALUES(?, ?, 'local', ?, ?, ?, ?, ?, ?, 'linked', 'active', ?, 0, 0)",
            )
            .bind(&w.id)
            .bind(&w.instance_id)
            .bind(&w.project_id)
            .bind(&w.name)
            .bind(&w.branch)
            .bind(&w.path)
            .bind(w.created_at.to_rfc3339())
            .bind(w.updated_at.to_rfc3339())
            .bind(&record.identity.base_sha)
            .execute(&mut *tx)
            .await?;
            let parent_instance: String =
                sqlx::query_scalar("SELECT instanceId FROM workspaces WHERE id = ?")
                    .bind(&record.identity.owner_workspace_id)
                    .fetch_one(&mut *tx)
                    .await?;
            sqlx::query(
                "INSERT INTO workspaceRelations(id, parentWorkspaceId, parentInstanceId,
                childWorkspaceId, childInstanceId, createdAt) VALUES(?, ?, ?, ?, ?, ?)",
            )
            .bind(uuid::Uuid::new_v4().to_string())
            .bind(&record.identity.owner_workspace_id)
            .bind(parent_instance)
            .bind(&w.id)
            .bind(&w.instance_id)
            .bind(w.created_at.to_rfc3339())
            .execute(&mut *tx)
            .await?;
        }
        sqlx::query(
            "UPDATE workflowWorkspaces SET phase = ?, setup_report = COALESCE(?, setup_report),
            error = ?, updated_at = datetime('now') WHERE id = ?",
        )
        .bind(next.as_str())
        .bind(report)
        .bind(error)
        .bind(id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.workflow_workspace(id).await
    }
}

async fn validate(
    tx: &mut Transaction<'_, Sqlite>,
    identity: &WorkflowWorkspaceIdentity,
    revision: i64,
) -> Result<()> {
    let (plan, sha) = approved_plan(tx, &identity.run_id, revision).await?;
    if identity.owner_workspace_id != plan.source_workspace.workspace_id
        || identity.repo_path != plan.source_workspace.project_repo_path
        || identity.workspace.project_id != plan.source_workspace.project_id
    {
        bail!("workflow resource belongs to another owner");
    }
    if let Some(task) = &identity.task_id {
        if revision != identity.revision || sha != identity.base_sha {
            bail!("workflow attempt revision or integration base changed");
        }
        eligible_task(tx, &identity.run_id, revision, task, &plan).await?;
    } else if plan.source_sha != identity.base_sha {
        bail!("workflow integration source changed");
    }
    Ok(())
}
