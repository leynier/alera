use super::super::server_command::ServerCommand;
use super::admission::AdmissionClass;
use super::{
    ServerInboxSendError, SERVER_COMMAND_COMPLETION_BYTES, SERVER_COMMAND_CONTROL_BYTES,
    SERVER_COMMAND_MAX_LINE_BYTES, SERVER_COMMAND_SMALL_LINE_BYTES, SERVER_COMMAND_WORK_BYTES,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::session::PtyEvent;
use serde::Serialize;

#[path = "server_command_inbox_deferred_budget.rs"]
mod deferred_budget;
#[path = "server_command_inbox_voice_budget.rs"]
mod voice_budget;

pub(super) fn command_admission_class(
    command: &ServerCommand,
) -> Result<AdmissionClass, ServerInboxSendError> {
    if is_completion_command(command) {
        let bytes = command_control_bytes(command);
        return Ok(AdmissionClass::Completion { bytes });
    }
    match command {
        ServerCommand::ClientLine { line, .. } | ServerCommand::RelayClientLine { line, .. } => {
            if line.len() > SERVER_COMMAND_MAX_LINE_BYTES {
                return Err(ServerInboxSendError::Oversized);
            }
            let bytes = line.len().max(1);
            if bytes > SERVER_COMMAND_SMALL_LINE_BYTES {
                Ok(AdmissionClass::Work { bytes })
            } else {
                Ok(AdmissionClass::Control { bytes })
            }
        }
        ServerCommand::Pty { event, .. } => match event {
            PtyEvent::Output(data) => {
                let bytes = data.len().max(1);
                if bytes > SERVER_COMMAND_WORK_BYTES {
                    return Err(ServerInboxSendError::Oversized);
                }
                Ok(AdmissionClass::Work { bytes })
            }
            _ => Ok(AdmissionClass::Work { bytes: 1 }),
        },
        ServerCommand::VoiceRealtime { event, .. } => {
            let bytes = voice_budget::voice_realtime_event_bytes(event);
            if bytes > SERVER_COMMAND_WORK_BYTES {
                return Err(ServerInboxSendError::Oversized);
            }
            Ok(AdmissionClass::Work { bytes })
        }
        _ => {
            let bytes = command_control_bytes(command);
            if bytes > SERVER_COMMAND_CONTROL_BYTES {
                return Err(ServerInboxSendError::Oversized);
            }
            Ok(AdmissionClass::Control { bytes })
        }
    }
}

fn command_control_bytes(command: &ServerCommand) -> usize {
    let bytes = deferred_budget::command_bytes(command).unwrap_or_else(|| match command {
        ServerCommand::RuntimeMutationFinished(finished) => {
            super::super::runtime_mutations::budget::runtime_mutation_finished_bytes(finished)
        }
        ServerCommand::WorkflowLaunch(command) => {
            super::super::workflow_launch_requests::budget::command_bytes(command)
        }
        ServerCommand::RemoteTerminalLifecycleFinished {
            verb,
            payload,
            result,
            ..
        } => string_bytes(verb) + value_bytes(payload) + host_result_serialized_bytes(result),
        ServerCommand::OwnerTerminalLifecycleFinished {
            operation_id,
            result,
            ..
        } => string_bytes(operation_id) + host_result_serialized_bytes(result),
        ServerCommand::RemoteSetupFinished { result, .. }
        | ServerCommand::RemoteRecoveryFinished { result, .. }
        | ServerCommand::HostLinkRequestFinished { result, .. }
        | ServerCommand::ProjectCheckoutRegistered { result, .. }
        | ServerCommand::ManagedWorkspaceCreated { result, .. }
        | ServerCommand::WorkspaceStorageMeasured { result, .. }
        | ServerCommand::WorkspaceSetupFinished { result, .. }
        | ServerCommand::AiAssistFinished { result, .. }
        | ServerCommand::AiDictationFinished { result, .. }
        | ServerCommand::LinkedIssueRequestFinished { result, .. }
        | ServerCommand::MobileWorkspaceFileFinished { result, .. }
        | ServerCommand::MobilePromptFileFinished { result, .. }
        | ServerCommand::AgentQuotaFinished { result, .. }
        | ServerCommand::AgentQuotaClaudeTuiFinished { result, .. }
        | ServerCommand::AgentQuotaCodexResetFinished { result, .. }
        | ServerCommand::HostToolFinished { result, .. }
        | ServerCommand::WorkflowWorkspaceFinished { result, .. }
        | ServerCommand::RemoteProjectConfigRead { result, .. }
        | ServerCommand::RemoteResourceSnapshot { result, .. }
        | ServerCommand::RemoteAgentPresenceListed { result, .. } => {
            host_result_serialized_bytes(result)
        }
        ServerCommand::RelayStatus { payload, .. }
        | ServerCommand::HostLinkEvent { event: payload, .. }
        | ServerCommand::MobileStatusFinished { payload, .. }
        | ServerCommand::ResourceSampleReady { snapshot: payload }
        | ServerCommand::CodexMessage { message: payload } => value_bytes(payload),
        ServerCommand::AgentHookEvent { event, .. } => {
            string_bytes(&event.terminal_session_id)
                + string_bytes(&event.workspace_id)
                + string_bytes(&event.tab_id)
                + string_bytes(&event.agent_type)
                + event
                    .event_name
                    .as_deref()
                    .map(string_bytes)
                    .unwrap_or_default()
                + value_bytes(&event.payload)
        }
        ServerCommand::BufferGuardExpired { id }
        | ServerCommand::LinkedIssuesChanged { workspace_id: id }
        | ServerCommand::ProjectCloneChanged { job_id: id }
        | ServerCommand::ProjectCloneFinished { job_id: id }
        | ServerCommand::HubReverseRequestExpired { reverse_id: id }
        | ServerCommand::HostLinkStateChanged { host_id: id }
        | ServerCommand::HostLinkClosed { host_id: id, .. }
        | ServerCommand::CodexProcessExited { reason: id }
        | ServerCommand::CodexMalformed { reason: id } => string_bytes(id),
        ServerCommand::AgentTitleReady { tab_id, id } => string_bytes(tab_id) + string_bytes(id),
        ServerCommand::HistoryWriterReady { session_id } => string_bytes(session_id),
        ServerCommand::OrchestrationStateWaitPoll(waiter_id) => {
            std::mem::size_of_val(waiter_id)
        }
        ServerCommand::OrchestrationWaitTimeout {
            waiter_id,
            effective_timeout_ms,
        } => std::mem::size_of_val(waiter_id) + std::mem::size_of_val(effective_timeout_ms),
        ServerCommand::OrchestrationDeferredEnter {
            session_id,
            session_instance_id,
            message_ids,
            force_submit,
        } => {
            string_bytes(session_id)
                + std::mem::size_of_val(session_instance_id)
                + string_list_bytes(message_ids)
                + std::mem::size_of_val(force_submit)
        }
        ServerCommand::TerminalStartupInput {
            session_id,
            interactive_shell,
            command,
            ..
        } => string_bytes(session_id) + string_bytes(interactive_shell) + string_bytes(command),
        ServerCommand::TerminalStartupSubmit { session_id, .. } => string_bytes(session_id),
        ServerCommand::TerminalPulseWatcherStarted {
            workspace_id,
            result,
            ..
        } => string_bytes(workspace_id) + host_result_watcher_bytes(result),
        ServerCommand::TerminalPulseWatcherFailed {
            workspace_id,
            error,
            ..
        } => string_bytes(workspace_id) + string_bytes(error),
        ServerCommand::TerminalPulseDue {
            session_id,
            session_instance_id,
            generation,
        } => {
            string_bytes(session_id)
                + std::mem::size_of_val(session_instance_id)
                + std::mem::size_of_val(generation)
        }
        ServerCommand::VoiceRealtimeReconnect { .. }
        | ServerCommand::VoiceGeminiTranscriptSettle { .. } => {
            std::mem::size_of::<u64>() * 2
        }
        ServerCommand::AgentTitleFinished {
            tab_id, id, result, ..
        } => string_bytes(tab_id) + string_bytes(id) + host_result_string_bytes(result),
        ServerCommand::VoiceRealtime { event, .. } => {
            voice_budget::voice_realtime_event_bytes(event)
        }
        ServerCommand::VoiceTurnFinished { result, .. } => host_result_string_bytes(result),
        ServerCommand::VoiceSynthesizeFinished { result, .. } => host_result_serialized_bytes(result),
        ServerCommand::OwnerAutomationPrecheckFinished { operation_id } => string_bytes(operation_id),
        ServerCommand::AutomationPrecheckFinished {
            definition,
            run,
            host_id,
            path,
            result,
        } => {
            serialized_bytes(definition)
                + serialized_bytes(run)
                + string_bytes(host_id)
                + string_bytes(path)
                + bool_result_bytes(result)
        }
        ServerCommand::AutomationCheckoutPrepared {
            definition,
            run,
            project,
            result,
        } => serialized_bytes(definition)
            + serialized_bytes(run)
            + serialized_bytes(project)
            + host_result_serialized_bytes(result),
        ServerCommand::AutomationSharedCleanupFinished { attempt, result } => {
            string_bytes(&attempt.id)
                + serialized_bytes(&attempt.run)
                + serialized_bytes(&attempt.workspace)
                + value_result_bytes(result)
        }
        ServerCommand::OrchestrationCompletionFinished(completion) => {
            string_bytes(&completion.dispatch_id)
                + string_bytes(&completion.assignee)
                + string_bytes(&completion.result)
                + host_result_string_bytes(&completion.completion_sha)
        }
        ServerCommand::Account(
            crate::terminal_host::server::account_requests::AccountCommand::SignInPrepared {
                result, ..
            }
            | crate::terminal_host::server::account_requests::AccountCommand::SignInCompleted {
                result,
            }
            | crate::terminal_host::server::account_requests::AccountCommand::OperationFinished {
                result, ..
            },
        ) => host_result_serialized_bytes(result),
        ServerCommand::Account(
            crate::terminal_host::server::account_requests::AccountCommand::SubscriptionSyncFinished {
                result,
            },
        ) => match result {
            Ok(value) => value.to_string().len().saturating_add(1),
            Err(error) => host_error_bytes(error),
        },
        ServerCommand::Push(
            crate::terminal_host::server::push_delivery::PushCommand::DeliveryFinished { result },
        ) => match result {
            Ok(value) => value.to_string().len().saturating_add(1),
            Err(error) => string_bytes(error),
        },
        ServerCommand::ClientLine { line, .. }
        | ServerCommand::RelayClientLine { line, .. }
        => string_bytes(line),
        _ => 1,
    });
    bytes.max(1)
}

pub(super) fn bound_completion_result(command: &mut ServerCommand) {
    let message =
        || HostError::state("Runtime response exceeds the 16 MiB command inbox budget".to_string());
    let oversized = command_control_bytes(command) > SERVER_COMMAND_COMPLETION_BYTES;
    if deferred_budget::bound(command) {
        return;
    }
    match command {
        ServerCommand::RuntimeMutationFinished(finished) => {
            super::super::runtime_mutations::budget::bound_runtime_mutation_finished(finished);
        }
        ServerCommand::WorkflowLaunch(command) => {
            super::super::workflow_launch_requests::budget::bound(command);
        }
        ServerCommand::OwnerTerminalLifecycleFinished { result, .. }
        | ServerCommand::RemoteSetupFinished { result, .. }
        | ServerCommand::RemoteRecoveryFinished { result, .. }
        | ServerCommand::HostLinkRequestFinished { result, .. }
        | ServerCommand::ProjectCheckoutRegistered { result, .. }
        | ServerCommand::ManagedWorkspaceCreated { result, .. }
        | ServerCommand::WorkspaceStorageMeasured { result, .. }
        | ServerCommand::WorkspaceSetupFinished { result, .. }
        | ServerCommand::AiAssistFinished { result, .. }
        | ServerCommand::AiDictationFinished { result, .. }
        | ServerCommand::LinkedIssueRequestFinished { result, .. }
        | ServerCommand::MobileWorkspaceFileFinished { result, .. }
        | ServerCommand::MobilePromptFileFinished { result, .. }
        | ServerCommand::AgentQuotaFinished { result, .. }
        | ServerCommand::AgentQuotaClaudeTuiFinished { result, .. }
        | ServerCommand::AgentQuotaCodexResetFinished { result, .. }
        | ServerCommand::HostToolFinished { result, .. }
        | ServerCommand::WorkflowWorkspaceFinished { result, .. }
        | ServerCommand::RemoteProjectConfigRead { result, .. }
        | ServerCommand::RemoteResourceSnapshot { result, .. }
        | ServerCommand::RemoteAgentPresenceListed { result, .. } => {
            if host_result_serialized_bytes(result) > SERVER_COMMAND_COMPLETION_BYTES {
                // JSON escaping can expand a captured process output beyond
                // its byte budget. Preserve the completion with an error.
                *result = Err(message());
            }
        }
        ServerCommand::VoiceTurnFinished { result, .. }
            if host_result_string_bytes(result) > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            *result = Err(message());
        }
        ServerCommand::VoiceSynthesizeFinished { result, .. }
            if host_result_serialized_bytes(result) > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            *result = Err(message());
        }
        ServerCommand::AutomationPrecheckFinished { result, .. } if oversized => {
            *result = Err(message().wire_message());
        }
        ServerCommand::AutomationCheckoutPrepared { result, .. } if oversized => {
            *result = Err(message());
        }
        ServerCommand::AutomationSharedCleanupFinished { result, .. } if oversized => {
            *result = Err(message().wire_message());
        }
        ServerCommand::ResourceSampleReady { snapshot }
            if value_bytes(snapshot) > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            *snapshot = serde_json::json!({
                "error": "Resource sample exceeds the 16 MiB command inbox budget"
            });
        }
        ServerCommand::OrchestrationCompletionFinished(completion)
            if orchestration_completion_bytes(completion) > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            completion.result = message().wire_message();
            completion.completion_sha = Err(message());
        }
        ServerCommand::VoiceRealtime { event, .. }
            if !matches!(
                event,
                super::super::voice_realtime::VoiceRealtimeEvent::Audio { .. }
            ) && voice_budget::voice_realtime_event_bytes(event)
                > SERVER_COMMAND_COMPLETION_BYTES =>
        {
            voice_budget::bound_voice_realtime_event(event);
        }
        _ => {}
    }
}

