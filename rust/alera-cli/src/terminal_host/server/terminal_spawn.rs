use alera_core::runtime::{WorkspaceStatus, WorkspaceTabRecord};
use serde_json::Value;

use crate::agent_status::prepare_launch_environment;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::TerminalHostLaunch;
use crate::terminal_host::session::Session;

use super::pty_event_forwarder::forward_pty_event;
use super::terminal_launch_defaults::default_terminal_launch;
use super::terminal_spawn_command::{resolve_spawn_command, SpawnCommand};
use super::terminal_startup_commands::{
    agent_profile_id, delivers_initial_command_once, delivers_initial_prompt_once,
    pending_agent_type, tab_agent_type, terminal_session_id,
};
use super::workflow_launch_requests::WorkflowLaunchPermit;
use super::ServerActor;

const DEFAULT_TERMINAL_COLS: u16 = 80;
const DEFAULT_TERMINAL_ROWS: u16 = 24;

mod tab_spawn;

impl ServerActor {
    pub(super) async fn reconcile_spawn_on_create_tabs(&mut self) {
        let workspaces = match self.runtime_store.list_all_workspaces().await {
            Ok(workspaces) => workspaces,
            Err(error) => {
                tracing::error!("failed to list workspaces for terminal reconciliation: {error}");
                return;
            }
        };
        for workspace in workspaces {
            match self
                .runtime_store
                .pending_workspace_checkout_relocation(&workspace.id)
                .await
            {
                Ok(None) => {}
                Ok(Some(_)) => continue,
                Err(error) => {
                    tracing::error!(
                        "could not verify checkout relocation before terminal restoration: {error}"
                    );
                    continue;
                }
            }
            let tabs = match self.runtime_store.list_workspace_tabs(&workspace.id).await {
                Ok(tabs) => tabs,
                Err(error) => {
                    tracing::error!(
                        "failed to list terminal tabs for workspace {}: {error}",
                        workspace.id
                    );
                    continue;
                }
            };
            for tab in tabs.into_iter().filter(spawns_on_create) {
                if let Err(error) = self.ensure_spawn_on_create_terminal(&tab).await {
                    tracing::error!(
                        "failed to restore spawn-on-create terminal {}: {}",
                        tab.id,
                        error.wire_message()
                    );
                    let _ = self.runtime_store.remove_workspace_tab(&tab.id).await;
                }
            }
        }
    }

    /// Spawns the PTY a `spawnOnCreate` tab asks for. Returns the tab record
    /// when spawning rewrote it, which happens for a one-shot initial command.
    pub(super) async fn ensure_spawn_on_create_terminal(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        self.ensure_spawn_on_create_terminal_with_permit(tab, None)
            .await
    }

    pub(super) async fn ensure_spawn_on_create_terminal_with_permit(
        &mut self,
        tab: &WorkspaceTabRecord,
        permit: Option<&WorkflowLaunchPermit>,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        if !spawns_on_create(tab) {
            return Ok(None);
        }
        let session_id = terminal_session_id(tab);
        if self.sessions.get(&session_id).is_some_and(Session::running) {
            return Ok(None);
        }
        if permit.is_none()
            && self
                .runtime_store
                .workflow_coordinator_for_terminal(&tab.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .is_some()
        {
            return Ok(None);
        }
        if permit.is_none()
            && self
                .runtime_store
                .workflow_launch_for_terminal(&tab.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .is_some()
        {
            // Restoration retains the tab and its diagnostics without replaying
            // an uncertain, failed or completed worker's bootstrap.
            return Ok(None);
        }
        let rearmed = self.rearm_terminal_after_ready_prompt(tab).await?;
        let tab = rearmed.as_ref().unwrap_or(tab);
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("workspace not found: {}", tab.workspace_id))
            })?;
        if workspace.status != WorkspaceStatus::Active {
            return Err(HostError::state(format!(
                "workspace is not active: {}",
                workspace.id
            )));
        }

