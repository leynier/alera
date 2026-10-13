use serde_json::json;

use super::agent_chat_test_support::{create_chat, item, next_snapshot, store_with_workspace};
use super::*;

fn task_for_parent(task_id: &str, parent_chat_id: &str) -> NewChatOrchestrationTask {
    NewChatOrchestrationTask {
        task_id: task_id.into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "chat:parent".into(),
        parent_task_id: None,
        parent_chat_id: Some(parent_chat_id.into()),
        child_chat_id: None,
        project_id: None,
        workspace_id: None,
        host_id: None,
        target: ChatOrchestrationTarget::Chat {
            chat_id: format!("child-{task_id}"),
        },
        title: None,
        role: None,
        brief: format!("work {task_id}"),
        notify: ChatOrchestrationNotify::Always,
        launch_options: None,
    }
}

async fn task(store: &RuntimeStore, task_id: &str, parent_chat_id: &str) -> ChatOrchestrationTask {
    match store
        .create_chat_orchestration_task(task_for_parent(task_id, parent_chat_id), None)
        .await
        .unwrap()
    {
        ChatOrchestrationCreateOutcome::Created(task) => *task,
        other => panic!("unexpected task outcome: {other:?}"),
    }
}

#[tokio::test]
async fn completions_merge_into_one_wake_then_seal_ack_and_open_a_new_generation() {
    let (_dir, store) = store_with_workspace("ws").await;
    let first = task(&store, "first", "parent").await;
    let second = task(&store, "second", "parent").await;
    let transition = |revision: i64| {
        let mut transition = ChatOrchestrationTaskTransition::new(
            [ChatOrchestrationTaskStatus::Preparing],
            ChatOrchestrationTaskStatus::Completed,
        );
        transition.expected_revision = Some(revision);
        transition.result_text = Some("done".into());
        transition
    };
    let first_outcome = store
        .transition_chat_orchestration_task(&first.task_id, &transition(first.revision))
        .await
        .unwrap();
    assert!(matches!(
        first_outcome,
        ChatOrchestrationTransitionOutcome::Applied { wake: Some(_), .. }
    ));
    let second_outcome = store
        .transition_chat_orchestration_task(&second.task_id, &transition(second.revision))
        .await
        .unwrap();
    let ChatOrchestrationTransitionOutcome::Applied {
        wake: Some(wake), ..
    } = second_outcome
    else {
        panic!("second completion did not join a wake");
    };
    assert_eq!(wake.generation, 1);
    assert_eq!(wake.entries.len(), 2);

    let duplicate = store
        .transition_chat_orchestration_task(&second.task_id, &transition(second.revision))
        .await
        .unwrap();
    assert!(matches!(
        duplicate,
        ChatOrchestrationTransitionOutcome::Rejected { .. }
    ));

    let sealed = store
        .seal_chat_orchestration_wake("parent")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sealed.status, ChatOrchestrationWakeStatus::Sealed);
    let delivered = store
        .ack_chat_orchestration_wake("parent", sealed.generation)
        .await
        .unwrap();
    assert_eq!(delivered.status, ChatOrchestrationWakeStatus::Delivered);
    let repeated = store
        .ack_chat_orchestration_wake("parent", sealed.generation)
        .await
        .unwrap();
    assert_eq!(repeated.status, ChatOrchestrationWakeStatus::Delivered);

    let third = task(&store, "third", "parent").await;
    let third_outcome = store
        .transition_chat_orchestration_task(&third.task_id, &transition(third.revision))
        .await
        .unwrap();
    let ChatOrchestrationTransitionOutcome::Applied {
        wake: Some(next), ..
    } = third_outcome
    else {
        panic!("third completion did not open a new wake");
    };
    assert_eq!(next.generation, 2);
}

#[tokio::test]
async fn acknowledging_a_result_withdraws_an_open_wake() {
    let (_dir, store) = store_with_workspace("ws").await;
    let task = task(&store, "withdraw", "parent").await;
    let mut complete = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Completed,
    );
    complete.expected_revision = Some(task.revision);
    store
        .transition_chat_orchestration_task(&task.task_id, &complete)
        .await
        .unwrap();
    assert_eq!(
        store
            .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
            .await
            .unwrap()
            .len(),
        1
    );
    let acknowledged = store
        .acknowledge_chat_orchestration_result(&task.task_id)
        .await
        .unwrap();
    assert_eq!(
        acknowledged.result_delivery,
        ChatOrchestrationResultDelivery::Acknowledged
    );
    assert!(store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap()
        .is_empty());
}

