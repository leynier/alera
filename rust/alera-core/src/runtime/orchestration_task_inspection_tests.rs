use serde_json::json;

use super::{OrchestrationTaskInspectionQuery as Query, RuntimeStore};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    sqlx::query(
        "INSERT INTO orchestrationCoordinatorRuns (id, spec, workspace_id)
         VALUES ('run', 'Deliver export', 'owner')",
    )
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO orchestrationTasks (id, spec, run_id, workspace_id, coordinator_handle, deps)
         VALUES ('task', 'Implement export', 'run', 'worker', 'coordinator', '[\"foundation\"]')",
    )
    .execute(store.pool())
    .await
    .unwrap();
    (dir, store)
}

fn query() -> Query {
    Query {
        run_id: "run".into(),
        task_id: "task".into(),
        cursor: None,
        limit: Some(2),
    }
}

#[tokio::test]
async fn task_inspection_projects_only_display_fields_and_recorded_evidence() {
    let (_dir, store) = store().await;
    sqlx::query(
        "INSERT INTO orchestrationDispatchContexts
         (id, task_id, run_id, workspace_id, coordinator_handle, assignee_handle,
          context_token_hash, agent_profile, status)
         VALUES ('dispatch', 'task', 'run', 'worker', 'coordinator', 'terminal',
          'SECRET_CONTEXT_HASH', 'Implementer', 'completed')",
    )
    .execute(store.pool())
    .await
    .unwrap();
    let result = json!({
        "summary": "Export implemented",
        "completionKind": "success",
        "artifacts": [{"path": "docs/export.md"}],
        "validation": ["cargo test passed"]
    });
    sqlx::query("UPDATE orchestrationTasks SET result = ? WHERE id = 'task'")
        .bind(result.to_string())
        .execute(store.pool())
        .await
        .unwrap();
    store
        .insert_orchestration_audit_event(Some("actor"), "task.recover", "task", "Retry")
        .await
        .unwrap();
    let snapshot = store.orchestration_task_inspection(&query()).await.unwrap();
    assert_eq!(snapshot.workspace_id, "worker");
    assert_eq!(
        snapshot.workspace_name, None,
        "removed workspaces remain inspectable"
    );
    assert_eq!(
        snapshot.base_sha, None,
        "legacy bases must not be inferred from current Git state"
    );
    assert_eq!(snapshot.profile.as_deref(), Some("Implementer"));
    assert_eq!(snapshot.terminal_handle.as_deref(), Some("terminal"));
    assert_eq!(snapshot.dependencies, ["foundation"]);
    assert!(!snapshot.dependencies_truncated);
    assert_eq!(
        snapshot.result.summary.as_deref(),
        Some("Export implemented")
    );
    assert_eq!(snapshot.result.validation, ["cargo test passed"]);
    assert_eq!(snapshot.result.artifacts, [r#"{"path":"docs/export.md"}"#]);
    assert!(!snapshot.result.truncated);
    assert_eq!(snapshot.history.len(), 2);
    let payload = serde_json::to_string(&snapshot).unwrap();
    assert!(!payload.contains("SECRET_CONTEXT_HASH"));
    assert!(!payload.contains("context_token"));
    assert!(!payload.contains("coordinator"));
}

#[tokio::test]
async fn task_inspection_selects_last_inserted_dispatch_with_tied_timestamps() {
    let (_dir, store) = store().await;
    for (id, profile, handle, status) in [
        ("z-first", "Initial", "old-terminal", "failed"),
        ("a-second", "Fallback", "current-terminal", "dispatched"),
    ] {
        sqlx::query(
            "INSERT INTO orchestrationDispatchContexts
             (id, task_id, run_id, workspace_id, coordinator_handle, assignee_handle,
              context_token_hash, agent_profile, status, created_at)
             VALUES (?, 'task', 'run', 'worker', 'coordinator', ?, ?, ?, ?,
              '2026-08-30 10:00:00')",
        )
        .bind(id)
        .bind(handle)
        .bind(format!("hash-{id}"))
        .bind(profile)
        .bind(status)
        .execute(store.pool())
        .await
        .unwrap();
    }
    let snapshot = store.orchestration_task_inspection(&query()).await.unwrap();
    assert_eq!(snapshot.profile.as_deref(), Some("Fallback"));
    assert_eq!(
        snapshot.terminal_handle.as_deref(),
        Some("current-terminal")
    );
}

#[tokio::test]
async fn task_inspection_preserves_bounded_legacy_json_results_without_a_summary() {
    let (_dir, store) = store().await;
    for result in [
        json!({
            "completedBy": "worker",
            "filesModified": ["src/export.rs"],
            "completedAt": "2026-08-30 10:00:00"
        }),
        json!({"artifacts": ["src/export.rs"]}),
        json!({"legacyEvidence": "界".repeat(20000)}),
    ] {
        let raw = result.to_string();
        sqlx::query(
            "UPDATE orchestrationTasks SET result = ?, status = 'completed' WHERE id = 'task'",
        )
        .bind(&raw)
        .execute(store.pool())
        .await
        .unwrap();
        let snapshot = store.orchestration_task_inspection(&query()).await.unwrap();
        assert_eq!(
            snapshot.result.preview,
            Some(raw.chars().take(16384).collect())
        );
        assert_eq!(snapshot.result.truncated, raw.chars().count() > 16384);
        assert!(snapshot.result.summary.is_none());
    }
}

#[tokio::test]
async fn task_history_pages_share_a_revision_and_audits_invalidate_cursors() {
    let (_dir, store) = store().await;
    for index in 0..5 {
        sqlx::query(
            "INSERT INTO orchestrationAuditEvents(id, action, target_id, reason, created_at)
             VALUES (?, 'task.recover', 'task', 'Retry', '2026-08-30 10:00:00')",
        )
        .bind(format!("audit-{index}"))
        .execute(store.pool())
        .await
        .unwrap();
    }
    let first = store.orchestration_task_inspection(&query()).await.unwrap();
    assert_eq!(
        first
            .history
            .iter()
            .map(|e| e.id.as_str())
            .collect::<Vec<_>>(),
        ["audit-4", "audit-3"]
    );
    let next = Query {
        cursor: first.next_cursor,
        ..query()
    };
    let second = store.orchestration_task_inspection(&next).await.unwrap();
    assert_eq!(
        second
            .history
            .iter()
            .map(|e| e.id.as_str())
            .collect::<Vec<_>>(),
        ["audit-2", "audit-1"]
    );
    store
        .insert_orchestration_audit_event(None, "task.recover", "task", "Changed")
        .await
        .unwrap();
    assert!(store
        .orchestration_task_inspection(&next)
        .await
        .unwrap_err()
        .to_string()
        .contains("stale"));
}

#[tokio::test]
async fn task_inspection_rejects_foreign_runs_and_unbounded_queries() {
    let (_dir, store) = store().await;
    assert!(store
        .orchestration_task_inspection(&Query {
            run_id: "other".into(),
            ..query()
        })
        .await
        .unwrap_err()
        .to_string()
        .contains("not found in this run"));
    for limit in [0, 101] {
        assert!(store
            .orchestration_task_inspection(&Query {
                limit: Some(limit),
                ..query()
            })
            .await
            .is_err());
    }
    assert!(serde_json::from_value::<Query>(json!({
        "task_id": "task", "run_id": "run", "actor": "app"
    }))
    .is_err());
    assert!(store
        .orchestration_task_inspection(&Query {
            task_id: "x".repeat(257),
            ..query()
        })
        .await
        .is_err());
}

#[tokio::test]
async fn task_inspection_bounds_legacy_and_structured_content() {
    let (_dir, store) = store().await;
    let result = json!({
        "summary": "x".repeat(17000),
        "artifacts": (0..40).map(|_| "x".repeat(300)).collect::<Vec<_>>(),
        "validation": ["x".repeat(2200)]
    });
    sqlx::query("UPDATE orchestrationTasks SET result = ?, deps = ?, spec = ? WHERE id = 'task'")
        .bind(result.to_string())
        .bind("not-json")
        .bind("界".repeat(17000))
        .execute(store.pool())
        .await
        .unwrap();
    let snapshot = store.orchestration_task_inspection(&query()).await.unwrap();
    assert_eq!(snapshot.description.chars().count(), 16384);
    assert!(snapshot.description_truncated);
    assert!(snapshot.dependencies_truncated);
    assert!(snapshot.result.truncated);
    assert_eq!(snapshot.result.summary.as_ref().unwrap().len(), 16384);
    assert_eq!(snapshot.result.artifacts.len(), 32);
    assert_eq!(snapshot.result.validation[0].len(), 2048);
    sqlx::query("UPDATE orchestrationTasks SET result = ?, deps = ? WHERE id = 'task'")
        .bind("界".repeat(70000))
        .bind("x".repeat(20000))
        .execute(store.pool())
        .await
        .unwrap();
    let snapshot = store.orchestration_task_inspection(&query()).await.unwrap();
    assert!(snapshot.result.truncated);
    assert_eq!(snapshot.result.preview.unwrap().chars().count(), 16384);
    assert!(snapshot.dependencies_truncated);
}
