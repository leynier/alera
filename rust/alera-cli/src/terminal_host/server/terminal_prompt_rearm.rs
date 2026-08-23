use alera_core::runtime::WorkspaceTabRecord;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::AgentInitialDeliveryMechanismV1;

use super::terminal_startup_commands::{
    initial_delivery_mechanism, initial_prompt, replays_initial_prompt_on_restart, tab_agent_type,
};
use super::ServerActor;

impl ServerActor {
    pub(super) async fn rearm_terminal_after_ready_prompt(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> HostResult<Option<WorkspaceTabRecord>> {
        if !replays_initial_prompt_on_restart(tab)?
            || initial_delivery_mechanism(tab)?
                != Some(AgentInitialDeliveryMechanismV1::TerminalAfterReady)
            || tab
                .payload
                .get("pendingAgentPrompt")
                .is_some_and(|value| !value.is_null())
        {
            return Ok(None);
        }
        let Some(prompt) = initial_prompt(tab) else {
            return Ok(None);
        };
        let Some(agent_type) = tab_agent_type(tab) else {
            return Ok(None);
        };

        let mut next = tab.clone();
        let Some(payload) = next.payload.as_object_mut() else {
            return Ok(None);
        };
        payload.insert(
            "pendingAgentPrompt".to_string(),
            serde_json::json!({"agent": agent_type, "prompt": prompt}),
        );
        next.updated_at = chrono::Utc::now();
        self.runtime_store
            .upsert_workspace_tab(next)
            .await
            .map(Some)
            .map_err(|error| HostError::state(error.to_string()))
    }
}
