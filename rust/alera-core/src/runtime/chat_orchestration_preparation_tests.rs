use serde_json::json;

use super::agent_chat_test_support::store_with_workspace;
use super::*;

pub(super) fn task(id: &str) -> NewChatOrchestrationTask {
    NewChatOrchestrationTask {
        task_id: id.into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "desktop".into(),
        parent_task_id: None,
        parent_chat_id: Some("parent".into()),
        child_chat_id: None,
        project_id: None,
        workspace_id: None,
        host_id: None,
        target: ChatOrchestrationTarget::Workspace {
            workspace_id: "ws".into(),
        },
        title: None,
        role: None,
        brief: "Inspect the child brief.".into(),
        notify: ChatOrchestrationNotify::Never,
        launch_options: None,
    }
}

async fn create(store: &RuntimeStore, id: &str) {
    assert!(matches!(
        store
            .create_chat_orchestration_task(task(id), None)
            .await
            .unwrap(),
        ChatOrchestrationCreateOutcome::Created(_)
    ));
}

#[tokio::test]
async fn created_resources_are_recorded_after_cancellation_without_rewriting_status() {
    let (_directory, store) = store_with_workspace("ws").await;
    create(&store, "cancelled-preparation").await;
    store
        .request_chat_orchestration_cancel("cancelled-preparation")
        .await
        .unwrap();
    let transition = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::CancelRequested],
        ChatOrchestrationTaskStatus::Cancelled,
    );
    let before = match store
        .transition_chat_orchestration_task("cancelled-preparation", &transition)
        .await
        .unwrap()
    {
        ChatOrchestrationTransitionOutcome::Applied { task, .. } => task,
        other => panic!("unexpected transition: {other:?}"),
    };
    let after = store
        .record_chat_orchestration_preparation(
            "cancelled-preparation",
            None,
            Some("project"),
            Some("created-workspace"),
            Some("local"),
        )
        .await
        .unwrap();
    assert_eq!(after.status, before.status);
    assert_eq!(after.revision, before.revision);
    assert_eq!(after.workspace_id.as_deref(), Some("created-workspace"));
    assert!(after.child_chat_id.is_none());
    assert!(store
        .record_chat_orchestration_preparation(
            "cancelled-preparation",
            Some("other-child"),
            None,
            Some("other-workspace"),
            None
        )
        .await
        .is_err());
    let unchanged = store
        .chat_orchestration_task("cancelled-preparation")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(unchanged.workspace_id, after.workspace_id);
    assert!(unchanged.child_chat_id.is_none());
}

#[tokio::test]
async fn task_receipt_finalization_preserves_digest_and_response_compare_and_swap() {
    let (_directory, store) = store_with_workspace("ws").await;
    let initial = json!({"taskId":"receipt-task", "status":"preparing"});
    let mut receipt = ChatOrchestrationReceipt {
        scope: "desktop".into(),
        verb: "delegate".into(),
        request_id: "receipt".into(),
        digest: chat_orchestration_request_digest("delegate", &json!({"task":"brief"})),
        response: initial.clone(),
    };
    store
        .create_chat_orchestration_task(task("receipt-task"), Some(&receipt))
        .await
        .unwrap();
    receipt.response = json!({"taskId":"receipt-task", "status":"running"});
    assert_eq!(
        store
            .finalize_chat_orchestration_receipt(&receipt, &initial)
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::Replay(receipt.response.clone())
    );
    let final_response = receipt.response.clone();
    receipt.response = json!({"taskId":"different-task"});
    assert_eq!(
        store
            .finalize_chat_orchestration_receipt(&receipt, &initial)
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::Replay(final_response.clone())
    );
    receipt.digest = chat_orchestration_request_digest("delegate", &json!({"task":"changed"}));
    assert_eq!(
        store
            .finalize_chat_orchestration_receipt(&receipt, &final_response)
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::Conflict
    );
}

