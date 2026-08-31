use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;

use crate::git::WorkflowIntegrationReceipt;

use super::orchestration_board_store::BOARD_REVISION_SQL;
use super::RuntimeStore;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OrchestrationTaskInspectionQuery {
    pub run_id: String,
    pub task_id: String,
    pub cursor: Option<TaskHistoryCursor>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TaskHistoryCursor {
    pub occurred_at: String,
    pub id: String,
    pub revision: i64,
}

#[derive(Debug, Serialize)]
pub struct OrchestrationTaskInspection {
    pub revision: i64,
    pub task_id: String,
    pub run_id: String,
    pub title: String,
    pub description: String,
    pub description_truncated: bool,
    pub status: String,
    pub stage_id: Option<String>,
    pub workspace_id: String,
    pub workspace_name: Option<String>,
    pub workspace_path: Option<String>,
    pub branch: Option<String>,
    // Legacy dispatches do not capture a Git base. Never substitute today's HEAD.
    pub base_sha: Option<String>,
    pub profile: Option<String>,
    pub terminal_handle: Option<String>,
    pub dependencies: Vec<String>,
    pub dependencies_truncated: bool,
    pub result: TaskResultInspection,
    pub history: Vec<TaskHistoryEntry>,
    pub next_cursor: Option<TaskHistoryCursor>,
    pub workflow: Option<TaskWorkflowInspection>,
}

#[derive(Debug, Serialize)]
pub struct TaskWorkflowInspection {
    pub state: String,
    pub integration_id: Option<String>,
    pub launch_id: Option<String>,
    pub execution_workspace_id: String,
    pub worktree: Option<String>,
    pub branch: Option<String>,
    pub base_sha: Option<String>,
    pub integrated_sha: Option<String>,
    pub conflict_paths: Vec<String>,
    pub conflicts_truncated: bool,
    pub error: Option<String>,
}

#[derive(Debug, Default, Serialize)]
pub struct TaskResultInspection {
    pub summary: Option<String>,
    pub completion_kind: Option<String>,
    pub artifacts: Vec<String>,
    pub validation: Vec<String>,
    pub preview: Option<String>,
    pub truncated: bool,
}

#[derive(Debug, Serialize)]
pub struct TaskHistoryEntry {
    pub id: String,
    pub occurred_at: String,
    pub kind: String,
    pub status: String,
    pub summary: Option<String>,
}

impl RuntimeStore {
    pub async fn orchestration_task_inspection(
        &self,
        query: &OrchestrationTaskInspectionQuery,
    ) -> Result<OrchestrationTaskInspection> {
        let limit = query.limit.unwrap_or(20);
        if !(1..=100).contains(&limit)
            || [&query.run_id, &query.task_id]
                .iter()
                .any(|id| id.is_empty() || id.len() > 256)
            || query.cursor.as_ref().is_some_and(|cursor| {
                cursor.id.is_empty() || cursor.id.len() > 256 || cursor.occurred_at.len() > 128
            })
        {
            bail!("invalid task inspection query");
        }
        let mut tx = self.pool().begin().await?;
        let revision: i64 = sqlx::query_scalar(BOARD_REVISION_SQL)
            .fetch_one(&mut *tx)
            .await?;
        if query
            .cursor
            .as_ref()
            .is_some_and(|c| c.revision != revision)
        {
            bail!("board cursor is stale; refresh the first page");
        }
        let row = sqlx::query(
            "SELECT t.id, t.run_id, t.workspace_id, t.status, t.stage_id,
                substr(COALESCE(t.display_name, t.task_title, t.spec), 1, 256) AS title,
                substr(t.spec, 1, 16384) AS description, length(t.spec) > 16384 AS truncated,
                CASE WHEN length(t.deps) <= 16384 THEN t.deps END AS deps,
                substr(t.result, 1, 65536) AS result,
                COALESCE(length(t.result) > 65536, 0) AS result_truncated,
                substr(w.name, 1, 256) AS workspace_name,
                substr(w.path, 1, 4096) AS workspace_path,
                substr(w.branch, 1, 256) AS branch
             FROM orchestrationTasks t LEFT JOIN workspaces w ON w.id = t.workspace_id
             WHERE t.id = ? AND t.run_id = ?",
        )
        .bind(&query.task_id)
        .bind(&query.run_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| anyhow!("task not found in this run"))?;
        let dispatch = sqlx::query(
            "SELECT substr(agent_profile, 1, 256) AS profile,
                CASE WHEN length(assignee_handle) <= 256 THEN assignee_handle END AS assignee_handle
             FROM orchestrationDispatchContexts WHERE task_id = ? AND run_id = ?
             ORDER BY rowid DESC LIMIT 1",
        )
        .bind(&query.task_id)
        .bind(&query.run_id)
        .fetch_optional(&mut *tx)
        .await?;
        let workflow = inspect_workflow_task(&mut tx, &query.run_id, &query.task_id).await?;
        let deps: Option<String> = row.try_get("deps")?;
        let (dependencies, dependencies_truncated) = bounded_dependencies(deps.as_deref());
        let result: Option<String> = row.try_get("result")?;
        let result = inspect_result(result.as_deref(), row.try_get("result_truncated")?);
        let cursor_time = query.cursor.as_ref().map(|c| c.occurred_at.as_str());
        let cursor_id = query.cursor.as_ref().map(|c| c.id.as_str());
        // Return only explicit display fields. Dispatch context hashes, profile
        // commands and arbitrary audit payloads never enter this projection.
        let history_rows = sqlx::query(
            "WITH history AS (
                SELECT id, COALESCE(completed_at, dispatched_at, created_at) AS occurred_at,
                    'attempt' AS kind, status, substr(agent_profile, 1, 256) AS summary
                FROM orchestrationDispatchContexts WHERE task_id = ? AND run_id = ?
                UNION ALL
                SELECT id, created_at AS occurred_at, 'audit' AS kind,
                    substr(action, 1, 256) AS status, substr(reason, 1, 2048) AS summary
                FROM orchestrationAuditEvents WHERE target_id = ? OR target_id IN (
                    SELECT id FROM orchestrationDispatchContexts WHERE task_id = ? AND run_id = ?
                )
                UNION ALL
                SELECT id, updated_at AS occurred_at, 'workflowLaunch' AS kind,
                    status, substr(error, 1, 2048) AS summary
                FROM workflowLaunches WHERE task_id = ? AND run_id = ?
                UNION ALL
                SELECT id, updated_at AS occurred_at, 'workflowIntegration' AS kind,
                    state AS status, substr(error, 1, 2048) AS summary
                FROM workflowIntegrations WHERE task_id = ? AND run_id = ?
             )
             SELECT * FROM history
             WHERE (? IS NULL OR occurred_at < ? OR (occurred_at = ? AND id < ?))
             ORDER BY occurred_at DESC, id DESC LIMIT ?",
        )
        .bind(&query.task_id)
        .bind(&query.run_id)
        .bind(&query.task_id)
        .bind(&query.task_id)
        .bind(&query.run_id)
        .bind(&query.task_id)
        .bind(&query.run_id)
        .bind(&query.task_id)
        .bind(&query.run_id)
        .bind(cursor_time)
        .bind(cursor_time)
        .bind(cursor_time)
        .bind(cursor_id)
        .bind(i64::from(limit) + 1)
        .fetch_all(&mut *tx)
        .await?;
        let mut history = history_rows
            .into_iter()
            .map(|row| {
                Ok(TaskHistoryEntry {
                    id: row.try_get("id")?,
                    occurred_at: row.try_get("occurred_at")?,
                    kind: row.try_get("kind")?,
                    status: row.try_get("status")?,
                    summary: row.try_get("summary")?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let has_more = history.len() > limit as usize;
        history.truncate(limit as usize);
        let next_cursor = history
            .last()
            .filter(|_| has_more)
            .map(|entry| TaskHistoryCursor {
                occurred_at: entry.occurred_at.clone(),
                id: entry.id.clone(),
                revision,
            });
        let inspection = OrchestrationTaskInspection {
            revision,
            task_id: row.try_get("id")?,
            run_id: row.try_get("run_id")?,
            title: row.try_get("title")?,
            description: row.try_get("description")?,
            description_truncated: row.try_get("truncated")?,
            status: row.try_get("status")?,
            stage_id: row.try_get("stage_id")?,
            workspace_id: row.try_get("workspace_id")?,
            workspace_name: row.try_get("workspace_name")?,
            workspace_path: row.try_get("workspace_path")?,
            branch: row.try_get("branch")?,
            base_sha: None,
            profile: dispatch
                .as_ref()
                .map(|d| d.try_get("profile"))
                .transpose()?
                .flatten(),
            terminal_handle: dispatch
                .as_ref()
                .map(|d| d.try_get("assignee_handle"))
                .transpose()?
                .flatten(),
            dependencies,
            dependencies_truncated,
            result,
            history,
            next_cursor,
            workflow,
        };
        tx.commit().await?;
        Ok(inspection)
    }
}

async fn inspect_workflow_task(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    run: &str,
    task: &str,
) -> Result<Option<TaskWorkflowInspection>> {
    let Some(row) = sqlx::query("SELECT x.id AS workspace_id, w.path, w.branch,
            json_extract(x.identity, '$.baseSha') AS base_sha,
            l.id AS launch_id, l.status AS launch_status, l.error AS launch_error,
            i.id AS integration_id, i.state AS integration_state, i.receipt,
            i.conflict_paths, i.conflicts_truncated, i.error AS integration_error,
            e.task_id AS evidence_id, t.status AS task_status, t.result IS NOT NULL AS has_result
        FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id = p.task_id
        JOIN workflowWorkspaces x ON x.sequence = (SELECT MAX(sequence) FROM workflowWorkspaces WHERE task_id = p.task_id)
        LEFT JOIN workspaces w ON w.id = x.id
        LEFT JOIN workflowLaunches l ON l.workspace_id = x.id
        LEFT JOIN workflowIntegrations i ON i.sequence = (SELECT MAX(sequence) FROM workflowIntegrations WHERE task_id = p.task_id)
        LEFT JOIN workflowTaskEvidence e ON e.task_id = p.task_id
        WHERE p.run_id = ? AND p.task_id = ?")
        .bind(run).bind(task).fetch_optional(&mut **tx).await? else { return Ok(None); };
    let integration_state: Option<String> = row.try_get("integration_state")?;
    let launch_state: Option<String> = row.try_get("launch_status")?;
    let task_state: String = row.try_get("task_status")?;
    let has_result: bool = row.try_get("has_result")?;
    let state = if integration_state.as_deref() == Some("integrated")
        && row.try_get::<Option<String>, _>("evidence_id")?.is_some()
    {
        "integrated"
    } else if integration_state.as_deref() == Some("integrated") {
        "attention"
    } else if integration_state.as_deref() == Some("conflict") {
        "conflict"
    } else if integration_state.as_deref() == Some("attention")
        || launch_state.as_deref() == Some("attention")
        || task_state == "failed"
    {
        "attention"
    } else if task_state == "completed" && has_result {
        "result_ready"
    } else {
        match launch_state.as_deref() {
            Some(state @ ("reserved" | "starting" | "started")) => state,
            _ => return Ok(None),
        }
    };
    let receipt: Option<String> = row.try_get("receipt")?;
    let integrated_sha = receipt
        .as_deref()
        .and_then(|raw| serde_json::from_str::<WorkflowIntegrationReceipt>(raw).ok())
        .map(|receipt| receipt.integrated_sha);
    let conflict_paths = row
        .try_get::<Option<String>, _>("conflict_paths")?
        .and_then(|raw| serde_json::from_str::<Vec<String>>(&raw).ok())
        .unwrap_or_default();
    Ok(Some(TaskWorkflowInspection {
        state: state.into(),
        integration_id: row.try_get("integration_id")?,
        launch_id: row.try_get("launch_id")?,
        execution_workspace_id: row.try_get("workspace_id")?,
        worktree: row.try_get("path")?,
        branch: row.try_get("branch")?,
        base_sha: row.try_get("base_sha")?,
        integrated_sha,
        conflict_paths,
        conflicts_truncated: row
            .try_get::<Option<bool>, _>("conflicts_truncated")?
            .unwrap_or(false),
        error: row
            .try_get::<Option<String>, _>("integration_error")?
            .or(row.try_get("launch_error")?),
    }))
}

pub(super) fn bounded_dependencies(raw: Option<&str>) -> (Vec<String>, bool) {
    let Some(Value::Array(values)) = raw.and_then(|s| serde_json::from_str(s).ok()) else {
        return (Vec::new(), true);
    };
    let truncated = values.len() > 100
        || values
            .iter()
            .any(|v| v.as_str().is_none_or(|id| id.len() > 256));
    let dependencies = values
        .into_iter()
        .filter_map(|value| {
            value
                .as_str()
                .filter(|id| id.len() <= 256)
                .map(str::to_owned)
        })
        .take(100)
        .collect();
    (dependencies, truncated)
}

fn inspect_result(raw: Option<&str>, mut truncated: bool) -> TaskResultInspection {
    let Some(raw) = raw else {
        return TaskResultInspection::default();
    };
    let parsed: Option<Value> = if truncated {
        None
    } else {
        serde_json::from_str(raw).ok()
    };
    let Some(Value::Object(fields)) = parsed else {
        return TaskResultInspection {
            preview: Some(bounded_text(raw, 16384, &mut truncated)),
            truncated,
            ..Default::default()
        };
    };
    let mut field_text = |key| {
        fields
            .get(key)
            .and_then(Value::as_str)
            .map(|text| bounded_text(text, 16384, &mut truncated))
    };
    let summary = field_text("summary");
    let completion_kind = field_text("completionKind");
    let artifacts = result_entries(fields.get("artifacts"), &mut truncated);
    let validation = result_entries(fields.get("validation"), &mut truncated);
    let preview = summary
        .is_none()
        .then(|| bounded_text(raw, 16384, &mut truncated));
    TaskResultInspection {
        summary,
        completion_kind,
        artifacts,
        validation,
        preview,
        truncated,
    }
}

fn result_entries(value: Option<&Value>, truncated: &mut bool) -> Vec<String> {
    let Some(values) = value.and_then(Value::as_array) else {
        return Vec::new();
    };
    *truncated |= values.len() > 32;
    values
        .iter()
        .take(32)
        .map(|value| {
            let text = value
                .as_str()
                .map(str::to_owned)
                .unwrap_or_else(|| value.to_string());
            bounded_text(&text, 2048, truncated)
        })
        .collect()
}

fn bounded_text(text: &str, limit: usize, truncated: &mut bool) -> String {
    let mut chars = text.chars();
    let result = chars.by_ref().take(limit).collect();
    *truncated |= chars.next().is_some();
    result
}
