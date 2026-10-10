//! `terminal.restart` for a caller that renders no terminal, such as the CLI
//! or an MCP client. The desktop computes the launch and types the tab's
//! startup command itself; here the host does both, the way it starts a
//! spawn-on-create tab.

use serde_json::json;

use super::super::terminal_startup_commands::{initial_command, initial_managed_agent_launch};
use super::*;

impl ServerActor {
    pub(in crate::terminal_host::server) async fn restart_terminal_headless(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let session_id = super::super::requests::require_string_key(payload, "sessionId")?;
        let tab = self
            .terminal_tab_for_session(&session_id)
            .await?
            .ok_or_else(|| HostError::state(format!("Terminal not found: {session_id}")))?;
        if tab.kind != "terminal" {
            return Err(HostError::state(format!(
                "Workspace tab is not a terminal: {}",
                tab.id
            )));
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
        let default_launch =
            default_terminal_launch(&workspace.path, self.config.login_shell).await;
        let request = json!({
            "sessionId": session_id,
            "workspaceId": workspace.id,
            "tabId": tab.id,
            "workingDirectory": workspace.path,
            "launch": default_launch.launch.to_json(),
            "cols": DEFAULT_TERMINAL_COLS,
            "rows": DEFAULT_TERMINAL_ROWS,
        });
        self.restart_terminal(client_id, &request).await?;
        // The caller shows no output, so it does not stay attached.
        if let Some(session) = self.sessions.get_mut(&session_id) {
            session.detach(client_id);
        }
        // The restart types a discovered resume line for a plain shell tab.
        // A launch or a command is the client's to type, so type it here.
        if initial_managed_agent_launch(&tab)?.is_some() || initial_command(&tab)?.is_some() {
            self.deliver_tab_startup_command(
                &tab,
                &session_id,
                default_launch.interactive_shell,
                None,
            )
            .await?;
        }
        Ok(json!({
            "sessionId": session_id,
            "tabId": tab.id,
            "workspaceId": tab.workspace_id,
            "restarted": true,
        }))
    }
}

impl ServerActor {
    /// The tab of a terminal session. An exited session may no longer be
    /// live, and its tab id need not equal the session id, so the tabs are
    /// searched for it.
    async fn terminal_tab_for_session(
        &self,
        session_id: &str,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        let store_error = |error: anyhow::Error| HostError::state(error.to_string());
        if let Some(session) = self.sessions.get(session_id) {
            return self
                .runtime_store
                .find_workspace_tab(&session.tab_id)
                .await
                .map_err(store_error);
        }
        Ok(self
            .runtime_store
            .list_all_workspace_tabs()
            .await
            .map_err(store_error)?
            .into_iter()
            .find(|tab| terminal_session_id(tab) == session_id))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use alera_core::runtime::WorkspaceTabRecord;
    use serde_json::json;

    use super::super::super::actor_test_harness::{local_client, test_actor};
    use super::ServerActor;
    use crate::terminal_host::client::ClientHandle;

    async fn actor_with_terminal_tab(directory: &tempfile::TempDir, kind: &str) -> ServerActor {
        let (handle, _receiver) = ClientHandle::test_channels();
        let actor = test_actor(
            directory,
            HashMap::from([(1, local_client(handle))]),
            HashMap::new(),
        )
        .await;
        let folder = directory.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        let project = crate::project_management::register_project(
            &actor.runtime_store,
            folder.to_str().unwrap(),
            None,
        )
        .await
        .unwrap()
        .project;
        let workspace = actor
            .runtime_store
            .list_workspaces(&project.id)
            .await
            .unwrap()
            .remove(0);
        let now = chrono::Utc::now();
        actor
            .runtime_store
            .insert_workspace_tab(WorkspaceTabRecord {
                id: "tab".into(),
                workspace_id: workspace.id,
                kind: kind.into(),
                title: "Terminal".into(),
                created_at: now,
                updated_at: now,
                payload: json!({ "terminalSessionId": "session", "initialCommand": "true" }),
            })
            .await
            .unwrap();
        actor
    }

    #[tokio::test]
    async fn headless_restart_starts_the_tab_without_keeping_the_caller_attached() {
        let directory = tempfile::tempdir().unwrap();
        let mut actor = actor_with_terminal_tab(&directory, "terminal").await;

        let result = actor
            .restart_terminal_headless(1, &json!({ "sessionId": "session", "headless": true }))
            .await
            .unwrap();

        assert_eq!(result["restarted"], true);
        assert_eq!(result["tabId"], "tab");
        let session = &actor.sessions["session"];
        assert!(session.running());
        assert!(!session.clients.contains(&1));
        actor
            .terminate_session_request("session".into())
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn headless_restart_refuses_unknown_terminals_and_other_tabs() {
        let directory = tempfile::tempdir().unwrap();
        let mut actor = actor_with_terminal_tab(&directory, "editor").await;

        let missing = actor
            .restart_terminal_headless(1, &json!({ "sessionId": "other" }))
            .await
            .unwrap_err();
        assert!(
            missing.to_string().contains("Terminal not found"),
            "{missing}"
        );
        let editor = actor
            .restart_terminal_headless(1, &json!({ "sessionId": "session" }))
            .await
            .unwrap_err();
        assert!(editor.to_string().contains("not a terminal"), "{editor}");
        assert!(actor.sessions.is_empty());
    }
}
