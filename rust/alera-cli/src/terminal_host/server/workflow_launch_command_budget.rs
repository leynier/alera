use alera_core::runtime::{WorkflowCancellationTarget, WorkflowProposalCancellation};

use super::{PreparedLaunch, ValidatedWorkflowLaunch, WorkflowLaunchCommand};
use crate::terminal_host::host_error::{HostError, HostResult};

const COMPLETION_BYTES: usize =
    crate::terminal_host::server::server_command_inbox::SERVER_COMMAND_COMPLETION_BYTES;

pub(crate) fn is_completion(command: &WorkflowLaunchCommand) -> bool {
    matches!(
        command,
        WorkflowLaunchCommand::CancellationFinished(_)
            | WorkflowLaunchCommand::ExecutionFinished(_)
            | WorkflowLaunchCommand::CoordinatorPrepared { .. }
            | WorkflowLaunchCommand::Prepared { .. }
            | WorkflowLaunchCommand::ExecutionPrepared { .. }
            | WorkflowLaunchCommand::Claimed { .. }
            | WorkflowLaunchCommand::SpawnValidated(_)
            | WorkflowLaunchCommand::AcceptanceTimeout(_)
    )
}

pub(crate) fn command_bytes(command: &WorkflowLaunchCommand) -> usize {
    let bytes = match command {
        WorkflowLaunchCommand::InspectCleanupOwners {
            cleanup_id,
            digest,
            workspace_id,
            ..
        } => string_bytes(cleanup_id) + string_bytes(digest) + string_bytes(workspace_id),
        WorkflowLaunchCommand::CancellationFinished(result) => host_result_bool_bytes(result),
        WorkflowLaunchCommand::RetainCancellationShutdown { tab, shutdown, .. } => {
            string_bytes(tab) + workspace_shutdown_bytes(shutdown)
        }
        WorkflowLaunchCommand::CancelProposalTerminal { target, .. } => {
            proposal_cancellation_bytes(target)
        }
        WorkflowLaunchCommand::CancelTerminal { target, .. } => cancellation_target_bytes(target),
        WorkflowLaunchCommand::ExecutionWake => 1,
        WorkflowLaunchCommand::ExecutionFinished(pass) => {
            pass.cursor.as_deref().map(string_bytes).unwrap_or_default()
                + pass.error.as_deref().map(string_bytes).unwrap_or_default()
                + 3
        }
        WorkflowLaunchCommand::CoordinatorPrepared { result, .. } => {
            host_result_serialized_bytes(result)
        }
        WorkflowLaunchCommand::Prepared { result, .. }
        | WorkflowLaunchCommand::ExecutionPrepared { result, .. } => prepared_result_bytes(result),
        WorkflowLaunchCommand::Claimed {
            record,
            token,
            result,
            ..
        } => serialized_bytes(record) + string_bytes(token) + host_result_serialized_bytes(result),
        WorkflowLaunchCommand::SpawnValidated(validated) => validated_bytes(validated),
        WorkflowLaunchCommand::AcceptanceTimeout(id) => string_bytes(id),
    };
    bytes.max(1)
}

pub(crate) fn bound(command: &mut WorkflowLaunchCommand) {
    if command_bytes(command) <= COMPLETION_BYTES {
        return;
    }
    let error = || HostError::state("Workflow response exceeds the 16 MiB command inbox budget");
    if matches!(
        command,
        WorkflowLaunchCommand::Prepared { .. } | WorkflowLaunchCommand::ExecutionPrepared { .. }
    ) {
        bound_prepared(command, error());
        return;
    }
    match command {
        WorkflowLaunchCommand::CancellationFinished(result) => *result = Err(error()),
        WorkflowLaunchCommand::CoordinatorPrepared { result, .. } => *result = Err(error()),
        WorkflowLaunchCommand::Claimed {
            record,
            token,
            result,
            ..
        } => {
            **result = Err(error());
            minimize_record(record);
            token.clear();
        }
        WorkflowLaunchCommand::SpawnValidated(validated) => {
            validated.result = Err(error());
            minimize_record(&mut validated.record);
            validated.token.clear();
            minimize_inputs(&mut validated.frozen);
        }
        WorkflowLaunchCommand::ExecutionFinished(pass) => {
            pass.cursor = None;
            pass.again = false;
            pass.changed = false;
            pass.error = Some(error().wire_message());
        }
        _ => {}
    }
}

fn bound_prepared(command: &mut WorkflowLaunchCommand, error: HostError) {
    let original = std::mem::replace(command, WorkflowLaunchCommand::ExecutionWake);
    match original {
        WorkflowLaunchCommand::Prepared {
            client_id,
            request_id,
            result,
        } => match result {
            Ok(prepared) => match *prepared {
                PreparedLaunch::Fresh {
                    record,
                    token,
                    locks,
                } => {
                    *command = WorkflowLaunchCommand::Claimed {
                        reply: super::WorkflowLaunchReply::Client(client_id, request_id),
                        record: Box::new(record),
                        token,
                        locks,
                        result: Box::new(Err(error)),
                    };
                }
                PreparedLaunch::Replay(_) => {
                    *command = WorkflowLaunchCommand::Prepared {
                        client_id,
                        request_id,
                        result: Err(error),
                    };
                }
            },
            Err(_) => {
                *command = WorkflowLaunchCommand::Prepared {
                    client_id,
                    request_id,
                    result: Err(error),
                };
            }
        },
        WorkflowLaunchCommand::ExecutionPrepared { reply, result } => match result {
            Ok(prepared) => match *prepared {
                PreparedLaunch::Fresh {
                    record,
                    token,
                    locks,
                } => {
                    *command = WorkflowLaunchCommand::Claimed {
                        reply: super::WorkflowLaunchReply::Execution(reply),
                        record: Box::new(record),
                        token,
                        locks,
                        result: Box::new(Err(error)),
                    };
                }
                PreparedLaunch::Replay(_) => {
                    *command = WorkflowLaunchCommand::ExecutionPrepared {
                        reply,
                        result: Err(error),
                    };
                }
            },
            Err(_) => {
                *command = WorkflowLaunchCommand::ExecutionPrepared {
                    reply,
                    result: Err(error),
                };
            }
        },
        _ => unreachable!("prepared command was checked before replacement"),
    }
}

