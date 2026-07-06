use anyhow::{anyhow, bail, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::Row;
use sqlx::{Sqlite, Transaction};

use super::orchestration_message_store::orchestration_id;
use super::{OrchestrationTask, OrchestrationTaskStatus, RuntimeStore};

pub struct NewOrchestrationTask {
    pub spec: String,
    pub task_title: Option<String>,
    pub display_name: Option<String>,
    pub deps: Vec<String>,
    pub parent_id: Option<String>,
    pub created_by_terminal_handle: Option<String>,
}

const TASK_COLUMNS: &str = "id, parent_id, created_by_terminal_handle, task_title, \
     display_name, spec, status, deps, result, created_at, completed_at";

pub(super) fn parse_string_array(raw: &str) -> Vec<String> {
    serde_json::from_str::<Vec<String>>(raw).unwrap_or_default()
}

fn task_from_row(row: SqliteRow) -> Result<OrchestrationTask> {
    let status_raw: String = row.try_get("status")?;
    let deps_raw: String = row.try_get("deps")?;
    Ok(OrchestrationTask {
        id: row.try_get("id")?,
        parent_id: row.try_get("parent_id")?,
        created_by_terminal_handle: row.try_get("created_by_terminal_handle")?,
        task_title: row.try_get("task_title")?,
        display_name: row.try_get("display_name")?,
        spec: row.try_get("spec")?,
        status: OrchestrationTaskStatus::parse(&status_raw)
            .unwrap_or(OrchestrationTaskStatus::Pending),
        deps: parse_string_array(&deps_raw),
        result: row.try_get("result")?,
        created_at: row.try_get("created_at")?,
        completed_at: row.try_get("completed_at")?,
        assignee_handle: None,
        dispatch_id: None,
    })
}

/// Derives UI display metadata from the spec when explicit titles are absent:
/// the first non-empty spec line, truncated to 80 chars.
fn derive_display_name(spec: &str) -> String {
    let line = spec
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("task");
    let mut name: String = line.chars().take(80).collect();
    if line.chars().count() > 80 {
        name.push('…');
    }
    name
}

async fn status_for_deps(
    tx: &mut Transaction<'_, Sqlite>,
    deps: &[String],
) -> Result<OrchestrationTaskStatus> {
    if deps.is_empty() {
        return Ok(OrchestrationTaskStatus::Ready);
    }
    let mut all_completed = true;
    for dep in deps {
        let dep_status: Option<String> =
            sqlx::query("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(dep)
                .fetch_optional(&mut **tx)
                .await?
                .map(|dep_row| dep_row.try_get("status"))
                .transpose()?;
        match dep_status.as_deref() {
            None => bail!("unknown orchestration task dependency: {dep}"),
            Some("completed") => {}
            Some("failed") => return Ok(OrchestrationTaskStatus::Failed),
            _ => all_completed = false,
        }
    }
    Ok(if all_completed {
        OrchestrationTaskStatus::Ready
    } else {
        OrchestrationTaskStatus::Pending
    })
}

pub(super) async fn refresh_pending_dependents_after_task_status(
    tx: &mut Transaction<'_, Sqlite>,
    changed_task_id: &str,
) -> Result<()> {
    let mut changed_ids = vec![changed_task_id.to_string()];
    while let Some(changed_id) = changed_ids.pop() {
        let pending =
            sqlx::query("SELECT id, deps FROM orchestrationTasks WHERE status = 'pending'")
                .fetch_all(&mut **tx)
                .await?;
        for row in pending {
            let candidate_id: String = row.try_get("id")?;
            let deps_raw: String = row.try_get("deps")?;
            let deps = parse_string_array(&deps_raw);
            if !deps.iter().any(|dep| dep == &changed_id) {
                continue;
            }
            match status_for_deps(tx, &deps).await? {
                OrchestrationTaskStatus::Ready => {
                    sqlx::query("UPDATE orchestrationTasks SET status = 'ready' WHERE id = ?")
                        .bind(&candidate_id)
                        .execute(&mut **tx)
                        .await?;
                }
                OrchestrationTaskStatus::Failed => {
                    let result = format!("dependency failed: {changed_id}");
                    sqlx::query(
                        "UPDATE orchestrationTasks \
                         SET status = 'failed', result = COALESCE(result, ?), completed_at = datetime('now') \
                         WHERE id = ?",
                    )
                    .bind(result)
                    .bind(&candidate_id)
                    .execute(&mut **tx)
                    .await?;
                    changed_ids.push(candidate_id);
                }
                _ => {}
            }
        }
    }
    Ok(())
}

impl RuntimeStore {
    pub async fn create_orchestration_task(
        &self,
        task: NewOrchestrationTask,
    ) -> Result<OrchestrationTask> {
        let id = orchestration_id("task");
        let mut tx = self.pool().begin().await?;
        let status = status_for_deps(&mut tx, &task.deps).await?;
        let display_name = task
            .display_name
            .clone()
            .or_else(|| task.task_title.clone())
            .unwrap_or_else(|| derive_display_name(&task.spec));
        sqlx::query(
            "INSERT INTO orchestrationTasks \
             (id, parent_id, created_by_terminal_handle, task_title, display_name, spec, status, deps) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&task.parent_id)
        .bind(&task.created_by_terminal_handle)
        .bind(&task.task_title)
        .bind(&display_name)
        .bind(&task.spec)
        .bind(status.as_str())
        .bind(serde_json::to_string(&task.deps)?)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.orchestration_task_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted orchestration task not found"))
    }

    pub async fn orchestration_task_by_id(&self, id: &str) -> Result<Option<OrchestrationTask>> {
        let row = sqlx::query(&format!(
            "SELECT {TASK_COLUMNS} FROM orchestrationTasks WHERE id = ?"
        ))
        .bind(id)
        .fetch_optional(self.pool())
        .await?;
        row.map(task_from_row).transpose()
    }

    /// Lists tasks joined with their most-recent active dispatch context so a
    /// coordinator can answer "who is working on task X" in one query.
    pub async fn list_orchestration_tasks(
        &self,
        status: Option<OrchestrationTaskStatus>,
    ) -> Result<Vec<OrchestrationTask>> {
        let mut sql = format!(
            "SELECT {TASK_COLUMNS}, \
             (SELECT assignee_handle FROM orchestrationDispatchContexts \
              WHERE task_id = orchestrationTasks.id AND status IN ('pending','dispatched') \
              ORDER BY rowid DESC LIMIT 1) AS active_assignee, \
             (SELECT id FROM orchestrationDispatchContexts \
              WHERE task_id = orchestrationTasks.id AND status IN ('pending','dispatched') \
              ORDER BY rowid DESC LIMIT 1) AS active_dispatch_id \
             FROM orchestrationTasks"
        );
        if status.is_some() {
            sql.push_str(" WHERE status = ?");
        }
        sql.push_str(" ORDER BY created_at ASC, id ASC");
        let mut query = sqlx::query(&sql);
        if let Some(status) = status {
            query = query.bind(status.as_str());
        }
        let rows = query.fetch_all(self.pool()).await?;
        rows.into_iter()
            .map(|row| {
                let assignee: Option<String> = row.try_get("active_assignee")?;
                let dispatch_id: Option<String> = row.try_get("active_dispatch_id")?;
                let mut task = task_from_row(row)?;
                task.assignee_handle = assignee;
                task.dispatch_id = dispatch_id;
                Ok(task)
            })
            .collect()
    }

    /// Sets a task's status. Completing a task promotes dependents and closes
    /// its active dispatch in the same transaction, so there is no window
    /// where a dependency is satisfied but the child is still `pending`.
    pub async fn update_orchestration_task_status(
        &self,
        id: &str,
        status: OrchestrationTaskStatus,
        result: Option<&str>,
    ) -> Result<OrchestrationTask> {
        let mut tx = self.pool().begin().await?;
        let existing = sqlx::query("SELECT id FROM orchestrationTasks WHERE id = ?")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
        if existing.is_none() {
            bail!("orchestration task not found: {id}");
        }
        let terminal = matches!(
            status,
            OrchestrationTaskStatus::Completed | OrchestrationTaskStatus::Failed
        );
        if terminal {
            sqlx::query(
                "UPDATE orchestrationTasks SET status = ?, result = COALESCE(?, result), \
                 completed_at = datetime('now') WHERE id = ?",
            )
            .bind(status.as_str())
            .bind(result)
            .bind(id)
            .execute(&mut *tx)
            .await?;
            // DAG refresh: completed deps promote dependents; failed deps make
            // still-pending dependents terminal instead of leaving the run stuck.
            refresh_pending_dependents_after_task_status(&mut tx, id).await?;
            let dispatch_status = if status == OrchestrationTaskStatus::Completed {
                "completed"
            } else {
                "failed"
            };
            sqlx::query(
                "UPDATE orchestrationDispatchContexts \
                 SET status = ?, completed_at = datetime('now') \
                 WHERE task_id = ? AND status IN ('pending','dispatched')",
            )
            .bind(dispatch_status)
            .bind(id)
            .execute(&mut *tx)
            .await?;
        } else {
            sqlx::query(
                "UPDATE orchestrationTasks SET status = ?, result = COALESCE(?, result) \
                 WHERE id = ?",
            )
            .bind(status.as_str())
            .bind(result)
            .bind(id)
            .execute(&mut *tx)
            .await?;
            if status != OrchestrationTaskStatus::Dispatched {
                let reason = format!("task status changed to {}", status.as_str());
                sqlx::query(
                    "UPDATE orchestrationDispatchContexts \
                     SET status = 'failed', last_failure = COALESCE(last_failure, ?), \
                     completed_at = datetime('now') \
                     WHERE task_id = ? AND status IN ('pending','dispatched')",
                )
                .bind(reason)
                .bind(id)
                .execute(&mut *tx)
                .await?;
            }
        }
        tx.commit().await?;
        self.orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("orchestration task not found after update: {id}"))
    }

    pub async fn reset_orchestration_tasks(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("DELETE FROM orchestrationTasks")
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM orchestrationDispatchContexts")
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM orchestrationDecisionGates")
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM orchestrationCoordinatorRuns")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }
}