async fn record_child_turn(store: &RuntimeStore, chat_id: &str, turn_id: &str, status: &str) {
    let (cursor, mut snapshot) = next_snapshot(store, chat_id).await;
    snapshot["turns"] = json!([{"turnId": turn_id, "status": status}]);
    let mut assistant = item("assistant", "assistant_message", "child result");
    assistant["turnId"] = json!(turn_id);
    let delta = json!({"turns": snapshot["turns"], "items": [assistant]});
    store
        .commit_agent_chat(chat_id, cursor, &snapshot, &delta, None)
        .await
        .unwrap();
}

#[tokio::test]
async fn recovery_settles_committed_turns_missing_children_cancels_and_keeps_remote() {
    let (_dir, store) = store_with_workspace("ws").await;
    let parent = create_chat(&store, "ws", "parent-tab").await;
    let child = create_chat(&store, "ws", "child-tab").await;
    record_child_turn(&store, &child, "child-turn", "completed").await;

    let mut completed = task(&store, "completed", &parent).await;
    completed.child_chat_id = Some(child.clone());
    completed.child_turn_id = Some("child-turn".into());
    sqlx::query(
        "UPDATE chatOrchestrationTasks SET childChatId = ?, childTurnId = ? WHERE taskId = ?",
    )
    .bind(&child)
    .bind("child-turn")
    .bind(&completed.task_id)
    .execute(store.pool())
    .await
    .unwrap();
    let mut running = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Running,
    );
    running.expected_revision = Some(completed.revision);
    store
        .transition_chat_orchestration_task(&completed.task_id, &running)
        .await
        .unwrap();

    let missing = task(&store, "missing", &parent).await;
    let mut missing_running = running.clone();
    missing_running.expected_revision = Some(missing.revision);
    store
        .transition_chat_orchestration_task(&missing.task_id, &missing_running)
        .await
        .unwrap();
    sqlx::query(
        "UPDATE chatOrchestrationTasks SET childChatId = 'gone-chat' WHERE taskId = 'missing'",
    )
    .execute(store.pool())
    .await
    .unwrap();

    let cancelled = task(&store, "cancelled", &parent).await;
    let mut cancel_running = running.clone();
    cancel_running.expected_revision = Some(cancelled.revision);
    store
        .transition_chat_orchestration_task(&cancelled.task_id, &cancel_running)
        .await
        .unwrap();
    store
        .request_chat_orchestration_cancel(&cancelled.task_id)
        .await
        .unwrap();

    let _remote = task(&store, "remote", &parent).await;
    sqlx::query("UPDATE chatOrchestrationTasks SET hostId = 'ssh-1' WHERE taskId = 'remote'")
        .execute(store.pool())
        .await
        .unwrap();

    let recovery = store.recover_chat_orchestration().await.unwrap();
    let statuses = recovery
        .settled
        .iter()
        .map(|task| (task.task_id.as_str(), task.status))
        .collect::<Vec<_>>();
    assert!(statuses.contains(&("completed", ChatOrchestrationTaskStatus::Completed)));
    assert!(statuses.contains(&("missing", ChatOrchestrationTaskStatus::Interrupted)));
    assert!(statuses.contains(&("cancelled", ChatOrchestrationTaskStatus::Cancelled)));
    assert_eq!(
        recovery
            .remote
            .iter()
            .map(|task| task.task_id.as_str())
            .collect::<Vec<_>>(),
        ["remote"]
    );
    let missing_task = store
        .chat_orchestration_task("missing")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        missing_task.error_code.as_deref(),
        Some(CHAT_ORCHESTRATION_INTERRUPT_CHILD_CHAT_MISSING)
    );
    let completed_task = store
        .chat_orchestration_task("completed")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(completed_task.result_text.as_deref(), Some("child result"));
}

#[tokio::test]
async fn recovery_revokes_credentials_and_can_resume_only_with_native_id_and_capability() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let secret = new_chat_orchestration_credential_secret();
    let hash = hash_chat_orchestration_credential(&secret);
    store
        .issue_chat_orchestration_credential(&chat_id, 1, &hash)
        .await
        .unwrap();
    assert_eq!(
        store
            .revoke_all_chat_orchestration_credentials("restart")
            .await
            .unwrap(),
        1
    );
    assert!(store
        .find_chat_orchestration_credential(&hash)
        .await
        .unwrap()
        .is_none());
    let record = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert!(record.native_thread_id.is_some());
    assert_eq!(
        record.snapshot["session"]["capabilities"].get("resume"),
        None
    );
}
