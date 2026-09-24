use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::session::Session;
use alera_core::runtime::WorkspaceTabRecord;
use std::collections::HashMap;
use tokio::sync::mpsc;

#[tokio::test]
async fn verified_action_retries_preserve_a_replacement_session_and_neighbor() {
    for action in [
        TerminalLifecycleAction::Close,
        TerminalLifecycleAction::Restart,
    ] {
        let root = tempfile::tempdir().unwrap();
        let (control, _responses) = mpsc::unbounded_channel();
        let (terminal, _output) = mpsc::channel(16);
        let client =
            super::super::actor_test_harness::local_client(ClientHandle::new(control, terminal));
        let mut actor = super::super::actor_test_harness::test_actor(
            &root,
            HashMap::from([(1, client)]),
            HashMap::new(),
        )
        .await;
        let folder = root.path().join("project");
        std::fs::create_dir(&folder).unwrap();
        let created = crate::project_management::register_project(
            &actor.runtime_store,
            folder.to_str().unwrap(),
            None,
        )
        .await
        .unwrap();
        let workspace = actor
            .runtime_store
            .list_workspaces(&created.project.id)
            .await
            .unwrap()
            .remove(0);
        let now = chrono::Utc::now();
        actor
            .runtime_store
            .insert_workspace_tab(WorkspaceTabRecord {
                id: "tab".into(),
                workspace_id: workspace.id.clone(),
                kind: "terminal".into(),
                title: "Terminal".into(),
                created_at: now,
                updated_at: now,
                payload: json!({"terminalSessionId":"session"}),
            })
            .await
            .unwrap();
        // These sessions own no OS processes; this test covers protocol/state isolation.
        let mut session = Session::driver_test_stub("session", 80, 24);
        session.workspace_id = workspace.id.clone();
        session.tab_id = "tab".into();
        let generation = session.instance_id();
        actor.sessions.insert("session".into(), session);
        actor.sessions.insert(
            "neighbor".into(),
            Session::driver_test_stub("neighbor", 80, 24),
        );
        let (inbox, mut commands) = mpsc::unbounded_channel();
        actor.inbox = inbox;
        let id = uuid::Uuid::new_v4().to_string();
        let payload = json!({"operationId":id,"workspace":workspace,"tabId":"tab","sessionId":"session","action":action});
        let mut foreign = payload.clone();
        foreign["tabId"] = json!("another-tab");
        assert!(actor
            .start_owner_terminal_lifecycle(1, 1, &foreign)
            .await
            .is_err());
        assert!(actor.sessions.contains_key("session"));
        assert!(actor
            .runtime_store
            .terminal_lifecycle_operation(&id)
            .await
            .unwrap()
            .is_none());
        actor
            .start_owner_terminal_lifecycle(1, 2, &payload)
            .await
            .unwrap();
        assert_eq!(actor.managed_workspace_jobs, 1);
        assert!(actor.sessions.contains_key("neighbor"));
        assert!(!actor.sessions.contains_key("session"));
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(3);
        let command = loop {
            let command = tokio::time::timeout_at(deadline, commands.recv())
                .await
                .unwrap()
                .unwrap();
            if matches!(
                &command,
                ServerCommand::WorkflowLaunch(
                    super::super::workflow_launch_requests::WorkflowLaunchCommand::ExecutionWake
                )
            ) {
                // A Board revision may queue a no-op workflow wake first.
                actor.handle(command).await;
                continue;
            }
            break command;
        };
        match &command {
            ServerCommand::OwnerTerminalLifecycleFinished { result: Ok(_), .. } => {}
            ServerCommand::OwnerTerminalLifecycleFinished {
                result: Err(error), ..
            } => panic!("terminal lifecycle failed: {}", error.wire_message()),
            _ => panic!("unexpected terminal lifecycle command"),
        }
        actor.handle(command).await;
        assert_eq!(actor.managed_workspace_jobs, 0);
        let saved = actor
            .runtime_store
            .terminal_lifecycle_operation(&id)
            .await
            .unwrap()
            .unwrap();
        assert!(saved.closure_verified);
        assert_eq!(saved.session_generation, generation);
        assert_eq!(
            actor
                .runtime_store
                .find_workspace_tab("tab")
                .await
                .unwrap()
                .is_some(),
            action == TerminalLifecycleAction::Restart
        );
        let replacement = Session::driver_test_stub("session", 120, 40);
        let replacement_generation = replacement.instance_id();
        actor.sessions.insert("session".into(), replacement);
        actor
            .start_owner_terminal_lifecycle(1, 3, &payload)
            .await
            .unwrap();
        assert_eq!(
            actor.sessions["session"].instance_id(),
            replacement_generation
        );
        assert!(actor
            .start_owner_terminal_lifecycle(1, 4, &foreign)
            .await
            .is_err());
        assert!(actor.sessions.contains_key("neighbor"));
    }
}

