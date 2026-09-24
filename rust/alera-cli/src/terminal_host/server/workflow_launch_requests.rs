use std::fs::File;

use alera_core::runtime::{WorkflowLaunchInputs, WorkflowLaunchRecord, WorkspaceTabRecord};
use serde_json::json;

use crate::managed_workspace::workflow::launch::PreparedLaunch;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::{
    AgentInitialDeliveryMechanismV1, AgentInitialDeliveryReplayV1, AgentProfileLaunchSnapshotV1,
    AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY,
};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::dispatch_preamble::build_dispatch_bootstrap;
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::orchestration_profile_spawn::launch_for_profile;
use super::ServerActor;

#[path = "workflow_cancellation_requests.rs"]
mod cancellation;
pub(crate) use cancellation::CancellationShutdown;
#[path = "workflow_cleanup_owners.rs"]
mod cleanup_owners;
#[path = "workflow_execution_pump.rs"]
pub(super) mod execution;
#[path = "workflow_launch_permit.rs"]
mod permit;

pub(crate) enum WorkflowLaunchReply {
    Client(u64, i64),
    Execution(tokio::sync::oneshot::Sender<HostResult<serde_json::Value>>),
}

#[cfg(test)]
mod tests;

pub(crate) enum WorkflowLaunchCommand {
    InspectCleanupOwners {
        cleanup_id: String,
        digest: String,
        workspace_id: String,
        reply: tokio::sync::oneshot::Sender<HostResult<()>>,
    },
    CancellationFinished(HostResult<bool>),
    RetainCancellationShutdown {
        tab: String,
        shutdown: WorkspaceShutdown,
        reply: tokio::sync::oneshot::Sender<()>,
    },
    CancelProposalTerminal {
        target: alera_core::runtime::WorkflowProposalCancellation,
        reply: tokio::sync::oneshot::Sender<HostResult<CancellationShutdown>>,
    },
    CancelTerminal {
        target: alera_core::runtime::WorkflowCancellationTarget,
        reply: tokio::sync::oneshot::Sender<HostResult<CancellationShutdown>>,
    },
    ExecutionWake,
    ExecutionFinished(execution::ExecutionPass),
    CoordinatorPrepared {
        client_id: u64,
        request_id: i64,
        result: HostResult<Box<alera_core::runtime::WorkflowProposalDraft>>,
    },
    Prepared {
        client_id: u64,
        request_id: i64,
        result: HostResult<Box<PreparedLaunch>>,
    },
    ExecutionPrepared {
        reply: tokio::sync::oneshot::Sender<HostResult<serde_json::Value>>,
        result: HostResult<Box<PreparedLaunch>>,
    },
    Claimed {
        reply: WorkflowLaunchReply,
        record: Box<WorkflowLaunchRecord>,
        token: String,
        locks: [File; 2],
        result: Box<HostResult<WorkflowLaunchInputs>>,
    },
    SpawnValidated(Box<ValidatedWorkflowLaunch>),
    AcceptanceTimeout(String),
}

/// Constructed only after the durable one-shot claim. No payload grants this.
pub(super) struct WorkflowLaunchPermit {
    record: Option<WorkflowLaunchRecord>,
    coordinator: Option<alera_core::runtime::WorkflowCoordinatorReceipt>,
}

pub(crate) struct ValidatedWorkflowLaunch {
    reply: WorkflowLaunchReply,
    record: WorkflowLaunchRecord,
    token: String,
    locks: [File; 2],
    frozen: WorkflowLaunchInputs,
    result: HostResult<()>,
}

