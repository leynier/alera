use anyhow::{anyhow, bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::orchestration_message_store::orchestration_id;
use super::orchestration_task_store::{derive_display_name, status_for_deps};
use super::{
    NewOrchestrationTask, OrchestrationTask, OrchestrationTaskStatus, RoleContractSnapshot,
    RuntimeStore,
};

impl RuntimeStore {
    pub(super) async fn migrate_role_contracts(&self) -> Result<()> {
        self.ensure_column("orchestrationTasks", "role_contract", "TEXT")
            .await?;
        sqlx::query(
            "CREATE TRIGGER IF NOT EXISTS orchestrationRoleContractImmutable
            BEFORE UPDATE OF role_contract ON orchestrationTasks
            WHEN OLD.role_contract IS NOT NEW.role_contract
            BEGIN SELECT RAISE(ABORT, 'role contract snapshot is immutable'); END",
        )
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn create_orchestration_task_with_contract(
        &self,
        task: NewOrchestrationTask,
        contract: Option<RoleContractSnapshot>,
    ) -> Result<OrchestrationTask> {
        let snapshot = contract
            .map(|contract| {
                contract.validate()?;
                if task.result_schema.is_some() {
                    bail!("role contract and legacy result schema are mutually exclusive");
                }
                serde_json::to_string(&contract).map_err(Into::into)
            })
            .transpose()?;
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
              run_id, workspace_id, coordinator_handle, result_schema, role_contract, result, completed_at, cancelled_at) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
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
        .bind(snapshot)
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
}

pub(super) async fn validate_task_contract_completion(
    tx: &mut Transaction<'_, Sqlite>,
    task_id: &str,
    result: &str,
) -> Result<()> {
    let raw: Option<String> =
        sqlx::query("SELECT role_contract FROM orchestrationTasks WHERE id = ?")
            .bind(task_id)
            .fetch_one(&mut **tx)
            .await?
            .try_get("role_contract")?;
    if let Some(raw) = raw {
        let contract: RoleContractSnapshot = serde_json::from_str(&raw)?;
        contract.validate_success_result(result)?;
    }
    Ok(())
}

pub(super) async fn guard_contract_status_update(
    tx: &mut Transaction<'_, Sqlite>,
    task_id: &str,
    status: OrchestrationTaskStatus,
) -> Result<()> {
    let row = sqlx::query("SELECT role_contract, status FROM orchestrationTasks WHERE id = ?")
        .bind(task_id)
        .fetch_one(&mut **tx)
        .await?;
    if row.try_get::<Option<String>, _>("role_contract")?.is_some()
        && (status == OrchestrationTaskStatus::Completed
            || row.try_get::<String, _>("status")? == "completed")
    {
        bail!("contracted task completion requires an active dispatch; completed evidence is immutable");
    }
    Ok(())
}
