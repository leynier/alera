use serde_json::json;

use super::agent_chat_test_support::store_with_workspace;
use super::chat_orchestration_preparation_tests::{move_task, task};
use super::*;

#[tokio::test]
async fn restart_restores_an_interrupted_bounded_wait_notification_policy() {
    let (_directory, store) = store_with_workspace("ws").await;
    let mut waiting = task("waiting-restart");
    waiting.launch_options = Some(json!({"waitNotify":"settled_only"}));
    store
        .create_chat_orchestration_task(waiting, None)
        .await
        .unwrap();
    let recovery = store.recover_chat_orchestration().await.unwrap();
    let task = recovery
        .settled
        .iter()
        .find(|task| task.task_id == "waiting-restart")
        .unwrap();
    assert_eq!(task.status, ChatOrchestrationTaskStatus::Interrupted);
    assert_eq!(task.notify, ChatOrchestrationNotify::SettledOnly);
    assert!(task
        .launch_options
        .as_ref()
        .unwrap()
        .get("waitNotify")
        .is_none());
    assert_eq!(recovery.wakes.len(), 1);
    assert_eq!(recovery.wakes[0].entries[0].task_id, "waiting-restart");
}

#[tokio::test]
async fn restart_restores_a_remote_wait_policy_before_preserving_the_live_task() {
    let (_directory, store) = store_with_workspace("ws").await;
    let mut waiting = task("remote-wait-restart");
    waiting.host_id = Some("remote-host".into());
    waiting.launch_options = Some(json!({"waitNotify":"always"}));
    store
        .create_chat_orchestration_task(waiting, None)
        .await
        .unwrap();
    use ChatOrchestrationTaskStatus as Status;
    let before = move_task(
        &store,
        "remote-wait-restart",
        Status::Preparing,
        Status::Running,
    )
    .await;
    let recovery = store.recover_chat_orchestration().await.unwrap();
    assert!(recovery.settled.is_empty());
    let task = &recovery.remote[0];
    assert_eq!(task.status, Status::Running);
    assert_eq!(task.revision, before.revision);
    assert_eq!(task.notify, ChatOrchestrationNotify::Always);
    assert!(task
        .launch_options
        .as_ref()
        .unwrap()
        .get("waitNotify")
        .is_none());
    assert!(recovery.wakes.is_empty());
    move_task(
        &store,
        "remote-wait-restart",
        Status::Running,
        Status::Completed,
    )
    .await;
    let wakes = store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap();
    assert_eq!(wakes.len(), 1);
    assert_eq!(wakes[0].entries[0].task_id, "remote-wait-restart");
}

#[tokio::test]
async fn restart_offers_a_result_that_settled_before_its_bounded_wait_returned() {
    let (_directory, store) = store_with_workspace("ws").await;
    let mut waiting = task("completed-wait-restart");
    waiting.launch_options = Some(json!({"waitNotify":"settled_only"}));
    store
        .create_chat_orchestration_task(waiting, None)
        .await
        .unwrap();
    use ChatOrchestrationTaskStatus as Status;
    let before = move_task(
        &store,
        "completed-wait-restart",
        Status::Preparing,
        Status::Completed,
    )
    .await;
    let recovery = store.recover_chat_orchestration().await.unwrap();
    assert!(recovery.settled.is_empty());
    let task = store
        .chat_orchestration_task("completed-wait-restart")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, Status::Completed);
    assert_eq!(task.revision, before.revision);
    assert_eq!(task.notify, ChatOrchestrationNotify::SettledOnly);
    assert_eq!(recovery.wakes.len(), 1);
    assert_eq!(
        recovery.wakes[0].entries[0].task_id,
        "completed-wait-restart"
    );
    assert_eq!(
        store
            .recover_chat_orchestration()
            .await
            .unwrap()
            .wakes
            .len(),
        1
    );
}