impl ServerActor {
    pub(super) async fn handle_workflow_launch_command(&mut self, command: WorkflowLaunchCommand) {
        match command {
            WorkflowLaunchCommand::InspectCleanupOwners {
                cleanup_id,
                digest,
                workspace_id,
                reply,
            } => {
                let result = self
                    .inspect_workflow_cleanup_owners(&cleanup_id, &digest, &workspace_id)
                    .await;
                let _ = reply.send(result);
            }
            WorkflowLaunchCommand::CancelProposalTerminal { target, reply } => {
                let result = self.cancel_workflow_proposal_terminal(&target).await;
                let _ = reply.send(result);
            }
            WorkflowLaunchCommand::RetainCancellationShutdown {
                tab,
                shutdown,
                reply,
            } => {
                self.retain_cancellation_shutdown(tab, shutdown);
                let _ = reply.send(());
            }
            WorkflowLaunchCommand::CancellationFinished(result) => {
                self.finish_workflow_cancellation(result).await
            }
            WorkflowLaunchCommand::CancelTerminal { target, reply } => {
                let result = self.cancel_workflow_terminal(&target).await;
                let _ = reply.send(result);
            }
            WorkflowLaunchCommand::ExecutionWake => self.wake_workflow_execution(),
            WorkflowLaunchCommand::ExecutionFinished(pass) => {
                self.finish_workflow_execution_pass(pass).await
            }
            WorkflowLaunchCommand::CoordinatorPrepared {
                client_id,
                request_id,
                result,
            } => {
                self.handle_workflow_coordinator_prepared(client_id, request_id, result)
                    .await;
            }
            WorkflowLaunchCommand::Prepared {
                client_id,
                request_id,
                result,
            } => {
                self.handle_workflow_launch_prepared(client_id, request_id, result)
                    .await;
            }
            WorkflowLaunchCommand::Claimed {
                reply,
                record,
                token,
                locks,
                result,
            } => {
                self.handle_workflow_launch_claimed(reply, *record, token, locks, *result)
                    .await;
            }
            WorkflowLaunchCommand::ExecutionPrepared { reply, result } => {
                self.managed_workspace_jobs += 1;
                self.cancel_shutdown_timer();
                self.launch_prepared_for(WorkflowLaunchReply::Execution(reply), result)
                    .await;
            }
            WorkflowLaunchCommand::SpawnValidated(validated) => {
                self.handle_workflow_launch_spawn_validated(*validated)
                    .await;
            }
            WorkflowLaunchCommand::AcceptanceTimeout(id) => {
                self.handle_workflow_launch_acceptance_timeout(&id).await
            }
        }
    }
    pub(super) async fn handle_workflow_launch_prepared(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Box<PreparedLaunch>>,
    ) {
        self.launch_prepared_for(WorkflowLaunchReply::Client(client_id, request_id), result)
            .await;
    }

    async fn launch_prepared_for(
        &mut self,
        reply: WorkflowLaunchReply,
        result: HostResult<Box<PreparedLaunch>>,
    ) {
        match result {
            Err(error) => {
                self.reply_workflow_launch(reply, Err(error)).await;
            }
            Ok(prepared) => match *prepared {
                PreparedLaunch::Replay(record) => {
                    self.reply_workflow_launch(reply, Ok(json!(record))).await;
                }
                PreparedLaunch::Fresh {
                    record,
                    token,
                    locks,
                } => self.start_workflow_launch_claim(reply, record, token, locks),
            },
        }
    }

