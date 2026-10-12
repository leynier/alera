use anyhow::{anyhow, bail, Result};
use sqlx::{sqlite::SqliteRow, QueryBuilder, Row, Sqlite, SqliteConnection};

use super::orchestration_board_schema::DUE_GATE_SQL;
use super::{
    OrchestrationBoardBucket, OrchestrationBoardCounts, OrchestrationBoardCursor,
    OrchestrationBoardQuery, OrchestrationBoardSnapshot, OrchestrationRunSummary,
    RunPendingGateRef, RuntimeStore, RUN_SUMMARY_PENDING_GATES_MAX,
};

pub(super) const BOARD_REVISION_SQL: &str =
    "SELECT revision FROM orchestrationBoardRevision WHERE id = 1";

impl RuntimeStore {
    pub async fn orchestration_board_revision(&self) -> Result<i64> {
        Ok(sqlx::query(BOARD_REVISION_SQL)
            .fetch_one(self.pool())
            .await?
            .try_get("revision")?)
    }

    pub async fn orchestration_board_snapshot(
        &self,
        filter: &OrchestrationBoardQuery,
    ) -> Result<OrchestrationBoardSnapshot> {
        let limit = filter.validate()?;
        let mut tx = self.pool().begin().await?;
        let revision: i64 = sqlx::query(BOARD_REVISION_SQL)
            .fetch_one(&mut *tx)
            .await?
            .try_get("revision")?;
        if filter
            .cursor
            .as_ref()
            .is_some_and(|c| c.revision != revision)
        {
            bail!("board cursor is stale; refresh the first page");
        }
        let mut counts_sql = QueryBuilder::new(
            "SELECT bucket, COUNT(*) AS count FROM orchestrationBoardRuns WHERE 1=1",
        );
        push_filters(&mut counts_sql, filter);
        counts_sql.push(" GROUP BY bucket");
        let mut counts = OrchestrationBoardCounts::default();
        for row in counts_sql.build().fetch_all(&mut *tx).await? {
            let count = row.try_get("count")?;
            match row.try_get::<String, _>("bucket")?.as_str() {
                "attention" => counts.attention = count,
                "active" => counts.active = count,
                "history" => counts.history = count,
                _ => bail!("invalid board bucket"),
            }
        }
        let mut items_sql = QueryBuilder::new("SELECT * FROM orchestrationBoardRuns WHERE 1=1");
        push_filters(&mut items_sql, filter);
        if let Some(bucket) = filter.bucket {
            items_sql.push(" AND bucket = ").push_bind(bucket.as_str());
        }
        if let Some(cursor) = &filter.cursor {
            items_sql
                .push(" AND (created_at, id) < (")
                .push_bind(&cursor.created_at)
                .push(", ")
                .push_bind(&cursor.id)
                .push(")");
        }
        items_sql
            .push(" ORDER BY created_at DESC, id DESC LIMIT ")
            .push_bind(limit + 1);
        let mut items = items_sql
            .build()
            .fetch_all(&mut *tx)
            .await?
            .into_iter()
            .map(summary_from_row)
            .collect::<Result<Vec<_>>>()?;
        let has_more = items.len() > limit as usize;
        items.truncate(limit as usize);
        attach_pending_gates(&mut tx, &mut items).await?;
        let next_cursor = items
            .last()
            .filter(|_| has_more)
            .map(|last| OrchestrationBoardCursor {
                created_at: last.created_at.clone(),
                id: last.id.clone(),
                revision,
            });
        tx.commit().await?;
        Ok(OrchestrationBoardSnapshot {
            revision,
            counts,
            items,
            next_cursor,
        })
    }
}

fn push_filters(sql: &mut QueryBuilder<Sqlite>, filter: &OrchestrationBoardQuery) {
    if let Some(project) = &filter.project_id {
        sql.push(" AND project_id = ").push_bind(project);
    }
    if let Some(workspace) = &filter.workspace_id {
        sql.push(" AND workspace_id = ").push_bind(workspace);
    }
    if let Some(search) = &filter.search {
        // instr keeps wildcard characters literal instead of widening a query.
        sql.push(" AND instr(lower(objective || ' ' || COALESCE(project_name, '') || ' ' || COALESCE(workspace_name, '') || ' ' || id), lower(")
            .push_bind(search)
            .push(")) > 0");
    }
}

