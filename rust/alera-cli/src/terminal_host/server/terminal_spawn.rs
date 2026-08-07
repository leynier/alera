use alera_core::runtime::{WorkspaceStatus, WorkspaceTabRecord};
use serde_json::Value;

use crate::agent_status::prepare_launch_environment;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_registry::{adapter_for, AgentStartupPrompt};
use crate::terminal_host::orchestration::agent_startup_command::{
    append_initial_prompt_argument, command_with_initial_prompt,
};
use crate::terminal_host::protocol::TerminalHostLaunch;
use crate::terminal_host::session::{PtyWriteCompletion, Session};

use super::pty_event_forwarder::forward_pty_event;
use super::terminal_launch_defaults::default_terminal_launch;
use super::terminal_startup_commands::{
    auto_close_setup_command, auto_closes_on_success, delivers_initial_command_once,
    delivers_initial_prompt_once, initial_command, initial_managed_agent_launch, initial_prompt,
    pending_agent_type, tab_agent_type, terminal_session_id,
};
use super::{ServerActor, ServerCommand};

const DEFAULT_TERMINAL_COLS: u16 = 80;
const DEFAULT_TERMINAL_ROWS: u16 = 24;
const STARTUP_INPUT_DELAY_MS: u64 = 120;
const STARTUP_SUBMIT_DELAY_MS: u64 = 500;

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

    pub(super) async fn upsert_workspace_tab_and_spawn(
        &mut self,
        tab: WorkspaceTabRecord,
    ) -> HostResult<WorkspaceTabRecord> {
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let saved = match self.ensure_spawn_on_create_terminal(&saved).await {
            Ok(rewritten) => rewritten.unwrap_or(saved),
            Err(error) => {
                let _ = self.runtime_store.remove_workspace_tab(&saved.id).await;
                self.terminate_sessions_for_tab(&saved.id).await;
                return Err(error);
            }
        };
        self.broadcast_workspace_tabs_changed(Some(&saved.workspace_id));
        Ok(saved)
    }

    /// Spawns the PTY a `spawnOnCreate` tab asks for. Returns the tab record
    /// when spawning rewrote it, which happens for a one-shot initial command.
    pub(super) async fn ensure_spawn_on_create_terminal(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        if !spawns_on_create(tab) {
            return Ok(None);
        }
        let session_id = terminal_session_id(tab);
        if self.sessions.get(&session_id).is_some_and(Session::running) {
            return Ok(None);
        }
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
        self.start_new_terminal_session(
            session_id.clone(),
            workspace.id,
            tab.id.clone(),
            workspace.path,
            default_launch.launch,
            DEFAULT_TERMINAL_COLS,
            DEFAULT_TERMINAL_ROWS,
            initial_scrollback,
            initial_output_stream_bytes,
            pending_agent_type(tab),
        )
        .await?;
        let managed_launch = initial_managed_agent_launch(tab)?;
        let prompt = initial_prompt(tab);
        // Which shape the prompt takes is the agent's business, and only the
        // adapter knows it. An unknown agent type leaves the launch bare rather
        // than guessing a flag the CLI would reject.
        let adapter = tab_agent_type(tab).and_then(adapter_for);
        let prompt_arguments = adapter.zip(prompt.as_deref());
        let command = if let Some(mut launch) = managed_launch {
            if let Some((adapter, prompt)) = prompt_arguments {
                append_initial_prompt_argument(adapter, &mut launch.arguments, prompt);
            }
            Some(
                crate::terminal_host::orchestration::managed_launch_shell_rendering::render_managed_launch(
                    &launch,
                    &default_launch.interactive_shell,
                ),
            )
        } else {
            initial_command(tab).map(|command| {
                let command = prompt_arguments
                    .map(|(adapter, prompt)| {
                        command_with_initial_prompt(
                            adapter,
                            &command,
                            prompt,
                            &default_launch.interactive_shell,
                        )
                    })
                    .unwrap_or(command);
                if auto_closes_on_success(tab) {
                    auto_close_setup_command(&command, &default_launch.interactive_shell)
                } else {
                    command
                }
            })
        };
        let command = match (prompt_arguments, command) {
            (Some((adapter, prompt)), Some(command))
                if adapter.startup_prompt == AgentStartupPrompt::StdinScript =>
            {
                Some(self.stdin_prompt_command(&session_id, &command, prompt))
            }
            (_, command) => command,
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
        Ok(None)
    }

    /// Rewrites a launch so the agent reads its prompt from stdin.
    ///
    /// Falls back to the bare launch when the script cannot be written: a tab
    /// holding an agent without its prompt is a far better outcome than a tab
    /// holding no agent at all.
    fn stdin_prompt_command(&self, session_id: &str, command: &str, prompt: &str) -> String {
        let Some(directory) = self.setup_script_directory() else {
            tracing::warn!(
                session_id = %session_id,
                "no runtime directory for the agent prompt script; launching without the prompt"
            );
            return command.to_string();
        };
        match crate::agent_prompt_stdin_script::write_agent_prompt_stdin_script(
            &directory, session_id, command, prompt,
        ) {
            Ok(script) => script.command,
            Err(error) => {
                tracing::error!(
                    session_id = %session_id,
                    "failed to write the agent prompt script; launching without the prompt: {error}"
                );
                command.to_string()
            }
        }
    }

    async fn clear_initial_command(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> Option<WorkspaceTabRecord> {
        let mut next = tab.clone();
        let payload = next.payload.as_object_mut()?;
        payload.remove("initialCommand");
        payload.remove("initialCommandOnce");
        match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => Some(saved),
            Err(error) => {
                eprintln!(
                    "failed to clear the one-shot initial command of tab {}: {error}",
                    tab.id
                );
                None
            }
        }
    }

    async fn clear_initial_prompt(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> Option<WorkspaceTabRecord> {
        let mut next = tab.clone();
        let payload = next.payload.as_object_mut()?;
        payload.remove("initialPrompt");
        payload.remove("initialPromptOnce");
        match self.runtime_store.upsert_workspace_tab(next).await {
            Ok(saved) => Some(saved),
            Err(error) => {
                tracing::error!(
                    tab_id = %tab.id,
                    "failed to clear one-shot initial agent prompt: {error}"
                );
                None
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn start_new_terminal_session(
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
    ) -> HostResult<()> {
        self.account_push.damper.reset_session(&session_id);
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
            if let Some(profile_id) = tab.payload.get("agentProfileId").and_then(Value::as_str) {
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
        let session = Session::start(
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
        )
        .await?;
        self.sessions.insert(session_id, session);
        Ok(())
    }

    pub(super) async fn take_terminal_restart_state(
        &mut self,
        session_id: &str,
        workspace_id: &str,
        tab_id: &str,
        max_bytes: usize,
    ) -> (Vec<u8>, u64) {
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

    fn schedule_terminal_startup_input(
        &self,
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(STARTUP_INPUT_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::TerminalStartupInput {
                session_id,
                session_instance_id,
                interactive_shell,
                command,
            });
        });
    }

    pub(super) fn handle_terminal_startup_input(
        &mut self,
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if session.instance_id() != session_instance_id || !session.running() {
            return;
        }
        let uses_paste = crate::terminal_host::orchestration::agent_prompt_injection::should_use_bracketed_paste_for_startup(&command)
            && crate::terminal_host::orchestration::agent_prompt_injection::shell_supports_bracketed_paste(&interactive_shell);
        let bytes = if uses_paste {
            crate::terminal_host::orchestration::agent_prompt_injection::build_agent_prompt_paste_bytes(&command)
        } else {
            crate::terminal_host::orchestration::agent_prompt_injection::build_plain_startup_command_bytes(&command)
        };
        let completion = if uses_paste {
            PtyWriteCompletion::StartupPaste {
                session_instance_id,
            }
        } else {
            PtyWriteCompletion::StartupPlain {
                session_instance_id,
            }
        };
        if let Err(error) = session.queue_write(completion, &bytes) {
            self.broadcast_terminal_error(&session_id, error.wire_message());
        }
    }

    pub(super) fn schedule_terminal_startup_submit(
        &self,
        session_id: String,
        session_instance_id: u64,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(STARTUP_SUBMIT_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::TerminalStartupSubmit {
                session_id,
                session_instance_id,
            });
        });
    }

    pub(super) fn handle_terminal_startup_submit(
        &mut self,
        session_id: String,
        session_instance_id: u64,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if session.instance_id() != session_instance_id || !session.running() {
            return;
        }
        if let Err(error) = session.queue_write(
            PtyWriteCompletion::StartupSubmit {
                session_instance_id,
            },
            crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
        ) {
            self.broadcast_terminal_error(&session_id, error.wire_message());
        }
    }
}

fn spawns_on_create(tab: &WorkspaceTabRecord) -> bool {
    tab.kind == "terminal"
        && tab.payload.get("spawnOnCreate").and_then(Value::as_bool) == Some(true)
}