        let max_bytes = self.config.scrollback_bytes as usize;
        let (initial_scrollback, initial_output_stream_bytes) = self
            .take_terminal_restart_state(&session_id, &workspace.id, &tab.id, max_bytes)
            .await;
        let default_launch =
            default_terminal_launch(&workspace.path, self.config.login_shell).await;
        let forced_hook = pending_agent_type(tab).or_else(|| {
            alera_core::runtime::is_voice_home_workspace_id(&workspace.id)
                .then(|| tab_agent_type(tab))
                .flatten()
        });
        self.start_new_terminal_session_with_permit(
            session_id.clone(),
            workspace.id,
            tab.id.clone(),
            workspace.path,
            default_launch.launch,
            DEFAULT_TERMINAL_COLS,
            DEFAULT_TERMINAL_ROWS,
            initial_scrollback,
            initial_output_stream_bytes,
            forced_hook,
            permit,
        )
        .await?;
        let command = match resolve_spawn_command(tab, &default_launch.interactive_shell)? {
            Some(SpawnCommand::Stdin { command, prompt }) => Some(if permit.is_some() {
                let directory = self
                    .setup_script_directory()
                    .ok_or_else(|| HostError::state("workflow prompt directory is unavailable"))?;
                crate::agent_prompt_stdin_script::write_agent_prompt_stdin_script(
                    &directory,
                    &session_id,
                    &command,
                    &prompt,
                )
                .map_err(|error| HostError::state(error.to_string()))?
                .command
            } else {
                self.stdin_prompt_command(&session_id, &command, &prompt)
            }),
            Some(SpawnCommand::Line(command)) => Some(command),
            None => None,
        };
        if let Some(command) = command {
            let instance_id = self
                .sessions
                .get(&session_id)
                .map(Session::instance_id)
                .expect("spawned terminal was inserted");
            self.schedule_terminal_startup_input(
                session_id,
                instance_id,
                default_launch.interactive_shell,
                command,
            );
            // A one-shot command is spent as soon as it is on its way. Agent
            // tabs deliberately do not set the flag: they re-mint their command
            // on every new PTY, including after host recovery.
            if delivers_initial_command_once(tab) {
                return Ok(self.clear_initial_command(tab).await);
            }
            if delivers_initial_prompt_once(tab) {
                return Ok(self.clear_initial_prompt(tab).await);
            }
        }
        Ok(rearmed)
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn start_new_terminal_session(
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
    async fn start_new_terminal_session_with_permit(
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
        let woken_workspace_id = workspace_id.clone();
        let woken_tab_id = tab_id.clone();
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
        self.sessions.insert(session_id, session);
        self.wake_workspace_for_tab(&woken_workspace_id, &woken_tab_id)
            .await;
        Ok(())
    }

    pub(super) async fn take_terminal_restart_state(
        &mut self,
        session_id: &str,
        workspace_id: &str,
        tab_id: &str,
        max_bytes: usize,
    ) -> (Vec<u8>, u64) {
        self.disarm_terminal_pulse(session_id);
        self.abandon_home_inject(session_id);
        if let Some(mut dead) = self.sessions.remove(session_id) {
            let scrollback = dead.buffer.to_bytes();
            let output_stream_bytes = dead.output_stream_range().1;
            dead.terminate(false, &self.store).await;
            self.agent_presence.remove(session_id);
            return (scrollback, output_stream_bytes);
        }
        if let Some(restored) = Session::restore_exited(
            session_id.to_string(),
            workspace_id.to_string(),
            tab_id.to_string(),
            &self.store,
            max_bytes,
        )
        .await
        {
            return (restored.buffer.to_bytes(), restored.output_stream_range().1);
        }
        (Vec::new(), 0)
    }
}

fn spawns_on_create(tab: &WorkspaceTabRecord) -> bool {
    tab.kind == "terminal"
        && tab.payload.get("spawnOnCreate").and_then(Value::as_bool) == Some(true)
}
