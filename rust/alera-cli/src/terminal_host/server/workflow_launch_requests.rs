use std::fs::File;

use alera_core::runtime::{
    WorkflowLaunchInputs, WorkflowLaunchRecord, WorkflowLaunchStatus, WorkspaceTabRecord,
};
use serde_json::json;

use crate::managed_workspace::workflow::launch::PreparedLaunch;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_profile_launch_snapshot::{
    AgentInitialDeliveryMechanismV1, AgentInitialDeliveryReplayV1, AgentProfileLaunchSnapshotV1,
    AGENT_PROFILE_LAUNCH_SNAPSHOT_KEY,
};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::dispatch_preamble::build_dispatch_bootstrap;

use super::orchestration_profile_spawn::launch_for_profile;
use super::ServerActor;

#[cfg(test)]
mod tests;

pub(crate) enum WorkflowLaunchCommand {
    Prepared {
        client_id: u64,
        request_id: i64,
        result: HostResult<Box<PreparedLaunch>>,
    },
    Claimed {
        client_id: u64,
        request_id: i64,
        record: WorkflowLaunchRecord,
        token: String,
        locks: [File; 2],
        result: Box<HostResult<WorkflowLaunchInputs>>,
    },
    SpawnValidated(Box<ValidatedWorkflowLaunch>),
    AcceptanceTimeout(String),
}

/// Constructed only after the durable one-shot claim. No payload grants this.
pub(super) struct WorkflowLaunchPermit {
    record: WorkflowLaunchRecord,
}

pub(crate) struct ValidatedWorkflowLaunch {
    client_id: u64,
    request_id: i64,
    record: WorkflowLaunchRecord,
    token: String,
    locks: [File; 2],
    frozen: WorkflowLaunchInputs,
    result: HostResult<()>,
}

impl WorkflowLaunchPermit {
    pub(super) fn allows(&self, record: &WorkflowLaunchRecord, workspace: &str, tab: &str) -> bool {
        self.record.id == record.id
            && self.record.terminal_handle == record.terminal_handle
            && record.request.workspace_id == workspace
            && record.terminal_handle == tab
            && record.status == WorkflowLaunchStatus::Starting
    }
}

impl ServerActor {
    pub(super) async fn handle_workflow_launch_command(&mut self, command: WorkflowLaunchCommand) {
        match command {
            WorkflowLaunchCommand::Prepared {
                client_id,
                request_id,
                result,
            } => {
                self.handle_workflow_launch_prepared(client_id, request_id, result)
                    .await;
            }
            WorkflowLaunchCommand::Claimed {
                client_id,
                request_id,
                record,
                token,
                locks,
                result,
            } => {
                self.handle_workflow_launch_claimed(
                    client_id, request_id, record, token, locks, *result,
                )
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
        match result {
            Err(error) => {
                self.handle_workflow_workspace_finished(client_id, request_id, Err(error), true)
                    .await;
            }
            Ok(prepared) => match *prepared {
                PreparedLaunch::Replay(record) => {
                    self.handle_workflow_workspace_finished(
                        client_id,
                        request_id,
                        Ok(json!(record)),
                        true,
                    )
                    .await;
                }
                PreparedLaunch::Fresh {
                    record,
                    token,
                    locks,
                } => self.start_workflow_launch_claim(client_id, request_id, record, token, locks),
            },
        }
    }

    fn start_workflow_launch_claim(
        &self,
        client_id: u64,
        request_id: i64,
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
                    client_id,
                    request_id,
                    record,
                    token,
                    locks,
                    result: Box::new(result),
                },
            ));
        });
    }

    async fn handle_workflow_launch_claimed(
        &mut self,
        client_id: u64,
        request_id: i64,
        record: WorkflowLaunchRecord,
        token: String,
        locks: [File; 2],
        result: HostResult<WorkflowLaunchInputs>,
    ) {
        match result {
            Ok(frozen) => self.start_workflow_launch_spawn_validation(
                client_id, request_id, record, token, locks, frozen,
            ),
            Err(error) => {
                self.finish_workflow_launch(client_id, request_id, record, locks, Err(error))
                    .await;
            }
        }
    }

    fn start_workflow_launch_spawn_validation(
        &self,
        client_id: u64,
        request_id: i64,
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
                    client_id,
                    request_id,
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
        self.finish_workflow_launch(
            validated.client_id,
            validated.request_id,
            validated.record,
            validated.locks,
            result,
        )
        .await;
    }

    async fn finish_workflow_launch(
        &mut self,
        client_id: u64,
        request_id: i64,
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
        self.handle_workflow_workspace_finished(client_id, request_id, result, true)
            .await;
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
            record: record.clone(),
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
