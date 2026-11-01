use super::*;

pub(crate) fn response_matches_request(
    request: &RuntimeRequest,
    response: &RuntimeResponse,
) -> bool {
    match request.kind {
        RequestKind::McpElicitationApproval => {
            matches!(response, RuntimeResponse::Elicitation { .. })
        }
        RequestKind::DynamicToolCall => matches!(response, RuntimeResponse::Native { .. }),
        RequestKind::ToolUserInput => matches!(response, RuntimeResponse::UserInput { .. }),
        _ => matches!(response, RuntimeResponse::Approval { .. }),
    }
}

pub(crate) fn resolved_payload(
    request: &RuntimeRequest,
    response: &RuntimeResponse,
) -> (EventKind, Value) {
    match response {
        RuntimeResponse::UserInput { answers, .. } => {
            (EventKind::UserInputResolved, json!({ "answers": answers }))
        }
        RuntimeResponse::Approval { decision, .. } => (
            EventKind::RequestResolved,
            json!({
                "requestType": request.kind,
                "decision": decision,
            }),
        ),
        // Form values may hold secrets, so they never ride an event.
        RuntimeResponse::Elicitation { action, .. } => (
            EventKind::RequestResolved,
            json!({
                "requestType": request.kind,
                "decision": action,
            }),
        ),
        RuntimeResponse::Native { result, .. } => (
            EventKind::RequestResolved,
            json!({
                "requestType": request.kind,
                "resolution": result,
            }),
        ),
    }
}
