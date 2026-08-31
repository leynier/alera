use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{int_or, require_object, TerminalHostLaunch};
use crate::terminal_host::session::Session;

use super::requests::require_string;
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
        self.start_new_terminal_session(
            session_id.clone(),
            workspace_id,
            tab_id,
            working_directory,
            launch,
            cols,
            rows,
            initial_scrollback,
            initial_output_stream_bytes,
            None,
        )
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
            tab_id,
            working_directory,
            launch,
            cols,
            rows,
            initial_scrollback,
            initial_output_stream_bytes,
            None,
        )
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
}
