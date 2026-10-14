use serde_json::json;

use super::agent_chat_test_support::{new_chat_id, store_with_workspace};
use super::*;

fn new_task(
    task_id: &str,
    parent_task_id: Option<&str>,
    parent_chat_id: Option<&str>,
    host_id: Option<&str>,
) -> NewChatOrchestrationTask {
    NewChatOrchestrationTask {
        task_id: task_id.into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "desktop".into(),
        parent_task_id: parent_task_id.map(str::to_owned),
        parent_chat_id: parent_chat_id.map(str::to_owned),
        child_chat_id: None,
        project_id: Some("project".into()),
        workspace_id: Some("ws".into()),
        host_id: host_id.map(str::to_owned),
        target: ChatOrchestrationTarget::Chat {
            chat_id: format!("target-{task_id}"),
        },
        title: Some(task_id.into()),
        role: None,
        brief: format!("brief for {task_id}"),
        notify: ChatOrchestrationNotify::Always,
        launch_options: Some(json!({"model": "gpt-6.1-sol"})),
    }
}

async fn create_task(
    store: &RuntimeStore,
    task_id: &str,
    parent_task_id: Option<&str>,
    parent_chat_id: Option<&str>,
) -> ChatOrchestrationTask {
    match store
        .create_chat_orchestration_task(
            new_task(task_id, parent_task_id, parent_chat_id, None),
            None,
        )
        .await
        .unwrap()
    {
        ChatOrchestrationCreateOutcome::Created(task) => *task,
        other => panic!("unexpected task outcome: {other:?}"),
    }
}

fn receipt(request_id: &str, digest: &str) -> ChatOrchestrationReceipt {
    ChatOrchestrationReceipt {
        scope: "desktop".into(),
        verb: "agentChat.send".into(),
        request_id: request_id.into(),
        digest: digest.into(),
        response: json!({"accepted": true}),
    }
}

#[tokio::test]
async fn orchestration_migration_is_idempotent_and_rejects_a_future_version() {
    let directory = tempfile::tempdir().unwrap();
    {
        let first = RuntimeStore::open(directory.path()).await.unwrap();
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name LIKE 'chatOrchestration%'",
        )
        .fetch_one(first.pool())
        .await
        .unwrap();
        assert_eq!(count, 6);
        first.pool().close().await;
    }
    let second = RuntimeStore::open(directory.path()).await.unwrap();
    second.pool().close().await;
    let raw = sqlx::SqlitePool::connect(&format!(
        "sqlite://{}",
        directory.path().join("runtime.sqlite").display()
    ))
    .await
    .unwrap();
    sqlx::query(
        "UPDATE runtimeMetadata SET value = '99' WHERE key = 'chatOrchestration.schemaVersion'",
    )
    .execute(&raw)
    .await
    .unwrap();
    raw.close().await;

    let refused = RuntimeStore::open(directory.path()).await;
    assert!(refused.is_err());
    let check = sqlx::SqlitePool::connect(&format!(
        "sqlite://{}",
        directory.path().join("runtime.sqlite").display()
    ))
    .await
    .unwrap();
    let value: String = sqlx::query_scalar(
        "SELECT value FROM runtimeMetadata WHERE key = 'chatOrchestration.schemaVersion'",
    )
    .fetch_one(&check)
    .await
    .unwrap();
    assert_eq!(value, "99");
    check.close().await;
}

#[tokio::test]
async fn task_transitions_use_revision_compare_and_set_and_preserve_result() {
    let (_dir, store) = store_with_workspace("ws").await;
    let created = create_task(&store, "root", None, None).await;
    assert_eq!(
        (created.status, created.revision),
        (ChatOrchestrationTaskStatus::Preparing, 1)
    );

    let mut running = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Running,
    );
    running.expected_revision = Some(1);
    let applied = store
        .transition_chat_orchestration_task("root", &running)
        .await
        .unwrap();
    let ChatOrchestrationTransitionOutcome::Applied { task, .. } = applied else {
        panic!("expected running transition");
    };
    assert_eq!(
        (task.status, task.revision),
        (ChatOrchestrationTaskStatus::Running, 2)
    );

    running.expected_revision = Some(1);
    let rejected = store
        .transition_chat_orchestration_task("root", &running)
        .await
        .unwrap();
    let ChatOrchestrationTransitionOutcome::Rejected { current } = rejected else {
        panic!("stale transition was applied");
    };
    assert_eq!(current.revision, 2);

    let mut completed = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Running],
        ChatOrchestrationTaskStatus::Completed,
    );
    completed.expected_revision = Some(2);
    completed.result_text = Some("done".into());
    completed.child_turn_id = Some("turn-1".into());
    let outcome = store
        .transition_chat_orchestration_task("root", &completed)
        .await
        .unwrap();
    let ChatOrchestrationTransitionOutcome::Applied { task, .. } = outcome else {
        panic!("expected completion transition");
    };
    assert_eq!(task.status, ChatOrchestrationTaskStatus::Completed);
    assert_eq!(task.revision, 3);
    assert_eq!(task.result_text.as_deref(), Some("done"));
    assert!(task.settled_at.is_some());
}

