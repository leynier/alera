//! The additive fields that let a client link straight to a gate, a task's
//! age, retained resources and a timeline diff without a second read.

use serde_json::{json, Value};

use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::{
    OrchestrationBoardQuery, OrchestrationRunSnapshotQuery, RunTimelineQuery, RuntimeStore,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

async fn execute(store: &RuntimeStore, sql: &'static str, binds: &[&str]) {
    let mut query = sqlx::query(sql);
    for bind in binds {
        query = query.bind(*bind);
    }
    query.execute(store.pool()).await.unwrap();
}

async fn running_run(store: &RuntimeStore, id: &str) {
    execute(
        store,
        "INSERT INTO orchestrationCoordinatorRuns (id, spec, status, workspace_id, created_at)
         VALUES (?, 'Objective', 'running', ?, '2026-10-01 09:00:00')",
        &[id, id],
    )
    .await;
}

async fn task(store: &RuntimeStore, id: &str, run: &str, status: &str) {
    execute(
        store,
        "INSERT INTO orchestrationTasks
         (id, spec, status, run_id, workspace_id, coordinator_handle, created_at)
         VALUES (?, 'task', ?, ?, 'workspace', 'coordinator', '2026-10-01 09:05:00')",
        &[id, status, run],
    )
    .await;
}

async fn board_item(store: &RuntimeStore, run: &str) -> Value {
    let board = store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    let item = board.items.iter().find(|item| item.id == run).unwrap();
    serde_json::to_value(item).unwrap()
}

#[tokio::test]
async fn board_rows_name_their_newest_due_gates_up_to_five() {
    let (_dir, store) = store().await;
    running_run(&store, "quiet").await;
    running_run(&store, "gated").await;
    task(&store, "blocked", "gated", "blocked").await;
    for minute in 0..7 {
        sqlx::query(
            "INSERT INTO runGates (id, run_id, task_id, kind, question, created_at)
             VALUES (?, 'gated', 'blocked', 'decision', 'Which?', ?)",
        )
        .bind(format!("decision-{minute}"))
        .bind(format!("2026-10-01 10:0{minute}:00"))
        .execute(store.pool())
        .await
        .unwrap();
    }
    // A stage gate without evidence is not due; a resolved gate is history.
    execute(
        &store,
        "INSERT INTO runGates (id, run_id, kind, scope, question, created_at)
         VALUES ('stage-not-due', 'gated', 'stage', 'build', 'Ship?', '2026-10-01 11:00:00')",
        &[],
    )
    .await;
    execute(
        &store,
        "INSERT INTO runGates (id, run_id, task_id, kind, question, status, created_at)
         VALUES ('resolved', 'gated', 'blocked', 'decision', 'Old?', 'resolved',
             '2026-10-01 11:30:00')",
        &[],
    )
    .await;
    execute(
        &store,
        "INSERT INTO runGates (id, run_id, kind, scope, question, created_at)
         VALUES ('plan', 'gated', 'plan', 'plan', 'Approve?', '2026-10-01 12:00:00')",
        &[],
    )
    .await;

    let item = board_item(&store, "gated").await;
    assert_eq!(item["pendingGateCount"], 8);
    let gates = item["pendingGates"].as_array().unwrap();
    assert_eq!(gates.len(), 5);
    assert_eq!(gates[0], json!({"id": "plan", "kind": "plan"}));
    assert_eq!(
        gates[1],
        json!({"id": "decision-6", "kind": "decision", "taskId": "blocked"})
    );
    assert_eq!(gates[4]["id"], "decision-3");
    assert_eq!(board_item(&store, "quiet").await["pendingGates"], json!([]));

    let snapshot = store
        .orchestration_run_snapshot(&OrchestrationRunSnapshotQuery {
            run_id: "gated".into(),
            after_task_id: None,
            revision: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(snapshot.run.pending_gates.len(), 5);
}

#[tokio::test]
async fn snapshot_tasks_carry_their_times_and_the_run_counts_retained_resources() {
    let (_dir, store) = store().await;
    running_run(&store, "run").await;
    task(&store, "waiting", "run", "pending").await;
    task(&store, "worked", "run", "completed").await;
    execute(
        &store,
        "UPDATE orchestrationTasks SET completed_at = '2026-10-01 09:40:00' WHERE id = 'worked'",
        &[],
    )
    .await;
    execute(
        &store,
        "INSERT INTO orchestrationDispatchContexts
         (id, task_id, status, dispatched_at, last_activity_at, run_id, workspace_id,
          coordinator_handle)
         VALUES ('dispatch', 'worked', 'completed', '2026-10-01 09:10:00',
             '2026-10-01 09:50:00', 'run', 'workspace', 'coordinator')",
        &[],
    )
    .await;
    for (id, task_id, path) in [
        ("integration", None, "/tmp/run-integration"),
        ("attempt-1", Some("worked"), "/tmp/run-attempt-1"),
        ("attempt-2", Some("waiting"), "/tmp/run-attempt-2"),
    ] {
        sqlx::query(
            "INSERT INTO runWorkspaces(id, run_id, revision, task_id, attempt, path, identity, phase)
             VALUES (?, 'run', 1, ?, 1, ?, '{}', 'ready')",
        )
        .bind(id)
        .bind(task_id)
        .bind(path)
        .execute(store.pool())
        .await
        .unwrap();
    }
    execute(
        &store,
        "INSERT INTO runCleanup (id, run_id, digest, document, expires_at, state)
         VALUES ('cleanup', 'run', 'digest', '{\"items\":[]}', 0, 'retired')",
        &[],
    )
    .await;
    execute(
        &store,
        "INSERT INTO runCleanupResources (workspace_id, cleanup_id, retired)
         VALUES ('attempt-1', 'cleanup', 1)",
        &[],
    )
    .await;

    let snapshot = store
        .orchestration_run_snapshot(&OrchestrationRunSnapshotQuery {
            run_id: "run".into(),
            after_task_id: None,
            revision: None,
            limit: None,
        })
        .await
        .unwrap();
    let snapshot = serde_json::to_value(snapshot).unwrap();
    assert_eq!(snapshot["resourceCount"], 2);
    let tasks = snapshot["tasks"].as_array().unwrap();
    let worked = tasks.iter().find(|task| task["id"] == "worked").unwrap();
    assert_eq!(worked["startedAt"], "2026-10-01 09:10:00");
    assert_eq!(worked["completedAt"], "2026-10-01 09:40:00");
    assert_eq!(worked["updatedAt"], "2026-10-01 09:50:00");
    let waiting = tasks.iter().find(|task| task["id"] == "waiting").unwrap();
    assert_eq!(waiting["startedAt"], Value::Null);
    assert_eq!(waiting["completedAt"], Value::Null);
    assert_eq!(waiting["updatedAt"], "2026-10-01 09:05:00");
}

#[tokio::test]
async fn timeline_entries_expose_the_diff_their_event_recorded() {
    let (_dir, store) = store().await;
    running_run(&store, "run").await;
    let mut conn = store.pool().acquire().await.unwrap();
    let mut integrated = NewRunEvent::new("run", RunEventKind::Integrated);
    integrated.task_id = Some("task");
    integrated.payload = Some(json!({
        "workspaceId": "integration",
        "sha": "b".repeat(40),
        "baseSha": "a".repeat(40),
    }));
    record_run_event(&mut conn, &integrated).await.unwrap();
    record_run_event(&mut conn, &NewRunEvent::new("run", RunEventKind::Paused))
        .await
        .unwrap();
    drop(conn);

    let timeline = store
        .run_timeline(&RunTimelineQuery {
            run_id: "run".into(),
            kinds: Some(vec!["integrated".into(), "paused".into()]),
            ..Default::default()
        })
        .await
        .unwrap();
    let entries = serde_json::to_value(&timeline.items).unwrap();
    let integrated = entries
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["kind"] == "integrated")
        .unwrap();
    assert_eq!(integrated["taskId"], "task");
    assert_eq!(integrated["workspaceId"], "integration");
    assert_eq!(integrated["sha"], "b".repeat(40));
    assert_eq!(integrated["baseSha"], "a".repeat(40));
    let paused = entries
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["kind"] == "paused")
        .unwrap();
    assert_eq!(paused["workspaceId"], Value::Null);
    assert_eq!(paused["sha"], Value::Null);
}
