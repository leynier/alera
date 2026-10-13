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
    handoff_owner: Option<runtime_owner::RuntimeOwnerIdentity>,
) -> Result<TerminalHostExit> {
    prepare_private_runtime_directory(&runtime_dir)?;
    // Ownership must be established before opening stores or constructing any
    // account service. A rejected duplicate host must not touch profile state.
    let _runtime_owner = if let Some(expected_owner) = handoff_owner {
        runtime_owner::RuntimeOwnerGuard::acquire_handoff(&runtime_dir, expected_owner)?
    } else {
        runtime_owner::RuntimeOwnerGuard::acquire(&runtime_dir)?
    };
    let store = TerminalHostHistoryStore::open(&runtime_dir).await?;
    chatgpt_session::initialize(runtime_dir.clone());
    let runtime_store = RuntimeStore::open_as_runtime_owner(&runtime_dir).await?;
    runtime_store.retire_removed_features().await?;
    crate::hosted_review_retention::reconcile(&runtime_store).await;

    crate::automation_autostart::reconcile_runtime_autostart(&runtime_store, &runtime_dir).await;
    let account_push =
        account_push_state::AccountPushState::new(runtime_dir.clone(), runtime_store.clone())
            .await?;
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    control_file::write_control_file(&control_file_path, port, &token, config.persistent)?;

    let (inbox, mut rx) = ServerInbox::channel();
    let agent_chat_instances =
        Arc::new(super::agent_chat_runtime::InstanceDirectory::from_runtime_dir(&runtime_dir));
    let agent_chat_tabs: Arc<dyn super::agent_chat_runtime::tab_directory::TabDirectory> =
        Arc::new(runtime_store.clone());
    let agent_chat_runtime = super::agent_chat_runtime::AgentChatRuntime::new(
        runtime_store.clone(),
        Arc::new(super::agent_chat_runtime::ProductionProviderFactory),
        agent_chat_tabs,
        Box::new(super::agent_chat_runtime::events::HostEventSink::new(
            inbox.clone(),
        )),
        agent_chat_instances,
    );
    let chat_credentials = super::chat_orchestration::ChatCredentialLaunchHook::new(
        runtime_store.clone(),
        runtime_dir.clone(),
    )?;
    agent_chat_runtime.register_launch_hook(chat_credentials.clone());
    let host_links = crate::terminal_host::host_link_registry::HostLinkRegistry::new(
        runtime_store.clone(),
        inbox.clone(),
    );
    let remote_agent_chats = super::agent_chat_remote::RemoteChatDirectory::default();
    let remote_router = super::agent_chat_remote::RemoteChatRouter::new(
        runtime_store.clone(),
        host_links.clone(),
        remote_agent_chats.clone(),
    );
    let routed_chat_runtime = super::chat_orchestration_remote::RoutedChatRuntime::new(
        agent_chat_runtime.clone(),
        remote_router,
    );
    let chat_orchestration = super::chat_orchestration::ChatOrchestrationService::new(
        runtime_store.clone(),
        agent_chat_runtime.clone(),
        Arc::new(
            super::chat_orchestration::RuntimeTargetResolver::new(runtime_store.clone())
                .with_setup_script_directory(runtime_dir.clone()),
        ),
        chat_credentials,
    )
    .with_runtime(routed_chat_runtime)
    .with_events(Arc::new(
        super::chat_orchestration_events::HostOrchestrationEventSink::new(inbox.clone()),
    ));
    if let Err(error) = agent_chat_runtime.recover_after_restart().await {
        tracing::warn!("agent chat startup recovery unavailable: {error}");
    }
    match runtime_store.recover_chat_orchestration().await {
        Ok(recovery) => {
            seed_remote_chat_routes(&remote_agent_chats, &recovery.remote);
            chat_orchestration.resume_task_monitors(&recovery.remote);
        }
        Err(error) => {
            tracing::warn!("chat orchestration startup recovery unavailable: {error}");
        }
    }
    let shutdown_signal = spawn_termination_listener(inbox.clone());
    let watch_ticker = pull_request_watch_runtime::spawn(inbox.clone());
    let event_forwarder =
        runtime_event_forwarder::spawn(runtime_store.clone(), account_push.service.clone());
    let presence_sweep = agent_presence_reconciliation::spawn(inbox.clone());
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

    let mut actor = ServerActor {
        runtime_dir,
        control_file_path,
        token,
        config,
        store,
        runtime_store: runtime_store.clone(),
        automation_wake,
        automations_active: false,
        pull_request_watches: Default::default(),
        sessions: HashMap::new(),
        ssh_bootstrap_jobs: HashMap::new(),
        host_links,
        remote_agent_chats,
        project_clone_jobs: HashMap::new(),
        prompt_workspace_operations: HashMap::new(),
        agent_title_jobs: HashMap::new(),
        managed_workspace_jobs: 0,
        workflow_execution: Default::default(),
        workflow_workspace_jobs: 0,
        workflow_workspace_recovery_running: false,
        automation_checkout_jobs: Default::default(),
        automation_precheck_jobs: Default::default(),
        automation_remote_owner_states: Default::default(),
        pending_terminal_lifecycle_shutdowns: Default::default(),
        checkout_buffer_guards: HashMap::new(),
        mutation_queue: Default::default(),
        agent_quota_cache: None,
        configuration_transfers: Default::default(),
        account_push,
        clients: HashMap::new(),
        mobile_prompt_file_uploads: HashMap::new(),
        pending_history_requests: HashMap::new(),
        history_writers: HashMap::new(),
        agent_presence: AgentPresenceRegistry::default(),
        agent_hook_links: Default::default(),
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
        agent_chat_runtime: Some(agent_chat_runtime),
        chat_orchestration: Some(chat_orchestration),
        inbox: inbox.clone(),
        next_client_id,
        mobile_gateway: None,
        shutdown_gen: 0,
        disposed: false,
    };
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
    actor.reconcile_interrupted_prompt_workspaces().await;
    actor.runtime_store.recover_workflow_coordinators().await?;
    actor.start_workflow_workspace_recovery();
    actor.reconcile_workflow_launches().await;
    actor
        .runtime_store
        .record_automation_runtime_started()
        .await?;
    if let Some(boot) =
        tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id)
            .await
            .ok()
            .and_then(Result::ok)
            .flatten()
    {
        actor
            .runtime_store
            .set_metadata("automations.runtimeBootId", &boot)
            .await?;
    }
    actor.migrate_retired_automation_gates().await;
    actor.reconcile_automation_runs().await;
    let host_link_supervisor = actor.start_host_link_supervisor();
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
    actor.automations_active = actor.runtime_store.has_pending_automation_work().await?;
    actor.schedule_shutdown_if_idle();

    // Lives with the loop rather than the actor: it describes the machine the
    // host is running on, not any of the state the actor owns.
    let mut sleep_detector = SleepDetector::default();
    let mut exit = None;
    while let Some(command) = inbox.recv(&mut rx).await {
        if let Some(slept) = sleep_detector.observe() {
            // The first thing to happen after a wake says so, which is what
            // keeps a lid closed overnight from being read later as a freeze.
            tracing::info!(
                "alera terminal host resumed after {}s of system sleep",
                slept.as_secs()
            );
        }
        record_exit_intent(&mut exit, &command, actor.config);
        actor.handle(command).await;
        if actor.disposed {
            break;
        }
    }
    inbox.close();
    watch_ticker.abort();
    let _ = watch_ticker.await;
    event_forwarder.abort();
    let _ = event_forwarder.await;
    presence_sweep.abort();
    let _ = presence_sweep.await;
    automation_ticker.abort();
    let _ = automation_ticker.await;
    host_link_supervisor.abort();
    let _ = host_link_supervisor.await;
    if let Some(shutdown_signal) = shutdown_signal {
        shutdown_signal.abort();
    }
    if let Ok(session) = chatgpt_session::session() {
        let _ = session.cancel().await;
    }
    Ok(exit.unwrap_or(TerminalHostExit::Shutdown))
}

