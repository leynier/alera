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
    pub run_id: Option<String>,
    pub workspace_id: String,
    pub coordinator_handle: String,
    pub result_schema: Option<String>,
}

const TASK_COLUMNS: &str = "id, parent_id, created_by_terminal_handle, task_title, \
     display_name, spec, status, deps, result, created_at, completed_at, run_id, workspace_id, \
     coordinator_handle, result_schema, startup_failure_count, cancelled_at, stalled_at";

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
        run_id: row.try_get("run_id")?,
        workspace_id: row.try_get("workspace_id")?,
        coordinator_handle: row.try_get("coordinator_handle")?,
        result_schema: row.try_get("result_schema")?,
        startup_failure_count: row.try_get("startup_failure_count")?,
        cancelled_at: row.try_get("cancelled_at")?,
        stalled_at: row.try_get("stalled_at")?,
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
            Some("cancelled") => return Ok(OrchestrationTaskStatus::Cancelled),
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
    pub async fn insert_orchestration_audit_event(
        &self,
        actor_handle: Option<&str>,
        action: &str,
        target_id: &str,
        reason: &str,
    ) -> Result<()> {
        let id = orchestration_id("audit");
        sqlx::query(
            "INSERT INTO orchestrationAuditEvents (id, actor_handle, action, target_id, reason) \
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(actor_handle)
        .bind(action)
        .bind(target_id)
        .bind(reason)
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn recover_stalled_orchestration_task(
        &self,
        id: &str,
        status: OrchestrationTaskStatus,
        actor_handle: Option<&str>,
        reason: &str,
        force: bool,
    ) -> Result<OrchestrationTask> {
        if !matches!(
            status,
            OrchestrationTaskStatus::Ready
                | OrchestrationTaskStatus::Failed
                | OrchestrationTaskStatus::Cancelled
        ) {
            bail!("recovery status must be ready, failed, or cancelled");
        }
        let task = self
            .orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("orchestration task not found: {id}"))?;
        if task.status != OrchestrationTaskStatus::Stalled {
            bail!("task {id} is not stalled");
        }
        let result = if status == OrchestrationTaskStatus::Cancelled {
            self.cancel_orchestration_task(id, reason).await?
        } else {
            self.update_orchestration_task_status(id, status, Some(reason))
                .await?
        };
        self.insert_orchestration_audit_event(
            actor_handle,
            if force {
                "task.recover.force"
            } else {
                "task.recover"
            },
            id,
            reason,
        )
        .await?;
        Ok(result)
    }

    pub async fn record_orchestration_task_startup_failure(
        &self,
        id: &str,
        error: &str,
    ) -> Result<OrchestrationTask> {
        let result = sqlx::query(
            "UPDATE orchestrationTasks SET startup_failure_count = startup_failure_count + 1, \
             status = CASE WHEN startup_failure_count + 1 >= 3 THEN 'stalled' ELSE 'ready' END, \
             result = ?, stalled_at = CASE WHEN startup_failure_count + 1 >= 3 THEN datetime('now') ELSE NULL END \
             WHERE id = ? AND status = 'ready' \
             AND NOT EXISTS (SELECT 1 FROM orchestrationDispatchContexts \
                 WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled'))",
        )
        .bind(error)
        .bind(id)
        .bind(id)
        .execute(self.pool())
        .await?;
        if result.rows_affected() == 0 {
            bail!("task startup failure rejected: task is missing or terminal");
        }
        self.orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("task not found after startup failure"))
    }

    pub async fn transfer_orchestration_task_coordinator(
        &self,
        id: &str,
        actor_handle: &str,
        new_coordinator_handle: &str,
        reason: &str,
        force: bool,
    ) -> Result<OrchestrationTask> {
        let task = self
            .orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("orchestration task not found: {id}"))?;
        if !force && task.coordinator_handle != actor_handle {
            bail!("only the current coordinator can transfer this task; use --force for audited recovery");
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationTasks SET coordinator_handle = ? WHERE id = ?")
            .bind(new_coordinator_handle)
            .bind(id)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET coordinator_handle = ? \
             WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
        )
        .bind(new_coordinator_handle)
        .bind(id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.insert_orchestration_audit_event(
            Some(actor_handle),
            if force {
                "task.transfer.force"
            } else {
                "task.transfer"
            },
            id,
            reason,
        )
        .await?;
        self.orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("task not found after transfer"))
    }
    pub async fn bind_manual_tasks_to_run(
        &self,
        run_id: &str,
        workspace_id: &str,
        coordinator_handle: &str,
    ) -> Result<u64> {
        let result = sqlx::query(
            "UPDATE orchestrationTasks SET run_id = ?, \
             workspace_id = CASE WHEN workspace_id = 'global' THEN ? ELSE workspace_id END \
             WHERE run_id IS NULL AND workspace_id IN (?, 'global') AND coordinator_handle = ? \
             AND status IN ('pending','ready','blocked','dispatched','stalled')",
        )
        .bind(run_id)
        .bind(workspace_id)
        .bind(workspace_id)
        .bind(coordinator_handle)
        .execute(self.pool())
        .await?;
        let affected = result.rows_affected();
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET run_id = ?, workspace_id = ? \
             WHERE task_id IN (SELECT id FROM orchestrationTasks WHERE run_id = ?)",
        )
        .bind(run_id)
        .bind(workspace_id)
        .bind(run_id)
        .execute(self.pool())
        .await?;
        Ok(affected)
    }

    pub async fn create_orchestration_task(
        &self,
        task: NewOrchestrationTask,
    ) -> Result<OrchestrationTask> {
        let id = orchestration_id("task");
        let mut tx = self.pool().begin().await?;
        let status = status_for_deps(&mut tx, &task.deps).await?;
        let dependency_result = match status {
            OrchestrationTaskStatus::Failed => Some("dependency failed"),
            OrchestrationTaskStatus::Cancelled => Some("dependency cancelled"),
            _ => None,
        };
        let dependency_completed = dependency_result.is_some();
        let display_name = task
            .display_name
            .clone()
            .or_else(|| task.task_title.clone())
            .unwrap_or_else(|| derive_display_name(&task.spec));
        sqlx::query(
            "INSERT INTO orchestrationTasks \
             (id, parent_id, created_by_terminal_handle, task_title, display_name, spec, status, deps, \
              run_id, workspace_id, coordinator_handle, result_schema, result, completed_at, cancelled_at) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
                     CASE WHEN ? THEN datetime('now') ELSE NULL END, \
                     CASE WHEN ? THEN datetime('now') ELSE NULL END)",
        )
        .bind(&id)
        .bind(&task.parent_id)
        .bind(&task.created_by_terminal_handle)
        .bind(&task.task_title)
        .bind(&display_name)
        .bind(&task.spec)
        .bind(status.as_str())
        .bind(serde_json::to_string(&task.deps)?)
        .bind(&task.run_id)
        .bind(&task.workspace_id)
        .bind(&task.coordinator_handle)
        .bind(&task.result_schema)
        .bind(dependency_result)
        .bind(dependency_completed)
        .bind(status == OrchestrationTaskStatus::Cancelled)
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
        self.list_scoped_orchestration_tasks(status, None, None)
            .await
    }

    pub async fn list_scoped_orchestration_tasks(
        &self,
        status: Option<OrchestrationTaskStatus>,
        run_id: Option<&str>,
        workspace_id: Option<&str>,
    ) -> Result<Vec<OrchestrationTask>> {
        let mut sql = format!(
            "SELECT {TASK_COLUMNS}, \
             (SELECT assignee_handle FROM orchestrationDispatchContexts \
              WHERE task_id = orchestrationTasks.id AND status IN ('pending','dispatched','awaiting_acceptance','stalled') \
              ORDER BY rowid DESC LIMIT 1) AS active_assignee, \
             (SELECT id FROM orchestrationDispatchContexts \
              WHERE task_id = orchestrationTasks.id AND status IN ('pending','dispatched','awaiting_acceptance','stalled') \
              ORDER BY rowid DESC LIMIT 1) AS active_dispatch_id \
             FROM orchestrationTasks"
        );
        let mut clauses = Vec::new();
        if status.is_some() {
            clauses.push("status = ?");
        }
        if run_id.is_some() {
            clauses.push("run_id = ?");
        }
        if workspace_id.is_some() {
            clauses.push("workspace_id = ?");
        }
        if !clauses.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&clauses.join(" AND "));
        }
        sql.push_str(" ORDER BY created_at ASC, id ASC");
        let mut query = sqlx::query(&sql);
        if let Some(status) = status {
            query = query.bind(status.as_str());
        }
        if let Some(run_id) = run_id {
            query = query.bind(run_id);
        }
        if let Some(workspace_id) = workspace_id {
            query = query.bind(workspace_id);
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
                 WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
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
                     WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
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

    pub async fn cancel_orchestration_task(
        &self,
        id: &str,
        reason: &str,
    ) -> Result<OrchestrationTask> {
        let mut tx = self.pool().begin().await?;
        let status: Option<String> =
            sqlx::query("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(id)
                .fetch_optional(&mut *tx)
                .await?
                .map(|row| row.try_get("status"))
                .transpose()?;
        match status.as_deref() {
            None => bail!("orchestration task not found: {id}"),
            Some("cancelled") => {
                tx.commit().await?;
                return self
                    .orchestration_task_by_id(id)
                    .await?
                    .ok_or_else(|| anyhow!("cancelled orchestration task not found: {id}"));
            }
            Some("completed" | "failed") => {
                bail!("cannot cancel terminal orchestration task {id}")
            }
            _ => {}
        }
        let mut cancelled = vec![id.to_string()];
        let mut cursor = 0;
        while cursor < cancelled.len() {
            let changed = cancelled[cursor].clone();
            cursor += 1;
            let rows = sqlx::query(
                "SELECT id, deps FROM orchestrationTasks \
                 WHERE status IN ('pending','ready','blocked','stalled')",
            )
            .fetch_all(&mut *tx)
            .await?;
            for row in rows {
                let candidate: String = row.try_get("id")?;
                let deps: String = row.try_get("deps")?;
                if parse_string_array(&deps).iter().any(|dep| dep == &changed)
                    && !cancelled.contains(&candidate)
                {
                    cancelled.push(candidate);
                }
            }
        }
        for task_id in &cancelled {
            let task_reason = if task_id == id {
                reason.to_string()
            } else {
                format!("dependency cancelled: {id}")
            };
            sqlx::query(
                "UPDATE orchestrationTasks SET status = 'cancelled', result = COALESCE(result, ?), \
                 cancelled_at = datetime('now'), completed_at = datetime('now') \
                 WHERE id = ? AND status NOT IN ('completed','failed','cancelled')",
            )
            .bind(task_reason)
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "UPDATE orchestrationDispatchContexts SET status = 'cancelled', completed_at = datetime('now') \
                 WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
            )
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "UPDATE orchestrationMessages SET state = 'obsolete', obsolete_at = datetime('now') \
                 WHERE task_id = ? AND state = 'queued'",
            )
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "UPDATE orchestrationDecisionGates SET status = 'timeout', resolved_at = datetime('now') \
                 WHERE task_id = ? AND status = 'pending'",
            )
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        self.orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("orchestration task not found after cancellation: {id}"))
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
