mod support;

use alera_provider_protocol::{EventKind, InteractionMode, Provider, ProviderEvent, TurnInput};
use serde_json::{json, Value};
use support::*;

fn ack(request_id: &str) -> Value {
    json!({
        "type": "control_response",
        "response": {"subtype": "success", "request_id": request_id, "response": {}}
    })
}

fn plan_turn(prompt: &str) -> TurnInput {
    let mut input = TurnInput::text("app-thread", prompt);
    input.interaction_mode = InteractionMode::Plan;
    input
}

async fn events_until_turn_end(provider: &mut impl Provider) -> Vec<ProviderEvent> {
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        let done = event.kind == EventKind::TurnCompleted;
        events.push(event);
        if done {
            return events;
        }
    }
}

fn permission_modes(writes: &[Value]) -> Vec<String> {
    writes
        .iter()
        .filter(|frame| frame["request"]["subtype"] == "set_permission_mode")
        .map(|frame| frame["request"]["mode"].as_str().unwrap().to_owned())
        .collect()
}

#[tokio::test]
async fn plan_turn_switches_permission_mode_and_default_turn_restores_it() {
    let (mut provider, handle) = started_provider([
        initialize_response(),
        ack("req_2"),
        result_message(false, None),
        result_message(false, None),
        ack("req_3"),
        result_message(false, None),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();

    provider.send_turn(plan_turn("plan it")).await.unwrap();
    events_until_turn_end(&mut provider).await;
    provider.send_turn(plan_turn("refine")).await.unwrap();
    events_until_turn_end(&mut provider).await;
    provider
        .send_turn(TurnInput::text("app-thread", "implement"))
        .await
        .unwrap();
    events_until_turn_end(&mut provider).await;

    let writes = handle.writes.lock().unwrap();
    assert_eq!(permission_modes(&writes), ["plan", "default"]);
    let first_mode = writes
        .iter()
        .position(|frame| frame["request"]["subtype"] == "set_permission_mode")
        .unwrap();
    let first_prompt = writes
        .iter()
        .position(|frame| frame["type"] == "user")
        .unwrap();
    assert!(first_mode < first_prompt);
}

#[tokio::test]
async fn todo_write_updates_the_turn_plan_and_exit_plan_mode_is_a_proposed_plan() {
    let exit_plan_request = json!({
        "type": "control_request",
        "request_id": "exit-plan-native-id",
        "request": {
            "subtype": "can_use_tool",
            "tool_name": "ExitPlanMode",
            "input": {"plan": "1. Read\n2. Edit"},
            "tool_use_id": "exit-plan-tool"
        }
    });
    let (mut provider, handle) = started_provider([
        initialize_response(),
        ack("req_2"),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {
                "id": "message-1",
                "content": [
                    {"type": "tool_use", "id": "todo-tool", "name": "TodoWrite", "input": {"todos": [
                        {"content": "Read", "status": "completed", "activeForm": "Reading"},
                        {"content": "Edit", "status": "in_progress", "activeForm": "Editing"}
                    ]}},
                    {"type": "tool_use", "id": "exit-plan-tool", "name": "ExitPlanMode", "input": {"plan": "1. Read\n2. Edit"}}
                ]
            }
        }),
        exit_plan_request,
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {
                "id": "message-2",
                "content": [{"type": "tool_result", "tool_use_id": "exit-plan-tool", "content": "denied", "is_error": true}]
            }
        }),
        result_message(false, None),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();

    provider.send_turn(plan_turn("plan it")).await.unwrap();
    let events = events_until_turn_end(&mut provider).await;

    let plan_update = events
        .iter()
        .find(|event| event.kind == EventKind::TurnPlanUpdated)
        .expect("TodoWrite updates the plan");
    assert_eq!(plan_update.payload["plan"][1]["content"], "Edit");
    assert_eq!(plan_update.payload["plan"][1]["status"], "in_progress");
    let proposed: Vec<_> = events
        .iter()
        .filter(|event| event.item_id.as_deref() == Some("exit-plan-tool"))
        .collect();
    assert_eq!(
        proposed.len(),
        1,
        "the denied result must not reopen the plan"
    );
    assert_eq!(proposed[0].kind, EventKind::ItemCompleted);
    assert_eq!(proposed[0].payload["itemType"], "plan");
    assert_eq!(proposed[0].payload["status"], "completed");
    assert_eq!(proposed[0].payload["data"]["text"], "1. Read\n2. Edit");
    assert!(events
        .iter()
        .all(|event| event.kind != EventKind::RequestOpened));

    tokio::task::yield_now().await;
    let writes = handle.writes.lock().unwrap();
    let reply = writes
        .iter()
        .find(|frame| {
            frame["type"] == "control_response"
                && frame["response"]["request_id"] == "exit-plan-native-id"
        })
        .expect("ExitPlanMode is answered without asking the person");
    assert_eq!(reply["response"]["response"]["behavior"], "deny");
}

#[tokio::test]
async fn exit_plan_mode_outside_alera_plan_mode_still_asks_for_approval() {
    let exit_plan_request = json!({
        "type": "control_request",
        "request_id": "exit-plan-native-id",
        "request": {
            "subtype": "can_use_tool",
            "tool_name": "ExitPlanMode",
            "input": {"plan": "steps"},
            "tool_use_id": "exit-plan-tool"
        }
    });
    let (mut provider, _handle) =
        started_provider([initialize_response(), exit_plan_request]).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "go"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
}
