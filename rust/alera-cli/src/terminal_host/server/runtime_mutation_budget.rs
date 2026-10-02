use super::{
    HandOnSessionRelocate, RuntimeMutationCompletion, RuntimeMutationEffect,
    RuntimeMutationFinished, RuntimeMutationOutcome,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};

const COMPLETION_BYTES: usize =
    crate::terminal_host::server::server_command_inbox::SERVER_COMMAND_COMPLETION_BYTES;
const OVERSIZED_RESPONSE: &str =
    "Runtime mutation response exceeds the 16 MiB command inbox budget";

pub(crate) fn runtime_mutation_finished_bytes(finished: &RuntimeMutationFinished) -> usize {
    std::mem::size_of_val(&finished.client_id)
        + std::mem::size_of_val(&finished.request_id)
        + runtime_mutation_outcome_bytes(&finished.outcome)
}

pub(crate) fn bound_runtime_mutation_finished(finished: &mut RuntimeMutationFinished) {
    if runtime_mutation_finished_bytes(finished) > COMPLETION_BYTES {
        let result = std::mem::replace(
            &mut finished.outcome.result,
            Err(HostError::state(OVERSIZED_RESPONSE)),
        );
        if let Ok(mut completion) = result {
            completion.response = json!({});
            completion.closed_tab_ids.clear();
            finished.outcome.completion_on_error = Some(completion);
        }
        bound_outcome_metadata(&mut finished.outcome);
    }
}

fn bound_outcome_metadata(outcome: &mut RuntimeMutationOutcome) {
    // The actor deliberately discards these after releasing the related
    // session bookkeeping. Dropping them here leaves the committed cleanup,
    // stopped tabs, process ownership and effects intact for the fallback.
    outcome.ended_pointer_tab_ids.clear();
    outcome.closed_session_tab_ids.clear();
    outcome.committed_tab_ids.clear();
    if let Some(completion) = outcome.completion_on_error.as_mut() {
        completion.response = json!({});
        completion.closed_tab_ids.clear();
    }
}

fn runtime_mutation_outcome_bytes(outcome: &RuntimeMutationOutcome) -> usize {
    host_result_completion_bytes(&outcome.result)
        + outcome
            .completion_on_error
            .as_ref()
            .map_or(0, runtime_mutation_completion_bytes)
        + string_list_bytes(&outcome.ended_pointer_tab_ids)
        + string_list_bytes(&outcome.closed_session_tab_ids)
        + string_list_bytes(&outcome.committed_tab_ids)
        + outcome
            .effect_on_error
            .as_ref()
            .map_or(0, runtime_mutation_effect_bytes)
        + string_list_bytes(&outcome.stopped_workspace_tab_ids)
        + outcome
            .pending_workspace_shutdown
            .as_ref()
            .map_or(0, |pending| {
                string_bytes(&pending.0)
                    + std::mem::size_of_val(&pending.1)
                    + string_list_bytes(&pending.1.closed_tab_ids)
            })
}

fn host_result_completion_bytes(result: &HostResult<RuntimeMutationCompletion>) -> usize {
    match result {
        Ok(completion) => runtime_mutation_completion_bytes(completion),
        Err(error) => host_error_bytes(error),
    }
}

fn runtime_mutation_completion_bytes(completion: &RuntimeMutationCompletion) -> usize {
    value_bytes(&completion.response)
        + runtime_mutation_effect_bytes(&completion.effect)
        + string_list_bytes(&completion.closed_tab_ids)
        + completion
            .hand_on_relocate
            .as_ref()
            .map_or(0, |relocate| hand_on_relocate_bytes(relocate))
}

fn hand_on_relocate_bytes(relocate: &HandOnSessionRelocate) -> usize {
    string_bytes(&relocate.source_workspace_id)
        + string_bytes(&relocate.destination_workspace_id)
        + string_bytes(&relocate.source_path)
        + string_bytes(&relocate.dest_path)
}

fn runtime_mutation_effect_bytes(effect: &RuntimeMutationEffect) -> usize {
    match effect {
        RuntimeMutationEffect::SetupFinished => 1,
        RuntimeMutationEffect::ProjectRemoved {
            project_id,
            workspace_ids,
        }
        | RuntimeMutationEffect::ProjectWorkspacesRemoved {
            project_id,
            workspace_ids,
        } => string_bytes(project_id) + string_list_bytes(workspace_ids),
        RuntimeMutationEffect::WorkspaceRemoved { workspace_id }
        | RuntimeMutationEffect::WorkspaceTabsRemoved { workspace_id }
        | RuntimeMutationEffect::WorkspaceSlept { workspace_id }
        | RuntimeMutationEffect::WorkspaceArchived { workspace_id } => string_bytes(workspace_id),
        RuntimeMutationEffect::ManagedWorkspaceRemoved {
            project_id,
            workspace_id,
        } => string_bytes(project_id) + string_bytes(workspace_id),
        RuntimeMutationEffect::WorkspaceRelocated {
            project_id,
            workspace_id,
            source_path,
        } => string_bytes(project_id) + string_bytes(workspace_id) + string_bytes(source_path),
        RuntimeMutationEffect::TabRemoved {
            tab_id,
            workspace_id,
        } => string_bytes(tab_id) + string_bytes(workspace_id.as_deref().unwrap_or_default()),
    }
}

fn string_list_bytes(values: &[String]) -> usize {
    values.iter().map(|value| string_bytes(value)).sum()
}

fn value_bytes(value: &Value) -> usize {
    super::super::server_command_payload_size::serialized_bytes(value, COMPLETION_BYTES)
}

fn host_error_bytes(error: &HostError) -> usize {
    string_bytes(&error.wire_message())
}

fn string_bytes(value: &str) -> usize {
    value.len().saturating_add(1)
}
