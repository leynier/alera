//! Policy-driven handling of workers that stopped showing liveness.
//!
//! The runtime never auto-redispatches stalled work, because the worker may
//! still be alive and two agents in one worktree corrupt each other. Failover
//! is therefore always confirm and stop the old worker before recovery. A
//! workflow attempt stays retained and requires an explicit fresh attempt;
//! legacy tasks can return to ready. This module adds the confirmation step
//! and the two policies that skip or defer it.

use alera_core::runtime::{OrchestrationDispatchContext, OrchestrationTaskStatus};
use serde_json::Value;

use super::ServerActor;

/// What to do when a worker stops showing liveness.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum StallPolicy {
    /// Open a gate and wait for the user. The default under a policy.
    Ask,
    /// Stop the old worker and begin the appropriate recovery without asking.
    AutoFailover,
    /// Leave the task stalled for manual recovery. The historical behavior and
    /// the default for runs without a policy.
    Wait,
}

impl StallPolicy {
    fn parse(value: &str) -> Self {
        match value {
            "auto-failover" => StallPolicy::AutoFailover,
            "ask" => StallPolicy::Ask,
            _ => StallPolicy::Wait,
        }
    }
}

pub(super) const STALL_OPTION_FAILOVER: &str = "Kill And Failover";
pub(super) const STALL_OPTION_WAIT: &str = "Keep Waiting";
pub(super) const STALL_OPTION_ABORT: &str = "Abort Stage";

/// How much terminal output to attach to the gate question.
const STALL_DIAGNOSTIC_BYTES: usize = 2_000;

impl ServerActor {
    /// The stall policy for a run: `wait` unless an approved plan says
    /// otherwise, so a run without a policy behaves exactly as before.
    pub(super) async fn stall_policy_for_run(&mut self, run_id: Option<&str>) -> StallPolicy {
        let Some(run_id) = run_id else {
            return StallPolicy::Wait;
        };
        let Ok(Some(run)) = self
            .runtime_store
            .orchestration_coordinator_run_by_id(run_id)
            .await
        else {
            return StallPolicy::Wait;
        };
        if !matches!(
            run.execution_policy_status,
            alera_core::runtime::OrchestrationPolicyStatus::Approved
        ) {
            return StallPolicy::Wait;
        }
        run.execution_policy
            .as_deref()
            .and_then(|raw| serde_json::from_str::<Value>(raw).ok())
            .and_then(|policy| {
                policy
                    .get("stallPolicy")
                    .and_then(Value::as_str)
                    .map(StallPolicy::parse)
            })
            .unwrap_or(StallPolicy::Ask)
    }

    /// Applies the run's stall policy to a dispatch that just stalled.
    pub(super) async fn apply_stall_policy(&mut self, dispatch: &OrchestrationDispatchContext) {
        match self.stall_policy_for_run(dispatch.run_id.as_deref()).await {
            StallPolicy::Wait => {}
            StallPolicy::Ask => self.open_stall_gate(dispatch).await,
            StallPolicy::AutoFailover => {
                self.coordinator_log(&format!(
                    "auto-failover: interrupting stalled dispatch {}",
                    dispatch.id
                ));
                self.failover_stalled_dispatch(&dispatch.task_id).await;
            }
        }
    }

    async fn open_stall_gate(&mut self, dispatch: &OrchestrationDispatchContext) {
        let handle = dispatch.assignee_handle.as_deref().unwrap_or("<unknown>");
        let last_activity = dispatch
            .last_activity_at
            .as_deref()
            .or(dispatch.dispatched_at.as_deref())
            .unwrap_or("unknown");
        let profile = dispatch.agent_profile.as_deref().unwrap_or("<none>");
        let tail = self.terminal_output_tail(handle);
        let question = format!(
            "Worker {handle} (profile {profile}) has shown no activity since {last_activity}. \
             It may still be running, so Alera will not respawn without a decision.\n\n\
             Recent output:\n{tail}"
        );
        let options = vec![
            STALL_OPTION_FAILOVER.to_string(),
            STALL_OPTION_WAIT.to_string(),
            STALL_OPTION_ABORT.to_string(),
        ];
        match self
            .runtime_store
            .create_orchestration_stall_gate(&dispatch.task_id, &question, &options)
            .await
        {
            Ok(gate) => {
                self.coordinator_log(&format!(
                    "opened stall gate {} for task {}",
                    gate.id, dispatch.task_id
                ));
                self.queue_gate_push(&dispatch.task_id, &question).await;
            }
            Err(error) => self.coordinator_log(&format!(
                "could not open a stall gate for task {}: {error}",
                dispatch.task_id
            )),
        }
    }

