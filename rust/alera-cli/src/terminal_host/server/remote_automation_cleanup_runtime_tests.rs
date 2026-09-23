use super::runtime_mutations::{run_runtime_mutation, RuntimeMutationRequest};
use super::{checkout_buffer_guards_tests::fixture, ServerActor};
use alera_core::runtime::RemoteAutomationCleanup;
use serde_json::json;

async fn owner() -> (tempfile::TempDir, ServerActor, RemoteAutomationCleanup) {
    let (root, actor) = fixture().await;
    actor
        .runtime_store
        .remove_workspace_tab("task-editor")
        .await
        .unwrap();
    let workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    crate::remote_owner_terminal_ownership::register_tab(
        &actor.runtime_store,
        &workspace,
        "owned",
        "session",
        Some("run"),
    )
    .await
    .unwrap();
    let scope = RemoteAutomationCleanup {
        run_id: "run".into(),
        workspace,
        tab_ids: vec!["owned".into()],
    };
    (root, actor, scope)
}

async fn mutation(
    actor: &mut ServerActor,
    scope: &RemoteAutomationCleanup,
) -> RuntimeMutationRequest {
    let scope = actor
        .requested_remote_automation_cleanup(3, "task", &json!({"remoteAutomationCleanup":scope}))
        .await
        .unwrap();
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id":"task","operation":"removeShared"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId":id,"blockers":[]}))
            .unwrap();
    }
    let buffer_guard = actor
        .claim_checkout_buffer_guard(3, 9, "task", "removeShared", &json!({"bufferGuardId":id}))
        .unwrap();
    RuntimeMutationRequest::RemoveSharedWorkspace {
        remote_automation_cleanup: scope,
        automation_cleanup: None,
        remote_retirement: None,
        buffer_guard,
        request: crate::managed_workspace::ManagedWorkspaceRemoveRequest {
            id: "task".into(),
            close_sessions: true,
            delete_branch: Some(false),
            active_workspace_id: None,
        },
    }
}

#[tokio::test]
async fn owner_scope_requires_buffer_proof_and_rejects_malformed_or_mixed_scopes() {
    let (_root, mut actor, scope) = owner().await;
    for value in [json!(null), json!(false), json!({})] {
        assert!(actor
            .requested_remote_automation_cleanup(
                3,
                "task",
                &json!({"remoteAutomationCleanup":value})
            )
            .await
            .is_err());
    }
    assert!(actor
        .requested_remote_automation_cleanup(
            3,
            "task",
            &json!({"remoteAutomationCleanup":scope,"automationCleanupRunId":"run"})
        )
        .await
        .is_err());
    let error = actor
        .try_start_deferred_request(
            3,
            9,
            "workspace.removeShared",
            &json!({"id":"task","closeSessions":true,"remoteAutomationCleanup":scope}),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("buffer"), "{error}");
    assert!(actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn user_tab_before_process_preparation_preserves_running_owner_session() {
    let (_root, mut actor, scope) = owner().await;
    let request = mutation(&mut actor, &scope).await;
    let mut session = crate::terminal_host::session::Session::driver_test_stub("session", 80, 24);
    session.workspace_id = "task".into();
    actor.sessions.insert("session".into(), session);
    crate::remote_owner_terminal_ownership::register_tab(
        &actor.runtime_store,
        &scope.workspace,
        "user",
        "user-session",
        None,
    )
    .await
    .unwrap();
    assert!(actor.prepare_runtime_mutation(&request).await.is_err());
    assert!(actor.sessions["session"].running());
    assert!(actor
        .runtime_store
        .find_workspace_tab("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn owner_mutation_retires_only_scoped_task_and_preserves_shared_files() {
    let (root, mut actor, scope) = owner().await;
    let file = root.path().join("shared-file");
    std::fs::write(&file, "retained").unwrap();
    let request = mutation(&mut actor, &scope).await;
    actor.prepare_runtime_mutation(&request).await.unwrap();
    let outcome = run_runtime_mutation(actor.runtime_store.clone(), request).await;
    if let Err(error) = outcome.result {
        panic!("{error}");
    }
    assert!(actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .is_none());
    assert!(actor
        .runtime_store
        .find_workspace("sibling")
        .await
        .unwrap()
        .is_some());
    assert!(actor
        .runtime_store
        .find_workspace_tab("sibling-editor")
        .await
        .unwrap()
        .is_some());
    assert_eq!(std::fs::read_to_string(file).unwrap(), "retained");
    assert!(actor
        .runtime_store
        .workspace_retirement_receipt("task", &scope.workspace.instance_id)
        .await
        .unwrap()
        .is_some());
}
