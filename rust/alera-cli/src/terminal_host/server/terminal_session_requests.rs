use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{int_or, require_object, TerminalHostLaunch};
use crate::terminal_host::session::Session;

use super::requests::require_string;
use super::terminal_spawn_command::{resolve_spawn_command, SpawnCommand};
use super::terminal_startup_commands::{initial_command, initial_managed_agent_launch};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn create_or_attach(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let session_id = require_string(payload, "sessionId")?;
        let workspace_id = require_string(payload, "workspaceId")?;
        let tab_id = require_string(payload, "tabId")?;
        let working_directory = require_string(payload, "workingDirectory")?;
        if self
            .runtime_store
            .find_workspace_tab(&tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .is_some_and(|tab| tab.payload["sshOwnerTerminal"] == true)
        {
            let workspace = self
                .runtime_store
                .find_workspace(&workspace_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| HostError::state("The owner workspace is missing"))?;
            if let Some(expected) = self
                .runtime_store
                .terminal_restart_launch_token(&workspace, &tab_id, &session_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                if payload["launchToken"].as_str() != Some(expected.as_str()) {
                    return Err(HostError::state(
                        "The terminal restart superseded this launch; reconnect using the replacement identity",
                    ));
                }
            }
        }

        if self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.workspace_id != workspace_id || session.tab_id != tab_id)
        {
            return Err(HostError::state(
                "This terminal session belongs to another workspace or tab; no session was replaced.",
            ));
        }

        if let Some(attachment) = self
            .attach_workflow_terminal(client_id, &session_id, &workspace_id, &tab_id)
            .await?
        {
            return Ok(attachment);
        }

        // Attaching a user client to a tab created for an automation is the
        // durable takeover signal. It prevents a later successful completion
        // from deleting a tab the user has started using.
        if let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(&tab_id).await {
            if tab
                .payload
                .get("automationOwned")
                .and_then(Value::as_bool)
                .unwrap_or(false)
            {
                let mut tab = tab;
                let run_id = tab
                    .payload
                    .get("automationRunId")
                    .and_then(Value::as_str)
                    .map(str::to_string);
                tab.updated_at = chrono::Utc::now();
                let _ = self.runtime_store.upsert_workspace_tab(tab).await;
                if let Some(run_id) = run_id.as_deref() {
                    let (mobile, local_role, id, human_client) = self
                        .clients
                        .get(&client_id)
                        .map(|client| {
                            (
                                client.kind == super::ClientKind::Mobile,
                                client.local_role,
                                client
                                    .mobile_device_id
                                    .clone()
                                    .or_else(|| Some(client_id.to_string())),
                                client.kind == super::ClientKind::Mobile
                                    || (client.kind == super::ClientKind::Local
                                        && client.local_role
                                            == super::client_delivery::LocalClientRole::App),
                            )
                        })
                        .unwrap_or((
                            false,
                            super::client_delivery::LocalClientRole::Cli,
                            None,
                            false,
                        ));
                    if human_client {
                        let actor =
                            super::automation_actor::actor_for_client(mobile, local_role, id);
                        // Only a desktop or authenticated mobile client counts
                        // as a user takeover. The automation CLI is a local
                        // client too, but it must not preserve its own cleanup
                        // target.
                        let _ = self
                            .runtime_store
                            .mark_automation_run_taken_over(run_id, actor)
                            .await;
                    }
                }
            }
        }

        let max_bytes = self.config.scrollback_bytes as usize;
        let restore_bytes = self.config.restore_snapshot_bytes as usize;

        // Live session: attach only. Dead session: remint with the same handle so
        // ALERA_TERMINAL_HANDLE / orchestration dispatch targets stay valid.
        if self.sessions.contains_key(&session_id) {
            let running = self.sessions.get(&session_id).is_some_and(Session::running);
            if running {
                self.flush_all_output(&session_id);
                let session = self.sessions.get_mut(&session_id).expect("just checked");
                session.attach(client_id);
                return Ok(session.attachment_payload(false, restore_bytes));
            }
        }
        let (initial_scrollback, initial_output_stream_bytes) = self
            .take_terminal_restart_state(&session_id, &workspace_id, &tab_id, max_bytes)
            .await;

        let launch = TerminalHostLaunch::from_json(&Value::Object(
            require_object(payload.get("launch"), "launch")?.clone(),
        ))?;
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        let interactive_shell = launch.shell.clone();
        self.start_new_terminal_session(
            session_id.clone(),
            workspace_id,
            tab_id.clone(),
            working_directory,
            launch,
            cols,
            rows,
            initial_scrollback,
            initial_output_stream_bytes,
            None,
        )
        .await?;
        self.schedule_discovered_session_resume(&session_id, &tab_id, &interactive_shell)
            .await?;
        let session = self.sessions.get_mut(&session_id).expect("just inserted");
        session.attach(client_id);
        Ok(session.attachment_payload(true, restore_bytes))
    }

    pub(super) async fn restart_terminal(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let session_id = require_string(payload, "sessionId")?;
        let workspace_id = require_string(payload, "workspaceId")?;
        let tab_id = require_string(payload, "tabId")?;
        let working_directory = require_string(payload, "workingDirectory")?;
        self.require_workflow_spawn_permit(&session_id, &workspace_id, &tab_id, None)
            .await?;
        let launch = TerminalHostLaunch::from_json(&Value::Object(
            require_object(payload.get("launch"), "launch")?.clone(),
        ))?;
        let cols = int_or(payload, "cols", 80) as u16;
        let rows = int_or(payload, "rows", 24) as u16;
        let interactive_shell = launch.shell.clone();

        if let Some(session) = self.sessions.get(&session_id) {
            if session.workspace_id != workspace_id || session.tab_id != tab_id {
                return Err(HostError::state(
                    "Terminal restart metadata does not match the live session.",
                ));
            }
        }

        let attached_clients = self
            .sessions
            .get(&session_id)
            .map(|session| session.clients.iter().copied().collect::<Vec<_>>())
            .unwrap_or_default();
        self.queue_terminal_exit_push(&session_id, None).await;
        self.cleanup_orchestration_for_closed_session(
            &session_id,
            "terminal was explicitly restarted",
        )
        .await;
        self.flush_all_output(&session_id);
        self.await_output_writes(&session_id).await;
        let max_bytes = self.config.scrollback_bytes as usize;
        let restore_bytes = self.config.restore_snapshot_bytes as usize;
        let (initial_scrollback, initial_output_stream_bytes) = self
            .take_terminal_restart_state(&session_id, &workspace_id, &tab_id, max_bytes)
            .await;
        self.start_new_terminal_session(
            session_id.clone(),
            workspace_id,
            tab_id.clone(),
            working_directory,
            launch,
            cols,
            rows,
            initial_scrollback,
            initial_output_stream_bytes,
            None,
        )
        .await?;
        self.schedule_discovered_session_resume(&session_id, &tab_id, &interactive_shell)
            .await?;

        let resync_clients = attached_clients
            .into_iter()
            .filter(|attached_client_id| {
                *attached_client_id != client_id && self.clients.contains_key(attached_client_id)
            })
            .collect::<Vec<_>>();
        let session = self.sessions.get_mut(&session_id).expect("just inserted");
        session.attach(client_id);
        for attached_client_id in &resync_clients {
            session.attach_for_resync(*attached_client_id);
        }
        let attachment = session.attachment_payload(true, restore_bytes);
        for attached_client_id in resync_clients {
            self.spawn_output_resync_timer(session_id.clone(), attached_client_id);
        }
        Ok(attachment)
    }

    /// Interactive tabs have no launch snapshot. After a remint, type the
    /// adapter resume line captured from hooks.
    pub(super) async fn schedule_discovered_session_resume(
        &mut self,
        session_id: &str,
        tab_id: &str,
        interactive_shell: &str,
    ) -> HostResult<()> {
        let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(tab_id).await else {
            return Ok(());
        };
        if initial_managed_agent_launch(&tab)?.is_some() || initial_command(&tab)?.is_some() {
            return Ok(());
        }
        let Some(SpawnCommand::Line(command)) = resolve_spawn_command(&tab, interactive_shell)?
        else {
            return Ok(());
        };
        let Some(instance_id) = self.sessions.get(session_id).map(Session::instance_id) else {
            return Ok(());
        };
        self.schedule_terminal_startup_input(
            session_id.to_string(),
            instance_id,
            interactive_shell.to_string(),
            command,
        );
        Ok(())
    }
}

