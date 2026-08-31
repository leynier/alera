use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use sqlx::{Row, Sqlite, Transaction};

use super::workflow_plan::workflow_digest;
use super::WorkflowPlanSnapshot;

pub(super) struct ApprovalState {
    pub plan: WorkflowPlanSnapshot,
    pub workspace_id: String,
    pub integration_sha: String,
    pub evidence_digest: String,
}

pub(super) async fn approval_state(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    revision: i64,
    scope: &str,
) -> Result<ApprovalState> {
    let unsettled: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workflowIntegrations
        WHERE run_id = ? AND state IN ('pending','prepared','attention'))",
    )
    .bind(run_id)
    .fetch_one(&mut **tx)
    .await?;
    if unsettled {
        bail!("reconcile the pending integration before approving a workflow plan or gate");
    }
    let row = sqlx::query("SELECT r.workspace_id, r.revision, r.status, r.integration_sha, p.snapshot, c.status AS coordinator_status
        FROM workflowRuns r JOIN workflowPlanRevisions p ON p.run_id = r.run_id AND p.revision = r.revision
        JOIN orchestrationCoordinatorRuns c ON c.id = r.run_id
        WHERE r.run_id = ?").bind(run_id).fetch_optional(&mut **tx).await?
        .ok_or_else(|| anyhow!("workflow run not found"))?;
    if row.try_get::<i64, _>("revision")? != revision {
        bail!("workflow plan revision is stale");
    }
    if !matches!(
        row.try_get::<String, _>("coordinator_status")?.as_str(),
        "idle" | "running"
    ) {
        bail!("workflow run is stopped or finished");
    }
    let plan: WorkflowPlanSnapshot = serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?;
    super::workflow_source_identity::require_source_workspace(tx, &plan.source_workspace).await?;
    if plan.digest != plan.content_digest()? {
        bail!("workflow plan snapshot is invalid");
    }
    let status: String = row.try_get("status")?;
    let integration_sha: String = row.try_get("integration_sha")?;
    let evidence_digest = if scope == "plan" {
        if status != "prepared" {
            bail!("workflow plan is not awaiting approval");
        }
        workflow_digest(&serde_json::json!([plan.digest, integration_sha]))?
    } else {
        if status != "approved" {
            bail!("workflow plan is not approved");
        }
        let stage_id = scope
            .strip_prefix("stage:")
            .ok_or_else(|| anyhow!("invalid workflow gate scope"))?;
        let stage = plan
            .recipe
            .recipe
            .stages
            .iter()
            .find(|stage| stage.id == stage_id && stage.gate.is_some())
            .ok_or_else(|| anyhow!("workflow stage has no human gate"))?;
        let pending: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowStageGates
            WHERE run_id = ? AND revision = ? AND stage_id = ? AND status = 'pending')",
        )
        .bind(run_id)
        .bind(revision)
        .bind(stage_id)
        .fetch_one(&mut **tx)
        .await?;
        if !pending {
            bail!("workflow gate is not awaiting approval");
        }
        let mut ancestors = std::collections::BTreeSet::from([stage.id.clone()]);
        let mut remaining = stage.depends_on.clone();
        while let Some(id) = remaining.pop() {
            if ancestors.insert(id.clone()) {
                let prior = plan
                    .recipe
                    .recipe
                    .stages
                    .iter()
                    .find(|stage| stage.id == id)
                    .ok_or_else(|| anyhow!("workflow stage dependency is missing"))?;
                remaining.extend(prior.depends_on.clone());
            }
        }
        for prior in &plan.recipe.recipe.stages {
            if prior.id != stage.id && prior.gate.is_some() && ancestors.contains(&prior.id) {
                let approved: bool = sqlx::query_scalar(
                    "SELECT EXISTS(SELECT 1 FROM workflowStageGates
                    WHERE run_id = ? AND revision = ? AND stage_id = ? AND status = 'approved')",
                )
                .bind(run_id)
                .bind(revision)
                .bind(&prior.id)
                .fetch_one(&mut **tx)
                .await?;
                if !approved {
                    bail!("workflow prerequisite human gate is not approved");
                }
            }
        }
        let rows = sqlx::query(
            "SELECT p.logical_id, t.status, t.result, t.stage_id,
            e.result_digest, e.artifact_digest, e.integration_sha
            FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id = p.task_id
            LEFT JOIN workflowTaskEvidence e ON e.task_id = t.id
            WHERE p.run_id = ? AND p.revision = ? ORDER BY p.logical_id",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_all(&mut **tx)
        .await?;
        let expected = plan
            .tasks
            .iter()
            .filter(|task| ancestors.contains(&task.task.stage_id))
            .count();
        let mut evidence = Vec::new();
        for row in rows {
            if !ancestors.contains(&row.try_get::<String, _>("stage_id")?) {
                continue;
            }
            let result: Option<String> = row.try_get("result")?;
            let result_digest: Option<String> = row.try_get("result_digest")?;
            let artifact_digest: Option<String> = row.try_get("artifact_digest")?;
            let sha: Option<String> = row.try_get("integration_sha")?;
            if row.try_get::<String, _>("status")? != "completed"
                || result.is_none()
                || result_digest.is_none()
                || artifact_digest.is_none()
                || sha.is_none()
                || result_digest.as_ref() != Some(&workflow_digest(&result)?)
            {
                bail!("workflow gate requires validated and integrated task evidence");
            }
            evidence.push(TaskEvidence {
                id: row.try_get("logical_id")?,
                result_digest,
                artifact_digest,
                integration_sha: sha,
            });
        }
        if evidence.len() != expected {
            bail!("workflow gate is missing task evidence");
        }
        workflow_digest(&evidence)?
    };
    Ok(ApprovalState {
        plan,
        workspace_id: row.try_get("workspace_id")?,
        integration_sha,
        evidence_digest,
    })
}

#[derive(Serialize)]
struct TaskEvidence {
    id: String,
    result_digest: Option<String>,
    artifact_digest: Option<String>,
    integration_sha: Option<String>,
}
