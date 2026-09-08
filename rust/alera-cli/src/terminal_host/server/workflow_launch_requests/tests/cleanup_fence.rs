use super::*;
use crate::terminal_host::protocol::TerminalHostLaunch;
use alera_core::runtime::{ControlWorkflowExecution, WorkflowCleanupItem, WorkflowExecutionAction};

#[tokio::test]
async fn workflow_cleanup_claim_blocks_new_terminal_owners_after_restart() {
    let fixture = Fixture::new("").await;
    let resource = fixture.integration().await;
    let workspace = resource.identity.workspace.clone();
    fixture
        .store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel-for-cleanup".into(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    let git = alera_core::git::preview_workflow_cleanup(
        &resource.identity.repo_path,
        &workspace.path,
        &resource.identity.base_sha,
        &workspace.id,
    )
    .unwrap();
    let preview = fixture
        .store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &fixture.plan.run_id,
            vec![WorkflowCleanupItem {
                identity: resource.identity,
                git,
                remove_branch: false,
            }],
        )
        .await
        .unwrap();
    fixture
        .store
        .require_workspace_outside_cleanup(&workspace.id)
        .await
        .unwrap();
    let now = chrono::Utc::now();
    fixture
        .store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "saved-browser".into(),
            workspace_id: workspace.id.clone(),
            kind: "browser".into(),
            title: "Saved Browser".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"browserProfileId": "default"}),
        })
        .await
        .unwrap();
    fixture
        .store
        .claim_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let (client, _responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(
            1,
            crate::terminal_host::server::ClientState::local(client, true),
        )]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store = alera_core::runtime::RuntimeStore::open(&fixture.runtime)
        .await
        .unwrap();
    actor.runtime_dir = fixture.runtime.clone();
    let error = actor
        .start_new_terminal_session(
            "cleanup-terminal".into(),
            workspace.id.clone(),
            "cleanup-tab".into(),
            workspace.path.clone(),
            TerminalHostLaunch {
                label: "Must Not Launch".into(),
                shell: "must-not-execute-cleanup-test".into(),
                arguments: vec![],
                environment: Default::default(),
            },
            80,
            24,
            vec![],
            0,
            None,
        )
        .await
        .unwrap_err();
    assert!(error
        .wire_message()
        .contains("reserved for reviewed cleanup"));
    assert!(actor.sessions.is_empty());
    actor.handle_browser_driver_request(1, "browser.driver.register", &json!({
        "appInstanceId":"app", "driverInstanceId":"driver", "engine":"test", "platform":"test", "capabilities":["stableGate"]
    })).await.unwrap();
    let error = actor
        .handle_browser_tab_request(
            "browser.tabs.open",
            &json!({"workspaceId":workspace.id,"pageId":"new-browser"}),
        )
        .await
        .unwrap_err();
    assert!(error
        .wire_message()
        .contains("reserved for reviewed cleanup"));
    let sync = actor
        .handle_browser_driver_request(
            1,
            "browser.driver.sync",
            &json!({
                "appInstanceId":"app", "driverInstanceId":"driver",
                "pages":[{"pageId":"saved-browser", "workspaceId":workspace.id}]
            }),
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sync["pages"][0]["accepted"], false);
    assert!(actor.browser.pages().is_empty());
    actor
        .runtime_store
        .require_workspace_outside_cleanup("owner")
        .await
        .unwrap();
    let now = chrono::Utc::now();
    assert!(actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "new-tab".into(),
            workspace_id: workspace.id,
            kind: "terminal".into(),
            title: "Must Not Appear".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .is_err());
    assert!(std::path::Path::new(&workspace.path).exists());
}