fn record_exit_intent(
    exit: &mut Option<TerminalHostExit>,
    command: &ServerCommand,
    config: TerminalHostConfig,
) {
    if exit.is_some() {
        return;
    }
    *exit = match command {
        ServerCommand::RequestedShutdown => Some(TerminalHostExit::Shutdown),
        ServerCommand::RequestedRestart => Some(TerminalHostExit::Restart(config)),
        _ => None,
    };
}

fn seed_remote_chat_routes(
    directory: &super::agent_chat_remote::RemoteChatDirectory,
    tasks: &[alera_core::runtime::ChatOrchestrationTask],
) {
    for task in tasks {
        seed_remote_chat_route(
            directory,
            task.child_chat_id.as_deref(),
            task.workspace_id.as_deref(),
            task.host_id.as_deref(),
        );
    }
}

fn seed_remote_chat_route(
    directory: &super::agent_chat_remote::RemoteChatDirectory,
    child_chat_id: Option<&str>,
    workspace_id: Option<&str>,
    host_id: Option<&str>,
) {
    if let (Some(chat_id), Some(workspace_id), Some(host_id)) =
        (child_chat_id, workspace_id, host_id)
    {
        if host_id != "local" && !chat_id.is_empty() && !workspace_id.is_empty() {
            directory.remember(chat_id, workspace_id, host_id);
        }
    }
}

