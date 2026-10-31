//! Errors an agent reports outside the prompt RPC: ACP v2's idle
//! `state_update` (after T3 Code `012e4ec056` and `5a969c17e7`), which also
//! ends every ACP v2 prompt, and Grok's failed completions.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderEvent, ProviderKind, SessionStartInput, SessionStatus, TurnInput,
};
use serde_json::{json, Value};
use std::time::Duration;

const SESSION: &str = "native-session";

fn config(flavor: AcpFlavor) -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("acp".into()),
        provider_instance_id: "idle-errors".into(),
        flavor,
        request_timeout: Duration::from_secs(1),
        ..AcpProviderConfig::default()
    }
}

fn open(v2: bool) -> Vec<Value> {
    let initialized = if v2 {
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"info":{"name":"agent","version":"1.0.0"},"capabilities":{"session":{}},"authMethods":[]}})
    } else {
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}})
    };
    vec![
        initialized,
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":SESSION}}),
    ]
}

fn notification(method: &str, update: Value) -> Value {
    json!({"jsonrpc":"2.0","method":method,"params":{"sessionId":SESSION,"update":update}})
}

fn idle_error(error: Option<Value>) -> Value {
    let mut update = json!({"sessionUpdate":"state_update","state":"idle","stopReason":"error"});
    if let Some(error) = error {
        update["error"] = error;
    }
    notification("session/update", update)
}

async fn started(frames: Vec<Value>, flavor: AcpFlavor) -> AcpProvider<MockTransport> {
    let mut provider = AcpProvider::with_transport(MockTransport::new(frames), config(flavor));
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
}

/// Sends a prompt and reads its events up to the turn's end.
async fn turn_events(provider: &mut AcpProvider<MockTransport>) -> Vec<ProviderEvent> {
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().expect("turn end");
        let ended = event.kind == EventKind::TurnCompleted;
        events.push(event);
        if ended {
            return events;
        }
    }
}

async fn turn(provider: &mut AcpProvider<MockTransport>) -> ProviderEvent {
    turn_events(provider).await.pop().unwrap()
}

fn auth_error() -> Value {
    json!({"code":-32000,"message":"Missing Authentication header","data":{"retry":false}})
}

fn accepted(id: u64) -> Value {
    json!({"jsonrpc":"2.0","id":id,"result":{"messageId":format!("user-{id}")}})
}

fn idle(stop_reason: &str) -> Value {
    notification(
        "session/update",
        json!({"sessionUpdate":"state_update","state":"idle","stopReason":stop_reason}),
    )
}

fn kinds(events: &[ProviderEvent]) -> Vec<EventKind> {
    events.iter().map(|event| event.kind.clone()).collect()
}

fn ended_by(event: &ProviderEvent) -> Option<&str> {
    event.raw.as_ref().and_then(|raw| raw.method.as_deref())
}

#[tokio::test]
async fn idle_errors_fail_the_turn_and_the_next_prompt_runs() {
    let detailed =
        json!({"code":-32000,"message":"Missing Authentication header","data":{"retry":false}});
    for error in [Some(detailed), None] {
        let mut frames = open(true);
        frames.extend([
            idle_error(error.clone()),
            json!({"jsonrpc":"2.0","id":4,"result":{"stopReason":"end_turn"}}),
        ]);
        let mut provider = started(frames, AcpFlavor::Generic).await;
        let failed = turn(&mut provider).await;
        assert_eq!(failed.payload["state"], "failed");
        if error.is_some() {
            assert_eq!(
                failed.payload["errorMessage"],
                "Missing Authentication header"
            );
            assert_eq!(
                failed.payload["error"],
                json!({"code":-32000,"data":{"retry":false}})
            );
        } else {
            assert!(failed.payload["errorMessage"].is_null());
            assert!(failed.payload.get("error").is_none());
        }
        let next = turn(&mut provider).await;
        assert_eq!(next.payload["state"], "completed");
    }
}

#[tokio::test]
async fn grok_failed_completions_carry_their_agent_result() {
    let failure = "API error (status 400 Bad Request): invalid_request_error";
    let mut frames = open(false);
    frames.extend([
        // T3 Code's grok_prompt_error transcript: the completion, then the
        // prompt_complete and RPC error for the prompt it already ended.
        notification(
            "_x.ai/session_notification",
            json!({"sessionUpdate":"turn_completed","prompt_id":"3","stop_reason":"error","agent_result":failure}),
        ),
        json!({"jsonrpc":"2.0","method":"_x.ai/session/prompt_complete","params":{"sessionId":SESSION,"promptId":"3","stopReason":"error","agentResult":failure}}),
        json!({"jsonrpc":"2.0","id":3,"error":{"code":-32603,"message":"Internal error","data":{"message":failure}}}),
        json!({"jsonrpc":"2.0","method":"_x.ai/session/prompt_complete","params":{"sessionId":SESSION,"promptId":"4","stopReason":"error","agentResult":format!("  {failure} ")}}),
        notification(
            "_x.ai/session_notification",
            json!({"sessionUpdate":"turn_completed","prompt_id":"5","stop_reason":"error","agent_result":"   "}),
        ),
        notification(
            "_x.ai/session_notification",
            json!({"sessionUpdate":"turn_completed","prompt_id":"6","stop_reason":"end_turn","agent_result":"Done."}),
        ),
    ]);
    let mut provider = started(frames, AcpFlavor::Grok).await;
    for expected in [Some(failure), Some(failure), None] {
        let failed = turn(&mut provider).await;
        assert_eq!(failed.payload["state"], "failed");
        assert_eq!(failed.payload["errorMessage"].as_str(), expected);
    }
    let completed = turn(&mut provider).await;
    assert_eq!(completed.payload["state"], "completed");
    assert_eq!(completed.payload["result"], "Done.");
    assert!(completed.payload["errorMessage"].is_null());
}