#[cfg(test)]
mod identity_tests {
    use super::*;
    use std::collections::HashMap;

    #[tokio::test]
    async fn attachment_rejects_foreign_workspace_or_tab_before_changing_session() {
        for (workspace, tab) in [("foreign", "owned-tab"), ("owned-workspace", "foreign")] {
            let directory = tempfile::tempdir().unwrap();
            let mut session = Session::driver_test_stub("owned-session", 80, 24);
            session.workspace_id = "owned-workspace".into();
            session.tab_id = "owned-tab".into();
            let mut actor = super::super::actor_test_harness::test_actor(
                &directory,
                HashMap::new(),
                HashMap::from([("owned-session".into(), session)]),
            )
            .await;
            let error = actor
                .create_or_attach(
                    123,
                    &serde_json::json!({
                        "sessionId":"owned-session", "workspaceId":workspace,
                        "tabId":tab, "workingDirectory":"/unused",
                    }),
                )
                .await
                .unwrap_err();
            assert!(error
                .to_string()
                .contains("belongs to another workspace or tab"));
            let retained = &actor.sessions["owned-session"];
            assert_eq!(retained.workspace_id, "owned-workspace");
            assert_eq!(retained.tab_id, "owned-tab");
            assert!(retained.output_clients().is_empty());
        }
    }
}