fn prepared_result_bytes(result: &HostResult<Box<PreparedLaunch>>) -> usize {
    match result {
        Ok(prepared) => prepared_bytes(prepared),
        Err(error) => string_bytes(&error.wire_message()),
    }
}

fn prepared_bytes(prepared: &PreparedLaunch) -> usize {
    match prepared {
        PreparedLaunch::Replay(record) => serialized_bytes(record),
        PreparedLaunch::Fresh { record, token, .. } => {
            serialized_bytes(record) + string_bytes(token)
        }
    }
}

fn validated_bytes(validated: &ValidatedWorkflowLaunch) -> usize {
    serialized_bytes(&validated.record)
        + string_bytes(&validated.token)
        + serialized_bytes(&validated.frozen)
        + host_result_unit_bytes(&validated.result)
}

fn cancellation_target_bytes(target: &WorkflowCancellationTarget) -> usize {
    string_bytes(target.launch_id.as_deref().unwrap_or_default())
        + string_bytes(target.proposal_id.as_deref().unwrap_or_default())
        + string_bytes(&target.run_id)
        + string_bytes(&target.terminal_handle)
        + string_bytes(&target.workspace_id)
}

fn proposal_cancellation_bytes(target: &WorkflowProposalCancellation) -> usize {
    string_bytes(&target.proposal_id)
        + string_bytes(target.tab_id.as_deref().unwrap_or_default())
        + string_bytes(&target.workspace_id)
        + string_bytes(&target.status)
        + string_bytes(target.error.as_deref().unwrap_or_default())
        + std::mem::size_of_val(&target.sequence)
}

fn workspace_shutdown_bytes(
    shutdown: &crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown,
) -> usize {
    std::mem::size_of_val(shutdown)
        + shutdown
            .closed_tab_ids
            .iter()
            .map(|tab| string_bytes(tab))
            .sum::<usize>()
}

fn serialized_bytes<T: serde::Serialize>(value: &T) -> usize {
    super::super::server_command_payload_size::serialized_bytes(value, COMPLETION_BYTES)
}

fn host_result_serialized_bytes<T: serde::Serialize>(result: &HostResult<T>) -> usize {
    match result {
        Ok(value) => serialized_bytes(value),
        Err(error) => string_bytes(&error.wire_message()),
    }
}

fn host_result_bool_bytes(result: &HostResult<bool>) -> usize {
    host_result_serialized_bytes(result)
}

fn host_result_unit_bytes(result: &HostResult<()>) -> usize {
    host_result_serialized_bytes(result)
}

fn string_bytes(value: &str) -> usize {
    value.len().saturating_add(1)
}

fn minimize_record(record: &mut alera_core::runtime::WorkflowLaunchRecord) {
    record.request.request_id.clear();
    record.request.run_id.clear();
    record.request.revision = 0;
    record.request.task_id.clear();
    record.base_sha.clear();
    record.profile_id.clear();
    record.profile_revision = 0;
    record.error = None;
}

fn minimize_inputs(inputs: &mut alera_core::runtime::WorkflowLaunchInputs) {
    let workspace = &mut inputs.workspace;
    workspace.workspace.instance_id.clear();
    workspace.workspace.host_id.clear();
    workspace.workspace.project_id.clear();
    workspace.workspace.name.clear();
    workspace.workspace.branch = None;
    workspace.workspace.path.clear();
    workspace.workspace.source_branch = None;
    workspace.workspace.tag_ids.clear();
    workspace.workspace.tag_names.clear();
    workspace.workspace.section_id = None;
    workspace.workspace.parent_workspace_id = None;
    workspace.repo_path.clear();
    workspace.run_id.clear();
    workspace.revision = 0;
    workspace.task_id = None;
    workspace.attempt = 0;
    workspace.base_sha.clear();

    let task = &mut inputs.task.task;
    task.title.clear();
    task.spec.clear();
    task.stage_id.clear();
    task.role_id.clear();
    task.depends_on.clear();
    task.inputs = serde_json::Value::Null;
    task.corrects_task_id = None;
    let contract = &mut inputs.task.contract;
    contract.contract.id.clear();
    contract.contract.name.clear();
    contract.contract.purpose.clear();
    contract.contract.instructions.clear();
    contract.contract.input_schema = serde_json::Value::Null;
    contract.contract.result_schema = serde_json::Value::Null;
    contract.contract.required_artifacts.clear();
    contract.contract.checklist.clear();
    contract.inputs = serde_json::Value::Null;
    contract.digest.clear();
    inputs.task.profile_id.clear();

    inputs.profile.id.clear();
    inputs.profile.name.clear();
    inputs.profile.agent_type.clear();
    inputs.profile.command.clear();
    inputs.profile.managed_config = None;
    inputs.profile.custom_prompt.clear();
    inputs.profile.description.clear();
    inputs.profile.quota_group = None;
    inputs.profile.revision = 0;
    inputs.plan_digest.clear();
}
