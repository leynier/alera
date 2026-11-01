//! Per-turn prompt usage for agents that report it, and live context usage
//! from `usage_update`, after T3 Code `68be2f7b32`.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderEvent, ProviderKind, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::time::Duration;

const SESSION: &str = "native";

fn v1() -> Vec<Value> {
    vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":SESSION}}),
    ]
}

fn v2() -> Vec<Value> {
    vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"info":{"name":"agent","version":"1"},"capabilities":{"session":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":SESSION}}),
    ]
}

fn update(update: Value) -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":SESSION,"update":update}})
}

fn usage() -> Value {
    json!({"inputTokens":120,"outputTokens":30,"totalTokens":150,"cachedReadTokens":20})
}

fn response(id: u64, stop_reason: &str, usage: Option<Value>) -> Value {
    let mut result = json!({"stopReason": stop_reason});
    if let Some(usage) = usage {
        result["usage"] = usage;
    }
    json!({"jsonrpc":"2.0","id":id,"result":result})
}

fn provider(frames: Vec<Value>, per_turn: bool, follows: bool) -> AcpProvider<MockTransport> {
    AcpProvider::with_transport(
        MockTransport::new(frames),
        AcpProviderConfig {
            provider: ProviderKind::Other("acpRegistry".into()),
            reports_per_turn_prompt_usage: per_turn,
            native_child_sessions: follows,
            request_timeout: Duration::from_millis(200),
            ..AcpProviderConfig::default()
        },
    )
}

/// Runs one prompt and returns its events through `turn.completed`.
async fn turn(provider: &mut AcpProvider<MockTransport>) -> Vec<ProviderEvent> {
    if provider.session().is_none() {
        provider
            .start_session(SessionStartInput::new("app"))
            .await
            .unwrap();
    }
    provider
        .send_turn(TurnInput::text("app", "hello"))
        .await
        .unwrap();
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        let ended = event.kind == EventKind::TurnCompleted;
        events.push(event);
        if ended {
            return events;
        }
    }
}

fn token_usage(events: &[ProviderEvent]) -> Option<Value> {
    events.last().unwrap().payload.get("tokenUsage").cloned()
}

#[tokio::test]
async fn agents_that_report_per_turn_usage_record_it_and_others_do_not() {
    for per_turn in [true, false] {
        let mut frames = v1();
        frames.push(response(3, "end_turn", Some(usage())));
        let mut provider = provider(frames, per_turn, false);
        let usage = token_usage(&turn(&mut provider).await);
        if per_turn {
            assert_eq!(
                usage.unwrap(),
                json!({"usageScope":"main_agent","usageStatus":"complete","hasSubagents":false,
                    "inputTokens":120,"outputTokens":30,"cachedInputTokens":20})
            );
        } else {
            assert!(usage.is_none());
        }
    }
}

#[tokio::test]
async fn a_cancelled_turns_usage_is_partial() {
    let mut frames = v1();
    frames.push(response(3, "cancelled", Some(usage())));
    let mut provider = provider(frames, true, false);
    assert_eq!(
        token_usage(&turn(&mut provider).await).unwrap()["usageStatus"],
        "partial"
    );
}

#[tokio::test]
async fn a_late_prompt_response_does_not_lend_its_usage_to_another_turn() {
    let mut frames = v2();
    frames.extend([
        update(json!({"sessionUpdate":"state_update","state":"idle","stopReason":"end_turn"})),
        response(3, "end_turn", Some(usage())),
        json!({"jsonrpc":"2.0","id":4,"result":{"messageId":"user-4"}}),
        update(json!({"sessionUpdate":"state_update","state":"idle","stopReason":"end_turn"})),
    ]);
    let mut provider = provider(frames, true, false);
    for _ in 0..2 {
        assert_eq!(
            token_usage(&turn(&mut provider).await).unwrap()["usageStatus"],
            "unavailable"
        );
    }
}

#[tokio::test]
async fn usage_updates_report_the_context_and_the_turn_repeats_it() {
    let mut frames = v1();
    frames.extend([
        update(json!({"sessionUpdate":"usage_update","used":5000,"size":200000,"cost":{"amount":0.1,"currency":"USD"}})),
        response(3, "end_turn", Some(usage())),
    ]);
    let mut provider = provider(frames, true, false);
    let events = turn(&mut provider).await;
    let context = events
        .iter()
        .find(|event| event.kind == EventKind::ThreadTokenUsageUpdated)
        .unwrap();
    assert_eq!(
        context.payload,
        json!({"contextTokens":5000,"contextWindow":200000,"cost":{"amount":0.1,"currency":"USD"}})
    );
    let usage = token_usage(&events).unwrap();
    assert_eq!(usage["contextTokens"], 5000);
    assert_eq!(usage["contextWindow"], 200000);
    assert_eq!(usage["inputTokens"], 120);
}

#[tokio::test]
async fn a_root_usage_update_reports_context_while_following_work_state() {
    let mut frames = v2();
    frames.extend([
        json!({"jsonrpc":"2.0","id":3,"result":{"messageId":"user-3"}}),
        update(json!({"sessionUpdate":"state_update","state":"running"})),
        update(json!({"sessionUpdate":"usage_update","used":42,"size":1000})),
        update(json!({"sessionUpdate":"state_update","state":"idle","stopReason":"end_turn"})),
    ]);
    let mut provider = provider(frames, false, true);
    let events = turn(&mut provider).await;
    let context = events
        .iter()
        .find(|event| event.kind == EventKind::ThreadTokenUsageUpdated)
        .expect("context usage");
    assert_eq!(
        context.payload,
        json!({"contextTokens":42,"contextWindow":1000})
    );
}