fn string_bytes(value: &str) -> usize {
    value.len().saturating_add(1)
}

fn string_list_bytes(values: &[String]) -> usize {
    values.iter().map(|value| string_bytes(value)).sum()
}

fn value_bytes(value: &serde_json::Value) -> usize {
    super::super::server_command_payload_size::serialized_bytes(
        value,
        SERVER_COMMAND_COMPLETION_BYTES,
    )
}

fn serialized_bytes<T: Serialize>(value: &T) -> usize {
    super::super::server_command_payload_size::serialized_bytes(
        value,
        SERVER_COMMAND_COMPLETION_BYTES,
    )
}

fn host_result_serialized_bytes<T: Serialize>(result: &HostResult<T>) -> usize {
    match result {
        Ok(value) => serialized_bytes(value),
        Err(error) => host_error_bytes(error),
    }
}

fn host_result_string_bytes(result: &HostResult<String>) -> usize {
    match result {
        Ok(value) => string_bytes(value),
        Err(error) => host_error_bytes(error),
    }
}

fn host_result_watcher_bytes(
    result: &HostResult<super::super::terminal_pulse::WorkspacePulseWatcher>,
) -> usize {
    match result {
        Ok(_) => 1,
        Err(error) => host_error_bytes(error),
    }
}

fn bool_result_bytes(result: &Result<bool, String>) -> usize {
    match result {
        Ok(value) => serialized_bytes(value),
        Err(error) => string_bytes(error),
    }
}