#[cfg(unix)]
fn spawn_termination_listener(inbox: ServerInbox) -> Option<tokio::task::JoinHandle<()>> {
    use tokio::signal::unix::{signal, SignalKind};

    let mut terminate = match signal(SignalKind::terminate()) {
        Ok(signal) => signal,
        Err(error) => {
            tracing::warn!("alera runtime host could not listen for SIGTERM: {error}");
            return None;
        }
    };
    Some(tokio::spawn(async move {
        terminate.recv().await;
        let _ = inbox.send(ServerCommand::RequestedShutdown);
    }))
}

#[cfg(not(unix))]
fn spawn_termination_listener(_inbox: ServerInbox) -> Option<tokio::task::JoinHandle<()>> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_shutdown_intent_survives_a_later_restart_request() {
        let config = TerminalHostConfig::default();
        let mut exit = None;
        record_exit_intent(&mut exit, &ServerCommand::RequestedShutdown, config);
        record_exit_intent(&mut exit, &ServerCommand::RequestedRestart, config);
        assert!(matches!(exit, Some(TerminalHostExit::Shutdown)));
    }

    #[test]
    fn first_restart_intent_survives_a_later_shutdown_request() {
        let config = TerminalHostConfig::default();
        let mut exit = None;
        record_exit_intent(&mut exit, &ServerCommand::RequestedRestart, config);
        record_exit_intent(&mut exit, &ServerCommand::RequestedShutdown, config);
        assert!(matches!(exit, Some(TerminalHostExit::Restart(_))));
    }

    #[test]
    fn startup_route_seed_keeps_remote_chat_identity() {
        let directory = super::super::agent_chat_remote::RemoteChatDirectory::default();
        super::seed_remote_chat_route(
            &directory,
            Some("chat-remote"),
            Some("workspace-local-mirror"),
            Some("ssh-host"),
        );
        assert_eq!(
            directory.route("chat-remote"),
            Some(("workspace-local-mirror".into(), "ssh-host".into()))
        );
        super::seed_remote_chat_route(
            &directory,
            Some("chat-local"),
            Some("workspace-local"),
            Some("local"),
        );
        assert_eq!(directory.route("chat-local"), None);
    }
}
