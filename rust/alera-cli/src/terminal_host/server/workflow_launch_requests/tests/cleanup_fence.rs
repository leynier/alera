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
    let (client, mut responses) = ClientHandle::test_channels();
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
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Must Not Appear".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .is_err());
    assert!(std::path::Path::new(&workspace.path).exists());
    assert!(actor
        .inspect_workflow_cleanup_owners(&preview.id, "forged", &workspace.id)
        .await
        .is_err());
    let mut live = crate::terminal_host::session::Session::driver_test_stub("live-cleanup", 80, 24);
    live.workspace_id = workspace.id.clone();
    actor.sessions.insert("live-cleanup".into(), live);
    assert!(actor
        .inspect_workflow_cleanup_owners(&preview.id, &preview.digest, &workspace.id)
        .await
        .unwrap_err()
        .wire_message()
        .contains("live terminal or process"));
    assert!(actor.sessions["live-cleanup"].running());
    actor.sessions.remove("live-cleanup");
    actor
        .browser
        .sync_page(
            1,
            crate::terminal_host::server::browser_broker::BrowserPage {
                tab_id: "saved-browser".into(),
                workspace_id: workspace.id.clone(),
                profile_id: "default".into(),
                generation: 0,
                document_generation: 0,
                url: None,
                title: None,
                capabilities: Default::default(),
                owner_client_id: 1,
            },
        )
        .unwrap();
    assert!(actor
        .inspect_workflow_cleanup_owners(&preview.id, &preview.digest, &workspace.id)
        .await
        .unwrap_err()
        .wire_message()
        .contains("live browser page"));
    actor.browser.remove_page_owned(1, "saved-browser").unwrap();
    actor.managed_workspace_jobs = 2;
    assert!(actor
        .inspect_workflow_cleanup_owners(&preview.id, &preview.digest, &workspace.id)
        .await
        .is_err());
    actor.managed_workspace_jobs = 0;
    let locked = crate::managed_workspace::workflow::cleanup::prepare(
        &fixture.store,
        &fixture.runtime,
        &preview.id,
        &preview.digest,
    )
    .await
    .unwrap();
    apply_and_wait(&mut actor, &preview, false).await;
    assert!(std::path::Path::new(&workspace.path).exists());
    drop(locked);
    let obstruction = std::path::Path::new(&workspace.path).join("cleanup-obstruction");
    std::fs::write(&obstruction, "preserve this change").unwrap();
    apply_and_wait(&mut actor, &preview, false).await;
    let status = fixture
        .store
        .workflow_cleanup_status(&preview.id)
        .await
        .unwrap();
    assert_eq!(
        status.state,
        alera_core::runtime::WorkflowCleanupState::Attention
    );
    assert!(status.error.is_some());
    assert!(obstruction.exists());
    std::fs::remove_file(obstruction).unwrap();
    apply_and_wait(&mut actor, &preview, false).await;
    cleanup_and_wait(&mut actor, &preview, "workflows.retryCleanup", true).await;
    assert!(!std::path::Path::new(&workspace.path).exists());
    assert!(fixture
        .store
        .find_workspace(&workspace.id)
        .await
        .unwrap()
        .is_none());
    assert!(fixture
        .store
        .workflow_workspace(&workspace.id)
        .await
        .is_ok());
    apply_and_wait(&mut actor, &preview, true).await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(actor
        .try_start_deferred_request(1, 801, "workflows.cleanupStatus", &json!({"id":preview.id}))
        .await
        .unwrap());
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);
    loop {
        let frame = tokio::time::timeout_at(deadline, responses.recv())
            .await
            .unwrap()
            .unwrap();
        if let Some(value) = frame.as_json().filter(|value| value["id"] == 801) {
            assert_eq!(value["ok"], true);
            assert_eq!(value["payload"]["state"], "retired");
            assert_eq!(value["payload"]["retiredWorkspaceIds"][0], workspace.id);
            break;
        }
    }
}

#[tokio::test]
async fn workflow_cleanup_rpc_rejects_untrusted_and_expanded_selections() {
    use crate::terminal_host::server::actor_test_harness::mobile_client;
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let (client, _responses) = ClientHandle::test_channels();
    let payload = json!({"id":uuid::Uuid::new_v4().to_string(),"digest":"a".repeat(64)});
    assert!(actor
        .start_workflow_cleanup_request(1, 1, &payload)
        .is_err());
    actor
        .clients
        .insert(1, mobile_client(client.clone(), "device"));
    assert!(actor
        .start_workflow_cleanup_request(1, 1, &payload)
        .is_err());
    actor.clients.insert(1, local_client(client));
    actor.clients.get_mut(&1).unwrap().authenticated = false;
    assert!(actor
        .start_workflow_cleanup_request(1, 1, &payload)
        .is_err());
    actor.clients.get_mut(&1).unwrap().authenticated = true;
    for invalid in [
        json!({"id":"invalid","digest":"x"}),
        json!({"id":payload["id"],"digest":"a".repeat(161)}),
        json!({"id":payload["id"],"digest":{},"path":"/foreign"}),
        json!({"id":payload["id"],"digest":payload["digest"],"removeBranch":true}),
    ] {
        assert!(actor
            .start_workflow_cleanup_request(1, 1, &invalid)
            .is_err());
    }
    assert_eq!(actor.managed_workspace_jobs, 0);
}

async fn apply_and_wait(
    actor: &mut ServerActor,
    preview: &alera_core::runtime::WorkflowCleanupPreview,
    expected_ok: bool,
) {
    cleanup_and_wait(actor, preview, "workflows.applyCleanup", expected_ok).await;
}

async fn cleanup_and_wait(
    actor: &mut ServerActor,
    preview: &alera_core::runtime::WorkflowCleanupPreview,
    verb: &str,
    expected_ok: bool,
) {
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    assert!(actor
        .try_start_deferred_request(
            1,
            99,
            verb,
            &json!({"id":preview.id,"digest":preview.digest})
        )
        .await
        .unwrap());
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);
    loop {
        let command = tokio::time::timeout_at(deadline, commands.recv())
            .await
            .unwrap()
            .unwrap();
        let finished =
            if let crate::terminal_host::server::ServerCommand::WorkflowWorkspaceFinished {
                result,
                ..
            } = &command
            {
                assert_eq!(result.is_ok(), expected_ok, "{result:?}");
                true
            } else {
                false
            };
        actor.handle(command).await;
        if finished {
            return;
        }
    }
}
