mod session_start;

use alera_core::runtime::{WorkspaceStatus, WorkspaceTabRecord};
use serde_json::Value;

use crate::agent_status::prepare_launch_environment;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::TerminalHostLaunch;
use crate::terminal_host::session::Session;

use super::pty_event_forwarder::forward_pty_event;
use super::run_launch_requests::WorkflowLaunchPermit;
use super::terminal_launch_defaults::default_terminal_launch;
use super::terminal_spawn_command::{resolve_spawn_command, SpawnCommand};
use super::terminal_startup_commands::{
    agent_profile_id, delivers_initial_command_once, delivers_initial_prompt_once,
    pending_agent_type, tab_agent_type, terminal_session_id,
};
use super::ServerActor;

const DEFAULT_TERMINAL_COLS: u16 = 80;
const DEFAULT_TERMINAL_ROWS: u16 = 24;

mod headless_restart;
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
                // The automation runner alone reconciles owner liveness and
                // retry budgets. The run decides whether a user took the tab
                // over; the tab's own marker only speaks for a pruned run.
                if tab.payload["automationOwned"] == true {
                    let run = match tab.payload["automationRunId"].as_str() {
                        Some(id) => self
                            .runtime_store
                            .find_automation_run(id)
                            .await
                            .ok()
                            .flatten(),
                        None => None,
                    };
                    let taken_over = match run {
                        Some(run) => run.taken_over,
                        None => tab.payload["automationTakenOver"] == true,
                    };
                    if !taken_over {
                        continue;
                    }
                }
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
            .await?;
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
        if let Some(spent) = self
            .deliver_tab_startup_command(tab, &session_id, default_launch.interactive_shell, permit)
            .await?
        {
            return Ok(spent);
        }
        Ok(rearmed)
    }

    /// Types the tab's startup command into its new PTY. Returns `Some` when
    /// a one-shot command or prompt was spent, holding the tab as saved
    /// without it (`None` inside when that save failed).
    pub(super) async fn deliver_tab_startup_command(
        &mut self,
        tab: &WorkspaceTabRecord,
        session_id: &str,
        interactive_shell: String,
        permit: Option<&WorkflowLaunchPermit>,
    ) -> HostResult<Option<Option<WorkspaceTabRecord>>> {
        let command = match resolve_spawn_command(tab, &interactive_shell)? {
            Some(SpawnCommand::Stdin { command, prompt }) => Some(if permit.is_some() {
                let directory = self
                    .setup_script_directory()
                    .ok_or_else(|| HostError::state("workflow prompt directory is unavailable"))?;
                crate::agent_prompt_stdin_script::write_agent_prompt_stdin_script(
                    &directory, session_id, &command, &prompt,
                )
                .map_err(|error| HostError::state(error.to_string()))?
                .command
            } else {
                self.stdin_prompt_command(session_id, &command, &prompt)
            }),
            Some(SpawnCommand::Line(command)) => Some(command),
            None => None,
        };
        let Some(command) = command else {
            return Ok(None);
        };
        let instance_id = self
            .sessions
            .get(session_id)
            .map(Session::instance_id)
            .expect("spawned terminal was inserted");
        self.schedule_terminal_startup_input(
            session_id.to_string(),
            instance_id,
            interactive_shell,
            command,
        );
        // A one-shot command is spent as soon as it is on its way. Agent
        // tabs deliberately do not set the flag: they re-mint their command
        // on every new PTY, including after host recovery.
        if delivers_initial_command_once(tab) {
            return Ok(Some(self.clear_initial_command(tab).await));
        }
        if delivers_initial_prompt_once(tab) {
            return Ok(Some(self.clear_initial_prompt(tab).await));
        }
        Ok(None)
    }

    pub(super) async fn take_terminal_restart_state(
        &mut self,
        session_id: &str,
        workspace_id: &str,
        tab_id: &str,
        max_bytes: usize,
    ) -> HostResult<(Vec<u8>, u64)> {
        self.disarm_terminal_pulse(session_id);
        self.abandon_home_inject(session_id);
        self.hold_history_barrier(session_id);
        self.flush_all_output(session_id).await;
        if !self.await_output_writes(session_id).await {
            return Err(HostError::state(
                "Terminal history could not be persisted; the session remains open for retry.",
            ));
        }
        if let Some(mut dead) = self.sessions.remove(session_id) {
            self.inbox.resume_pty_session(session_id);
            self.history_writers.remove(session_id);
            let scrollback = dead.buffer.to_bytes();
            let output_stream_bytes = dead.output_stream_range().1;
            dead.terminate(false, &self.store).await;
            self.agent_presence.remove(session_id);
            return Ok((scrollback, output_stream_bytes));
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
            return Ok((restored.buffer.to_bytes(), restored.output_stream_range().1));
        }
        Ok((Vec::new(), 0))
    }
}

fn spawns_on_create(tab: &WorkspaceTabRecord) -> bool {
    tab.kind == "terminal"
        && tab.payload.get("spawnOnCreate").and_then(Value::as_bool) == Some(true)
}