#[tokio::test]
async fn enabling_notifications_offers_an_already_settled_task_once() {
    let (_directory, store) = store_with_workspace("ws").await;
    create(&store, "deferred-notification").await;
    store
        .transition_chat_orchestration_task(
            "deferred-notification",
            &ChatOrchestrationTaskTransition::new(
                [ChatOrchestrationTaskStatus::Preparing],
                ChatOrchestrationTaskStatus::Completed,
            ),
        )
        .await
        .unwrap();
    assert!(store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap()
        .is_empty());
    store
        .set_chat_orchestration_notify("deferred-notification", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    store
        .set_chat_orchestration_notify("deferred-notification", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    let wakes = store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap();
    assert_eq!(wakes.len(), 1);
    assert_eq!(wakes[0].entries.len(), 1);
}

#[tokio::test]
async fn finishing_wait_acknowledges_settled_result_or_enables_later_notification() {
    let (_directory, store) = store_with_workspace("ws").await;
    create(&store, "settled-wait").await;
    store
        .transition_chat_orchestration_task(
            "settled-wait",
            &ChatOrchestrationTaskTransition::new(
                [ChatOrchestrationTaskStatus::Preparing],
                ChatOrchestrationTaskStatus::Completed,
            ),
        )
        .await
        .unwrap();
    store
        .set_chat_orchestration_notify("settled-wait", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    let settled = store
        .finish_chat_orchestration_wait("settled-wait", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    assert_eq!(
        settled.result_delivery,
        ChatOrchestrationResultDelivery::Acknowledged
    );
    assert!(store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap()
        .is_empty());
    create(&store, "timed-out-wait").await;
    let waiting = store
        .finish_chat_orchestration_wait("timed-out-wait", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    assert_eq!(
        waiting.result_delivery,
        ChatOrchestrationResultDelivery::Pending
    );
    store
        .transition_chat_orchestration_task(
            "timed-out-wait",
            &ChatOrchestrationTaskTransition::new(
                [ChatOrchestrationTaskStatus::Preparing],
                ChatOrchestrationTaskStatus::Completed,
            ),
        )
        .await
        .unwrap();
    let wakes = store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap();
    assert_eq!(wakes.len(), 1);
    assert_eq!(wakes[0].entries[0].task_id, "timed-out-wait");
}

pub(super) async fn move_task(
    store: &RuntimeStore,
    id: &str,
    from: ChatOrchestrationTaskStatus,
    to: ChatOrchestrationTaskStatus,
) -> ChatOrchestrationTask {
    match store
        .transition_chat_orchestration_task(id, &ChatOrchestrationTaskTransition::new([from], to))
        .await
        .unwrap()
    {
        ChatOrchestrationTransitionOutcome::Applied { task, .. } => task,
        other => panic!("unexpected transition: {other:?}"),
    }
}

#[tokio::test]
async fn an_open_cohort_keeps_only_the_latest_status_of_each_task() {
    let (_directory, store) = store_with_workspace("ws").await;
    create(&store, "cohort-task").await;
    store
        .set_chat_orchestration_notify("cohort-task", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    use ChatOrchestrationTaskStatus as Status;
    move_task(&store, "cohort-task", Status::Preparing, Status::Running).await;
    move_task(&store, "cohort-task", Status::Running, Status::NeedsInput).await;
    move_task(&store, "cohort-task", Status::NeedsInput, Status::Running).await;
    let task = move_task(&store, "cohort-task", Status::Running, Status::Completed).await;
    let wake = store
        .seal_chat_orchestration_wake("parent")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(wake.entries.len(), 1);
    assert_eq!(wake.entries[0].task_status, Status::Completed);
    assert_eq!(wake.entries[0].task_revision, task.revision);
}

#[tokio::test]
async fn an_older_needs_input_wake_does_not_acknowledge_a_new_completed_result() {
    let (_directory, store) = store_with_workspace("ws").await;
    create(&store, "revised-task").await;
    store
        .set_chat_orchestration_notify("revised-task", ChatOrchestrationNotify::Always)
        .await
        .unwrap();
    use ChatOrchestrationTaskStatus as Status;
    move_task(&store, "revised-task", Status::Preparing, Status::Running).await;
    move_task(&store, "revised-task", Status::Running, Status::NeedsInput).await;
    let earlier = store
        .seal_chat_orchestration_wake("parent")
        .await
        .unwrap()
        .unwrap();
    move_task(&store, "revised-task", Status::NeedsInput, Status::Running).await;
    move_task(&store, "revised-task", Status::Running, Status::Completed).await;
    store
        .ack_chat_orchestration_wake("parent", earlier.generation)
        .await
        .unwrap();
    assert_eq!(
        store
            .chat_orchestration_task("revised-task")
            .await
            .unwrap()
            .unwrap()
            .result_delivery,
        ChatOrchestrationResultDelivery::Pending
    );
    let completed = store
        .seal_chat_orchestration_wake("parent")
        .await
        .unwrap()
        .unwrap();
    assert!(completed.generation > earlier.generation);
    store
        .ack_chat_orchestration_wake("parent", completed.generation)
        .await
        .unwrap();
    assert_eq!(
        store
            .chat_orchestration_task("revised-task")
            .await
            .unwrap()
            .unwrap()
            .result_delivery,
        ChatOrchestrationResultDelivery::Notified
    );
}

#[tokio::test]
async fn a_started_queued_turn_is_immutably_linked_and_recovers_its_actual_result() {
    use super::agent_chat_test_support as chat;
    let (_directory, store) = store_with_workspace("ws").await;
    let child = chat::new_chat_id();
    let mut snapshot = chat::snapshot(&child, "ws", "child-tab", 0);
    snapshot["turns"] = json!([{"turnId":"owned-turn", "status":"completed"}]);
    let mut user = chat::item("owned-user", "user_message", "Brief.");
    user["turnId"] = json!("owned-turn");
    user["clientMessageId"] = json!("chat-orchestration-task:queued-started");
    let mut assistant = chat::item(
        "owned-assistant",
        "assistant_message",
        "Actual queued result.",
    );
    assistant["turnId"] = json!("owned-turn");
    snapshot["items"] = json!([user, assistant]);
    store
        .create_agent_chat(
            &chat::record(&child, "ws", "child-tab", snapshot),
            &chat::tab(&child, "ws", "child-tab"),
            None,
        )
        .await
        .unwrap();
    create(&store, "queued-started").await;
    store
        .record_chat_orchestration_preparation("queued-started", Some(&child), None, None, None)
        .await
        .unwrap();
    let running = move_task(
        &store,
        "queued-started",
        ChatOrchestrationTaskStatus::Preparing,
        ChatOrchestrationTaskStatus::Running,
    )
    .await;
    let linked = store
        .record_chat_orchestration_task_turn("queued-started", &child, "owned-turn")
        .await
        .unwrap();
    assert_eq!(linked.status, running.status);
    assert_eq!(linked.revision, running.revision);
    assert_eq!(
        store
            .record_chat_orchestration_task_turn("queued-started", &child, "owned-turn")
            .await
            .unwrap()
            .revision,
        running.revision
    );
    assert!(store
        .record_chat_orchestration_task_turn("queued-started", &child, "different-turn")
        .await
        .is_err());
    assert!(store
        .record_chat_orchestration_task_turn("queued-started", "different-chat", "owned-turn")
        .await
        .is_err());
    let recovery = store.recover_chat_orchestration().await.unwrap();
    let task = recovery
        .settled
        .iter()
        .find(|task| task.task_id == "queued-started")
        .unwrap();
    assert_eq!(task.status, ChatOrchestrationTaskStatus::Completed);
    assert_eq!(task.result_text.as_deref(), Some("Actual queued result."));
}
