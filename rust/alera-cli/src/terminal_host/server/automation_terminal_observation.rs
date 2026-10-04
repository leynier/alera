use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::session::Session;
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn retains_automation_terminal_history(&self, session_id: &str) -> bool {
        let Some(session) = self.sessions.get(session_id) else {
            return false;
        };
        self.runtime_store
            .find_workspace_tab(&session.tab_id)
            .await
            .ok()
            .flatten()
            .is_some_and(|tab| {
                tab.payload["automationOwned"] == true && tab.payload["automationTakenOver"] != true
            })
    }

    pub(super) fn require_terminal_writer(
        &self,
        client_id: u64,
        session_id: &str,
    ) -> HostResult<()> {
        if self
            .sessions
            .get(session_id)
            .is_some_and(|s| s.observer_clients.contains(&client_id))
        {
            return Err(HostError::state("Observing. Take over to type."));
        }
        Ok(())
    }

    pub(super) async fn observe_automation_terminal(
        &mut self,
        client_id: u64,
        session_id: &str,
        workspace_id: &str,
        tab_id: &str,
    ) -> HostResult<Value> {
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .ok_or_else(|| HostError::state("Automation terminal is missing"))?;
        let run_id = tab.payload["automationRunId"]
            .as_str()
            .ok_or_else(|| HostError::state("This tab is not an automation terminal"))?;
        let run = self
            .runtime_store
            .find_automation_run(run_id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .ok_or_else(|| HostError::state("Automation run is missing"))?;
        if tab.payload["automationOwned"] != true || tab.workspace_id != workspace_id {
            return Err(HostError::state(
                "Automation terminal identity does not match its run",
            ));
        }
        let matching_attempt = self
            .runtime_store
            .automation_attempts(run_id)
            .await
            .map_err(|e| HostError::state(e.to_string()))?
            .iter()
            .any(|attempt| {
                attempt.session_id.as_deref() == Some(session_id)
                    && attempt.tab_id.as_deref() == Some(tab_id)
            });
        if !matching_attempt
            && (run.session_id.as_deref() != Some(session_id)
                || run.tab_id.as_deref() != Some(tab_id))
        {
            return Err(HostError::state(
                "Automation attempt terminal identity changed",
            ));
        }
        if !self.sessions.contains_key(session_id) {
            let session = Session::restore_exited(
                session_id.into(),
                workspace_id.into(),
                tab_id.into(),
                &self.store,
                self.config.scrollback_bytes as usize,
            )
            .await
            .ok_or_else(|| HostError::state("No terminal output retained for this attempt"))?;
            self.sessions.insert(session_id.into(), session);
        }
        if self
            .sessions
            .get(session_id)
            .is_some_and(|s| s.workspace_id != workspace_id || s.tab_id != tab_id)
        {
            return Err(HostError::state("Terminal identity changed"));
        }
        self.flush_all_output(session_id).await;
        let session = self.sessions.get_mut(session_id).expect("restored session");
        session.attach(client_id);
        session.observer_clients.insert(client_id);
        let mut attachment =
            session.attachment_payload(false, self.config.restore_snapshot_bytes as usize);
        attachment["readOnly"] = json!(true);
        attachment["attachmentMode"] = json!("observe");
        Ok(attachment)
    }

    pub(super) async fn automation_take_over_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        let run_id = super::requests::require_string_key(payload, "runId")?;
        let actor = self
            .resolve_policy_actor(
                client_id,
                payload,
                self.automation_actor(client_id, payload),
            )
            .await?;
        let run = self
            .runtime_store
            .mark_automation_run_taken_over(&run_id, actor)
            .await
            .map_err(|e| HostError::state(e.to_string()))?;
        if let Some(session) = run
            .session_id
            .as_deref()
            .and_then(|id| self.sessions.get_mut(id))
        {
            session.observer_clients.remove(&client_id);
        }
        self.broadcast_workspace_tabs_changed(run.workspace_id.as_deref());
        self.automation_run_event(&run);
        Ok(
            json!({"run":run,"sessionId":run.session_id,"workspaceId":run.workspace_id,"tabId":run.tab_id}),
        )
    }
}
