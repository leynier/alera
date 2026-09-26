use super::server_actor_test_support::account_push_for_test;
use super::*;
use crate::terminal_host::history_store::TerminalHostCheckpoint;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use alera_core::runtime::{
    NewOrchestrationTask, OrchestrationDispatchStatus, OrchestrationTaskStatus,
};

#[tokio::test]
async fn terminal_exit_fails_active_orchestration_dispatch() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let task = runtime_store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "do work".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: None,
            run_id: None,
            workspace_id: "workspace-1".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    let dispatch = runtime_store
        .create_orchestration_dispatch(&task.id, "term-1")
        .await
        .unwrap();
    let (inbox, _rx) = mpsc::unbounded_channel();
    let mut actor = ServerActor {
        runtime_dir: dir.path().to_path_buf(),
        control_file_path: dir.path().join("runtime-host.json"),
        token: "token".to_string(),
        config: TerminalHostConfig::default(),
        store,
        runtime_store: runtime_store.clone(),
        automation_wake: Arc::new(Notify::new()),
        automations_active: false,
        pull_request_watches: Default::default(),
        sessions: HashMap::new(),
        ssh_bootstrap_jobs: HashMap::new(),
        host_links: crate::terminal_host::host_link_registry::HostLinkRegistry::new(
            runtime_store.clone(),
            inbox.clone(),
        ),
        project_clone_jobs: HashMap::new(),
        agent_title_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        automation_checkout_jobs: Default::default(),
        automation_precheck_jobs: Default::default(),
        pending_terminal_lifecycle_shutdowns: Default::default(),
        checkout_buffer_guards: HashMap::new(),
        mutation_queue: Default::default(),
        agent_quota_cache: None,
        configuration_transfers: Default::default(),
        account_push: account_push_for_test(&dir, &runtime_store).await,
        clients: HashMap::new(),
        mobile_prompt_file_uploads: HashMap::new(),
        pending_output_writes: HashMap::new(),
        agent_presence: AgentPresenceRegistry::default(),
        orchestration_waiters: MessageWaiterRegistry::default(),
        orchestration_delivery_in_flight: HashSet::new(),
        orchestration_delivery_backpressured: HashSet::new(),
        orchestration_activity_last_recorded: HashMap::new(),
        coordinators: HashMap::new(),
        resources: ResourceMonitorState::default(),
        hub_reverse: Default::default(),
        remote_project_configs: Default::default(),
        terminal_pulses: Default::default(),
        voice: Default::default(),
        codex: None,
        codex_starting: None,
        inbox,
        next_client_id: Arc::new(AtomicU64::new(1)),
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    };

    actor.handle_session_exit("term-1".to_string(), 9).await;

    let updated_dispatch = actor
        .runtime_store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(updated_dispatch.status, OrchestrationDispatchStatus::Failed);
    assert_eq!(updated_dispatch.failure_count, 1);
    assert_eq!(
        updated_dispatch.last_failure.as_deref(),
        Some("terminal exited with code 9")
    );
    let updated_task = actor
        .runtime_store
        .orchestration_task_by_id(&task.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(updated_task.status, OrchestrationTaskStatus::Ready);
}

#[tokio::test]
async fn host_dispose_fails_active_orchestration_dispatch() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let task = runtime_store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "do work".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: None,
            run_id: None,
            workspace_id: "workspace-1".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    let dispatch = runtime_store
        .create_orchestration_dispatch(&task.id, "term-1")
        .await
        .unwrap();
    store
        .upsert(TerminalHostCheckpoint {
            session_id: "term-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            working_directory: "/tmp".to_string(),
            running: false,
            exit_code: None,
            ended_at: None,
            output_stream_bytes: 0,
            updated_at: chrono::Utc::now(),
            buffer: Vec::new(),
        })
        .await
        .unwrap();
    let session = Session::restore_exited(
        "term-1".to_string(),
        "workspace-1".to_string(),
        "tab-1".to_string(),
        &store,
        1024,
    )
    .await
    .unwrap();
    let (inbox, _rx) = mpsc::unbounded_channel();
    let mut actor = ServerActor {
        runtime_dir: dir.path().to_path_buf(),
        control_file_path: dir.path().join("runtime-host.json"),
        token: "token".to_string(),
        config: TerminalHostConfig::default(),
        store,
        runtime_store: runtime_store.clone(),
        automation_wake: Arc::new(Notify::new()),
        automations_active: false,
        pull_request_watches: Default::default(),
        sessions: HashMap::from([("term-1".to_string(), session)]),
        ssh_bootstrap_jobs: HashMap::new(),
        host_links: crate::terminal_host::host_link_registry::HostLinkRegistry::new(
            runtime_store.clone(),
            inbox.clone(),
        ),
        project_clone_jobs: HashMap::new(),
        agent_title_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        automation_checkout_jobs: Default::default(),
        automation_precheck_jobs: Default::default(),
        pending_terminal_lifecycle_shutdowns: Default::default(),
        checkout_buffer_guards: HashMap::new(),
        mutation_queue: Default::default(),
        agent_quota_cache: None,
        configuration_transfers: Default::default(),
        account_push: account_push_for_test(&dir, &runtime_store).await,
        clients: HashMap::new(),
        mobile_prompt_file_uploads: HashMap::new(),
        pending_output_writes: HashMap::new(),
        agent_presence: AgentPresenceRegistry::default(),
        orchestration_waiters: MessageWaiterRegistry::default(),
        orchestration_delivery_in_flight: HashSet::new(),
        orchestration_delivery_backpressured: HashSet::new(),
        orchestration_activity_last_recorded: HashMap::new(),
        coordinators: HashMap::new(),
        resources: ResourceMonitorState::default(),
        hub_reverse: Default::default(),
        remote_project_configs: Default::default(),
        terminal_pulses: Default::default(),
        voice: Default::default(),
        codex: None,
        codex_starting: None,
        inbox,
        next_client_id: Arc::new(AtomicU64::new(1)),
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    };

    actor.dispose().await;

    let updated_dispatch = actor
        .runtime_store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(updated_dispatch.status, OrchestrationDispatchStatus::Failed);
    assert_eq!(updated_dispatch.failure_count, 1);
    assert_eq!(
        updated_dispatch.last_failure.as_deref(),
        Some("terminal host shut down")
    );
    let updated_task = actor
        .runtime_store
        .orchestration_task_by_id(&task.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(updated_task.status, OrchestrationTaskStatus::Ready);
}

