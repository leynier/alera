mod support;

use alera_provider_protocol::{
    ApprovalDecision, EventKind, Provider, RequestKind, RuntimeResponse, TurnInput,
};
use serde_json::json;
use support::*;

#[tokio::test]
async fn approval_request_round_trips_and_keeps_request_id() {
    let request = json!({
        "type": "control_request",
        "request_id": "permission-native-id",
        "request": {
            "subtype": "can_use_tool",
            "tool_name": "Bash",
            "input": {"command": "ls"},
            "tool_use_id": "tool-1"
        }
    });
    let (mut provider, handle) = started_provider([initialize_response(), request]).await;
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "run"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    let runtime_request = event.runtime_request.clone().unwrap();
    assert_eq!(runtime_request.kind, RequestKind::PermissionApproval);
    assert_eq!(runtime_request.item_id.as_deref(), Some("tool-1"));
    provider
        .respond(RuntimeResponse::Approval {
            request_id: runtime_request.request_id.clone(),
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    assert_eq!(event.turn_id.as_deref(), Some(turn.turn_id.as_str()));
    tokio::task::yield_now().await;
    let writes = handle.writes.lock().unwrap();
    assert!(writes
        .iter()
        .any(|frame| frame["type"] == "control_response"
            && frame["response"]["request_id"] == "permission-native-id"));
}

#[tokio::test]
async fn ask_user_question_without_native_id_gets_stable_question_id() {
    let request = json!({
        "type": "control_request",
        "request_id": "permission-native-id",
        "request": {
            "subtype": "can_use_tool",
            "tool_name": "AskUserQuestion",
            "input": {
                "questions": [{
                    "header": "Choice",
                    "question": "Continue?",
                    "options": [{"label": "Yes", "description": "Continue"}]
                }]
            }
        },
        "vendor_sentinel": {"kept": true}
    });
    let (mut provider, handle) = started_provider([initialize_response(), request]).await;
    let _ = provider
        .send_turn(TurnInput::text("app-thread", "question"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::UserInputRequested);
    assert_eq!(
        event.raw.as_ref().unwrap().payload["vendor_sentinel"]["kept"],
        true
    );
    assert_eq!(
        event
            .provider_refs
            .as_ref()
            .and_then(|refs| refs.provider_request_id.as_deref()),
        Some("permission-native-id")
    );
    let runtime_request = event.runtime_request.clone().unwrap();
    assert_eq!(runtime_request.kind, RequestKind::ToolUserInput);
    assert_eq!(runtime_request.questions[0].id, "Choice");
    let mut answers = std::collections::BTreeMap::new();
    answers.insert("Choice".into(), json!("Yes"));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: runtime_request.request_id,
            answers,
        })
        .await
        .unwrap();
    tokio::task::yield_now().await;
    let writes = handle.writes.lock().unwrap();
    assert!(writes.iter().any(|frame| {
        frame["type"] == "control_response"
            && frame["response"]["request_id"] == "permission-native-id"
            && frame["response"]["response"]["behavior"] == "allow"
    }));
}

#[tokio::test]
async fn generic_mcp_control_request_is_dynamic_tool_call_with_raw_context() {
    let request = json!({
        "type": "control_request",
        "request_id": "mcp-native-id",
        "request": {
            "subtype": "mcp_message",
            "server_name": "files",
            "message": {"jsonrpc": "2.0", "id": 7, "method": "tools/list"},
            "unknown_field": {"kept": true}
        },
        "vendor_envelope": "preserve-me"
    });
    let (mut provider, handle) = started_provider([initialize_response(), request]).await;
    assert!(!provider.capabilities().mcp_elicitation);
    provider
        .send_turn(TurnInput::text("app-thread", "mcp"))
        .await
        .unwrap();
    let event = loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::RequestOpened {
            break event;
        }
    };
    let runtime_request = event.runtime_request.clone().unwrap();
    assert_eq!(runtime_request.kind, RequestKind::DynamicToolCall);
    assert_eq!(
        event.raw.as_ref().unwrap().payload["vendor_envelope"],
        "preserve-me"
    );
    assert_eq!(
        event
            .provider_refs
            .as_ref()
            .and_then(|refs| refs.provider_request_id.as_deref()),
        Some("mcp-native-id")
    );
    provider
        .respond(RuntimeResponse::Native {
            request_id: runtime_request.request_id,
            result: json!({"jsonrpc": "2.0", "id": 7, "result": {"tools": []}}),
        })
        .await
        .unwrap();
    let resolved = provider.next_event().await.unwrap().unwrap();
    assert_eq!(resolved.kind, EventKind::RequestResolved);
    assert_eq!(resolved.raw.as_ref().unwrap().source, "claude.sdk.message");
    for _ in 0..8 {
        tokio::task::yield_now().await;
    }
    let writes = handle.writes.lock().unwrap();
    assert!(writes.iter().any(|frame| {
        frame["type"] == "control_response"
            && frame["response"]["request_id"] == "mcp-native-id"
            && frame["response"]["response"]["mcp_response"]["result"]["tools"].is_array()
    }));
}
