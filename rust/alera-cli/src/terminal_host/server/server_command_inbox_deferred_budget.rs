use crate::terminal_host::host_error::HostError;
use crate::terminal_host::server::server_command::ServerCommand;
use crate::terminal_host::server::server_command_inbox::SERVER_COMMAND_COMPLETION_BYTES;

pub(super) fn is_completion(command: &ServerCommand) -> bool {
    matches!(
        command,
        ServerCommand::HistoryRequestRetry { .. }
            | ServerCommand::SshBootstrapFinished { .. }
            | ServerCommand::PullRequestWatchSnapshot { .. }
            | ServerCommand::PullRequestWatchMerged { .. }
    )
}

pub(super) fn command_bytes(command: &ServerCommand) -> Option<usize> {
    let bytes = match command {
        ServerCommand::HistoryRequestRetry { line, .. } => string_bytes(line),
        ServerCommand::SshBootstrapFinished {
            target_id, job_id, ..
        } => string_bytes(target_id) + string_bytes(job_id),
        ServerCommand::PullRequestWatchSnapshot { watch, result, .. } => {
            serialized_bytes(watch) + host_result_value_bytes(result)
        }
        ServerCommand::PullRequestWatchMerged { watch, result, .. } => {
            serialized_bytes(watch) + host_result_string_bytes(result)
        }
        _ => return None,
    };
    Some(bytes.max(1))
}

pub(super) fn bound(command: &mut ServerCommand) -> bool {
    match command {
        ServerCommand::PullRequestWatchSnapshot { result, .. }
            if host_result_value_bytes(result) > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            *result = Err(HostError::state(
                "Pull request watch snapshot exceeds the 16 MiB command inbox budget",
            ));
            true
        }
        ServerCommand::PullRequestWatchMerged { result, .. }
            if host_result_string_bytes(result) > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            *result = Err(HostError::state(
                "Pull request watch merge result exceeds the 16 MiB command inbox budget",
            ));
            true
        }
        _ => false,
    }
}

fn serialized_bytes<T: serde::Serialize>(value: &T) -> usize {
    crate::terminal_host::server::server_command_payload_size::serialized_bytes(
        value,
        SERVER_COMMAND_COMPLETION_BYTES,
    )
}

fn host_result_value_bytes(
    result: &crate::terminal_host::host_error::HostResult<serde_json::Value>,
) -> usize {
    match result {
        Ok(value) => serialized_bytes(value),
        Err(error) => string_bytes(&error.wire_message()),
    }
}

fn host_result_string_bytes(
    result: &crate::terminal_host::host_error::HostResult<String>,
) -> usize {
    match result {
        Ok(value) => string_bytes(value),
        Err(error) => string_bytes(&error.wire_message()),
    }
}

fn string_bytes(value: &str) -> usize {
    value.len().saturating_add(1)
}
