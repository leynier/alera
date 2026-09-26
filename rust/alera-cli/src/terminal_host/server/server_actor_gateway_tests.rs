use super::server_actor_test_support::account_push_for_test;
use super::*;
use std::net::Ipv6Addr;

#[tokio::test]
async fn stale_ssh_bootstrap_progress_is_not_broadcast() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let (inbox, _rx) = mpsc::unbounded_channel();
    let (handle, mut out_rx) = ClientHandle::test_channels();
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
        ssh_bootstrap_jobs: HashMap::from([(
            "remote".to_string(),
            SshBootstrapJobState {
                job_id: "active-job".to_string(),
                target_id: "remote".to_string(),
                status: SshBootstrapStatus::Installing,
                handle: tokio::spawn(async {}),
            },
        )]),
        host_links: crate::terminal_host::host_link_registry::HostLinkRegistry::new(
            runtime_store.clone(),
            inbox.clone(),
        ),
        project_clone_jobs: HashMap::new(),
        agent_title_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        workflow_workspace_jobs: 0,
        workflow_workspace_recovery_running: false,
        automation_checkout_jobs: Default::default(),
        automation_precheck_jobs: Default::default(),
        pending_terminal_lifecycle_shutdowns: Default::default(),
        checkout_buffer_guards: HashMap::new(),
        mutation_queue: Default::default(),
        agent_quota_cache: None,
        configuration_transfers: Default::default(),
        account_push: account_push_for_test(&dir, &runtime_store).await,
        clients: HashMap::from([(1, ClientState::local(handle, true))]),
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

    actor.handle_ssh_bootstrap_progress(SshTargetBootstrapProgress {
        job_id: "stale-job".to_string(),
        target_id: "remote".to_string(),
        status: SshBootstrapStatus::Failed,
        stage: "failed".to_string(),
        message: "Stale failure".to_string(),
        error: Some("stale".to_string()),
    });

    assert!(out_rx.try_recv().is_err());
    assert_eq!(
        actor.ssh_bootstrap_jobs["remote"].status,
        SshBootstrapStatus::Installing
    );
}

#[tokio::test]
async fn mobile_gateway_rebinds_same_port_after_releasing_old_listener() {
    let port_probe = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
    let port = port_probe.local_addr().unwrap().port();
    drop(port_probe);
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let (inbox, _rx) = mpsc::unbounded_channel();
    let current = MobileAccessSettings {
        enabled: true,
        bind_host: "127.0.0.1".to_string(),
        port: i64::from(port),
        ..MobileAccessSettings::default()
    };
    let next = MobileAccessSettings {
        enabled: true,
        bind_host: "0.0.0.0".to_string(),
        port: i64::from(port),
        ..MobileAccessSettings::default()
    };
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
        workflow_workspace_jobs: 0,
        workflow_workspace_recovery_running: false,
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

    actor
        .apply_mobile_gateway_settings(MobileAccessSettings::default(), current.clone())
        .await
        .unwrap();
    let saved = actor
        .apply_mobile_gateway_settings(current, next)
        .await
        .unwrap();

    assert_eq!(saved.bind_host, "0.0.0.0");
    assert!(actor.mobile_gateway.is_some());
    actor.dispose().await;
}

#[tokio::test]
async fn mobile_gateway_binds_ipv6_loopback() {
    let port_probe = match TcpListener::bind((Ipv6Addr::LOCALHOST, 0)).await {
        Ok(listener) => listener,
        Err(_) => return,
    };
    let port = port_probe.local_addr().unwrap().port();
    drop(port_probe);
    let dir = tempfile::tempdir().unwrap();
    let actor = actor_test_harness::test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let settings = MobileAccessSettings {
        enabled: true,
        bind_host: "::1".to_string(),
        port: i64::from(port),
        ..MobileAccessSettings::default()
    };

    let replacement = actor
        .prepare_mobile_gateway_replacement(&settings)
        .await
        .unwrap();

    match replacement {
        MobileGatewayReplacement::Bound { bind_address, .. } => {
            assert!(bind_address.starts_with("[::1]:"));
        }
        MobileGatewayReplacement::Disabled => panic!("expected bound mobile gateway"),
        MobileGatewayReplacement::Keep => panic!("expected bound mobile gateway"),
    }
}

#[tokio::test]
async fn run_stop_clears_persisted_run_without_in_memory_ticker() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let run = runtime_store
        .create_orchestration_coordinator_run("coordinate", Some("coord"), 1000)
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
        workflow_workspace_jobs: 0,
        workflow_workspace_recovery_running: false,
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

    let response = actor
        .orchestration_run_stop(&json!({
            "id": run.id,
            "actor": "coord",
            "reason": "maintenance"
        }))
        .await
        .unwrap();
    assert_eq!(response["runId"], json!(run.id));
    assert_eq!(response["status"], json!("stopped"));
    assert!(actor
        .runtime_store
        .active_orchestration_coordinator_run()
        .await
        .unwrap()
        .is_none());
    let stopped = actor
        .runtime_store
        .orchestration_coordinator_run_by_id(&run.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(stopped.stop_reason.as_deref(), Some("maintenance"));
}