#[tokio::test]
async fn failed_shutdown_retries_original_capture_and_keeps_unknown_closure_pending() {
    let root = tempfile::tempdir().unwrap();
    let (control, _responses) = mpsc::unbounded_channel();
    let (terminal, _output) = mpsc::channel(16);
    let client =
        super::super::actor_test_harness::local_client(ClientHandle::new(control, terminal));
    let mut actor = super::super::actor_test_harness::test_actor(
        &root,
        HashMap::from([(1, client)]),
        HashMap::new(),
    )
    .await;
    let folder = root.path().join("project");
    std::fs::create_dir(&folder).unwrap();
    let project = crate::project_management::register_project(
        &actor.runtime_store,
        folder.to_str().unwrap(),
        None,
    )
    .await
    .unwrap();
    let workspace = actor
        .runtime_store
        .list_workspaces(&project.project.id)
        .await
        .unwrap()
        .remove(0);
    let now = chrono::Utc::now();
    actor
        .runtime_store
        .insert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"terminalSessionId":"session"}),
        })
        .await
        .unwrap();
    let operation = TerminalLifecycleOperation {
        id: uuid::Uuid::new_v4().to_string(),
        workspace,
        tab_id: "tab".into(),
        session_id: "session".into(),
        session_generation: 7,
        initiator_epoch: None,
        action: TerminalLifecycleAction::Restart,
        closure_verified: false,
    };
    actor
        .runtime_store
        .begin_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    let (inbox, mut commands) = mpsc::unbounded_channel();
    actor.inbox = inbox;
    let mut shutdown = WorkspaceShutdown::default();
    shutdown.fail_next_waits(1);
    actor.wait_owner_terminal_lifecycle(1, 1, operation.clone(), shutdown);
    let command = tokio::time::timeout(std::time::Duration::from_secs(3), commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        &command,
        ServerCommand::OwnerTerminalLifecycleFinished { result: Err(_), .. }
    ));
    actor.handle(command).await;
    assert!(actor
        .pending_terminal_lifecycle_shutdowns
        .contains_key(&operation.id));
    assert!(
        !actor
            .runtime_store
            .terminal_lifecycle_operation(&operation.id)
            .await
            .unwrap()
            .unwrap()
            .closure_verified
    );
    let payload = json!({"operationId":operation.id,"workspace":operation.workspace,"tabId":"tab","sessionId":"session","action":"restart"});
    let guard = actor
        .pending_terminal_lifecycle_shutdowns
        .remove(&operation.id)
        .unwrap();
    // With no retained capture (as after a restart), the durable pending record is not proof.
    assert!(actor
        .start_owner_terminal_lifecycle(1, 2, &payload)
        .await
        .unwrap_err()
        .to_string()
        .contains("unverified"));
    actor
        .pending_terminal_lifecycle_shutdowns
        .insert(operation.id.clone(), guard);
    actor
        .start_owner_terminal_lifecycle(1, 3, &payload)
        .await
        .unwrap();
    let command = tokio::time::timeout(std::time::Duration::from_secs(3), commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        &command,
        ServerCommand::OwnerTerminalLifecycleFinished { result: Ok(_), .. }
    ));
    actor.handle(command).await;
    assert!(actor.pending_terminal_lifecycle_shutdowns.is_empty());
    assert_eq!(actor.managed_workspace_jobs, 0);
    let saved = actor
        .runtime_store
        .terminal_lifecycle_operation(&operation.id)
        .await
        .unwrap()
        .unwrap();
    assert!(saved.closure_verified);
    assert_eq!(saved.session_generation, 7);
}

