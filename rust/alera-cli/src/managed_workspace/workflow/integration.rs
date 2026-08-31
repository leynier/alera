use alera_core::runtime::{
    IntegrateWorkflowResult, WorkflowIntegrationRecord, WorkflowIntegrationState as State,
};
use sqlx::Row;

use super::*;

/// Called on the bounded blocking lane. The integration resource lock serializes
/// all results of a run, including recovery after a disconnected caller.
pub(crate) async fn integrate(
    store: &RuntimeStore,
    runtime_dir: &Path,
    input: IntegrateWorkflowResult,
) -> Result<WorkflowIntegrationRecord> {
    if let Some(record) = store.workflow_integration_for_request(&input).await? {
        if matches!(record.state, State::Integrated | State::Conflict) {
            return Ok(record);
        }
        let _lock = resource_lock(runtime_dir, &record.request.integration.id)?
            .ok_or_else(|| anyhow!("workflow integration is busy; inspect or retry shortly"))?;
        return resume(store, record).await;
    }
    let integration = store.workflow_integration_workspace(&input.run_id).await?;
    let _lock = resource_lock(runtime_dir, &integration.identity.workspace.id)?
        .ok_or_else(|| anyhow!("workflow integration is busy; inspect or retry shortly"))?;
    let source = store.workflow_workspace(&input.workspace_id).await?;
    let sha = core_git::verify_workflow_worktree_tip(
        &source.identity.repo_path,
        &source.identity.workspace.path,
        &source.identity.base_sha,
        &source.identity.workspace.id,
    )?;
    let record = store.reserve_workflow_integration(&input, &sha).await?;
    resume(store, record).await
}

async fn resume(
    store: &RuntimeStore,
    record: WorkflowIntegrationRecord,
) -> Result<WorkflowIntegrationRecord> {
    let record = store.workflow_integration(&record.request.id).await?;
    if matches!(record.state, State::Integrated | State::Conflict) {
        return Ok(record);
    }
    let id = &record.request.id;
    let result = async {
        let outcome = core_git::prepare_workflow_integration(&record.request)?;
        let record = store
            .record_workflow_integration_preparation(id, &outcome)
            .await?;
        if record.state == State::Conflict {
            return Ok(record);
        }
        let receipt = core_git::apply_workflow_integration(&record.request)?;
        store.complete_workflow_integration(&receipt).await
    }
    .await;
    match result {
        Ok(record) => Ok(record),
        Err(error) => {
            store
                .workflow_integration_attention(id, &error.to_string())
                .await
        }
    }
}

pub(crate) async fn reconcile(store: &RuntimeStore, runtime_dir: &Path) -> Result<()> {
    let upper: i64 =
        sqlx::query_scalar("SELECT COALESCE(MAX(sequence), 0) FROM workflowIntegrations")
            .fetch_one(store.pool())
            .await?;
    let mut after = 0_i64;
    loop {
        let rows = sqlx::query("SELECT sequence, id FROM workflowIntegrations
            WHERE sequence > ? AND sequence <= ? AND state IN ('pending','prepared') ORDER BY sequence LIMIT 25")
            .bind(after).bind(upper).fetch_all(store.pool()).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("sequence")?;
            let id: String = row.try_get("id")?;
            let record = store.workflow_integration(&id).await?;
            let Some(_lock) = resource_lock(runtime_dir, &record.request.integration.id)? else {
                continue;
            };
            let record = store.workflow_integration(&id).await?;
            if matches!(record.state, State::Pending | State::Prepared) {
                resume(store, record).await?;
            }
        }
    }
    Ok(())
}
