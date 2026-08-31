use anyhow::{anyhow, bail, Result};
use sqlx::{sqlite::SqliteRow, Row};

use super::workflow_launch_validation::{inputs, validate_request};
use super::workflow_plan::workflow_digest;
use super::{
    LaunchWorkflowTask, RuntimeStore, WorkflowLaunchInputs, WorkflowLaunchPage,
    WorkflowLaunchQuery, WorkflowLaunchRecord,
};

impl RuntimeStore {
    pub async fn workflow_launch_summaries(
        &self,
        query: &WorkflowLaunchQuery,
    ) -> Result<WorkflowLaunchPage> {
        super::workflow_plan::workflow_text(&query.run_id, 160)?;
        let rows = sqlx::query("SELECT sequence,id,request,terminal_handle,dispatch_id,base_sha,profile_id,profile_revision,status,error
            FROM workflowLaunches WHERE run_id = ? AND sequence > ? ORDER BY sequence LIMIT 26")
            .bind(&query.run_id).bind(query.after_row.unwrap_or(0)).fetch_all(self.pool()).await?;
        Ok(WorkflowLaunchPage {
            next_after_row: if rows.len() > 25 {
                Some(rows[24].try_get("sequence")?)
            } else {
                None
            },
            items: rows.iter().take(25).map(decode).collect::<Result<_>>()?,
        })
    }
    /// Private context for the authenticated worker, never a catalog export.
    pub async fn workflow_launch_inputs_for_dispatch(
        &self,
        dispatch: &str,
    ) -> Result<Option<WorkflowLaunchInputs>> {
        sqlx::query_scalar::<_, String>("SELECT inputs FROM workflowLaunches WHERE dispatch_id = ?")
            .bind(dispatch)
            .fetch_optional(self.pool())
            .await?
            .map(|raw| serde_json::from_str(&raw).map_err(anyhow::Error::from))
            .transpose()
    }
    pub async fn workflow_launch(&self, id: &str) -> Result<WorkflowLaunchRecord> {
        decode(
            &sqlx::query("SELECT * FROM workflowLaunches WHERE id = ?")
                .bind(id)
                .fetch_one(self.pool())
                .await?,
        )
    }

    pub async fn workflow_launch_for_terminal(
        &self,
        terminal: &str,
    ) -> Result<Option<WorkflowLaunchRecord>> {
        sqlx::query("SELECT * FROM workflowLaunches WHERE terminal_handle = ?")
            .bind(terminal)
            .fetch_optional(self.pool())
            .await?
            .as_ref()
            .map(decode)
            .transpose()
    }

    pub async fn workflow_launch_for_request(
        &self,
        request: &LaunchWorkflowTask,
    ) -> Result<Option<WorkflowLaunchRecord>> {
        validate_request(request)?;
        let row = sqlx::query("SELECT * FROM workflowLaunches WHERE request_id = ?")
            .bind(&request.request_id)
            .fetch_optional(self.pool())
            .await?;
        row.as_ref().map(|row| replay(row, request)).transpose()
    }

    pub async fn workflow_launches_page(
        &self,
        run: &str,
        after: i64,
    ) -> Result<Vec<(i64, WorkflowLaunchRecord)>> {
        sqlx::query("SELECT * FROM workflowLaunches WHERE run_id = ? AND sequence > ? ORDER BY sequence LIMIT 25")
            .bind(run).bind(after).fetch_all(self.pool()).await?.iter()
            .map(|row| Ok((row.try_get("sequence")?, decode(row)?))).collect()
    }

    pub async fn workflow_launch_recovery_page(
        &self,
        after: i64,
    ) -> Result<Vec<(i64, WorkflowLaunchRecord)>> {
        sqlx::query("SELECT * FROM workflowLaunches WHERE sequence > ? AND status <> 'attention' ORDER BY sequence LIMIT 25")
            .bind(after).fetch_all(self.pool()).await?.iter()
            .map(|row| Ok((row.try_get("sequence")?, decode(row)?))).collect()
    }

    pub async fn validate_workflow_launch(
        &self,
        request: &LaunchWorkflowTask,
    ) -> Result<WorkflowLaunchInputs> {
        validate_request(request)?;
        let mut tx = self.pool().begin().await?;
        let result = inputs(&mut tx, request, false).await?;
        tx.commit().await?;
        Ok(result)
    }

    /// Only the reservation creator may install the context token and spawn.
    /// A replay returns the original identity, including after cancellation.
    pub async fn reserve_workflow_launch(
        &self,
        request: &LaunchWorkflowTask,
        context_hash: &str,
    ) -> Result<(WorkflowLaunchRecord, bool)> {
        validate_request(request)?;
        if context_hash.len() != 64
            || !context_hash
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        {
            bail!("workflow context requires a SHA-256 token hash");
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query("SELECT * FROM workflowLaunches WHERE request_id = ?")
            .bind(&request.request_id)
            .fetch_optional(&mut *tx)
            .await?
        {
            return Ok((replay(&row, request)?, false));
        }
        let frozen = inputs(&mut tx, request, false).await?;
        let id = uuid::Uuid::new_v4().to_string();
        let terminal = uuid::Uuid::new_v4().to_string();
        let dispatch = format!("ctx_{}", uuid::Uuid::new_v4());
        sqlx::query("INSERT INTO workflowLaunches(id,request_id,request_digest,request,run_id,revision,task_id,workspace_id,terminal_handle,dispatch_id,inputs,context_hash,base_sha,profile_id,profile_revision,status)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'reserved')")
            .bind(&id).bind(&request.request_id).bind(workflow_digest(request)?).bind(serde_json::to_string(request)?)
            .bind(&request.run_id).bind(request.revision).bind(&request.task_id).bind(&request.workspace_id)
            .bind(&terminal).bind(&dispatch).bind(serde_json::to_string(&frozen)?).bind(context_hash)
            .bind(&frozen.workspace.base_sha).bind(&frozen.profile.id).bind(frozen.profile.revision).execute(&mut *tx).await?;
        sqlx::query("UPDATE workflowWorkspaces SET dispatch_id = ?, updated_at = datetime('now') WHERE id = ? AND dispatch_id IS NULL")
            .bind(&dispatch).bind(&request.workspace_id).execute(&mut *tx).await?;
        sqlx::query("INSERT INTO orchestrationDispatchContexts(id,task_id,assignee_handle,status,failure_count,dispatched_at,run_id,workspace_id,coordinator_handle,context_token_hash,completion_policy,terminal_policy,last_activity_at)
            VALUES(?,?,?,'awaiting_acceptance',0,datetime('now'),?,?,'',?,'return-immediately','keep-open',datetime('now'))")
            .bind(&dispatch).bind(&request.task_id).bind(&terminal).bind(&request.run_id).bind(&request.workspace_id).bind(context_hash)
            .execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationTasks SET status = 'dispatched' WHERE id = ?")
            .bind(&request.task_id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok((self.workflow_launch(&id).await?, true))
    }
}

fn replay(row: &SqliteRow, request: &LaunchWorkflowTask) -> Result<WorkflowLaunchRecord> {
    if row.try_get::<String, _>("request_digest")? != workflow_digest(request)? {
        bail!("launch request id was already used for different contents");
    }
    decode(row)
}

pub(super) fn decode(row: &SqliteRow) -> Result<WorkflowLaunchRecord> {
    Ok(WorkflowLaunchRecord {
        id: row.try_get("id")?,
        request: serde_json::from_str(&row.try_get::<String, _>("request")?)?,
        terminal_handle: row.try_get("terminal_handle")?,
        dispatch_id: row.try_get("dispatch_id")?,
        base_sha: row.try_get("base_sha")?,
        profile_id: row.try_get("profile_id")?,
        profile_revision: row.try_get("profile_revision")?,
        status: serde_json::from_value(serde_json::Value::String(row.try_get("status")?))
            .map_err(|_| anyhow!("invalid workflow launch state"))?,
        error: row.try_get("error")?,
    })
}
