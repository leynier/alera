use serde_json::json;

use super::agent_chat_test_support::store_with_workspace;
use super::chat_orchestration_preparation_tests::{move_task, task};
use super::*;

#[tokio::test]
async fn recursive_cancellation_commits_bound_authority_and_preserves_it_after_reopen() {
    let (directory, store) = store_with_workspace("ws").await;
    for (id, parent) in [
        ("cancel-root", None),
        ("cancel-child", Some("cancel-root")),
        ("settled-child", Some("cancel-root")),
    ] {
        let mut value = task(id);
        value.parent_task_id = parent.map(str::to_owned);
        value.host_id = Some("remote-host".into());
        value.launch_options = Some(json!({"runtimeMode":"auto", "providerInstanceId":"provider"}));
        store
            .create_chat_orchestration_task(value, None)
            .await
            .unwrap();
    }
    let settled = move_task(
        &store,
        "settled-child",
        ChatOrchestrationTaskStatus::Preparing,
        ChatOrchestrationTaskStatus::Completed,
    )
    .await;
    let cancelled = store
        .request_chat_orchestration_cancel_with_authority(
            "cancel-root",
            "chat:parent",
            Some("auto"),
        )
        .await
        .unwrap();
    assert_eq!(cancelled.requested.len(), 2);
    for task in &cancelled.requested {
        assert_eq!(task.status, ChatOrchestrationTaskStatus::CancelRequested);
        let options = task.launch_options.as_ref().unwrap();
        assert_eq!(options["cancellationRuntimeModeCeiling"], "auto");
        assert_eq!(options["cancellationCallerScope"], "chat:parent");
        assert_eq!(options["cancellationPolicy"], "bound");
        assert_eq!(options["providerInstanceId"], "provider");
    }
    store.pool().close().await;
    drop(store);
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let recovery = store.recover_chat_orchestration().await.unwrap();
    assert!(recovery.settled.is_empty());
    assert_eq!(recovery.remote.len(), 2);
    assert!(recovery
        .remote
        .iter()
        .all(
            |task| task.launch_options.as_ref().unwrap()["cancellationRuntimeModeCeiling"]
                == "auto"
        ));
    let unchanged = store
        .chat_orchestration_task("settled-child")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(unchanged.revision, settled.revision);
    assert!(unchanged
        .launch_options
        .as_ref()
        .unwrap()
        .get("cancellationPolicy")
        .is_none());
}

#[tokio::test]
async fn a_human_override_clears_the_pending_bound_ceiling_without_a_new_status_revision() {
    let (_directory, store) = store_with_workspace("ws").await;
    store
        .create_chat_orchestration_task(task("override"), None)
        .await
        .unwrap();
    let bound = store
        .request_chat_orchestration_cancel_with_authority("override", "chat:parent", Some("auto"))
        .await
        .unwrap()
        .task;
    let human = store
        .request_chat_orchestration_cancel_with_authority("override", "desktop", None)
        .await
        .unwrap()
        .task;
    assert_eq!(human.status, ChatOrchestrationTaskStatus::CancelRequested);
    assert_eq!(human.revision, bound.revision);
    let options = human.launch_options.as_ref().unwrap();
    assert_eq!(options["cancellationPolicy"], "human");
    assert_eq!(options["cancellationCallerScope"], "desktop");
    assert!(options["cancellationRuntimeModeCeiling"].is_null());
    let retry = store
        .request_chat_orchestration_cancel_with_authority(
            "override",
            "chat:parent",
            Some("approval-required"),
        )
        .await
        .unwrap()
        .task;
    assert_eq!(retry.revision, human.revision);
    assert_eq!(retry.launch_options, human.launch_options);
}

#[tokio::test]
async fn invalid_cancellation_authority_does_not_admit_a_cancel_request() {
    let (_directory, store) = store_with_workspace("ws").await;
    store
        .create_chat_orchestration_task(task("invalid-authority"), None)
        .await
        .unwrap();
    assert!(store
        .request_chat_orchestration_cancel_with_authority(
            "invalid-authority",
            "chat:parent",
            Some("unknown")
        )
        .await
        .is_err());
    assert!(store
        .request_chat_orchestration_cancel_with_authority("invalid-authority", "", None)
        .await
        .is_err());
    let task = store
        .chat_orchestration_task("invalid-authority")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, ChatOrchestrationTaskStatus::Preparing);
    assert_eq!(task.revision, 1);
    assert!(task.launch_options.is_none());
}
