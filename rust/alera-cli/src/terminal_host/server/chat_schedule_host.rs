//! The host side of scheduled tasks (`chatOrchestrationSchedulesV1`): the
//! chat orchestration service asks the actor, through its inbox, to save,
//! trash or run an agent chat automation, so readiness, the scheduler wake
//! and the broadcasts stay where every other automation change happens.

use alera_core::runtime::{AutomationDefinition, AutomationState};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::oneshot;

use super::automation_agent_chat_runs::AgentChatRunEvent;
use super::chat_orchestration::{ScheduleHost, ScheduleOp};
use super::{ServerActor, ServerCommand, ServerInbox};
use crate::terminal_host::host_error::{HostError, HostResult};

/// No client sends these requests; the actor resolves no client from it.
const NO_CLIENT: u64 = u64::MAX;

pub(crate) struct InboxScheduleHost {
    inbox: ServerInbox,
}

impl InboxScheduleHost {
    pub(crate) fn new(inbox: ServerInbox) -> Self {
        Self { inbox }
    }
}

#[async_trait]
impl ScheduleHost for InboxScheduleHost {
    async fn apply(&self, op: ScheduleOp) -> HostResult<Value> {
        let (reply, answer) = oneshot::channel();
        self.inbox
            .send_wait(ServerCommand::AutomationAgentChat(
                AgentChatRunEvent::Schedule { op, reply },
            ))
            .await
            .map_err(|_| HostError::state("The runtime is shutting down."))?;
        answer
            .await
            .unwrap_or_else(|_| Err(HostError::state("The runtime is shutting down.")))
    }
}

impl ServerActor {
    pub(super) async fn apply_schedule_op(&mut self, op: ScheduleOp) -> HostResult<Value> {
        match op {
            ScheduleOp::Save {
                definition,
                state,
                actor,
            } => self.save_scheduled_task(*definition, state, actor).await,
            ScheduleOp::Trash { id, actor } => {
                self.automation_state_request(
                    NO_CLIENT,
                    &json!({"id": id, "reason": "Deleted from an agent chat"}),
                    actor,
                    AutomationState::Trashed,
                )
                .await
            }
            ScheduleOp::RunNow { id, actor } => {
                self.run_automation_now(NO_CLIENT, &json!({"id": id}), actor)
                    .await
            }
        }
    }

    async fn save_scheduled_task(
        &mut self,
        mut definition: AutomationDefinition,
        state: Option<AutomationState>,
        actor: alera_core::runtime::AutomationActor,
    ) -> HostResult<Value> {
        let existing = self
            .runtime_store
            .find_automation(&definition.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if let Some(existing) = &existing {
            definition.state = state.unwrap_or(existing.state);
        }
        if definition.target.agent_chat().is_none() {
            return Err(HostError::state(
                "A scheduled task needs an agent chat target",
            ));
        }
        if definition.state == AutomationState::Active {
            let readiness = self.automation_readiness(&definition, true).await;
            if readiness["ready"] != true {
                let reason = readiness["issues"]
                    .as_array()
                    .and_then(|issues| issues.first())
                    .and_then(|issue| issue["message"].as_str())
                    .unwrap_or("The scheduled task is not ready")
                    .to_owned();
                return Err(HostError::conflict("automationNotReady", reason, readiness));
            }
        }
        let saved = self
            .runtime_store
            .upsert_automation(definition.clone(), actor.clone())
            .await
            .map_err(|error| HostError::format(error.to_string()))?;
        self.automations_active = self
            .runtime_store
            .has_pending_automation_work()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automation_wake.notify_one();
        self.broadcast_automation_changed(Some(&saved.id));
        if existing.is_some() && definition.state != saved.state {
            // The store keeps a saved definition's state; a change goes
            // through the state request, which keeps active runs going.
            return self
                .automation_state_request(
                    NO_CLIENT,
                    &json!({"id": saved.id, "activeRuns": "continue-active"}),
                    actor,
                    definition.state,
                )
                .await;
        }
        serde_json::to_value(saved).map_err(|error| HostError::state(error.to_string()))
    }
}
