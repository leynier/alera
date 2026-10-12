//! `runs.snapshot`: one run with its plan, coordinator, integration,
//! pending gates, cleanup and a page of tasks.

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::orchestration_board_store::{
    attach_pending_gates, summary_from_row, BOARD_REVISION_SQL,
};
use super::orchestration_task_inspection::bounded_dependencies;
use super::run_gate_resolution::{run_gate_from_row, RUN_GATE_COLUMNS};
use super::{OrchestrationRunSummary, RunGate, RuntimeStore};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OrchestrationRunSnapshotQuery {
    pub run_id: String,
    pub after_task_id: Option<String>,
    pub revision: Option<i64>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunTaskAttempt {
    pub workspace_id: String,
    pub attempt: i64,
    pub branch: Option<String>,
    pub base_sha: Option<String>,
    pub phase: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunTaskIntegration {
    pub state: String,
    pub sha: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrchestrationTaskSummary {
    pub id: String,
    pub logical_id: Option<String>,
    pub title: String,
    pub status: String,
    pub stage_id: Option<String>,
    pub role_id: Option<String>,
    pub plan_revision: Option<i64>,
    pub workspace_id: String,
    pub dependencies: Vec<String>,
    pub dependencies_truncated: bool,
    /// Isolated attempt progress: `reserved`, `ready`, `starting`, `started`,
    /// `result_ready`, `integrated`, `conflict`, `refused`, `attention`,
    /// `stalled` or `cancelled`. Absent for shared runs.
    pub attempt_state: Option<String>,
    pub attempt: Option<RunTaskAttempt>,
    pub integration: Option<RunTaskIntegration>,
    pub profile: Option<String>,
    pub assignee: Option<String>,
    /// When the latest dispatch of the task started.
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    /// The newest of the task's own and its latest dispatch's timestamps.
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunPlanSummary {
    pub revision: i64,
    pub digest: String,
    pub previous_revision: Option<i64>,
    pub change_reason: Option<String>,
    /// `planning` (a change request placeholder), `awaitingApproval`,
    /// `approved` or `superseded`.
    pub state: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunCoordinatorSummary {
    pub handle: Option<String>,
    pub tab_id: Option<String>,
    pub profile_id: Option<String>,
    /// `none`, `reserved`, `started` or `attention`.
    pub state: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunIntegrationSummary {
    pub workspace_id: Option<String>,
    pub branch: Option<String>,
    pub sha: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunCleanupSummary {
    pub id: String,
    pub state: String,
    pub error: Option<String>,
    pub abandoned: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrchestrationRunSnapshot {
    pub revision: i64,
    pub run: OrchestrationRunSummary,
    pub objective: String,
    pub objective_truncated: bool,
    pub control_sequence: i64,
    pub stall_policy: String,
    pub max_concurrent: i64,
    pub stop_reason: Option<String>,
    pub recipe_source: Option<serde_json::Value>,
    pub source_sha: Option<String>,
    pub plan: Option<RunPlanSummary>,
    pub coordinator: RunCoordinatorSummary,
    pub integration: Option<RunIntegrationSummary>,
    pub pending_gates: Vec<RunGate>,
    pub cleanup: Option<RunCleanupSummary>,
    /// Worktrees and branches an isolated run still retains (not retired by
    /// a cleanup). Zero for shared runs.
    pub resource_count: i64,
    pub tasks: Vec<OrchestrationTaskSummary>,
    pub next_task_id: Option<String>,
}

impl RuntimeStore {
    pub async fn orchestration_run_snapshot(
        &self,
        query: &OrchestrationRunSnapshotQuery,
    ) -> Result<OrchestrationRunSnapshot> {
        let limit = query.limit.unwrap_or(100);
        if !(1..=200).contains(&limit)
            || query.run_id.is_empty()
            || query.run_id.len() > 256
            || query
                .after_task_id
                .as_ref()
                .is_some_and(|id| id.len() > 256)
        {
            bail!("invalid run snapshot query");
        }
        let mut tx = self.pool().begin().await?;
        let revision: i64 = sqlx::query(BOARD_REVISION_SQL)
            .fetch_one(&mut *tx)
            .await?
            .try_get("revision")?;
        if query.after_task_id.is_some() && query.revision != Some(revision) {
            bail!("board cursor is stale; refresh the first page");
        }
        let row = sqlx::query("SELECT * FROM orchestrationBoardRuns WHERE id = ?")
            .bind(&query.run_id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| anyhow!("run_not_found: no run {}", query.run_id))?;
        let mut run = summary_from_row(row)?;
        attach_pending_gates(&mut tx, std::slice::from_mut(&mut run)).await?;
        let row = sqlx::query(
            "SELECT substr(spec, 1, 16384) AS objective, length(spec) > 16384 AS truncated,
                control_sequence, stall_policy, max_concurrent, stop_reason, recipe_source,
                json_extract(source_snapshot, '$.sourceSha') AS source_sha,
                coordinator_handle, coordinator_tab_id, coordinator_profile_id,
                coordinator_state, coordinator_error, integration_workspace_id,
                integration_branch, integration_sha, plan_revision, isolation
             FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(&query.run_id)
        .fetch_one(&mut *tx)
        .await?;
        let plan = match row.try_get::<Option<i64>, _>("plan_revision")? {
            Some(plan_revision) => {
                let plan = sqlx::query(
                    "SELECT revision, digest, previous_revision, change_reason, request_id
                    FROM runPlanRevisions WHERE run_id = ? AND revision = ?",
                )
                .bind(&query.run_id)
                .bind(plan_revision)
                .fetch_one(&mut *tx)
                .await?;
                let placeholder = plan
                    .try_get::<String, _>("request_id")?
                    .starts_with("changes:");
                Some(RunPlanSummary {
                    revision: plan.try_get("revision")?,
                    digest: plan.try_get("digest")?,
                    previous_revision: plan.try_get("previous_revision")?,
                    change_reason: plan.try_get("change_reason")?,
                    state: if placeholder {
                        "planning"
                    } else if run.plan_gate_pending {
                        "awaitingApproval"
                    } else {
                        "approved"
                    }
                    .into(),
                })
            }
            None => None,
        };
        let isolated = row.try_get::<String, _>("isolation")? == "isolated";
        let integration_sha: Option<String> = row.try_get("integration_sha")?;
        let integration = isolated.then(|| -> Result<RunIntegrationSummary> {
            Ok(RunIntegrationSummary {
                workspace_id: row.try_get("integration_workspace_id")?,
                branch: row.try_get("integration_branch")?,
                sha: integration_sha.clone(),
            })
        });
        let mut integration = integration.transpose()?;
        if let Some(summary) = integration
            .as_mut()
            .filter(|summary| summary.workspace_id.is_none())
        {
            if let Some(workspace) = sqlx::query(
                "SELECT x.id, w.branch FROM runWorkspaces x LEFT JOIN workspaces w ON w.id = x.id
                WHERE x.run_id = ? AND x.task_id IS NULL",
            )
            .bind(&query.run_id)
            .fetch_optional(&mut *tx)
            .await?
            {
                summary.workspace_id = workspace.try_get("id")?;
                summary.branch = workspace.try_get("branch")?;
            }
        }
        let pending_gates = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates g WHERE g.run_id = ? AND {}
             ORDER BY rowid DESC LIMIT 50",
            super::orchestration_board_schema::DUE_GATE_SQL.replace("{gate}", "g")
        )))
        .bind(&query.run_id)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .map(run_gate_from_row)
        .collect::<Result<Vec<_>>>()?;
        let cleanup = sqlx::query(
            "SELECT id, state, error, abandoned FROM runCleanup WHERE run_id = ?
            ORDER BY rowid DESC LIMIT 1",
        )
        .bind(&query.run_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(|cleanup| -> Result<RunCleanupSummary> {
            Ok(RunCleanupSummary {
                id: cleanup.try_get("id")?,
                state: cleanup.try_get("state")?,
                error: cleanup.try_get("error")?,
                abandoned: cleanup.try_get("abandoned")?,
            })
        })
        .transpose()?;
        let resource_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM runWorkspaces x WHERE x.run_id = ?
             AND NOT EXISTS(SELECT 1 FROM runCleanupResources c
                 WHERE c.workspace_id = x.id AND c.retired = 1)",
        )
        .bind(&query.run_id)
        .fetch_one(&mut *tx)
        .await?;
        let tasks = self
            .run_task_page(
                &mut tx,
                &query.run_id,
                query.after_task_id.as_deref(),
                limit,
            )
            .await?;
        let (tasks, next_task_id) = tasks;
        let recipe_source: Option<String> = row.try_get("recipe_source")?;
        let snapshot = OrchestrationRunSnapshot {
            revision,
            run,
            objective: row.try_get("objective")?,
            objective_truncated: row.try_get("truncated")?,
            control_sequence: row.try_get("control_sequence")?,
            stall_policy: row.try_get("stall_policy")?,
            max_concurrent: row.try_get("max_concurrent")?,
            stop_reason: row.try_get("stop_reason")?,
            recipe_source: recipe_source
                .as_deref()
                .and_then(|raw| serde_json::from_str(raw).ok()),
            source_sha: row.try_get("source_sha")?,
            plan,
            coordinator: RunCoordinatorSummary {
                handle: row.try_get("coordinator_handle")?,
                tab_id: row.try_get("coordinator_tab_id")?,
                profile_id: row.try_get("coordinator_profile_id")?,
                state: row.try_get("coordinator_state")?,
                error: row.try_get("coordinator_error")?,
            },
            integration,
            pending_gates,
            cleanup,
            resource_count,
            tasks,
            next_task_id,
        };
        tx.commit().await?;
        Ok(snapshot)
    }

    async fn run_task_page(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
        run_id: &str,
        after_task_id: Option<&str>,
        limit: u32,
    ) -> Result<(Vec<OrchestrationTaskSummary>, Option<String>)> {
        let rows = sqlx::query(
            "SELECT t.id, t.logical_id, t.role_id, t.plan_revision,
                substr(COALESCE(t.display_name, t.task_title, t.spec), 1, 256) AS title,
                t.status, t.stage_id, t.workspace_id,
                CASE WHEN length(deps) <= 16384 THEN deps END AS deps,
                x.id AS attempt_workspace, x.attempt, x.phase, xw.branch AS attempt_branch,
                json_extract(x.identity, '$.baseSha') AS attempt_base_sha,
                CASE WHEN i.id IS NULL THEN NULL WHEN i.cancelled = 1 THEN 'cancelled'
                    ELSE i.state END AS integration_state,
                e.integration_sha AS integrated_sha,
                (SELECT substr(agent_profile, 1, 256) FROM orchestrationDispatchContexts d
                    WHERE d.task_id = t.id ORDER BY rowid DESC LIMIT 1) AS profile,
                (SELECT assignee_handle FROM orchestrationDispatchContexts d
                    WHERE d.task_id = t.id ORDER BY rowid DESC LIMIT 1) AS assignee,
                (SELECT dispatched_at FROM orchestrationDispatchContexts d
                    WHERE d.task_id = t.id ORDER BY rowid DESC LIMIT 1) AS started_at,
                t.completed_at,
                max(t.created_at, COALESCE(t.completed_at, ''), COALESCE(t.cancelled_at, ''),
                    COALESCE(t.stalled_at, ''),
                    COALESCE((SELECT max(COALESCE(d.completed_at, ''),
                            COALESCE(d.last_activity_at, ''), COALESCE(d.dispatched_at, ''))
                        FROM orchestrationDispatchContexts d
                        WHERE d.task_id = t.id ORDER BY rowid DESC LIMIT 1), '')) AS updated_at,
                CASE WHEN r.isolation <> 'isolated' OR t.plan_revision IS NULL THEN NULL
                  WHEN i.cancelled=1 THEN 'cancelled'
                  WHEN i.state = 'integrated' AND e.task_id IS NOT NULL THEN 'integrated'
                  WHEN i.state = 'integrated' THEN 'attention'
                  WHEN i.state = 'conflict' AND i.error IS NOT NULL THEN 'refused'
                  WHEN i.state = 'conflict' THEN 'conflict'
                  WHEN i.state = 'attention' OR l.status = 'attention' OR x.phase = 'attention' THEN 'attention'
                  WHEN t.status = 'completed' AND t.result IS NOT NULL THEN 'result_ready'
                  WHEN t.status = 'stalled' THEN 'stalled'
                  WHEN t.status = 'cancelled' THEN 'cancelled'
                  WHEN l.status IN ('reserved','starting','started') THEN l.status
                  WHEN x.phase = 'ready' THEN 'ready'
                  WHEN x.phase IN ('reserved','creating','created','setupRunning') THEN 'reserved'
                 END AS attempt_state
             FROM orchestrationTasks t
             JOIN orchestrationCoordinatorRuns r ON r.id = t.run_id
             LEFT JOIN runWorkspaces x ON x.sequence = (SELECT MAX(sequence) FROM runWorkspaces WHERE task_id = t.id)
             LEFT JOIN workspaces xw ON xw.id = x.id
             LEFT JOIN runLaunches l ON l.workspace_id = x.id
             LEFT JOIN runIntegrations i ON i.sequence = (SELECT MAX(sequence) FROM runIntegrations WHERE task_id = t.id)
             LEFT JOIN runTaskEvidence e ON e.task_id = t.id
             WHERE t.run_id = ? AND (? IS NULL OR t.id > ?)
             ORDER BY t.id LIMIT ?",
        )
        .bind(run_id)
        .bind(after_task_id)
        .bind(after_task_id)
        .bind(i64::from(limit) + 1)
        .fetch_all(&mut **tx)
        .await?;
        let mut tasks = rows
            .into_iter()
            .map(|row| {
                let deps: Option<String> = row.try_get("deps")?;
                let (mut dependencies, mut dependencies_truncated) =
                    bounded_dependencies(deps.as_deref());
                // The ledger needs a preview; the on-demand inspector owns the
                // larger list, keeping a 100-task page cheap for the UI.
                dependencies_truncated |= dependencies.len() > 8;
                dependencies.truncate(8);
                let attempt_workspace: Option<String> = row.try_get("attempt_workspace")?;
                let integration_state: Option<String> = row.try_get("integration_state")?;
                Ok(OrchestrationTaskSummary {
                    id: row.try_get("id")?,
                    logical_id: row.try_get("logical_id")?,
                    title: row.try_get("title")?,
                    status: row.try_get("status")?,
                    stage_id: row.try_get("stage_id")?,
                    role_id: row.try_get("role_id")?,
                    plan_revision: row.try_get("plan_revision")?,
                    workspace_id: row.try_get("workspace_id")?,
                    dependencies,
                    dependencies_truncated,
                    attempt_state: row.try_get("attempt_state")?,
                    attempt: attempt_workspace
                        .map(|workspace_id| -> Result<RunTaskAttempt> {
                            Ok(RunTaskAttempt {
                                workspace_id,
                                attempt: row.try_get("attempt")?,
                                branch: row.try_get("attempt_branch")?,
                                base_sha: row.try_get("attempt_base_sha")?,
                                phase: row.try_get("phase")?,
                            })
                        })
                        .transpose()?,
                    integration: integration_state
                        .map(|state| -> Result<RunTaskIntegration> {
                            Ok(RunTaskIntegration {
                                state,
                                sha: row.try_get("integrated_sha")?,
                            })
                        })
                        .transpose()?,
                    profile: row.try_get("profile")?,
                    assignee: row.try_get("assignee")?,
                    started_at: row.try_get("started_at")?,
                    completed_at: row.try_get("completed_at")?,
                    updated_at: row.try_get("updated_at")?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let has_more = tasks.len() > limit as usize;
        tasks.truncate(limit as usize);
        let next_task_id = tasks
            .last()
            .filter(|_| has_more)
            .map(|task| task.id.clone());
        Ok((tasks, next_task_id))
    }
}