    fn start_workflow_launch_claim(
        &self,
        reply: WorkflowLaunchReply,
        record: WorkflowLaunchRecord,
        token: String,
        locks: [File; 2],
    ) {
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        let validation_record = record.clone();
        tokio::spawn(async move {
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(
                    crate::managed_workspace::workflow::launch::claim_and_validate(
                        &store,
                        &validation_record,
                    ),
                )
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))
            .and_then(|result| result.map_err(|error| HostError::state(error.to_string())));
            let _ = inbox.send(super::ServerCommand::WorkflowLaunch(
                WorkflowLaunchCommand::Claimed {
                    reply,
                    record: Box::new(record),
                    token,
                    locks,
                    result: Box::new(result),
                },
            ));
        });
    }

    async fn handle_workflow_launch_claimed(
        &mut self,
        reply: WorkflowLaunchReply,
        record: WorkflowLaunchRecord,
        token: String,
        locks: [File; 2],
        result: HostResult<WorkflowLaunchInputs>,
    ) {
        match result {
            Ok(frozen) => {
                self.start_workflow_launch_spawn_validation(reply, record, token, locks, frozen)
            }
            Err(error) => {
                self.finish_workflow_launch(reply, record, locks, Err(error))
                    .await;
            }
        }
    }

    fn start_workflow_launch_spawn_validation(
        &self,
        reply: WorkflowLaunchReply,
        record: WorkflowLaunchRecord,
        token: String,
        locks: [File; 2],
        frozen: WorkflowLaunchInputs,
    ) {
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let runtime = tokio::runtime::Handle::current();
        let validation_record = record.clone();
        tokio::spawn(async move {
            let result = tokio::task::spawn_blocking(move || {
                runtime.block_on(
                    crate::managed_workspace::workflow::launch::revalidate_at_spawn_boundary(
                        &store,
                        &validation_record,
                    ),
                )
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))
            .and_then(|result| result.map_err(|error| HostError::state(error.to_string())));
            let _ = inbox.send(super::ServerCommand::WorkflowLaunch(
                WorkflowLaunchCommand::SpawnValidated(Box::new(ValidatedWorkflowLaunch {
                    reply,
                    record,
                    token,
                    locks,
                    frozen,
                    result,
                })),
            ));
        });
    }

    async fn handle_workflow_launch_spawn_validated(&mut self, validated: ValidatedWorkflowLaunch) {
        let result = match validated.result {
            Ok(()) => {
                self.spawn_workflow_launch(&validated.record, &validated.token, validated.frozen)
                    .await
            }
            Err(error) => Err(error),
        };
        self.finish_workflow_launch(validated.reply, validated.record, validated.locks, result)
            .await;
    }

    async fn finish_workflow_launch(
        &mut self,
        reply: WorkflowLaunchReply,
        record: WorkflowLaunchRecord,
        locks: [File; 2],
        result: HostResult<WorkflowLaunchRecord>,
    ) {
        // Process teardown and durable settlement finish before releasing the fences.
        let result = match result {
            Ok(record) => Ok(json!(record)),
            Err(error) => {
                self.terminate_sessions_for_tab(&record.terminal_handle)
                    .await;
                self.remove_dispatch_context(&record.terminal_handle);
                self.settle_closed_workflow_terminal(
                    &record.terminal_handle,
                    &error.wire_message(),
                )
                .await;
                let result = self
                    .runtime_store
                    .workflow_launch_attention(&record.id, &error.wire_message())
                    .await
                    .map(|record| json!(record))
                    .map_err(|error| HostError::state(error.to_string()));
                if self
                    .runtime_store
                    .find_workspace_tab(&record.terminal_handle)
                    .await
                    .is_ok_and(|tab| tab.is_some())
                {
                    self.broadcast_workspace_tabs_changed(Some(&record.request.workspace_id));
                }
                result
            }
        };
        drop(locks);
        self.reply_workflow_launch(reply, result).await;
    }

    async fn reply_workflow_launch(
        &mut self,
        reply: WorkflowLaunchReply,
        result: HostResult<serde_json::Value>,
    ) {
        match reply {
            WorkflowLaunchReply::Client(client, request) => {
                self.handle_workflow_workspace_finished(client, request, result, true)
                    .await
            }
            WorkflowLaunchReply::Execution(reply) => {
                self.managed_workspace_jobs = self.managed_workspace_jobs.saturating_sub(1);
                self.broadcast_workspaces_changed(None);
                self.broadcast_orchestration_board_change().await;
                let _ = reply.send(result);
                self.schedule_shutdown_if_idle();
            }
        }
    }

    async fn spawn_workflow_launch(
        &mut self,
        record: &WorkflowLaunchRecord,
        token: &str,
        frozen: WorkflowLaunchInputs,
    ) -> HostResult<WorkflowLaunchRecord> {
        self.runtime_store
            .require_workflow_launch_spawnable(&record.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let profile = &frozen.profile;
        let adapter = adapter_for(&profile.agent_type)
            .ok_or_else(|| HostError::state("frozen workflow adapter is unavailable"))?;
        let (command, managed) = launch_for_profile(profile).map_err(HostError::format)?;
        let snapshot = AgentProfileLaunchSnapshotV1::new(
            profile,
            adapter,
            command,
            managed,
            AgentInitialDeliveryReplayV1::Once,
        )
        .map_err(HostError::format)?;
        let after_ready = snapshot.initial_delivery.mechanism
            == AgentInitialDeliveryMechanismV1::TerminalAfterReady;
        let bootstrap = build_dispatch_bootstrap();
        let now = chrono::Utc::now();
        let mut payload = json!({
            "terminalSessionId": record.terminal_handle,
            "spawnOnCreate": true,
            "initialPrompt": (!after_ready).then(|| bootstrap.clone()),
            "pendingAgentPrompt": after_ready.then(|| json!({"agent": adapter.agent_type,"prompt": bootstrap})),
        });
        payload[AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY] =
            serde_json::to_value(snapshot).map_err(|error| HostError::state(error.to_string()))?;
        let mut tab = WorkspaceTabRecord {
            id: record.terminal_handle.clone(),
            workspace_id: record.request.workspace_id.clone(),
            kind: "terminal".into(),
            title: frozen.task.task.title.clone(),
            created_at: now,
            updated_at: now,
            payload,
        };
        super::agent_title_state::initialize(&mut tab, &frozen.task.task.title);
        self.install_dispatch_context(&record.terminal_handle, &record.dispatch_id, token)?;
        let tab = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let permit = WorkflowLaunchPermit {
            record: Some(record.clone()),
            coordinator: None,
        };
        self.ensure_spawn_on_create_terminal_with_permit(&tab, Some(&permit))
            .await?;
        self.broadcast_workspace_tabs_changed(Some(&record.request.workspace_id));
        let started = self
            .runtime_store
            .mark_workflow_launch_started(&record.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.schedule_workflow_launch_acceptance_timeout(&record.id);
        Ok(started)
    }

    pub(super) async fn require_workflow_spawn_permit(
        &self,
        session: &str,
        workspace: &str,
        tab: &str,
        permit: Option<&WorkflowLaunchPermit>,
    ) -> HostResult<()> {
        for terminal in [session, tab] {
            if let Some(record) = self
                .runtime_store
                .workflow_coordinator_for_terminal(terminal)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
            {
                if record.tab_id != session
                    || record.tab_id != tab
                    || record.workspace_id != workspace
                    || !permit
                        .and_then(|p| p.coordinator.as_ref())
                        .is_some_and(|p| {
                            p.proposal_id == record.proposal_id
                                && p.tab_id == tab
                                && p.workspace_id == workspace
                        })
                {
                    return Err(HostError::state(
                        "workflow coordinators cannot restart; inspect the retained proposal",
                    ));
                }
                self.runtime_store
                    .require_workflow_coordinator_spawnable(tab)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
            }
        }
        let by_session = self
            .runtime_store
            .workflow_launch_for_terminal(session)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let by_tab = self
            .runtime_store
            .workflow_launch_for_terminal(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        for record in by_session.iter().chain(by_tab.iter()) {
            if record.terminal_handle != session
                || !permit.is_some_and(|permit| permit.allows(record, workspace, tab))
            {
                return Err(HostError::state("workflow workers require a fresh approved attempt; automatic restart is disabled"));
            }
            self.runtime_store
                .require_workflow_launch_spawnable(&record.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
        }
        Ok(())
    }
}
