use anyhow::{anyhow, bail, Result};
use sqlx::{sqlite::SqliteRow, Row};

use super::workflow_integration_validation::{capture, require_current};
use super::workflow_plan::{workflow_digest, workflow_text};
use super::{
    IntegrateWorkflowResult, RuntimeStore, WorkflowIntegrationRecord,
    WorkflowIntegrationState as State,
};
use crate::git::{WorkflowGitPreparation, WorkflowIntegrationReceipt};

impl RuntimeStore {
    pub async fn workflow_integration_for_request(
        &self,
        input: &IntegrateWorkflowResult,
    ) -> Result<Option<WorkflowIntegrationRecord>> {
        for value in [
            &input.request_id,
            &input.run_id,
            &input.task_id,
            &input.workspace_id,
        ] {
            workflow_text(value, 160)?;
        }
        let Some(row) = sqlx::query("SELECT * FROM workflowIntegrations WHERE request_id = ?")
            .bind(&input.request_id)
            .fetch_optional(self.pool())
            .await?
        else {
            return Ok(None);
        };
        if row.try_get::<String, _>("request_digest")? != workflow_digest(input)? {
            bail!("integration request id was already used for different contents");
        }
        Ok(Some(decode(&row)?))
    }

    pub async fn workflow_integration(&self, id: &str) -> Result<WorkflowIntegrationRecord> {
        decode(
            &sqlx::query("SELECT * FROM workflowIntegrations WHERE id = ?")
                .bind(id)
                .fetch_optional(self.pool())
                .await?
                .ok_or_else(|| anyhow!("workflow integration not found"))?,
        )
    }

    pub async fn workflow_integrations_page(
        &self,
        run: &str,
        after: i64,
    ) -> Result<Vec<(i64, WorkflowIntegrationRecord)>> {
        workflow_text(run, 160)?;
        sqlx::query("SELECT * FROM workflowIntegrations WHERE run_id = ? AND sequence > ? ORDER BY sequence LIMIT 25")
            .bind(run).bind(after).fetch_all(self.pool()).await?.iter()
            .map(|row| Ok((row.try_get("sequence")?, decode(row)?))).collect()
    }

