use sqlx::Row;

use super::*;

/// One bounded-page sweep per host start, never a polling loop. Live jobs from
/// a graceful restart retain their OS locks and are not adopted by the new host.
pub(crate) async fn reconcile(store: &RuntimeStore, runtime_dir: &Path) -> Result<()> {
    let upper: i64 =
        sqlx::query_scalar("SELECT COALESCE(MAX(sequence), 0) FROM workflowWorkspaces")
            .fetch_one(store.pool())
            .await?;
    let mut after = 0_i64;
    loop {
        let rows = sqlx::query("SELECT x.sequence, x.id, COALESCE(r.revision, x.revision) AS revision
            FROM workflowWorkspaces x LEFT JOIN workflowRuns r ON r.run_id = x.run_id
            WHERE x.sequence > ? AND x.sequence <= ? AND x.phase IN ('reserved','creating','created','setupRunning')
            ORDER BY x.sequence LIMIT 25")
            .bind(after).bind(upper).fetch_all(store.pool()).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("sequence")?;
            let id: String = row.try_get("id")?;
            let revision = row.try_get("revision")?;
            let Some(_lock) = resource_lock(runtime_dir, &id)? else {
                continue;
            };
            let record = store.workflow_workspace(&id).await?;
            if matches!(record.phase, Phase::Ready | Phase::Attention) {
                continue;
            }
            let result = if record.phase == Phase::SetupRunning {
                attention(store, &record, revision,
                    "Setup was interrupted. Its outcome is unknown and it will not run again. Inspect the retained workspace and retry in a new attempt.").await
            } else {
                advance(store, record, revision).await
            };
            if let Err(error) = result {
                let record = store.workflow_workspace(&id).await?;
                attention(store, &record, revision, &error.to_string()).await?;
            }
        }
    }
    Ok(())
}
