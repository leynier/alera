//! `workspace.wake`: start again the terminals a workspace sleep stopped.
//!
//! Opening a slept workspace in the desktop or mobile app attaches each of its
//! terminal tabs, and the first session that starts clears the sleep. A client
//! without a terminal view (the CLI, an MCP tool) asks the host to do the same
//! attach for every slept tab, the way a phone attaches one tab: the host
//! resolves each tab's command and native agent session from its record.
//! An app types a command or agent launch tab's startup line itself on attach,
//! so for a caller that types nothing the host delivers it, the way
//! `terminal.restart` does for a headless caller.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::requests::{require_string_key, terminal_session_id_from_tab};
use crate::terminal_host::server::terminal_launch_defaults::default_terminal_launch;
use crate::terminal_host::server::terminal_startup_commands::{
    initial_command, initial_managed_agent_launch,
};
use crate::terminal_host::server::ServerActor;

impl ServerActor {
    pub(in crate::terminal_host::server) async fn wake_workspace_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(state_error)?
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
            return Err(HostError::state(format!(
                "Workspace {workspace_id} runs on SSH host {}, whose runtime keeps its own terminals, so it is never asleep here.",
                workspace.host_id
            )));
        }
        if workspace.is_archived {
            return Err(HostError::state(format!(
                "Workspace {workspace_id} is archived. Unarchive it before waking it."
            )));
        }
        let slept = self
            .slept_workspace_tab_ids()
            .await?
            .remove(&workspace_id)
            .unwrap_or_default();
        let mut woken = Vec::new();
        let mut failed = Vec::new();
        for tab_id in &slept {
            let tab = self
                .runtime_store
                .find_workspace_tab(tab_id)
                .await
                .map_err(state_error)?
                .filter(|tab| tab.kind == "terminal" && tab.workspace_id == workspace_id);
            // A slept terminal closed since then has nothing to start.
            let Some(tab) = tab else { continue };
            let session_id = terminal_session_id_from_tab(&tab).unwrap_or_else(|| tab.id.clone());
            let launch = default_terminal_launch(&workspace.path, self.config.login_shell).await;
            let attachment = json!({
                "sessionId": session_id,
                "workspaceId": workspace.id,
                "tabId": tab.id,
                "workingDirectory": workspace.path,
                "launch": launch.launch.to_json(),
                "cols": 80,
                "rows": 24,
            });
            let started = match self.create_or_attach(client_id, &attachment).await {
                Ok(attached) => {
                    // The caller only asked for the wake; it does not view
                    // the terminal, so an app that opens it later drives it.
                    if let Some(session) = self.sessions.get_mut(&session_id) {
                        session.detach(client_id);
                    }
                    // Only a new PTY needs its startup line; a terminal still
                    // running already has its command.
                    if attached["created"] == true {
                        self.deliver_woken_tab_startup(&tab, &session_id, launch.interactive_shell)
                            .await
                    } else {
                        Ok(())
                    }
                }
                Err(error) => Err(error),
            };
            match started {
                Ok(()) => woken.push(json!({ "tabId": tab.id, "sessionId": session_id })),
                Err(error) => failed.push(json!({ "tabId": tab.id, "error": error.to_string() })),
            }
        }
        if woken.is_empty() && !failed.is_empty() {
            return Err(HostError::state(format!(
                "No terminal of workspace {workspace_id} could start: {}",
                failed
                    .iter()
                    .filter_map(|item| item["error"].as_str())
                    .collect::<Vec<_>>()
                    .join("; ")
            )));
        }
        // A started session already cleared the sleep. A terminal still
        // running, or every slept terminal closed since, leaves it recorded.
        if let Some(first) = slept.first() {
            self.wake_workspace_for_tab(&workspace_id, first).await;
        }
        Ok(json!({
            "workspaceId": workspace_id,
            "wasAsleep": !slept.is_empty(),
            "woken": woken,
            "failed": failed,
        }))
    }
}

impl ServerActor {
    /// The attach typed a discovered resume line for a plain shell tab. A
    /// command or managed agent launch is the attaching client's to type, so
    /// type it here, in its resume form once the agent reported a session.
    async fn deliver_woken_tab_startup(
        &mut self,
        tab: &alera_core::runtime::WorkspaceTabRecord,
        session_id: &str,
        interactive_shell: String,
    ) -> HostResult<()> {
        if initial_managed_agent_launch(tab)?.is_none() && initial_command(tab)?.is_none() {
            return Ok(());
        }
        if self
            .deliver_tab_startup_command(tab, session_id, interactive_shell, None)
            .await?
            .is_some()
        {
            // A one-shot command or prompt was spent with this delivery.
            self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
        }
        Ok(())
    }
}

fn state_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

#[cfg(test)]
#[path = "workspace_wake_requests_tests.rs"]
mod tests;