fn value_result_bytes(result: &Result<serde_json::Value, String>) -> usize {
    match result {
        Ok(value) => value_bytes(value),
        Err(error) => string_bytes(error),
    }
}

fn host_error_bytes(error: &HostError) -> usize {
    match error {
        HostError::State(message) | HostError::Format(message) => string_bytes(message),
        HostError::Conflict {
            code,
            message,
            details,
        } => string_bytes(code) + string_bytes(message) + value_bytes(details),
    }
}

fn orchestration_completion_bytes(
    completion: &super::super::orchestration_completion::OrchestrationCompletionFinished,
) -> usize {
    string_bytes(&completion.dispatch_id)
        + string_bytes(&completion.assignee)
        + string_bytes(&completion.result)
        + host_result_string_bytes(&completion.completion_sha)
}

fn is_completion_command(command: &ServerCommand) -> bool {
    if deferred_budget::is_completion(command) {
        return true;
    }
    if matches!(
        command,
        ServerCommand::RemoteTerminalLifecycleFinished { .. }
            | ServerCommand::OwnerTerminalLifecycleFinished { .. }
            | ServerCommand::RemoteSetupFinished { .. }
            | ServerCommand::RemoteRecoveryFinished { .. }
            | ServerCommand::HostLinkRequestFinished { .. }
            | ServerCommand::ProjectCheckoutRegistered { .. }
            | ServerCommand::ManagedWorkspaceCreated { .. }
            | ServerCommand::WorkspaceStorageMeasured { .. }
            | ServerCommand::WorkspaceSetupFinished { .. }
            | ServerCommand::AgentTitleFinished { .. }
            | ServerCommand::AiAssistFinished { .. }
            | ServerCommand::AiDictationFinished { .. }
            | ServerCommand::LinkedIssueRequestFinished { .. }
            | ServerCommand::MobileWorkspaceFileFinished { .. }
            | ServerCommand::MobilePromptFileFinished { .. }
            | ServerCommand::AgentQuotaFinished { .. }
            | ServerCommand::AgentQuotaClaudeTuiFinished { .. }
            | ServerCommand::AgentQuotaCodexResetFinished { .. }
            | ServerCommand::HostToolFinished { .. }
            | ServerCommand::WorkflowWorkspaceFinished { .. }
            | ServerCommand::RemoteProjectConfigRead { .. }
            | ServerCommand::RemoteResourceSnapshot { .. }
            | ServerCommand::RemoteAgentPresenceListed { .. }
            | ServerCommand::RuntimeMutationFinished(_)
            | ServerCommand::MobileStatusFinished { .. }
            | ServerCommand::OwnerAutomationPrecheckFinished { .. }
            | ServerCommand::AutomationPrecheckFinished { .. }
            | ServerCommand::AutomationCheckoutPrepared { .. }
            | ServerCommand::AutomationSharedCleanupFinished { .. }
            | ServerCommand::WorkflowWorkspaceRecoveryFinished
            | ServerCommand::ProjectCloneFinished { .. }
            | ServerCommand::OrchestrationCompletionFinished(_)
            | ServerCommand::Account(_)
            | ServerCommand::Push(
                crate::terminal_host::server::push_delivery::PushCommand::DeliveryFinished { .. },
            )
            | ServerCommand::VoiceTurnFinished { .. }
            | ServerCommand::VoiceSynthesizeFinished { .. }
            | ServerCommand::ResourceSampleReady { .. }
            | ServerCommand::OrchestrationWaitTimeout { .. }
            | ServerCommand::OrchestrationStateWaitPoll(_)
            | ServerCommand::OrchestrationDeferredEnter { .. }
            | ServerCommand::TerminalStartupInput { .. }
            | ServerCommand::TerminalStartupSubmit { .. }
            | ServerCommand::TerminalPulseWatcherStarted { .. }
            | ServerCommand::TerminalPulseWatcherFailed { .. }
            | ServerCommand::AgentTitleReady { .. }
            | ServerCommand::HistoryWriterReady { .. }
            | ServerCommand::BufferGuardExpired { .. }
            | ServerCommand::TerminalPulseDue { .. }
            | ServerCommand::VoiceRealtimeReconnect { .. }
            | ServerCommand::VoiceGeminiTranscriptSettle { .. }
            | ServerCommand::HubReverseRequestExpired { .. }
            | ServerCommand::CodexProcessExited { .. }
    ) {
        return true;
    }
    match command {
        ServerCommand::WorkflowLaunch(command) => {
            super::super::workflow_launch_requests::budget::is_completion(command)
        }
        ServerCommand::VoiceRealtime { event, .. } => !matches!(
            event,
            super::super::voice_realtime::VoiceRealtimeEvent::Audio { .. }
        ),
        _ => false,
    }
}
