use super::*;

#[tokio::test]
async fn workflow_cleanup_retires_terminal_metadata_without_erasing_launch_history() {
    let (dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&launch.id).await.unwrap();
    let now = chrono::Utc::now();
    let tab = WorkspaceTabRecord {
        id: launch.terminal_handle.clone(),
        workspace_id: request.workspace_id.clone(),
        kind: "terminal".into(),
        title: "Workflow Worker".into(),
        created_at: now,
        updated_at: now,
        payload: serde_json::json!({"terminalSessionId": launch.terminal_handle}),
    };
    store.upsert_workspace_tab(tab.clone()).await.unwrap();
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel-for-cleanup".into(),
            run_id: request.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    for target in store.workflow_cancellation_page().await.unwrap() {
        store
            .settle_workflow_cancellation(&target, None)
            .await
            .unwrap();
    }
    assert!(store.remove_workspace_tab(&tab.id).await.is_err());
    let resource = store
        .workflow_workspace(&request.workspace_id)
        .await
        .unwrap();
    let identity = resource.identity;
    let git = crate::git::preview_workflow_cleanup(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.base_sha,
        &identity.workspace.id,
    )
    .unwrap();
    let preview = store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &request.run_id,
            vec![WorkflowCleanupItem {
                identity: identity.clone(),
                git: git.clone(),
                remove_branch: false,
            }],
        )
        .await
        .unwrap();
    store
        .claim_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .unwrap();
    assert!(store.remove_workspace_tab(&tab.id).await.is_err());
    crate::git::remove_workflow_cleanup_resource(
        &identity.repo_path,
        &crate::git::WorkflowCleanupRemoval {
            cleanup_id: preview.id.clone(),
            resource_id: identity.workspace.id.clone(),
            path: identity.workspace.path.clone(),
            base_sha: identity.base_sha,
            expected_head: git.head_sha,
            remove_branch: false,
        },
    )
    .unwrap();
    store
        .record_workflow_cleanup_retirement(&preview.id, &preview.digest, &request.workspace_id)
        .await
        .unwrap();
    assert!(store.find_workspace_tab(&tab.id).await.unwrap().is_none());
    assert!(store
        .find_workspace(&request.workspace_id)
        .await
        .unwrap()
        .is_none());
    assert!(store
        .workflow_workspace(&request.workspace_id)
        .await
        .is_ok());
    let retained: i64 = sqlx::query_scalar("SELECT count(*) FROM workflowLaunches WHERE id=?")
        .bind(&launch.id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(retained, 1);
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let mut ordinary = tab.clone();
    ordinary.id = "ordinary-cleanup-test".into();
    ordinary.workspace_id = "workspace".into();
    ordinary.kind = "editor".into();
    ordinary.payload = serde_json::json!({});
    reopened.upsert_workspace_tab(ordinary).await.unwrap();
    assert!(
        sqlx::query("UPDATE workspaceTabs SET workspaceId=? WHERE id='ordinary-cleanup-test'")
            .bind(&request.workspace_id)
            .execute(reopened.pool())
            .await
            .is_err()
    );
    assert!(
        sqlx::query("UPDATE workspaces SET id=? WHERE id='workspace'")
            .bind(&request.workspace_id)
            .execute(reopened.pool())
            .await
            .is_err()
    );
    assert!(reopened.upsert_workspace_tab(tab).await.is_err());
    assert!(reopened.upsert_workspace(identity.workspace).await.is_err());
    reopened
        .record_workflow_cleanup_retirement(&preview.id, &preview.digest, &request.workspace_id)
        .await
        .unwrap();
}
