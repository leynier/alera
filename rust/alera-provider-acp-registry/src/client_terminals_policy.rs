use super::ClientTerminals;
use crate::client_terminals_output::normalize_terminal_content;
use alera_provider_protocol::{
    ApprovalDecision, EventKind, ProviderError, ProviderEvent, ProviderSession, RequestKind,
    RuntimeResponse,
};
use serde_json::Value;

impl ClientTerminals {
    pub(crate) fn sync_session(&self, session: &ProviderSession) {
        let mut state = self.state.lock().expect("terminal state mutex poisoned");
        if state.session_id.as_deref() != Some(&session.native_thread_id) {
            state.session_execute = false;
            state.pending_approvals.clear();
        }
        if state.turn_id != session.active_turn_id {
            state.turn_execute = None;
            state.pending_approvals.clear();
        }
        state.session_id = Some(session.native_thread_id.clone());
        state.turn_id.clone_from(&session.active_turn_id);
        if let Some(cwd) = &session.cwd {
            state.cwd.clone_from(cwd);
        }
    }

    pub(crate) fn observe(&self, event: &mut ProviderEvent) {
        let mut state = self.state.lock().expect("terminal state mutex poisoned");
        if let Some(request) = &event.runtime_request {
            if request.kind == RequestKind::CommandExecutionApproval
                && request.payload.get("sessionId").and_then(Value::as_str)
                    == state.session_id.as_deref()
                && request.turn_id.is_some()
                && request.turn_id == state.turn_id
            {
                state
                    .pending_approvals
                    .insert(request.request_id.clone(), request.clone());
            }
        }
        normalize_terminal_content(event, &state);
        if event.kind == EventKind::TurnCompleted {
            state.turn_id = None;
            state.turn_execute = None;
            state.pending_approvals.clear();
        }
    }

    pub(crate) fn validate_response(
        &self,
        response: &RuntimeResponse,
    ) -> Result<(), ProviderError> {
        let RuntimeResponse::Approval {
            request_id,
            decision,
            updated_input,
            feedback: None,
        } = response
        else {
            return Ok(());
        };
        let state = self.state.lock().expect("terminal state mutex poisoned");
        let Some(request) = state.pending_approvals.get(request_id) else {
            return Ok(());
        };
        if updated_input.is_some() {
            return Err(ProviderError::Unsupported(
                "ACP client command approvals cannot change the native command input".into(),
            ));
        }
        if *decision == ApprovalDecision::AcceptForSession && !has_session_option(&request.payload)
        {
            return Err(ProviderError::Validation(
                "ACP command permission does not offer a session approval scope".into(),
            ));
        }
        if matches!(
            decision,
            ApprovalDecision::Accept | ApprovalDecision::AcceptAlways
        ) && !has_accept_option(&request.payload, *decision)
        {
            return Err(ProviderError::Validation(
                "ACP command permission lacks a valid native acceptance option".into(),
            ));
        }
        Ok(())
    }

    pub(crate) fn record_response(&self, response: &RuntimeResponse) {
        let mut state = self.state.lock().expect("terminal state mutex poisoned");
        let Some(request) = state.pending_approvals.remove(response.request_id()) else {
            return;
        };
        let RuntimeResponse::Approval { decision, .. } = response else {
            return;
        };
        if request.turn_id != state.turn_id || state.turn_id.is_none() || state.closed {
            return;
        }
        match decision {
            ApprovalDecision::AcceptForSession if has_session_option(&request.payload) => {
                state.session_execute = true
            }
            ApprovalDecision::Accept | ApprovalDecision::AcceptAlways => {
                state.turn_execute.clone_from(&request.turn_id)
            }
            _ => {}
        }
    }
}

fn has_session_option(payload: &Value) -> bool {
    valid_selected_option(payload, &["allow_always"])
}

fn has_accept_option(payload: &Value, decision: ApprovalDecision) -> bool {
    let wanted = if decision == ApprovalDecision::Accept {
        ["allow_once", "allow_always"]
    } else {
        ["allow_always", "allow_once"]
    };
    valid_selected_option(payload, &wanted)
}

fn valid_selected_option(payload: &Value, wanted: &[&str]) -> bool {
    let Some(options) = payload.get("options").and_then(Value::as_array) else {
        return false;
    };
    wanted
        .iter()
        .find_map(|kind| {
            options
                .iter()
                .find(|option| option.get("kind").and_then(Value::as_str) == Some(*kind))
        })
        .and_then(|option| option.get("optionId"))
        .and_then(Value::as_str)
        .is_some_and(|id| !id.is_empty())
}