#[tokio::test]
async fn registered_never_started_terminal_can_close_without_inventing_session_exit() {
    let root = tempfile::tempdir().unwrap();
    let (control, _responses) = mpsc::unbounded_channel();
    let (terminal, _output) = mpsc::channel(16);
    let client =
        super::super::actor_test_harness::local_client(ClientHandle::new(control, terminal));
    let mut actor = super::super::actor_test_harness::test_actor(
        &root,
        HashMap::from([(1, client)]),
        HashMap::new(),
    )
    .await;
    let folder = root.path().join("project");
    std::fs::create_dir(&folder).unwrap();
    let created = crate::project_management::register_project(
        &actor.runtime_store,
        folder.to_str().unwrap(),
        None,
    )
    .await
    .unwrap();
    let workspace = actor
        .runtime_store
        .list_workspaces(&created.project.id)
        .await
        .unwrap()
        .remove(0);
    let now = chrono::Utc::now();
    actor
        .runtime_store
        .insert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"terminalSessionId":"session"}),
        })
        .await
        .unwrap();

    let id = uuid::Uuid::new_v4().to_string();
    let payload = json!({"operationId":id,"workspace":workspace,"tabId":"tab","sessionId":"session","action":"close"});
    actor
        .start_owner_terminal_lifecycle(1, 1, &payload)
        .await
        .unwrap();
    let receipt = actor
        .runtime_store
        .terminal_lifecycle_operation(&id)
        .await
        .unwrap()
        .unwrap();
    assert!(receipt.closure_verified);
    assert_eq!(
        receipt.initiator_epoch.as_deref(),
        Some("never-started-close")
    );
    assert!(actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .is_none());
    assert!(actor
        .runtime_store
        .record_workspace_tab_terminal_launch(&workspace.id, "tab", "session")
        .await
        .is_err());
    actor
        .start_owner_terminal_lifecycle(1, 2, &payload)
        .await
        .unwrap();
    assert_eq!(actor.managed_workspace_jobs, 0);
}

#[tokio::test]
async fn never_started_restart_rejects_delayed_launch_and_accepts_replacement_token() {
    let root = tempfile::tempdir().unwrap();
    let (control, _responses) = mpsc::unbounded_channel();
    let (terminal, _output) = mpsc::channel(16);
    let client =
        super::super::actor_test_harness::local_client(ClientHandle::new(control, terminal));
    let mut actor = super::super::actor_test_harness::test_actor(
        &root,
        HashMap::from([(1, client)]),
        HashMap::new(),
    )
    .await;
    let folder = root.path().join("project");
    std::fs::create_dir(&folder).unwrap();
    let created = crate::project_management::register_project(
        &actor.runtime_store,
        folder.to_str().unwrap(),
        None,
    )
    .await
    .unwrap();
    let workspace = actor
        .runtime_store
        .list_workspaces(&created.project.id)
        .await
        .unwrap()
        .remove(0);
    let now = chrono::Utc::now();
    actor
        .runtime_store
        .insert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"terminalSessionId":"session"}),
        })
        .await
        .unwrap();

    crate::remote_owner_terminal_ownership::register_tab(
        &actor.runtime_store,
        &workspace,
        "tab",
        "session",
        None,
    )
    .await
    .unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let payload = json!({"operationId":id,"workspace":workspace,"tabId":"tab","sessionId":"session","action":"restart"});
    actor
        .start_owner_terminal_lifecycle(1, 1, &payload)
        .await
        .unwrap();
    assert_eq!(
        actor
            .runtime_store
            .terminal_restart_launch_token(&workspace, "tab", "session")
            .await
            .unwrap(),
        Some(id.clone())
    );
    let mut session = Session::driver_test_stub("session", 80, 24);
    session.workspace_id = workspace.id.clone();
    session.tab_id = "tab".into();
    actor.sessions.insert("session".into(), session);
    let mut attach = json!({"sessionId":"session","workspaceId":workspace.id,"tabId":"tab","workingDirectory":workspace.path,"cols":80,"rows":24});
    assert!(actor
        .create_or_attach(1, &attach)
        .await
        .unwrap_err()
        .to_string()
        .contains("superseded"));
    attach["launchToken"] = json!(id);
    actor.create_or_attach(1, &attach).await.unwrap();
    let replacement_generation = actor.sessions["session"].instance_id();
    actor
        .start_owner_terminal_lifecycle(1, 2, &payload)
        .await
        .unwrap();
    assert_eq!(
        actor.sessions["session"].instance_id(),
        replacement_generation
    );
}
