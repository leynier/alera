use alera_core::runtime::ChatOrchestrationStoreError;
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::native_operation_guard::{require_unfrozen_chat, task_creation_error};
use super::paused_runtime_fixture::PausedChatRuntime;
use super::test_support::{error_code, human, TestHarness};

#[tokio::test]
async fn frozen_person_parent_rejects_before_any_workspace_task_or_provider_effect() {
    for (workspace, state, expected) in [
        ("ws-a", "prepared", "nativeOperationPending"),
        ("ws-b", "uncertain", "nativeOperationUncertain"),
    ] {
        let harness = TestHarness::new().await;
        let parent = harness.create_chat(workspace, "approval-required").await;
        let child = harness.create_chat("ws-a", "approval-required").await;
        let service =
            harness
                .service
                .clone()
                .with_runtime(PausedChatRuntime::with_pending_operation(
                    harness.service.runtime.clone(),
                    &parent,
                    state,
                ));
        let mut payload = delegate_payload(
            "frozen-parent",
            json!({"newWorkspace":{
            "projectId":"project-b", "hostId":"ssh-b", "mode":"worktree", "branch":"frozen-no-work"}}),
        );
        payload["parentChatId"] = json!(parent);
        let error = service
            .handle("delegate", &payload, &human("desktop"))
            .await
            .unwrap_err();
        assert_eq!(error_code(&error), expected);
        let send = json!({"requestId":"frozen-message", "chatId":child, "parentChatId":parent,
            "message":"Do not begin this work.", "expectReply":true});
        assert_eq!(
            error_code(
                &service
                    .handle("send", &send, &human("mobile:phone"))
                    .await
                    .unwrap_err()
            ),
            expected
        );
        assert!(harness.targets.created.lock().unwrap().is_empty());
        assert!(harness.factory.launches.lock().unwrap().is_empty());
        let tasks = service
            .handle("tasks.list", &json!({}), &human("desktop"))
            .await
            .unwrap();
        assert!(tasks["tasks"].as_array().unwrap().is_empty());
        let snapshot = harness.service.runtime.snapshot(&child).await.unwrap();
        assert!(snapshot["items"].as_array().unwrap().is_empty());
        assert!(snapshot["queue"].as_array().unwrap().is_empty());
        harness.finish().await;
    }
}

#[tokio::test]
async fn frozen_bound_parent_cannot_prepare_a_descendant_workspace() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(
            &parent,
            "parent",
            "Remain live to authenticate the bound caller.",
        )
        .await;
    let caller = harness.agent(&parent).await;
    let before = harness.factory.launches.lock().unwrap().len();
    let service = harness
        .service
        .clone()
        .with_runtime(PausedChatRuntime::with_pending_operation(
            harness.service.runtime.clone(),
            &parent,
            "uncertain",
        ));
    let payload = delegate_payload(
        "bound-frozen",
        json!({"newWorkspace":{
        "projectId":"project-b", "hostId":"ssh-b", "mode":"shared"}}),
    );
    let error = service
        .handle("delegate", &payload, &caller)
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "nativeOperationUncertain");
    assert!(harness.targets.created.lock().unwrap().is_empty());
    assert_eq!(harness.factory.launches.lock().unwrap().len(), before);
    let tasks = service
        .handle("tasks.list", &json!({}), &caller)
        .await
        .unwrap();
    assert!(tasks["tasks"].as_array().unwrap().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn frozen_existing_target_rejects_a_standalone_task_before_task_admission() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-b", "approval-required").await;
    let service = harness
        .service
        .clone()
        .with_runtime(PausedChatRuntime::with_pending_operation(
            harness.service.runtime.clone(),
            &child,
            "executing",
        ));
    let payload = delegate_payload("frozen-target", json!({"chat":{"chatId":child}}));
    assert_eq!(
        error_code(
            &service
                .handle("delegate", &payload, &human("desktop"))
                .await
                .unwrap_err()
        ),
        "nativeOperationPending"
    );
    assert!(harness.targets.created.lock().unwrap().is_empty());
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap()["tasks"]
        .as_array()
        .unwrap()
        .is_empty());
    harness.finish().await;
}

#[test]
fn atomic_store_freeze_conflict_keeps_the_native_operation_wire_code() {
    let error = anyhow::Error::new(ChatOrchestrationStoreError::Conflict(
        "native operation pending; reconcile it before creating linked tasks".into(),
    ));
    assert_eq!(
        error_code(&task_creation_error(error)),
        "nativeOperationPending"
    );
    for snapshot in [json!({}), json!({"pendingNativeOperation":null})] {
        assert!(require_unfrozen_chat(&snapshot).is_ok());
    }
}
