//! Relaunches an automation conversation in a copy of an earlier tab: the
//! same workspace and agent, resumed through the agent's native session when
//! one is known and started with the prompt otherwise. Recovery after a
//! restart and conversation reuse both go through here.

use alera_core::runtime::{AutomationRun, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};

use super::terminal_startup_commands::{
    agent_profile_id, initial_delivery_mechanism, tab_agent_type,
};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::AgentInitialDeliveryMechanismV1;

pub(super) struct AutomationTabRelaunch<'a> {
    pub prompt: &'a str,
    pub native_session_id: Option<String>,
    pub launch_kind: &'a str,
}

impl ServerActor {
    /// Clones `source` into a new automation-owned tab bound to the run's
    /// current attempt, saves the run, and spawns the tab. The caller decides
    /// what happens to `source`; it is never relaunched in place.
    pub(super) async fn relaunch_automation_tab(
        &mut self,
        source: &WorkspaceTabRecord,
        run: &mut AutomationRun,
        relaunch: AutomationTabRelaunch<'_>,
    ) -> HostResult<WorkspaceTabRecord> {
        let mut tab = source.clone();
        let agent = tab_agent_type(&tab).unwrap_or("").to_string();
        match relaunch.native_session_id.as_deref() {
            Some(native) => {
                tab.payload["agentNativeSessionId"] = json!(native);
                tab.payload["pendingAgentPrompt"] =
                    json!({"agent": agent, "prompt": relaunch.prompt});
            }
            None => {
                tab.payload["agentNativeSessionId"] = Value::Null;
                tab.payload["initialPrompt"] = json!(relaunch.prompt);
                tab.payload["initialPromptOnce"] = json!(false);
                if initial_delivery_mechanism(&tab)
                    .ok()
                    .flatten()
                    .is_some_and(|mechanism| {
                        matches!(
                            mechanism,
                            AgentInitialDeliveryMechanismV1::TerminalAfterReady
                        )
                    })
                {
                    tab.payload["pendingAgentPrompt"] =
                        json!({"agent": agent, "prompt": relaunch.prompt});
                }
            }
        }
        tab.id = uuid::Uuid::new_v4().to_string();
        tab.created_at = Utc::now();
        tab.updated_at = tab.created_at;
        tab.payload["terminalSessionId"] = json!(tab.id);
        tab.payload["conversationId"] = json!(uuid::Uuid::new_v4().to_string());
        tab.payload["spawnOnCreate"] = json!(true);
        tab.payload["automationOwned"] = json!(true);
        tab.payload["automationRunId"] = json!(run.id);
        tab.payload["automationAttemptId"] = json!(run.attempt_id);
        if let Some(object) = tab.payload.as_object_mut() {
            object.remove("automationTakenOver");
        }
        run.workspace_id = Some(tab.workspace_id.clone());
        run.tab_id = Some(tab.id.clone());
        run.session_id = Some(tab.id.clone());
        run.owned_tab = true;
        if let Some(identity) = run.target_identity.as_mut() {
            identity.workspace_id = Some(tab.workspace_id.clone());
            identity.tab_id = Some(tab.id.clone());
            identity.session_id = Some(tab.id.clone());
            identity.terminal_handle = Some(tab.id.clone());
            identity.conversation_id = tab.payload["conversationId"].as_str().map(str::to_string);
            if let Some(profile) = agent_profile_id(&tab) {
                identity.profile_id = Some(profile.to_string());
            }
        }
        let _ = self
            .runtime_store
            .bind_automation_attempt(run, relaunch.launch_kind)
            .await;
        let _ = self.runtime_store.save_automation_run(run).await;
        self.runtime_store
            .upsert_workspace_tab(tab.clone())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Box::pin(self.ensure_spawn_on_create_terminal(&tab)).await?;
        self.broadcast_workspace_tabs_changed(Some(&tab.workspace_id));
        Ok(tab)
    }
}
