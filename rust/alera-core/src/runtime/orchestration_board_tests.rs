use serde_json::json;

use super::{
    OrchestrationBoardBucket as Bucket, OrchestrationBoardQuery as Query,
    OrchestrationRunSnapshotQuery, RuntimeStore,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

async fn run(store: &RuntimeStore, id: &str, status: &str, policy: &str) {
    sqlx::query(
        "INSERT INTO orchestrationCoordinatorRuns
         (id, spec, status, workspace_id, execution_policy_status, created_at)
         VALUES (?, ?, ?, ?, ?, '2026-08-29 12:00:00')",
    )
    .bind(id)
    .bind(format!("Objective {id}"))
    .bind(status)
    .bind(id)
    .bind(policy)
    .execute(store.pool())
    .await
    .unwrap();
}

async fn task(store: &RuntimeStore, id: &str, run: &str, status: &str) {
    sqlx::query(
        "INSERT INTO orchestrationTasks
         (id, spec, status, run_id, workspace_id, coordinator_handle)
         VALUES (?, 'task', ?, ?, 'task-workspace', 'coordinator')",
    )
    .bind(id)
    .bind(status)
    .bind(run)
    .execute(store.pool())
    .await
    .unwrap();
}

#[tokio::test]
async fn board_counts_are_aggregated_without_gate_join_multiplication() {
    let (_dir, store) = store().await;
    run(&store, "active", "running", "none").await;
    run(&store, "review", "running", "draft").await;
    run(&store, "rejected", "running", "rejected").await;
    run(&store, "failed", "failed", "none").await;
    run(&store, "history", "completed", "draft").await;
    task(&store, "done", "active", "completed").await;
    task(&store, "worker", "active", "dispatched").await;
    task(&store, "gate-task", "review", "blocked").await;
    for id in ["gate-1", "gate-2"] {
        sqlx::query(
            "INSERT INTO orchestrationDecisionGates (id, task_id, question)
             VALUES (?, 'gate-task', 'Approve?')",
        )
        .bind(id)
        .execute(store.pool())
        .await
        .unwrap();
    }
    let snapshot = store
        .orchestration_board_snapshot(&Query::default())
        .await
        .unwrap();
    assert_eq!(snapshot.counts.attention, 3);
    assert_eq!(snapshot.counts.active, 1);
    assert_eq!(snapshot.counts.history, 1);
    let active = snapshot.items.iter().find(|r| r.id == "active").unwrap();
    assert_eq!(
        (
            active.task_count,
            active.completed_count,
            active.running_count
        ),
        (2, 1, 1)
    );
    assert_eq!(active.project_id, None, "legacy global runs remain visible");
    let review = snapshot.items.iter().find(|r| r.id == "review").unwrap();
    assert_eq!((review.task_count, review.pending_gate_count), (1, 2));
    assert_eq!(review.bucket, Bucket::Attention);
}

#[tokio::test]
async fn attention_tracks_failures_stalls_and_pending_gates() {
    let (_dir, store) = store().await;
    for status in ["failed", "stalled", "blocked"] {
        run(&store, status, "running", "none").await;
        task(&store, status, status, status).await;
    }
    run(&store, "gate", "running", "none").await;
    task(&store, "gated", "gate", "pending").await;
    sqlx::query(
        "INSERT INTO orchestrationDecisionGates (id, task_id, question) VALUES ('g', 'gated', '?')",
    )
    .execute(store.pool())
    .await
    .unwrap();
    assert_eq!(
        store
            .orchestration_board_snapshot(&Query::default())
            .await
            .unwrap()
            .counts
            .attention,
        4
    );
    sqlx::query("UPDATE orchestrationDecisionGates SET status = 'resolved' WHERE id = 'g'")
        .execute(store.pool())
        .await
        .unwrap();
    assert_eq!(
        store
            .orchestration_board_snapshot(&Query::default())
            .await
            .unwrap()
            .counts
            .attention,
        3
    );
}

#[tokio::test]
async fn stable_keyset_pagination_counts_all_filtered_runs_and_rejects_stale_cursors() {
    let (_dir, store) = store().await;
    for id in ["a", "b", "c", "d", "e"] {
        run(&store, id, "stopped", "none").await;
    }
    let first = store
        .orchestration_board_snapshot(&Query {
            limit: Some(2),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(
        first
            .items
            .iter()
            .map(|r| r.id.as_str())
            .collect::<Vec<_>>(),
        ["e", "d"]
    );
    assert_eq!(first.counts.history, 5);
    let query = Query {
        cursor: first.next_cursor.clone(),
        limit: Some(2),
        ..Default::default()
    };
    let second = store.orchestration_board_snapshot(&query).await.unwrap();
    assert_eq!(
        second
            .items
            .iter()
            .map(|r| r.id.as_str())
            .collect::<Vec<_>>(),
        ["c", "b"]
    );
    let third = store
        .orchestration_board_snapshot(&Query {
            cursor: second.next_cursor,
            ..query.clone()
        })
        .await
        .unwrap();
    assert_eq!(third.items[0].id, "a");
    assert!(third.next_cursor.is_none());
    task(&store, "new", "a", "pending").await;
    assert!(store
        .orchestration_board_snapshot(&query)
        .await
        .unwrap_err()
        .to_string()
        .contains("stale"));
}

#[tokio::test]
async fn filters_are_literal_and_counts_ignore_selected_bucket_and_page() {
    let (_dir, store) = store().await;
    run(&store, "100%", "running", "draft").await;
    run(&store, "other", "running", "none").await;
    let snapshot = store
        .orchestration_board_snapshot(&Query {
            search: Some("%".into()),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(snapshot.items.len(), 1);
    assert_eq!(snapshot.items[0].id, "100%");
    let snapshot = store
        .orchestration_board_snapshot(&Query {
            bucket: Some(Bucket::Active),
            limit: Some(1),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(snapshot.items[0].id, "other");
    assert_eq!((snapshot.counts.attention, snapshot.counts.active), (1, 1));
    let snapshot = store
        .orchestration_board_snapshot(&Query {
            workspace_id: Some("100%".into()),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(snapshot.items.len(), 1);
    let snapshot = store
        .orchestration_board_snapshot(&Query {
            project_id: Some("absent".into()),
            ..Default::default()
        })
        .await
        .unwrap();
    assert!(snapshot.items.is_empty());
}

#[tokio::test]
async fn board_rejects_unbounded_and_malformed_queries() {
    let (_dir, store) = store().await;
    for limit in [0, 101, u32::MAX] {
        assert!(store
            .orchestration_board_snapshot(&Query {
                limit: Some(limit),
                ..Default::default()
            })
            .await
            .is_err());
    }
    assert!(store
        .orchestration_board_snapshot(&Query {
            search: Some("x".repeat(257)),
            ..Default::default()
        })
        .await
        .is_err());
    assert!(serde_json::from_value::<Query>(json!({"limit": -1})).is_err());
    assert!(serde_json::from_value::<Query>(json!({"actor": "app"})).is_err());
    assert!(serde_json::from_value::<Query>(json!({"bucket": "unknown"})).is_err());
}

#[tokio::test]
async fn project_filters_follow_actual_owner_and_preserve_missing_workspaces() {
    let (_dir, store) = store().await;
    run(&store, "owned", "running", "none").await;
    run(&store, "legacy", "stopped", "none").await;
    sqlx::query(
        "INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind)
        VALUES ('project', 'Project Name', '/repo', '2026-08-29T12:00:00Z', '2026-08-29T12:00:00Z', 'gitRepository')",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query("INSERT INTO workspaces
        (id, instanceId, hostId, projectId, name, path, createdAt, updatedAt, kind, status)
        VALUES ('owned', 'instance', 'local', 'project', 'Workspace Name', '/repo', '2026-08-29T12:00:00Z', '2026-08-29T12:00:00Z', 'linked', 'active')")
        .execute(store.pool()).await.unwrap();
    let query = Query {
        project_id: Some("project".into()),
        search: Some("workspace name".into()),
        ..Default::default()
    };
    let snapshot = store.orchestration_board_snapshot(&query).await.unwrap();
    assert_eq!(snapshot.items.len(), 1);
    assert_eq!(snapshot.items[0].id, "owned");
    assert_eq!(
        snapshot.items[0].project_name.as_deref(),
        Some("Project Name")
    );
    let before = snapshot.revision;
    sqlx::query("DELETE FROM workspaces WHERE id = 'owned'")
        .execute(store.pool())
        .await
        .unwrap();
    let snapshot = store
        .orchestration_board_snapshot(&Query::default())
        .await
        .unwrap();
    assert_eq!(snapshot.items.len(), 2);
    assert!(snapshot.revision > before);
    assert!(snapshot.items.iter().all(|r| r.project_id.is_none()));
}

#[tokio::test]
async fn large_board_keeps_pages_bounded_and_counts_complete() {
    let (_dir, store) = store().await;
    sqlx::query(
        "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x + 1 FROM n WHERE x < 1200)
        INSERT INTO orchestrationCoordinatorRuns (id, spec, status, workspace_id)
        SELECT printf('run-%04d', x), 'Objective', 'stopped', 'legacy' FROM n",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x + 1 FROM n WHERE x < 12000)
        INSERT INTO orchestrationTasks (id, spec, status, run_id, workspace_id, coordinator_handle)
        SELECT printf('task-%05d', x), 'Task', 'completed',
            printf('run-%04d', ((x - 1) / 10) + 1), 'legacy', 'coordinator' FROM n",
    )
    .execute(store.pool())
    .await
    .unwrap();
    let snapshot = store
        .orchestration_board_snapshot(&Query {
            limit: Some(100),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(snapshot.items.len(), 100);
    assert_eq!(snapshot.counts.history, 1200);
    assert!(snapshot.next_cursor.is_some());
    assert!(snapshot
        .items
        .iter()
        .all(|r| r.task_count == 10 && r.completed_count == 10));
}

#[tokio::test]
async fn revision_survives_reopen_and_changes_only_with_committed_evidence() {
    let (dir, store) = store().await;
    run(&store, "run", "running", "none").await;
    let revision = store.orchestration_board_revision().await.unwrap();
    assert!(store
        .take_orchestration_board_change()
        .await
        .unwrap()
        .is_some());
    assert!(store
        .take_orchestration_board_change()
        .await
        .unwrap()
        .is_none());
    let mut tx = store.pool().begin().await.unwrap();
    sqlx::query("UPDATE orchestrationCoordinatorRuns SET status = 'failed' WHERE id = 'run'")
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.rollback().await.unwrap();
    assert_eq!(
        store.orchestration_board_revision().await.unwrap(),
        revision
    );
    assert!(store
        .take_orchestration_board_change()
        .await
        .unwrap()
        .is_none());
    drop(store);
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened.orchestration_board_revision().await.unwrap(),
        revision
    );
    task(&reopened, "t", "run", "failed").await;
    assert!(
        reopened
            .take_orchestration_board_change()
            .await
            .unwrap()
            .unwrap()
            > revision
    );
}

#[tokio::test]
async fn run_details_bound_payloads_and_page_tasks_without_results_or_tokens() {
    let (_dir, store) = store().await;
    run(&store, "run", "running", "none").await;
    sqlx::query("UPDATE orchestrationCoordinatorRuns SET spec = ? WHERE id = 'run'")
        .bind("é".repeat(20000))
        .execute(store.pool())
        .await
        .unwrap();
    for id in ["a", "b", "c"] {
        task(&store, id, "run", "pending").await;
    }
    let query = OrchestrationRunSnapshotQuery {
        run_id: "run".into(),
        after_task_id: None,
        revision: None,
        limit: Some(2),
    };
    let first = store.orchestration_run_snapshot(&query).await.unwrap();
    assert_eq!(first.run.objective.chars().count(), 256);
    assert_eq!(first.objective.chars().count(), 16384);
    assert!(first.objective_truncated);
    assert_eq!(first.tasks.len(), 2);
    assert_eq!(first.next_task_id.as_deref(), Some("b"));
    let encoded = serde_json::to_value(&first).unwrap();
    assert!(encoded["tasks"][0].get("result").is_none());
    assert!(encoded["tasks"][0].get("context_token_hash").is_none());
    let next = OrchestrationRunSnapshotQuery {
        after_task_id: first.next_task_id,
        revision: Some(first.revision),
        ..query
    };
    assert_eq!(
        store.orchestration_run_snapshot(&next).await.unwrap().tasks[0].id,
        "c"
    );
    task(&store, "d", "run", "completed").await;
    assert!(store
        .orchestration_run_snapshot(&next)
        .await
        .unwrap_err()
        .to_string()
        .contains("stale"));
}

#[tokio::test]
async fn orchestration_reset_invalidates_old_pages_without_resetting_revision() {
    let (_dir, store) = store().await;
    run(&store, "a", "stopped", "none").await;
    run(&store, "b", "stopped", "none").await;
    let query = Query {
        limit: Some(1),
        ..Default::default()
    };
    let before = store.orchestration_board_snapshot(&query).await.unwrap();
    store.reset_orchestration_tasks().await.unwrap();
    let after = store.orchestration_board_snapshot(&query).await.unwrap();
    assert!(after.revision > before.revision);
    assert!(after.items.is_empty());
    assert_eq!(after.counts.history, 0);
    assert!(store
        .orchestration_board_snapshot(&Query {
            cursor: before.next_cursor,
            ..query
        })
        .await
        .unwrap_err()
        .to_string()
        .contains("stale"));
}
