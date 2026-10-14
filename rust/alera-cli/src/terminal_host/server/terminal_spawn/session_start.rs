use super::*;

impl ServerActor {
    #[allow(clippy::too_many_arguments)]
    pub(in crate::terminal_host::server) async fn start_new_terminal_session(
        &mut self,
        session_id: String,
        workspace_id: String,
        tab_id: String,
        working_directory: String,
        launch: TerminalHostLaunch,
        cols: u16,
        rows: u16,
        initial_scrollback: Vec<u8>,
        initial_output_stream_bytes: u64,
        forced_agent_hook: Option<&str>,
    ) -> HostResult<()> {
        self.start_new_terminal_session_with_permit(
            session_id,
            workspace_id,
            tab_id,
            working_directory,
            launch,
            cols,
            rows,
            initial_scrollback,
            initial_output_stream_bytes,
            forced_agent_hook,
            None,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn start_new_terminal_session_with_permit(
        &mut self,
        session_id: String,
        workspace_id: String,
        tab_id: String,
        working_directory: String,
        mut launch: TerminalHostLaunch,
        cols: u16,
        rows: u16,
        initial_scrollback: Vec<u8>,
        initial_output_stream_bytes: u64,
        forced_agent_hook: Option<&str>,
        permit: Option<&WorkflowLaunchPermit>,
    ) -> HostResult<()> {
        self.require_workflow_spawn_permit(&session_id, &workspace_id, &tab_id, permit)
            .await?;
        self.runtime_store
            .require_workspace_outside_cleanup(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        // This is the final owner-creation boundary for client, automation,
        // and orchestration launches. Runtime mutations perform filesystem
        // cleanup concurrently with the actor, so no new terminal owner may
        // cross this fence while one is outstanding.
        if self.mutation_queue.has_runtime_mutations() {
            return Err(HostError::state(
                "A runtime mutation is in progress. Wait for it to finish and retry.",
            ));
        }
        self.disarm_terminal_pulse(&session_id);
        self.account_push.damper.reset_session(&session_id);
        let mut working_directory = working_directory;
        if let Some((remote_launch, remote_cwd)) =
            crate::ssh_remote::remote_workspace_terminal_override(
                &self.runtime_store,
                &workspace_id,
                crate::remote_owner_terminal_launch::TerminalIdentity {
                    session_id: &session_id,
                    tab_id: &tab_id,
                    cols,
                    rows,
                },
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            launch = remote_launch;
            working_directory = remote_cwd;
            if let Ok(Some(workspace)) = self.runtime_store.find_workspace(&workspace_id).await {
                self.ensure_host_link_for_remote_terminal(&workspace.host_id);
            }
        }
        let mut agent_settings = self
            .runtime_store
            .agent_status_hook_settings()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if let Some(agent) = forced_agent_hook {
            agent_settings.set_enabled(agent, true);
        }
        let runtime_dir = self.runtime_dir.clone();
        let launch_session_id = session_id.clone();
        let launch_workspace_id = workspace_id.clone();
        let launch_tab_id = tab_id.clone();
        let mut environment = std::mem::take(&mut launch.environment);
        if let Some(path) = crate::login_shell_environment::login_shell_merged_path(
            environment.get("PATH").map(String::as_str),
        )
        .await
        {
            environment.insert("PATH".to_string(), path);
        }
        launch.environment = tokio::task::spawn_blocking(move || {
            prepare_launch_environment(
                &runtime_dir,
                &launch_session_id,
                &launch_workspace_id,
                &launch_tab_id,
                &agent_settings,
                &mut environment,
            )?;
            Ok::<_, anyhow::Error>(environment)
        })
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .map_err(|error| HostError::state(error.to_string()))?;
        if let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(&tab_id).await {
            if let Some(profile_id) = agent_profile_id(&tab) {
                launch
                    .environment
                    .insert("ALERA_AGENT_PROFILE_ID".to_string(), profile_id.to_string());
            }
            if let Some(conversation_id) = tab.payload.get("conversationId").and_then(Value::as_str)
            {
                launch.environment.insert(
                    "ALERA_AGENT_CONVERSATION_ID".to_string(),
                    conversation_id.to_string(),
                );
            }
            if tab.payload.get("automationOwned").and_then(Value::as_bool) == Some(true) {
                if let Some(run_id) = tab.payload.get("automationRunId").and_then(Value::as_str) {
                    // These values come from the host-owned tab record, never
                    // from a launch request. They bind automation CLI calls to
                    // the exact PTY that the host created for the run.
                    launch
                        .environment
                        .insert("ALERA_AUTOMATION_RUN_ID".to_string(), run_id.to_string());
                    if let Some(attempt) = tab.payload["automationAttemptId"].as_str() {
                        launch
                            .environment
                            .insert("ALERA_AUTOMATION_ATTEMPT_ID".into(), attempt.into());
                    }
                    launch
                        .environment
                        .insert("ALERA_WORKSPACE_ID".to_string(), workspace_id.clone());
                    launch
                        .environment
                        .insert("ALERA_TAB_ID".to_string(), tab_id.clone());
                    launch
                        .environment
                        .insert("ALERA_TERMINAL_SESSION_ID".to_string(), session_id.clone());
                }
            }
        }
        let inbox = self.inbox.clone();
        let reader_session_id = session_id.clone();
        self.runtime_store
            .record_workspace_tab_terminal_launch(&workspace_id, &tab_id, &session_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let tracked_owner = self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .ok()
            .flatten()
            .is_some_and(|tab| {
                tab.payload["automationOwned"] == true || tab.payload["sshOwnerTerminal"] == true
            });
        if tracked_owner {
            self.record_terminal_owner_intent(&session_id, &workspace_id, &tab_id)
                .await?;
        }
        let woken_workspace_id = workspace_id.clone();
        let woken_tab_id = tab_id.clone();
        if launch.provider_setup.is_some() {
            self.agent_chat_provider_settings
                .as_ref()
                .ok_or_else(|| HostError::state("Providers Settings is unavailable."))?
                .prepare_provider_setup_launch(&mut launch)
                .await?;
        }
        let session = Box::pin(Session::start(
            session_id.clone(),
            workspace_id,
            tab_id,
            working_directory,
            &launch,
            cols,
            rows,
            self.config.scrollback_bytes as usize,
            &initial_scrollback,
            initial_output_stream_bytes,
            &self.store,
            move |event| forward_pty_event(&inbox, &reader_session_id, event),
        ))
        .await?;
        self.sessions.insert(session_id.clone(), session);
        if tracked_owner {
            self.record_terminal_owner_process(&session_id).await;
        }
        self.wake_workspace_for_tab(&woken_workspace_id, &woken_tab_id)
            .await;
        Ok(())
    }
}
