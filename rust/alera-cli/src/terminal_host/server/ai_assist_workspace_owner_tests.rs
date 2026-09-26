use super::checkout_buffer_guards_tests::fixture;
use serde_json::json;

#[tokio::test]
async fn ai_assist_resolves_tab_owner_rejects_conflicts_and_keeps_remote_workspaces() {
    let (_root, actor) = fixture().await;
    let workspace = actor
        .resolve_ai_assist_workspace(None, Some("task-editor".into()))
        .await
        .unwrap();
    assert_eq!(workspace.id, "task");
    assert!(actor
        .resolve_ai_assist_workspace(Some("sibling".into()), Some("task-editor".into()))
        .await
        .unwrap_err()
        .to_string()
        .contains("different workspace"));
    let mut remote = workspace;
    remote.host_id = "ssh".into();
    actor.runtime_store.upsert_workspace(remote).await.unwrap();
    // A remote workspace resolves: the caller forwards its generation to the
    // host that owns the checkout instead of refusing it.
    let resolved = actor
        .resolve_ai_assist_workspace(Some("task".into()), None)
        .await
        .unwrap();
    assert!(crate::ssh_remote::is_remote_host_id(Some(
        &resolved.host_id
    )));
}

#[tokio::test]
async fn ai_assist_respects_removal_guard_without_blocking_shared_neighbors() {
    let (_root, mut actor) = fixture().await;
    actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id":"task","operation":"removeShared"}),
        )
        .await
        .unwrap();
    assert!(actor
        .resolve_ai_assist_workspace(Some("task".into()), None)
        .await
        .is_err());
    assert!(actor
        .resolve_ai_assist_workspace(Some("sibling".into()), None)
        .await
        .is_ok());
}

#[tokio::test]
async fn ai_assist_ownership_keeps_shared_jobs_independent_until_the_future_finishes() {
    use super::ai_assist_operation_registry::AiAssistOperationRegistry;
    let (_root, actor) = fixture().await;
    let registry = std::sync::Arc::new(AiAssistOperationRegistry::default());
    let workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    let sibling = actor
        .runtime_store
        .find_workspace("sibling")
        .await
        .unwrap()
        .unwrap();
    let (job, mut cancellation) = registry
        .register("speech-job".into(), Some(workspace.clone()))
        .unwrap();
    assert!(registry
        .require_workspace_idle(&workspace, "Hand Off")
        .unwrap_err()
        .to_string()
        .contains("speech-job"));
    assert!(registry
        .require_workspace_idle(&sibling, "workspace removal")
        .is_ok());
    assert!(registry.cancel("speech-job").unwrap());
    assert_eq!(cancellation.try_recv(), Ok(()));
    assert!(registry
        .require_workspace_idle(&workspace, "Hand Off")
        .is_err());
    drop(job);
    assert!(registry
        .require_workspace_idle(&workspace, "Hand Off")
        .is_ok());
}

#[tokio::test]
async fn runtime_removal_reports_the_active_ai_assist_operation_before_deleting_records() {
    let (_root, mut actor) = fixture().await;
    let mut workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    workspace.id = uuid::Uuid::new_v4().to_string();
    workspace.instance_id = uuid::Uuid::new_v4().to_string();
    actor
        .runtime_store
        .upsert_workspace(workspace.clone())
        .await
        .unwrap();
    let operation = uuid::Uuid::new_v4().to_string();
    let (_job, _cancel) = super::ai_assist_operation_registry::active_generations()
        .register(operation.clone(), Some(workspace.clone()))
        .unwrap();
    let request = super::runtime_mutations::RuntimeMutationRequest::RemoveWorkspace {
        workspace_id: workspace.id.clone(),
        cascade_tabs: true,
    };
    let error = match actor.prepare_runtime_mutation(&request).await {
        Ok(_) => panic!("an active workspace job must prevent retirement"),
        Err(error) => error,
    };
    assert!(error.to_string().contains(&operation), "{error}");
    assert!(actor
        .runtime_store
        .find_workspace(&workspace.id)
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn shared_removal_cancels_only_owned_jobs_and_waits_for_their_completion() {
    use super::ai_assist_operation_registry::active_generations;
    use super::ai_assist_process_journal::AiAssistProcessOwner;
    use crate::managed_workspace::ManagedWorkspaceRemoveRequest;
    use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;
    let (_root, mut actor) = fixture().await;
    let mut workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    workspace.id = uuid::Uuid::new_v4().to_string();
    workspace.instance_id = uuid::Uuid::new_v4().to_string();
    actor
        .runtime_store
        .upsert_workspace(workspace.clone())
        .await
        .unwrap();
    let owner = AiAssistProcessOwner {
        store: actor.runtime_store.clone(),
        workspace: workspace.clone(),
        operation_id: uuid::Uuid::new_v4().to_string(),
    };
    let mut journal = owner.begin().await.unwrap();
    let (registration, mut cancel) = active_generations()
        .register(owner.operation_id.clone(), Some(workspace.clone()))
        .unwrap();
    let sibling = actor
        .runtime_store
        .find_workspace("sibling")
        .await
        .unwrap()
        .unwrap();
    let (_neighbor, mut neighbor_cancel) = active_generations()
        .register(uuid::Uuid::new_v4().to_string(), Some(sibling))
        .unwrap();
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id":workspace.id,"operation":"removeShared"}),
        )
        .await
        .unwrap();
    let guard_id = acquired["guardId"].as_str().unwrap();
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId":guard_id,"blockers":[]}))
            .unwrap();
    }
    let proof = actor
        .claim_checkout_buffer_guard(
            3,
            81,
            &workspace.id,
            "removeShared",
            &json!({"bufferGuardId":guard_id}),
        )
        .unwrap();
    let removal = ManagedWorkspaceRemoveRequest {
        id: workspace.id.clone(),
        delete_branch: Some(false),
        active_workspace_id: None,
        close_sessions: true,
    };
    let mut shutdown = actor
        .prepare_runtime_mutation(
            &super::runtime_mutations::RuntimeMutationRequest::RemoveSharedWorkspace {
                remote_automation_cleanup: None,
                automation_cleanup: None,
                request: removal.clone(),
                buffer_guard: proof,
                remote_retirement: None,
            },
        )
        .await
        .unwrap();
    assert_eq!(cancel.try_recv(), Ok(()));
    assert_eq!(
        neighbor_cancel.try_recv(),
        Err(tokio::sync::oneshot::error::TryRecvError::Empty)
    );
    assert!(
        tokio::time::timeout(std::time::Duration::from_millis(20), shutdown.wait())
            .await
            .is_err()
    );
    assert!(
        crate::shared_workspace_removal::remove_shared_workspace(&owner.store, &removal)
            .await
            .is_err()
    );
    journal.spawn_failed().await.unwrap();
    drop(registration);
    let mut retry = WorkspaceShutdown::default();
    retry.merge(shutdown);
    retry.wait().await.unwrap();
    crate::shared_workspace_removal::remove_shared_workspace(&owner.store, &removal)
        .await
        .unwrap();
    assert!(owner
        .store
        .find_workspace(&workspace.id)
        .await
        .unwrap()
        .is_none());
    assert!(owner
        .store
        .find_workspace("sibling")
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        neighbor_cancel.try_recv(),
        Err(tokio::sync::oneshot::error::TryRecvError::Empty)
    );
}
