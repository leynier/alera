use anyhow::{bail, Result};
use serde::Serialize;
use sqlx::Row;

use super::workflow_gate_evidence::approval_state;
use super::{RuntimeStore, WorkflowPlanSnapshot};
use crate::workflow_approval::WorkflowApprovalChallenge;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowReview {
    pub challenge: WorkflowApprovalChallenge,
    pub plan: WorkflowPlanSnapshot,
    pub tasks: Vec<WorkflowReviewTask>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowReviewTask {
    pub task_id: String,
    pub logical_id: String,
    pub stage_id: String,
    pub status: String,
    pub result_preview: Option<String>,
    pub result_truncated: bool,
    pub result_digest: Option<String>,
    pub artifact_digest: Option<String>,
    pub integration_sha: Option<String>,
}

impl RuntimeStore {
    pub async fn workflow_review(
        &self,
        run_id: &str,
        revision: i64,
        scope: &str,
        audience: &str,
    ) -> Result<WorkflowReview> {
        let challenge = self
            .workflow_approval_challenge(run_id, revision, scope, audience)
            .await?;
        let mut tx = self.pool().begin().await?;
        let state = approval_state(&mut tx, run_id, revision, scope).await?;
        // The challenge and the rendered evidence must describe the same state,
        // even when an integration settles between these transactions.
        if state.plan.digest != challenge.plan_digest
            || state.evidence_digest != challenge.evidence_digest
            || state.integration_sha != challenge.integration_sha
        {
            bail!("workflow evidence changed while opening review; refresh the review");
        }
        let rows = sqlx::query(
            "SELECT p.task_id, p.logical_id, t.stage_id, t.status,
            substr(t.result, 1, 1024) AS result_preview,
            COALESCE(length(t.result) > 1024, 0) AS result_truncated,
            e.result_digest, e.artifact_digest, e.integration_sha
            FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id = p.task_id
            LEFT JOIN workflowTaskEvidence e ON e.task_id = p.task_id
            WHERE p.run_id = ? AND p.revision = ? ORDER BY p.logical_id LIMIT 129",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_all(&mut *tx)
        .await?;
        if rows.len() > super::WORKFLOW_PLAN_MAX_TASKS {
            bail!("workflow review exceeds the task limit");
        }
        let mut stages = std::collections::BTreeSet::new();
        let mut pending = scope
            .strip_prefix("stage:")
            .map(str::to_owned)
            .into_iter()
            .collect::<Vec<_>>();
        while let Some(id) = pending.pop() {
            if stages.insert(id.clone()) {
                if let Some(stage) = state.plan.recipe.recipe.stages.iter().find(|s| s.id == id) {
                    pending.extend(stage.depends_on.iter().cloned());
                }
            }
        }
        let tasks = rows
            .into_iter()
            .map(|row| {
                Ok(WorkflowReviewTask {
                    task_id: row.try_get("task_id")?,
                    logical_id: row.try_get("logical_id")?,
                    stage_id: row.try_get("stage_id")?,
                    status: row.try_get("status")?,
                    result_preview: row.try_get("result_preview")?,
                    result_truncated: row.try_get("result_truncated")?,
                    result_digest: row.try_get("result_digest")?,
                    artifact_digest: row.try_get("artifact_digest")?,
                    integration_sha: row.try_get("integration_sha")?,
                })
            })
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .filter(|task| stages.contains(&task.stage_id))
            .collect();
        tx.commit().await?;
        Ok(WorkflowReview {
            challenge,
            plan: state.plan,
            tasks,
        })
    }
}
