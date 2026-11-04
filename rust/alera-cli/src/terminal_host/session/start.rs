use super::*;

impl Session {
    /// Spawn a fresh shell PTY, persist an initial checkpoint, and start the
    /// reader thread.
    #[allow(clippy::too_many_arguments)]
    pub async fn start(
        id: String,
        workspace_id: String,
        tab_id: String,
        working_directory: String,
        launch: &TerminalHostLaunch,
        cols: u16,
        rows: u16,
        max_bytes: usize,
        initial_scrollback: &[u8],
        initial_output_stream_bytes: u64,
        store: &TerminalHostHistoryStore,
        on_event: impl Fn(PtyEvent) + Send + Sync + 'static,
    ) -> HostResult<Session> {
        let durable_output_batch_sequence = store
            .next_output_sequence(&id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        #[cfg(windows)]
        let spawned = {
            let launch = launch.clone();
            let terminal_handle = id.clone();
            let spawn_cwd = working_directory.clone();
            tokio::task::spawn_blocking(move || {
                spawn_pty(launch, terminal_handle, spawn_cwd, cols, rows)
            })
            .await
            .map_err(|error| HostError::state(format!("PTY setup worker failed: {error}")))??
        };
        #[cfg(not(windows))]
        let spawned = spawn_pty(
            launch.clone(),
            id.clone(),
            working_directory.clone(),
            cols,
            rows,
        )?;
        let SpawnedPty {
            child,
            master,
            reader,
            writer,
            killer,
            #[cfg(windows)]
            process_job,
            shell,
        } = spawned;
        let (input_tx, input_rx) = sync_channel(INPUT_QUEUE_CAPACITY);
        let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(on_event);

        let mut title_tracker = TerminalTitleTracker::default();
        title_tracker.feed(initial_scrollback);
        let mut session = Session {
            #[cfg(unix)]
            child_reaper: Arc::default(),
            instance_id: next_session_instance_id(),
            initial_agent_prompt_delivered: false,
            id,
            workspace_id,
            tab_id,
            working_directory,
            provider_setup: launch.provider_setup.clone(),
            provider_setup_desktop_leases: Default::default(),
            clients: HashSet::new(),
            observer_clients: HashSet::new(),
            driver: SessionDriver::Idle,
            desktop_dims: None,
            current_dims: (cols, rows),
            output_paused_clients: HashSet::new(),
            output_resync_pending_clients: HashSet::new(),
            delivered_output_cursors: HashMap::new(),
            buffer: ScrollbackBuffer::new(max_bytes, initial_scrollback),
            running: true,
            exit_code: None,
            ended_at: None,
            shell,
            master: Some(master),
            input_tx: Some(input_tx),
            killer: Some(killer),
            #[cfg(windows)]
            process_job: Some(process_job),
            terminated: false,
            termination_requested: false,
            history_barrier_held: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
            checkpoint_retry_timer: None,
            output_batch: Vec::new(),
            output_batch_gen: 0,
            output_batch_armed: false,
            durable_output_batch: Vec::new(),
            durable_output_batch_gen: 0,
            durable_output_batch_armed: false,
            durable_retry_timer: None,
            durable_output_batch_sequence,
            durable_output_failures: VecDeque::new(),
            pending_pty_ack: None,
            deferred_exit: None,
            checkpoint_job: None,
            checkpoint_output_blocked: false,
            output_stream_bytes: resumed_output_stream_bytes(
                initial_output_stream_bytes,
                initial_scrollback.len(),
            ),
            last_output_at: std::time::Instant::now(),
            title_tracker,
        };
        session.write_checkpoint(store, None).await?;
        spawn_reader(
            reader,
            child,
            Arc::clone(&on_event),
            #[cfg(unix)]
            Arc::clone(&session.child_reaper),
        );
        spawn_writer(writer, input_rx, on_event);
        Ok(session)
    }
}
