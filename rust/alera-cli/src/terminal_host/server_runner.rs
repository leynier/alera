use super::*;

#[derive(Debug, Clone, Copy)]
pub enum TerminalHostExit {
    Shutdown,
    Restart(TerminalHostConfig),
}

/// Run the persistent terminal host until it shuts down (idle timeout or the
/// last session terminating). Binds a loopback socket, publishes the control
/// file, and serves clients.
pub async fn run_terminal_host_server(
    runtime_dir: PathBuf,
    control_file_path: PathBuf,
    token: String,
    config: TerminalHostConfig,
) -> Result<TerminalHostExit> {
    prepare_private_runtime_directory(&runtime_dir)?;
    let store = TerminalHostHistoryStore::open(&runtime_dir).await?;
    let runtime_store = RuntimeStore::open(&runtime_dir).await?;
    crate::hosted_review_retention::reconcile(&runtime_store).await;
    runtime_store.cleanup_agent_canvases().await?;
    runtime_store.expire_agent_canvas_decisions().await?;
    runtime_store.ensure_default_browser_profile().await?;
    crate::automation_autostart::reconcile_runtime_autostart(&runtime_store, &runtime_dir).await;
    let account_push =
        account_push_state::AccountPushState::new(runtime_dir.clone(), runtime_store.clone())
            .await?;
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    control_file::write_control_file(&control_file_path, port, &token, config.persistent)?;

    let (inbox, mut rx) = mpsc::unbounded_channel::<ServerCommand>();
    let automation_wake = Arc::new(Notify::new());
    let automation_ticker = automation_scheduler::spawn(
        runtime_store.clone(),
        inbox.clone(),
        automation_wake.clone(),
    );
    if let Err(error) = start_hook_receiver(&runtime_dir, inbox.clone()).await {
        tracing::warn!("alera agent hook receiver unavailable: {error}");
    }
    if let Err(error) = start_fx_herdr_receiver(&runtime_dir, inbox.clone()).await {
        tracing::warn!("alera fx lifecycle receiver unavailable: {error}");
    }
    let next_client_id = Arc::new(AtomicU64::new(1));
    spawn_accept_loop(listener, inbox.clone(), next_client_id.clone());

    tokio::spawn(async {
        // Variables first: the PATH cache is filled from the same probe.
        let _ = crate::login_shell_environment::login_shell_variables().await;
        let _ = crate::login_shell_environment::login_shell_path_segments().await;
    });

    let emulators = match EmulatorManager::new(&runtime_dir).await {
        Ok(manager) => Some(Arc::new(Mutex::new(manager))),
        Err(error) => {
            tracing::warn!("alera emulator manager unavailable: {}", error.message);
            None
        }
    };
    let mut actor = ServerActor {
        runtime_dir,
        control_file_path,
        token,
        config,
        store,
        runtime_store,
        automation_wake,
        automations_active: false,
        sessions: HashMap::new(),
        ssh_bootstrap_jobs: HashMap::new(),
        project_clone_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        emulator_requests: Default::default(),
        agent_quota_cache: None,
        account_push,
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
        terminal_pulses: Default::default(),
        browser: BrowserBroker::default(),
        emulators,
        codex: None,
        codex_presence: HashMap::new(),
        codex_presence_scheduled: false,
        codex_pending_messages: HashMap::new(),
        codex_flush_scheduled: HashSet::new(),
        inbox,
        next_client_id,
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    };
    actor.reconcile_codex_presence().await;
    let hook_settings = actor.runtime_store.agent_status_hook_settings().await?;
    let hook_runtime_dir = actor.runtime_dir.clone();
    let hook_warnings = tokio::task::spawn_blocking(move || {
        start_agent_integrations(&hook_runtime_dir, &hook_settings)
    })
    .await
    .unwrap_or_else(|error| vec![error.to_string()]);
    for warning in hook_warnings {
        tracing::warn!("alera agent integration warning: {warning}");
    }
    if let Err(error) = actor.restart_mobile_gateway().await {
        tracing::warn!("alera mobile gateway unavailable: {}", error.wire_message());
    }
    actor.restart_remote_relay().await;
    actor.reconcile_interrupted_project_clones().await;
    actor.reconcile_spawn_on_create_tabs().await;
    if actor.account_push.push_enabled
        && actor.account_push.service.local_account().await?.is_some()
    {
        actor.start_push_subscription_sync(None);
    }
    // A deferred setup script deletes itself when it finishes, so anything
    // still here outlived the host that wrote it and its terminal is gone. An
    // agent prompt script never deletes itself, so the same sweep is the only
    // thing that clears one.
    if let Some(directory) = actor.setup_script_directory() {
        crate::worktree_setup_script::remove_stale_setup_scripts(&directory);
        crate::agent_prompt_stdin_script::remove_stale_agent_prompt_scripts(&directory);
    }
    actor.automations_active = actor.runtime_store.has_active_automations().await?
        || !actor
            .runtime_store
            .list_active_automation_runs()
            .await?
            .is_empty();
    actor.schedule_shutdown_if_idle();

    // Lives with the loop rather than the actor: it describes the machine the
    // host is running on, not any of the state the actor owns.
    let mut sleep_detector = SleepDetector::default();
    let mut exit = TerminalHostExit::Shutdown;
    while let Some(command) = rx.recv().await {
        if let Some(slept) = sleep_detector.observe() {
            // The first thing to happen after a wake says so, which is what
            // keeps a lid closed overnight from being read later as a freeze.
            tracing::info!(
                "alera terminal host resumed after {}s of system sleep",
                slept.as_secs()
            );
            actor.queue_emulator_park_all();
        }
        if matches!(&command, ServerCommand::RequestedRestart) {
            exit = TerminalHostExit::Restart(actor.config);
        }
        actor.handle(command).await;
        if actor.disposed {
            break;
        }
    }
    automation_ticker.abort();
    let _ = automation_ticker.await;
    Ok(exit)
}