    /// `source_sha` is captured by the native Git boundary, never accepted from RPC.
    pub async fn reserve_workflow_integration(
        &self,
        input: &IntegrateWorkflowResult,
        source_sha: &str,
    ) -> Result<WorkflowIntegrationRecord> {
        for value in [
            &input.request_id,
            &input.run_id,
            &input.task_id,
            &input.workspace_id,
        ] {
            workflow_text(value, 160)?;
        }
        if source_sha.len() != 40
            || !source_sha
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        {
            bail!("integration requires an exact committed result SHA");
        }
        let digest = workflow_digest(input)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query("SELECT * FROM workflowIntegrations WHERE request_id = ?")
            .bind(&input.request_id)
            .fetch_optional(&mut *tx)
            .await?
        {
            if row.try_get::<String, _>("request_digest")? != digest {
                bail!("integration request id was already used for different contents");
            }
            return decode(&row);
        }
        let done: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowTaskEvidence WHERE task_id = ?)",
        )
        .bind(&input.task_id)
        .fetch_one(&mut *tx)
        .await?;
        if done {
            bail!("workflow task is already integrated");
        }
        let request = capture(&mut tx, input, source_sha, uuid::Uuid::new_v4().to_string()).await?;
        sqlx::query("INSERT INTO workflowIntegrations(id,request_id,request_digest,run_id,revision,task_id,workspace_id,request,state)
            VALUES(?,?,?,?,?,?,?,?,'pending')")
            .bind(&request.id).bind(&input.request_id).bind(digest).bind(&input.run_id).bind(input.revision)
            .bind(&input.task_id).bind(&input.workspace_id).bind(serde_json::to_string(&request)?)
            .execute(&mut *tx).await?;
        tx.commit().await?;
        self.workflow_integration(&request.id).await
    }

    pub async fn record_workflow_integration_preparation(
        &self,
        id: &str,
        outcome: &WorkflowGitPreparation,
    ) -> Result<WorkflowIntegrationRecord> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let record = decode(
            &sqlx::query("SELECT * FROM workflowIntegrations WHERE id = ?")
                .bind(id)
                .fetch_one(&mut *tx)
                .await?,
        )?;
        if record.state == State::Integrated {
            return Ok(record);
        }
        require_current(&mut tx, &record.request).await?;
        match outcome {
            WorkflowGitPreparation::Ready { receipt } => {
                if receipt.request != record.request
                    || receipt.version != 1
                    || record
                        .receipt
                        .as_ref()
                        .is_some_and(|stored| stored != receipt.as_ref())
                {
                    bail!("Git receipt does not match the integration reservation");
                }
                sqlx::query("UPDATE workflowIntegrations SET state = 'prepared', receipt = ?, conflict_paths = '[]',
                    conflicts_truncated = 0, error = NULL, updated_at = datetime('now') WHERE id = ?")
                    .bind(serde_json::to_string(receipt)?).bind(id).execute(&mut *tx).await?;
            }
            WorkflowGitPreparation::Conflict { paths, truncated } => {
                if record.receipt.is_some()
                    || paths.len() > 128
                    || paths.iter().any(|p| p.chars().count() > 1024)
                {
                    bail!(
                        "conflict report is invalid or integration already has a prepared receipt"
                    );
                }
                sqlx::query("UPDATE workflowIntegrations SET state = 'conflict', conflict_paths = ?, conflicts_truncated = ?,
                    error = NULL, updated_at = datetime('now') WHERE id = ?")
                    .bind(serde_json::to_string(paths)?).bind(truncated).bind(id).execute(&mut *tx).await?;
            }
        }
        tx.commit().await?;
        self.workflow_integration(id).await
    }

    /// Invoke only after native Git verifies/applies the persisted receipt.
    pub async fn complete_workflow_integration(
        &self,
        receipt: &WorkflowIntegrationReceipt,
    ) -> Result<WorkflowIntegrationRecord> {
        let id = &receipt.request.id;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        let record = decode(
            &sqlx::query("SELECT * FROM workflowIntegrations WHERE id = ?")
                .bind(id)
                .fetch_one(&mut *tx)
                .await?,
        )?;
        if record.receipt.as_ref() != Some(receipt) {
            bail!("integration receipt was not prepared durably");
        }
        if record.state == State::Integrated {
            return Ok(record);
        }
        if record.state != State::Prepared {
            bail!("integration is not prepared");
        }
        require_current(&mut tx, &record.request).await?;
        sqlx::query("INSERT INTO workflowTaskEvidence(task_id,result_digest,artifact_digest,integration_sha) VALUES(?,?,?,?)")
            .bind(&record.request.task_id).bind(&record.request.result_digest).bind(&receipt.artifact_digest)
            .bind(&receipt.integrated_sha).execute(&mut *tx).await?;
        sqlx::query("UPDATE workflowRuns SET integration_sha = ? WHERE run_id = ?")
            .bind(&receipt.integrated_sha)
            .bind(&record.request.run_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE workflowIntegrations SET state = 'integrated', error = NULL, updated_at = datetime('now') WHERE id = ?")
            .bind(id).execute(&mut *tx).await?;
        tx.commit().await?;
        self.workflow_integration(id).await
    }

    pub async fn workflow_integration_attention(
        &self,
        id: &str,
        error: &str,
    ) -> Result<WorkflowIntegrationRecord> {
        let error = error.chars().take(1000).collect::<String>();
        sqlx::query("UPDATE workflowIntegrations SET state = 'attention', error = ?, updated_at = datetime('now')
            WHERE id = ? AND state NOT IN ('integrated','conflict')")
            .bind(error).bind(id).execute(self.pool()).await?;
        self.workflow_integration(id).await
    }
}

fn decode(row: &SqliteRow) -> Result<WorkflowIntegrationRecord> {
    Ok(WorkflowIntegrationRecord {
        request: serde_json::from_str(&row.try_get::<String, _>("request")?)?,
        state: serde_json::from_value(serde_json::Value::String(row.try_get("state")?))?,
        receipt: row
            .try_get::<Option<String>, _>("receipt")?
            .map(|raw| serde_json::from_str(&raw))
            .transpose()?,
        conflict_paths: serde_json::from_str(&row.try_get::<String, _>("conflict_paths")?)?,
        conflicts_truncated: row.try_get("conflicts_truncated")?,
        error: row.try_get("error")?,
    })
}
