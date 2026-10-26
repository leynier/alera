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