    /// Acts on stall gates the user already resolved.
    pub(super) async fn coordinator_process_stall_decisions(&mut self) -> anyhow::Result<()> {
        let gates = self.runtime_store.resolved_stall_gates().await?;
        for gate in gates {
            let Some(resolution) = gate.resolution.as_deref() else {
                continue;
            };
            match resolution {
                STALL_OPTION_FAILOVER => {
                    self.coordinator_log(&format!(
                        "stall gate {} resolved: killing and failing over",
                        gate.id
                    ));
                    self.failover_stalled_dispatch(&gate.task_id).await;
                }
                STALL_OPTION_WAIT => {
                    self.coordinator_log(&format!(
                        "stall gate {} resolved: resuming the wait",
                        gate.id
                    ));
                    self.runtime_store
                        .resume_stalled_orchestration_dispatch(&gate.task_id)
                        .await?;
                }
                STALL_OPTION_ABORT => {
                    self.coordinator_log(&format!("stall gate {} resolved: aborting", gate.id));
                    let _ = self
                        .runtime_store
                        .cancel_orchestration_task(&gate.task_id, "stage aborted after a stall")
                        .await;
                }
                other => self.coordinator_log(&format!(
                    "stall gate {} has an unrecognized resolution: {other}",
                    gate.id
                )),
            }
        }
        Ok(())
    }

    /// A short tail of the worker's retained output, so the user can judge
    /// whether it is hung or just slow without opening the terminal.
    fn terminal_output_tail(&self, handle: &str) -> String {
        let Some(session) = self.sessions.get(handle) else {
            return "<terminal is gone>".to_string();
        };
        let snapshot = session.snapshot_payload();
        let Ok(bytes) =
            crate::terminal_host::protocol::decode_bytes(snapshot.get("snapshotBase64"))
        else {
            return "<output unavailable>".to_string();
        };
        let start = bytes.len().saturating_sub(STALL_DIAGNOSTIC_BYTES);
        String::from_utf8_lossy(&bytes[start..]).into_owned()
    }

    /// Sends the adapter's interrupt sequence. Best effort: a worker that
    /// already died leaves nothing to interrupt, which is fine.
    async fn interrupt_stalled_worker(&mut self, handle: &str) {
        let agent_type = self
            .agent_presence
            .agent_type(handle)
            .unwrap_or("codex")
            .to_string();
        let Some(adapter) =
            crate::terminal_host::orchestration::agent_registry::adapter_for(&agent_type)
        else {
            return;
        };
        if let Err(error) = self.queue_orchestration_control(handle, adapter.interrupt_bytes) {
            self.coordinator_log(&format!("could not interrupt worker {handle}: {error}"));
        }
    }

    /// Stops the old worker before recovery. Workflow attempts stay retained
    /// for an explicit retry, while legacy tasks return to ready.
    pub(super) async fn failover_stalled_dispatch(&mut self, task_id: &str) {
        let dispatch = match self
            .runtime_store
            .stalled_orchestration_dispatch_for_task(task_id)
            .await
        {
            Ok(Some(dispatch)) => dispatch,
            Ok(None) => {
                self.coordinator_log(&format!(
                    "could not fail over task {task_id}: no stalled dispatch remains"
                ));
                return;
            }
            Err(error) => {
                self.coordinator_log(&format!(
                    "could not inspect stalled task {task_id}: {error}"
                ));
                return;
            }
        };
        match self
            .settle_stalled_workflow_dispatch(
                &dispatch,
                "The stalled workflow worker was terminated. Inspect the retained attempt and retry explicitly in a new attempt.",
            )
            .await
        {
            Ok(true) => {
                self.coordinator_log(&format!(
                    "stalled workflow task {task_id} was retained for an explicit fresh attempt"
                ));
                return;
            }
            Ok(false) => {}
            Err(error) => {
                self.coordinator_log(&format!(
                    "could not settle stalled workflow task {task_id}: {error}"
                ));
                return;
            }
        }
        if let Some(handle) = dispatch.assignee_handle.as_deref() {
            self.interrupt_stalled_worker(handle).await;
        }
        if let Err(error) = self
            .runtime_store
            .recover_stalled_orchestration_task(
                task_id,
                OrchestrationTaskStatus::Ready,
                Some("coordinator"),
                "stall policy failover",
                true,
            )
            .await
        {
            self.coordinator_log(&format!(
                "could not return stalled task {task_id} to ready: {error}"
            ));
        }
    }
}