#[tokio::test]
async fn coordinator_does_not_spawn_worker_tab_for_cli_only_client() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    runtime_store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "do work".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: None,
            run_id: None,
            workspace_id: "workspace-1".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    let (inbox, _rx) = mpsc::unbounded_channel();
    let (handle, _control_out_rx) = ClientHandle::test_channels();
    let mut actor = ServerActor {
        runtime_dir: dir.path().to_path_buf(),
        control_file_path: dir.path().join("runtime-host.json"),
        token: "token".to_string(),
        config: TerminalHostConfig::default(),
        store,
        runtime_store: runtime_store.clone(),
        automation_wake: Arc::new(Notify::new()),
        automations_active: false,
        pull_request_watches: Default::default(),
        sessions: HashMap::new(),
        ssh_bootstrap_jobs: HashMap::new(),
        host_links: crate::terminal_host::host_link_registry::HostLinkRegistry::new(
            runtime_store.clone(),
            inbox.clone(),
        ),
        project_clone_jobs: HashMap::new(),
        agent_title_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        automation_checkout_jobs: Default::default(),
        automation_precheck_jobs: Default::default(),
        pending_terminal_lifecycle_shutdowns: Default::default(),
        checkout_buffer_guards: HashMap::new(),
        mutation_queue: Default::default(),
        agent_quota_cache: None,
        configuration_transfers: Default::default(),
        account_push: account_push_for_test(&dir, &runtime_store).await,
        clients: HashMap::from([(1, ClientState::local(handle, false))]),
        mobile_prompt_file_uploads: HashMap::new(),
        pending_output_writes: HashMap::new(),
        agent_presence: AgentPresenceRegistry::default(),
        orchestration_waiters: MessageWaiterRegistry::default(),
        orchestration_delivery_in_flight: HashSet::new(),
        orchestration_delivery_backpressured: HashSet::new(),
        orchestration_activity_last_recorded: HashMap::new(),
        coordinators: HashMap::new(),
        resources: ResourceMonitorState::default(),
        hub_reverse: Default::default(),
        remote_project_configs: Default::default(),
        terminal_pulses: Default::default(),
        voice: Default::default(),
        codex: None,
        codex_starting: None,
        inbox,
        next_client_id: Arc::new(AtomicU64::new(2)),
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    };
    let response = actor
        .orchestration_run(&json!({
            "spec": "coordinate",
            "from": "coord",
            "workspace": "workspace-1",
            "pollIntervalMs": 600_000,
        }))
        .await
        .unwrap();

    actor
        .handle(ServerCommand::CoordinatorTick {
            run_id: response["runId"].as_str().unwrap().to_string(),
        })
        .await;

    assert!(actor
        .runtime_store
        .list_workspace_tabs("workspace-1")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn last_app_client_disconnect_preserves_host_agent_presence() {
    let dir = tempfile::tempdir().unwrap();
    let (first_app_handle, _first_app_rx) = ClientHandle::test_channels();
    let (second_app_handle, _second_app_rx) = ClientHandle::test_channels();
    let (cli_handle, _cli_rx) = ClientHandle::test_channels();
    let mut actor = actor_test_harness::test_actor(
        &dir,
        HashMap::from([
            (1, ClientState::local(first_app_handle, true)),
            (2, ClientState::local(second_app_handle, true)),
            (3, ClientState::local(cli_handle, false)),
        ]),
        HashMap::new(),
    )
    .await;
    actor
        .agent_presence
        .update("term-1", "claude".to_string(), AgentPresenceState::Done);

    actor.dispose_client(3).await;
    assert!(actor.agent_presence.is_injection_ready("term-1"));
    actor.dispose_client(1).await;
    assert!(actor.agent_presence.is_injection_ready("term-1"));
    actor.dispose_client(2).await;

    assert!(actor.agent_presence.is_injection_ready("term-1"));
}
