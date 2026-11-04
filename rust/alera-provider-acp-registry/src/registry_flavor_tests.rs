use super::registry_flavor::{normalize_event, RegistryFlavorState};
use crate::AcpRegistryAgentFlavor;
use alera_provider_protocol::{EventKind, ProviderEvent, ProviderKind, RawEvent};
use serde_json::{json, Value};

fn event(method: &str, params: Value, kind: EventKind, payload: Value) -> ProviderEvent {
    ProviderEvent::new(
        ProviderKind::Other("acpRegistry".into()),
        "instance",
        "thread",
        kind,
        payload,
        Some(RawEvent {
            source: "acp.jsonrpc".into(),
            method: Some(method.into()),
            message_type: Some(method.into()),
            payload: json!({"jsonrpc":"2.0","method":method,"params":params}),
        }),
    )
}

#[test]
fn devin_meta_names_tools_and_projects_subagents() {
    let params = json!({"update": {
        "sessionUpdate":"tool_call",
        "toolCallId":"tool-1",
        "status":"in_progress",
        "title":"Tool",
        "_meta":{"cognition.ai":{
            "inferenceToolName":"terminal",
            "subagent_started":{"agentId":"agent-1","task":"inspect"}
        }}
    }});
    let mut state = RegistryFlavorState::default();
    let mapped = normalize_event(
        event(
            "session/update",
            params,
            EventKind::ItemStarted,
            json!({"itemType":"dynamicToolCall","status":"inProgress","title":"Tool","data":{}}),
        ),
        AcpRegistryAgentFlavor::Devin,
        &mut state,
    );
    assert_eq!(mapped.kind, EventKind::TaskStarted);
    assert_eq!(mapped.payload["taskId"], "devin-task:agent-1");
    assert_eq!(mapped.payload["agentId"], "agent-1");
}

#[test]
fn copilot_session_event_routes_following_chunk() {
    let mut state = RegistryFlavorState::default();
    let extension = event(
        "github.com/copilot/sessionEvent",
        json!({"sessionId":"root","type":"assistant.message_delta","data":{"deltaContent":"hello","parentToolCallId":"task-1"}}),
        EventKind::Unknown("acp.github.com/copilot/sessionEvent".into()),
        json!({"sessionId":"root"}),
    );
    let _ = normalize_event(extension, AcpRegistryAgentFlavor::Copilot, &mut state);
    let chunk = event(
        "session/update",
        json!({"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hello"}}}),
        EventKind::ContentDelta,
        json!({"streamKind":"assistant_text","delta":"hello"}),
    );
    let mapped = normalize_event(chunk, AcpRegistryAgentFlavor::Copilot, &mut state);
    assert_eq!(mapped.payload["agentId"], "task-1");
    assert_eq!(mapped.payload["childSessionId"], "copilot-task:task-1");
}

#[test]
fn copilot_cancelled_task_reports_cancelled() {
    let params = json!({"update": {
        "sessionUpdate":"tool_call_update",
        "toolCallId":"task-1",
        "status":"cancelled",
        "rawInput":{"agent_type":"explore","prompt":"inspect","description":"Inspect"}
    }});
    let mut state = RegistryFlavorState::default();
    let mapped = normalize_event(
        event(
            "session/update",
            params,
            EventKind::ItemCompleted,
            json!({"itemType":"dynamicToolCall","status":"failed","data":{}}),
        ),
        AcpRegistryAgentFlavor::Copilot,
        &mut state,
    );
    assert_eq!(mapped.kind, EventKind::TaskCompleted);
    assert_eq!(mapped.payload["status"], "cancelled");
}

#[test]
fn mistral_retry_is_a_retryable_rate_limit_warning() {
    let mut state = RegistryFlavorState::default();
    let mapped = normalize_event(
        event(
            "_session/retrying",
            json!({"category":"rate_limited","detail":"slow down"}),
            EventKind::Unknown("acp._session/retrying".into()),
            json!({}),
        ),
        AcpRegistryAgentFlavor::MistralVibe,
        &mut state,
    );
    assert_eq!(mapped.kind, EventKind::RuntimeWarning);
    assert_eq!(mapped.payload["appCode"], -31_001);
    assert_eq!(mapped.payload["failureClass"], "usage_limit");
}

#[test]
fn mistral_idle_rate_limit_error_is_a_usage_limit() {
    let mut state = RegistryFlavorState::default();
    let mapped = normalize_event(
        event(
            "session/update",
            json!({"sessionId":"root","update":{"sessionUpdate":"state_update","state":"idle","stopReason":"error","error":{"code":-31_001,"message":"Rate limit exceeded"}}}),
            EventKind::TurnCompleted,
            json!({"state":"failed","stopReason":"error","errorMessage":"Rate limit exceeded","error":{"code":-31_001,"data":null}}),
        ),
        AcpRegistryAgentFlavor::MistralVibe,
        &mut state,
    );
    assert_eq!(mapped.payload["appCode"], -31_001);
    assert_eq!(mapped.payload["failureClass"], "usage_limit");
    assert_eq!(mapped.payload["rateLimited"], true);
}

#[test]
fn mistral_rate_limit_code_leaves_an_unfailed_turn_unclassified() {
    let mut state = RegistryFlavorState::default();
    let mapped = normalize_event(
        event(
            "session/update",
            json!({"sessionId":"root","update":{"sessionUpdate":"state_update","state":"idle","stopReason":"cancelled","error":{"code":-31_001,"message":"Rate limit exceeded"}}}),
            EventKind::TurnCompleted,
            json!({"state":"interrupted","stopReason":"cancelled","errorMessage":"Rate limit exceeded","error":{"code":-31_001,"data":null}}),
        ),
        AcpRegistryAgentFlavor::MistralVibe,
        &mut state,
    );
    assert!(mapped.payload.get("failureClass").is_none());
    mapped.validate().unwrap();
}
