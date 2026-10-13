//! `runs.gates` and `runs.gate`: gates with the evidence a person decides
//! on. A plan gate shows its plan revision; a stage gate shows the results,
//! digests and integrations of its stage and the stages before it.

use std::collections::BTreeSet;

use anyhow::{anyhow, Result};
use serde::Serialize;
use sqlx::Row;

use super::run_gate_resolution::{run_gate_from_row, RUN_GATE_COLUMNS};
use super::{RunGate, RunGateKind, RunPlanView, RuntimeStore, WorkflowPlanSnapshot};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunGateEvidenceTask {
    pub task_id: String,
    pub logical_id: Option<String>,
    pub title: String,
    pub stage_id: Option<String>,
    pub status: String,
    pub result_preview: Option<String>,
    pub result_truncated: bool,
    pub result_digest: Option<String>,
    pub artifact_digest: Option<String>,
    pub integration_sha: Option<String>,
    pub integration_state: Option<String>,
    pub conflict_paths: Vec<String>,
    pub assignee: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunGateDetail {
    pub gate: RunGate,
    /// Plan gates: the plan revision being approved.
    pub plan: Option<RunPlanView>,
    /// Stage gates: every task of the stage and of its prerequisites.
    /// Decision and stall gates: their task.
    pub tasks: Vec<RunGateEvidenceTask>,
}

#[derive(Debug, Default)]
pub struct RunGateFilter {
    pub run_id: String,
    pub task_id: Option<String>,
    pub kind: Option<RunGateKind>,
    pub status: Option<String>,
}

impl RuntimeStore {
    /// A run's gates, newest first, including the gates of its tasks.
    pub async fn run_gates(&self, filter: &RunGateFilter) -> Result<Vec<RunGate>> {
        let mut sql = format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates WHERE (run_id = ? OR task_id IN
                (SELECT id FROM orchestrationTasks WHERE run_id = ?))"
        );
        if filter.task_id.is_some() {
            sql.push_str(" AND task_id = ?");
        }
        if filter.kind.is_some() {
            sql.push_str(" AND kind = ?");
        }
        if filter.status.is_some() {
            sql.push_str(" AND status = ?");
        }
        sql.push_str(" ORDER BY rowid DESC LIMIT 200");
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql))
            .bind(&filter.run_id)
            .bind(&filter.run_id);
        if let Some(task) = &filter.task_id {
            query = query.bind(task);
        }
        if let Some(kind) = filter.kind {
            query = query.bind(kind.as_str());
        }
        if let Some(status) = &filter.status {
            query = query.bind(status);
        }
        query
            .fetch_all(self.pool())
            .await?
            .into_iter()
            .map(run_gate_from_row)
            .collect()
    }

    pub async fn run_gate_detail(&self, gate_id: &str) -> Result<RunGateDetail> {
        let gate = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates WHERE id = ?"
        )))
        .bind(gate_id)
        .fetch_optional(self.pool())
        .await?
        .map(run_gate_from_row)
        .transpose()?
        .ok_or_else(|| anyhow!("gate_not_found: no gate {gate_id}"))?;
        let run_id = gate.run_id.clone().unwrap_or_default();
        let (plan, tasks) = match gate.kind {
            RunGateKind::Plan => (
                self.run_plan_view(&run_id, gate.plan_revision).await?,
                Vec::new(),
            ),
            RunGateKind::Stage => (None, self.stage_evidence_tasks(&gate).await?),
            RunGateKind::Decision | RunGateKind::Stall => {
                let ids = gate.task_id.iter().cloned().collect::<Vec<_>>();
                (None, self.evidence_tasks(&run_id, None, &ids).await?)
            }
        };
        Ok(RunGateDetail { gate, plan, tasks })
    }

    async fn stage_evidence_tasks(&self, gate: &RunGate) -> Result<Vec<RunGateEvidenceTask>> {
        let run_id = gate.run_id.clone().unwrap_or_default();
        let Some(revision) = gate.plan_revision else {
            return Ok(Vec::new());
        };
        let snapshot: Option<String> = sqlx::query_scalar(
            "SELECT snapshot FROM runPlanRevisions WHERE run_id = ? AND revision = ?",
        )
        .bind(&run_id)
        .bind(revision)
        .fetch_optional(self.pool())
        .await?;
        let mut stages = BTreeSet::from([gate.scope.clone()]);
        if let Some(plan) = snapshot
            .as_deref()
            .and_then(|raw| serde_json::from_str::<WorkflowPlanSnapshot>(raw).ok())
        {
            let mut remaining = vec![gate.scope.clone()];
            while let Some(id) = remaining.pop() {
                if let Some(stage) = plan
                    .recipe
                    .recipe
                    .stages
                    .iter()
                    .find(|stage| stage.id == id)
                {
                    for prior in &stage.depends_on {
                        if stages.insert(prior.clone()) {
                            remaining.push(prior.clone());
                        }
                    }
                }
            }
        }
        let tasks = self.evidence_tasks(&run_id, Some(revision), &[]).await?;
        Ok(tasks
            .into_iter()
            .filter(|task| {
                task.stage_id
                    .as_ref()
                    .is_some_and(|stage| stages.contains(stage))
            })
            .collect())
    }

    async fn evidence_tasks(
        &self,
        run_id: &str,
        revision: Option<i64>,
        ids: &[String],
    ) -> Result<Vec<RunGateEvidenceTask>> {
        sqlx::query(
            "SELECT t.id, t.logical_id, t.stage_id, t.status,
                substr(COALESCE(t.display_name, t.task_title, t.spec), 1, 256) AS title,
                substr(t.result, 1, 1024) AS result_preview,
                COALESCE(length(t.result) > 1024, 0) AS result_truncated,
                e.result_digest, e.artifact_digest, e.integration_sha,
                CASE WHEN i.cancelled = 1 THEN 'cancelled' ELSE i.state END AS integration_state,
                i.conflict_paths,
                (SELECT assignee_handle FROM orchestrationDispatchContexts d
                    WHERE d.task_id = t.id ORDER BY rowid DESC LIMIT 1) AS assignee
            FROM orchestrationTasks t
            LEFT JOIN runTaskEvidence e ON e.task_id = t.id
            LEFT JOIN runIntegrations i ON i.sequence =
                (SELECT MAX(sequence) FROM runIntegrations WHERE task_id = t.id)
            WHERE t.run_id = ? AND (? IS NULL OR t.plan_revision = ?)
              AND (? = 0 OR t.id IN (SELECT value FROM json_each(?)))
            ORDER BY t.logical_id, t.id LIMIT 129",
        )
        .bind(run_id)
        .bind(revision)
        .bind(revision)
        .bind(!ids.is_empty())
        .bind(serde_json::to_string(ids)?)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(|row| {
            Ok(RunGateEvidenceTask {
                task_id: row.try_get("id")?,
                logical_id: row.try_get("logical_id")?,
                title: row.try_get("title")?,
                stage_id: row.try_get("stage_id")?,
                status: row.try_get("status")?,
                result_preview: row.try_get("result_preview")?,
                result_truncated: row.try_get("result_truncated")?,
                result_digest: row.try_get("result_digest")?,
                artifact_digest: row.try_get("artifact_digest")?,
                integration_sha: row.try_get("integration_sha")?,
                integration_state: row.try_get("integration_state")?,
                conflict_paths: row
                    .try_get::<Option<String>, _>("conflict_paths")?
                    .and_then(|raw| serde_json::from_str(&raw).ok())
                    .unwrap_or_default(),
                assignee: row.try_get("assignee")?,
            })
        })
        .collect()
    }
}
