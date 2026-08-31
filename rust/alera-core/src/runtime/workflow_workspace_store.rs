use anyhow::{anyhow, bail, Result};
use sqlx::{sqlite::SqliteRow, Row};

use super::workflow_plan::{workflow_digest, workflow_text};
use super::workflow_workspace_eligibility::{approved_plan, eligible_task};
use super::*;

impl RuntimeStore {
    pub async fn workflow_integration_workspace(
        &self,
        run: &str,
    ) -> Result<WorkflowWorkspaceRecord> {
        decode(
            &sqlx::query("SELECT * FROM workflowWorkspaces WHERE run_id = ? AND task_id IS NULL")
                .bind(run)
                .fetch_one(self.pool())
                .await?,
        )
    }

    pub async fn workflow_workspace(&self, id: &str) -> Result<WorkflowWorkspaceRecord> {
        decode(
            &sqlx::query("SELECT * FROM workflowWorkspaces WHERE id = ?")
                .bind(id)
                .fetch_optional(self.pool())
                .await?
                .ok_or_else(|| anyhow!("workflow workspace not found"))?,
        )
    }

    pub async fn workflow_workspace_owned(&self, id: &str) -> Result<bool> {
        Ok(
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowWorkspaces WHERE id = ?)")
                .bind(id)
                .fetch_one(self.pool())
                .await?,
        )
    }

    pub async fn workflow_workspaces(
        &self,
        query: &WorkflowWorkspaceQuery,
    ) -> Result<WorkflowWorkspacePage> {
        workflow_text(&query.run_id, 160)?;
        let limit = query.limit.unwrap_or(20).clamp(1, 25) as usize;
        let rows = sqlx::query(
            "SELECT * FROM workflowWorkspaces WHERE run_id = ? AND sequence < ?
            ORDER BY sequence DESC LIMIT ?",
        )
        .bind(&query.run_id)
        .bind(query.before_row.unwrap_or(i64::MAX))
        .bind((limit + 1) as i64)
        .fetch_all(self.pool())
        .await?;
        let next_before_row = if rows.len() > limit {
            Some(rows[limit - 1].try_get("sequence")?)
        } else {
            None
        };
        Ok(WorkflowWorkspacePage {
            items: rows.iter().take(limit).map(decode).collect::<Result<_>>()?,
            next_before_row,
        })
    }

    /// The candidate's location comes from the host's managed workspace policy,
    /// never from a request payload. Only a fresh reservation consumes it.
    pub async fn reserve_workflow_workspace(
        &self,
        request: &PrepareWorkflowWorkspace,
        mut candidate: Workspace,
    ) -> Result<WorkflowWorkspaceRecord> {
        workflow_text(&request.request_id, 160)?;
        workflow_text(&request.run_id, 160)?;
        if let Some(task) = &request.task_id {
            workflow_text(task, 160)?;
        }
        if let Some(previous) = &request.retry_of {
            workflow_text(previous, 160)?;
        }
        let digest = workflow_digest(request)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query(
            "SELECT digest, workspace_id FROM workflowWorkspaceRequests WHERE request_id = ?",
        )
        .bind(&request.request_id)
        .fetch_optional(&mut *tx)
        .await?
        {
            if row.try_get::<String, _>("digest")? != digest {
                bail!("workflow request id was already used for different contents");
            }
            let id: String = row.try_get("workspace_id")?;
            tx.commit().await?;
            return self.workflow_workspace(&id).await;
        }
        let (plan, integration_sha) =
            approved_plan(&mut tx, &request.run_id, request.revision).await?;
        let mut attempt = 0;
        let mut existing_id = None;
        if let Some(task) = &request.task_id {
            eligible_task(&mut tx, &request.run_id, request.revision, task, &plan).await?;
            let ready: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM workflowWorkspaces
                WHERE run_id = ? AND task_id IS NULL AND phase = 'ready')",
            )
            .bind(&request.run_id)
            .fetch_one(&mut *tx)
            .await?;
            if !ready {
                bail!("workflow integration workspace is not ready");
            }
            let previous = sqlx::query(
                "SELECT id, attempt, phase FROM workflowWorkspaces
                WHERE task_id = ? ORDER BY attempt DESC LIMIT 1",
            )
            .bind(task)
            .fetch_optional(&mut *tx)
            .await?;
            if let Some(previous) = previous {
                let id: String = previous.try_get("id")?;
                attempt = previous.try_get::<i64, _>("attempt")? + 1;
                if let Some(retry) = &request.retry_of {
                    if retry != &id || previous.try_get::<String, _>("phase")? != "attention" {
                        bail!("retry requires the latest attempt in Attention");
                    }
                } else {
                    existing_id = Some(id);
                }
            } else {
                if request.retry_of.is_some() {
                    bail!("workflow attempt to retry was not found");
                }
                attempt = 1;
            }
            if existing_id.is_none() {
                let active: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowWorkspaces
                    WHERE run_id = ? AND revision = ? AND task_id IS NOT NULL AND phase <> 'attention'")
                    .bind(&request.run_id).bind(request.revision).fetch_one(&mut *tx).await?;
                if active >= i64::from(plan.max_concurrent) {
                    bail!("workflow concurrency limit reached");
                }
            }
        } else {
            if request.retry_of.is_some() {
                bail!("integration workspace cannot be replaced by a task retry");
            }
            existing_id = sqlx::query_scalar(
                "SELECT id FROM workflowWorkspaces WHERE run_id = ? AND task_id IS NULL",
            )
            .bind(&request.run_id)
            .fetch_optional(&mut *tx)
            .await?;
        }
        let id = if let Some(id) = existing_id {
            id
        } else {
            uuid::Uuid::parse_str(&candidate.id)?;
            uuid::Uuid::parse_str(&candidate.instance_id)?;
            if candidate.project_id != plan.source_workspace.project_id
                || candidate.host_id != LOCAL_HOST_ID
                || candidate.kind != WorkspaceKind::Linked
                || !std::path::Path::new(&candidate.path).is_absolute()
                || candidate.branch.as_deref()
                    != Some(format!("alera/workflows/{}", candidate.id).as_str())
            {
                bail!("invalid managed workflow workspace candidate");
            }
            let collision: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM workspaces WHERE id = ? OR path = ?
                OR (projectId = ? AND branch = ?))",
            )
            .bind(&candidate.id)
            .bind(&candidate.path)
            .bind(&candidate.project_id)
            .bind(&candidate.branch)
            .fetch_one(&mut *tx)
            .await?;
            if collision {
                bail!("workflow workspace identity is already in use");
            }
            candidate.source_branch = Some(integration_sha.clone());
            let identity = WorkflowWorkspaceIdentity {
                workspace: candidate,
                repo_path: plan.source_workspace.project_repo_path.clone(),
                owner_workspace_id: plan.source_workspace.workspace_id.clone(),
                run_id: request.run_id.clone(),
                revision: request.revision,
                task_id: request.task_id.clone(),
                attempt,
                base_sha: if request.task_id.is_some() {
                    integration_sha
                } else {
                    plan.source_sha
                },
            };
            let id = identity.workspace.id.clone();
            sqlx::query("INSERT INTO workflowWorkspaces(id, run_id, revision, task_id, attempt, path, identity, phase)
                VALUES(?, ?, ?, ?, ?, ?, ?, 'reserved')")
                .bind(&id).bind(&identity.run_id).bind(identity.revision).bind(&identity.task_id)
                .bind(attempt).bind(&identity.workspace.path).bind(serde_json::to_string(&identity)?)
                .execute(&mut *tx).await?;
            id
        };
        sqlx::query("INSERT INTO workflowWorkspaceRequests(request_id, digest, workspace_id) VALUES(?, ?, ?)")
            .bind(&request.request_id).bind(digest).bind(&id).execute(&mut *tx).await?;
        tx.commit().await?;
        self.workflow_workspace(&id).await
    }
}

pub(super) fn decode(row: &SqliteRow) -> Result<WorkflowWorkspaceRecord> {
    Ok(WorkflowWorkspaceRecord {
        identity: serde_json::from_str(&row.try_get::<String, _>("identity")?)?,
        phase: serde_json::from_value(serde_json::Value::String(row.try_get("phase")?))?,
        setup_report: row
            .try_get::<Option<String>, _>("setup_report")?
            .map(|value| serde_json::from_str(&value))
            .transpose()?,
        error: row.try_get("error")?,
        dispatch_id: row.try_get("dispatch_id")?,
    })
}