#[tokio::test]
async fn cancel_marks_the_entire_unsettled_descendant_tree_and_lineage_is_queryable() {
    let (_dir, store) = store_with_workspace("ws").await;
    let root = create_task(&store, "root", None, Some("parent")).await;
    let child = create_task(&store, "child", Some(&root.task_id), Some("child")).await;
    let grandchild = create_task(
        &store,
        "grandchild",
        Some(&child.task_id),
        Some("grandchild"),
    )
    .await;
    let requested = store
        .request_chat_orchestration_cancel("root")
        .await
        .unwrap();
    assert_eq!(requested.requested.len(), 3);
    assert!(requested
        .requested
        .iter()
        .all(|task| task.status == ChatOrchestrationTaskStatus::CancelRequested));

    let descendants = store
        .chat_orchestration_task_descendants("root")
        .await
        .unwrap();
    assert_eq!(
        descendants
            .iter()
            .map(|task| task.task_id.as_str())
            .collect::<Vec<_>>(),
        ["child", "grandchild"]
    );
    let ancestors = store
        .chat_orchestration_task_ancestors(&grandchild.task_id)
        .await
        .unwrap();
    assert_eq!(
        ancestors
            .iter()
            .map(|task| task.task_id.as_str())
            .collect::<Vec<_>>(),
        ["child", "root"]
    );
    assert!(store
        .is_chat_orchestration_task_in_lineage("parent", &grandchild.task_id)
        .await
        .unwrap());
}

#[tokio::test]
async fn task_listing_filters_status_and_pages_by_sequence() {
    let (_dir, store) = store_with_workspace("ws").await;
    create_task(&store, "first", None, None).await;
    create_task(&store, "second", None, None).await;
    let page = store
        .list_chat_orchestration_tasks(&ChatOrchestrationTaskFilter {
            statuses: vec![ChatOrchestrationTaskStatus::Preparing],
            limit: Some(1),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(page.tasks.len(), 1);
    assert_eq!(page.tasks[0].task_id, "second");
    let next = store
        .list_chat_orchestration_tasks(&ChatOrchestrationTaskFilter {
            statuses: vec![ChatOrchestrationTaskStatus::Preparing],
            before_sequence: page.next_before_sequence,
            limit: Some(10),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(
        next.tasks
            .iter()
            .map(|task| task.task_id.as_str())
            .collect::<Vec<_>>(),
        ["first"]
    );
}

#[tokio::test]
async fn receipts_are_canonical_conflict_safe_and_atomic() {
    let (_dir, store) = store_with_workspace("ws").await;
    let payload = json!({"requestId": "ignored", "b": 2, "a": 1});
    let digest = chat_orchestration_request_digest("agentChat.send", &payload);
    let first = receipt("r1", &digest);
    assert_eq!(
        store
            .record_chat_orchestration_receipt(None, &first)
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::New
    );
    assert!(matches!(
        store
            .record_chat_orchestration_receipt(None, &first)
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::Replay(_)
    ));
    let conflict = receipt("r1", "different-digest");
    assert_eq!(
        store
            .record_chat_orchestration_receipt(None, &conflict)
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::Conflict
    );

    let second = receipt("r2", &digest);
    let (left, right) = tokio::join!(
        store.record_chat_orchestration_receipt(None, &second),
        store.record_chat_orchestration_receipt(None, &second),
    );
    let outcomes = [left.unwrap(), right.unwrap()];
    assert_eq!(
        outcomes
            .iter()
            .filter(|outcome| **outcome == ChatOrchestrationReceiptCheck::New)
            .count(),
        1
    );
    assert_eq!(
        outcomes
            .iter()
            .filter(|outcome| matches!(outcome, ChatOrchestrationReceiptCheck::Replay(_)))
            .count(),
        1
    );
}

#[tokio::test]
async fn credentials_supersede_old_generations_and_revoke() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let first_secret = new_chat_orchestration_credential_secret();
    let first_hash = hash_chat_orchestration_credential(&first_secret);
    store
        .issue_chat_orchestration_credential(&chat_id, 1, &first_hash)
        .await
        .unwrap();
    assert!(store
        .find_chat_orchestration_credential(&first_hash)
        .await
        .unwrap()
        .is_some());
    let second_secret = new_chat_orchestration_credential_secret();
    let second_hash = hash_chat_orchestration_credential(&second_secret);
    store
        .issue_chat_orchestration_credential(&chat_id, 2, &second_hash)
        .await
        .unwrap();
    assert!(store
        .find_chat_orchestration_credential(&first_hash)
        .await
        .unwrap()
        .is_none());
    let older = store
        .issue_chat_orchestration_credential(&chat_id, 1, &first_hash)
        .await;
    assert!(older.is_err());
    assert_eq!(
        store
            .revoke_chat_orchestration_credentials(&chat_id, "chatClosed")
            .await
            .unwrap(),
        1
    );
    assert!(store
        .find_chat_orchestration_credential(&second_hash)
        .await
        .unwrap()
        .is_none());
}
