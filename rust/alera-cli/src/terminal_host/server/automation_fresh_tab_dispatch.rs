use super::super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::AutomationRun;
use chrono::Utc;
use serde_json::{json, Value};

impl ServerActor {
    pub(super) async fn dispatch_fresh_tab(
        &mut self,
        run: &mut AutomationRun,
        workspace_id: &str,
        profile_id: &str,
        prompt: &str,
        owned_workspace: bool,
    ) -> HostResult<()> {
        let response = Box::pin(self.launch_agent_profile(
            None,
            &json!({
                "workspaceId": workspace_id,
                "profileId": profile_id,
                "prompt": prompt,
                "automationRunId": run.id,
                "automationAttemptId": run.attempt_id,
                "automationOwned": true,
            }),
        ))
        .await?;
        let tab = response
            .get("tab")
            .ok_or_else(|| HostError::state("agent profile launch returned no tab"))?;
        let tab_id = tab
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::state("agent profile launch returned no tab id"))?;
        let session_id = tab
            .get("payload")
            .and_then(|value| value.get("terminalSessionId"))
            .and_then(Value::as_str)
            .unwrap_or(tab_id)
            .to_string();
        if let Ok(Some(mut record)) = self.runtime_store.find_workspace_tab(tab_id).await {
            record.payload["automationRunId"] = Value::String(run.id.clone());
            record.payload["automationOwned"] = Value::Bool(true);
            record.payload["automationAttemptId"] = json!(run.attempt_id);
            record.updated_at = Utc::now();
            let _ = self.runtime_store.upsert_workspace_tab(record).await;
        }
        run.workspace_id = Some(workspace_id.to_string());
        run.tab_id = Some(tab_id.to_string());
        run.session_id = Some(session_id);
        run.owned_tab = true;
        run.owned_workspace = owned_workspace;
        Ok(())
    }
}