/// Fills each summary's newest due gates (bounded per run) in one query.
pub(super) async fn attach_pending_gates(
    conn: &mut SqliteConnection,
    items: &mut [OrchestrationRunSummary],
) -> Result<()> {
    if items.iter().all(|item| item.pending_gate_count == 0) {
        return Ok(());
    }
    let due = DUE_GATE_SQL.replace("{gate}", "g");
    let mut sql = QueryBuilder::<Sqlite>::new(format!(
        "SELECT run_id, id, kind, task_id FROM (
            SELECT COALESCE(g.run_id, t.run_id) AS run_id, g.id, g.kind, g.task_id,
                ROW_NUMBER() OVER (PARTITION BY COALESCE(g.run_id, t.run_id)
                    ORDER BY g.created_at DESC, g.rowid DESC) AS position
            FROM runGates g LEFT JOIN orchestrationTasks t ON t.id = g.task_id
            WHERE {due} AND COALESCE(g.run_id, t.run_id) IN ("
    ));
    let mut ids = sql.separated(", ");
    for item in items.iter().filter(|item| item.pending_gate_count > 0) {
        ids.push_bind(item.id.clone());
    }
    sql.push(") ) WHERE position <= ")
        .push_bind(RUN_SUMMARY_PENDING_GATES_MAX)
        .push(" ORDER BY run_id, position");
    for row in sql.build().fetch_all(&mut *conn).await? {
        let run_id: String = row.try_get("run_id")?;
        if let Some(item) = items.iter_mut().find(|item| item.id == run_id) {
            item.pending_gates.push(RunPendingGateRef {
                id: row.try_get("id")?,
                kind: row.try_get("kind")?,
                task_id: row.try_get("task_id")?,
            });
        }
    }
    Ok(())
}

pub(super) fn summary_from_row(row: SqliteRow) -> Result<OrchestrationRunSummary> {
    let bucket = match row.try_get::<String, _>("bucket")?.as_str() {
        "attention" => OrchestrationBoardBucket::Attention,
        "active" => OrchestrationBoardBucket::Active,
        "history" => OrchestrationBoardBucket::History,
        value => return Err(anyhow!("invalid board bucket: {value}")),
    };
    Ok(OrchestrationRunSummary {
        id: row.try_get("id")?,
        objective: row.try_get("objective")?,
        status: row.try_get("status")?,
        bucket,
        workspace_id: row.try_get("workspace_id")?,
        workspace_name: row.try_get("workspace_name")?,
        project_id: row.try_get("project_id")?,
        project_name: row.try_get("project_name")?,
        created_at: row.try_get("created_at")?,
        last_activity_at: row.try_get("last_activity_at")?,
        completed_at: row.try_get("completed_at")?,
        plan_gate_pending: row.try_get("plan_gate_pending")?,
        isolation: row.try_get("isolation")?,
        approval_required: row.try_get("approval_required")?,
        plan_revision: row.try_get("plan_revision")?,
        attention_reason: row.try_get("attention_reason")?,
        coordinator_state: row.try_get("coordinator_state")?,
        paused_by: row.try_get("paused_by")?,
        control_sequence: row.try_get("control_sequence")?,
        pending_gate_kinds: row
            .try_get::<String, _>("pending_gate_kinds")?
            .split(',')
            .filter(|kind| !kind.is_empty())
            .map(str::to_string)
            .collect(),
        task_count: row.try_get("task_count")?,
        completed_count: row.try_get("completed_count")?,
        running_count: row.try_get("running_count")?,
        failed_count: row.try_get("failed_count")?,
        stalled_count: row.try_get("stalled_count")?,
        blocked_count: row.try_get("blocked_count")?,
        pending_gate_count: row.try_get("pending_gate_count")?,
        cleanup_attention: row.try_get("cleanup_attention")?,
        cleanup_applying: row.try_get("cleanup_applying")?,
        pending_gates: Vec::new(),
    })
}