#[tokio::test]
async fn v2_prompt_acceptance_waits_for_the_idle_error() {
    let mut frames = open(true);
    frames.extend([
        accepted(3),
        notification(
            "session/update",
            json!({"sessionUpdate":"tool_call","toolCallId":"t1","title":"Terminal","kind":"execute","status":"in_progress"}),
        ),
        idle_error(Some(auth_error())),
        accepted(4),
        idle("end_turn"),
    ]);
    let mut provider = started(frames, AcpFlavor::Generic).await;
    let events = turn_events(&mut provider).await;
    assert_eq!(
        kinds(&events),
        [
            EventKind::TurnStarted,
            EventKind::Unknown("acp.prompt.accepted".into()),
            EventKind::ItemStarted,
            EventKind::TurnCompleted,
        ]
    );
    let failed = events.last().unwrap();
    assert_eq!(failed.payload["state"], "failed");
    assert_eq!(
        failed.payload["errorMessage"],
        "Missing Authentication header"
    );
    assert_eq!(ended_by(failed), Some("session/update"));
    assert_eq!(provider.session().unwrap().status, SessionStatus::Ready);

    let next = turn_events(&mut provider).await;
    assert_eq!(next.len(), 3, "accepted, then ended by its idle");
    assert_eq!(next[2].payload["state"], "completed");
    assert!(provider.next_event().await.unwrap().is_none());
}

#[tokio::test]
async fn v2_prompt_responses_that_end_the_turn_keep_their_late_idle_out_of_the_next() {
    let rpc_error = json!({"jsonrpc":"2.0","id":3,"error":auth_error()});
    let stopped = json!({"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}});
    for (response, late_idle, state) in [
        (stopped, idle("end_turn"), "completed"),
        (rpc_error, idle_error(Some(auth_error())), "failed"),
    ] {
        let mut frames = open(true);
        frames.extend([
            response,
            late_idle,
            accepted(4),
            notification(
                "session/update",
                json!({"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Done."}}),
            ),
            idle("end_turn"),
        ]);
        let mut provider = started(frames, AcpFlavor::Generic).await;
        let first = turn(&mut provider).await;
        assert_eq!(first.payload["state"], state);
        assert_eq!(ended_by(&first), Some("session/prompt"));

        let next = turn_events(&mut provider).await;
        assert_eq!(
            kinds(&next),
            [
                EventKind::TurnStarted,
                EventKind::ThreadStateChanged,
                EventKind::Unknown("acp.prompt.accepted".into()),
                EventKind::ContentDelta,
                EventKind::TurnCompleted,
            ],
            "the late idle neither ends nor fails the next turn"
        );
        assert_eq!(next[4].payload["state"], "completed");
        assert!(provider.next_event().await.unwrap().is_none());
    }
}

#[tokio::test]
async fn turnless_idle_errors_are_notices_unless_they_repeat_a_failed_turn() {
    let mut frames = open(true);
    frames.extend([idle_error(Some(auth_error())), idle_error(None)]);
    let mut provider = started(frames, AcpFlavor::Generic).await;
    let notice = provider.next_event().await.unwrap().unwrap();
    assert_eq!(notice.kind, EventKind::RuntimeError);
    assert_eq!(
        notice.payload,
        json!({"message":"Missing Authentication header","code":-32000,"data":{"retry":false}})
    );
    assert!(notice.turn_id.is_none());
    let unexplained = provider.next_event().await.unwrap().unwrap();
    assert_eq!(unexplained.kind, EventKind::ThreadStateChanged);

    let mut frames = open(true);
    frames.extend([
        json!({"jsonrpc":"2.0","id":3,"error":auth_error()}),
        idle_error(Some(auth_error())),
    ]);
    let mut provider = started(frames, AcpFlavor::Generic).await;
    let failed = turn(&mut provider).await;
    assert_eq!(failed.payload["state"], "failed");
    let repeated = provider.next_event().await.unwrap().unwrap();
    assert_eq!(repeated.kind, EventKind::ThreadStateChanged);
}
