//! The `runsChanged {revision}` event and the coordinator tick and hook
//! wrappers that announce run changes after they commit.

use serde_json::json;

use crate::terminal_host::protocol::event;

use super::ServerActor;

impl ServerActor {
    pub(super) async fn broadcast_orchestration_board_change(&mut self) {
        match self.runtime_store.take_orchestration_board_change().await {
            Ok(Some(revision)) => {
                // This method runs on the actor. Waking through its own inbox
                // can deadlock behind a full admission queue, so use the
                // existing busy/dirty coalescing state directly through the
                // actor-local command handler.
                self.wake_workflow_execution_command(
                    super::run_launch_requests::WorkflowLaunchCommand::ExecutionWake,
                );
                // Every authenticated client watches runs, phones included.
                self.broadcast_authenticated(event("runsChanged", json!({ "revision": revision })));
            }
            Ok(None) => {}
            Err(error) => tracing::warn!("could not read orchestration board revision: {error}"),
        }
    }

    fn wake_workflow_execution_command(
        &mut self,
        command: super::run_launch_requests::WorkflowLaunchCommand,
    ) {
        match command {
            super::run_launch_requests::WorkflowLaunchCommand::ExecutionWake => {
                self.wake_workflow_execution()
            }
            _ => unreachable!("only an execution wake belongs on the actor-local path"),
        }
    }

    pub(super) async fn handle_board_coordinator_tick(&mut self, run_id: String) {
        self.handle_coordinator_tick(run_id).await;
        self.broadcast_orchestration_board_change().await;
    }

    pub(super) async fn handle_board_agent_hook(
        &mut self,
        event: crate::agent_status::AgentHookEvent,
        relayed: bool,
    ) {
        self.handle_agent_hook_event(event, relayed).await;
        self.broadcast_orchestration_board_change().await;
    }
}
