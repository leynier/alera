//! ACP v2 native child sessions, with Claude Agent's frames (after T3 Code's
//! Claude lifecycle fixtures).

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderKind, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::time::Duration;

const ROOT: &str = "root-session";

fn config(native_child_sessions: bool) -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("acpRegistry".into()),
        provider_instance_id: "claude-acp".into(),
        flavor: AcpFlavor::Registry,
        request_timeout: Duration::from_secs(1),
        native_child_sessions,
        ..AcpProviderConfig::default()
    }
}

fn open_v2() -> Vec<Value> {
    vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"info":{"name":"@agentclientprotocol/claude-agent-acp","version":"0.90.0"},"capabilities":{"session":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":ROOT}}),
    ]
}

fn update(session: &str, update: Value) -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":session,"update":update}})
}

fn child_state(parent: &str, child: &str, state: &str) -> Value {
    update(
        parent,
        json!({"sessionUpdate":"subagent_update","sessionId":child,"state":{"state":state}}),
    )
}

fn chunk(session: &str, message: &str, text: &str) -> Value {
    update(
        session,
        json!({"sessionUpdate":"agent_message_chunk","messageId":message,"content":{"type":"text","text":text}}),
    )
}

fn delegation(child: &str, sender: &str, message: &str, text: &str) -> Value {
    update(
        child,
        json!({"sessionUpdate":"session_message","messageId":message,"senderSessionId":sender,"recipientSessionId":child,"content":[{"type":"text","text":text}]}),
    )
}

fn state(session: &str, state: &str, stop_reason: Option<&str>) -> Value {
    let mut update_value = json!({"sessionUpdate":"state_update","state":state});
    if let Some(reason) = stop_reason {
        update_value["stopReason"] = json!(reason);
    }
    update(session, update_value)
}

fn agent_call(id: &str) -> Value {
    update(
        ROOT,
        json!({"sessionUpdate":"tool_call_update","toolCallId":id,"name":"Agent","title":"Review","kind":"think","status":"in_progress","rawInput":{"prompt":"Review the code","description":"Review","run_in_background":true}}),
    )
}

fn accepted() -> Value {
    json!({"jsonrpc":"2.0","id":3,"result":{"messageId":"user-1"}})
}

async fn started(frames: Vec<Value>) -> AcpProvider<MockTransport> {
    let mut provider = AcpProvider::with_transport(MockTransport::new(frames), config(true));
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
        .send_turn(TurnInput::text("app-thread", "review"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    provider
}

async fn drain(provider: &mut AcpProvider<MockTransport>) -> Vec<ProviderEvent> {
    let mut events = Vec::new();
    while let Ok(Some(event)) = provider.next_event().await {
        events.push(event);
    }
    events
}

fn kinds<'a>(events: &'a [ProviderEvent], kind: &EventKind) -> Vec<&'a ProviderEvent> {
    events.iter().filter(|event| &event.kind == kind).collect()
}

#[tokio::test]
async fn child_session_streams_under_its_agent_call_and_resumes_the_root() {
    let mut frames = open_v2();
    frames.extend([
        accepted(),
        state(ROOT, "running", None),
        agent_call("agent-1"),
        child_state(ROOT, "child-1", "running"),
        chunk("child-1", "early", "Reading."),
        delegation("child-1", ROOT, "agent-1", "Review the code"),
        child_state("unknown-parent", "unrelated-child", "running"),
        delegation("unrelated-child", "unknown-parent", "agent-1", "Unrelated"),
        chunk("unlinked-child", "unlinked", "Unlinked output"),
        update(
            "child-1",
            json!({"sessionUpdate":"tool_call","toolCallId":"t1","title":"Run tests","kind":"execute","status":"in_progress"}),
        ),
        update(
            "child-1",
            json!({"sessionUpdate":"usage_update","used":2500,"size":10000}),
        ),
        chunk(ROOT, "reply", "The review is running."),
        state(ROOT, "idle", Some("end_turn")),
        chunk("child-1", "final", "Found the regression."),
        state("child-1", "idle", Some("end_turn")),
        child_state(ROOT, "child-1", "idle"),
        state(ROOT, "running", None),
        chunk(ROOT, "wake", "Fixing it."),
        state(ROOT, "idle", Some("end_turn")),
    ]);
    let mut provider = started(frames).await;
    let events = drain(&mut provider).await;

    let starts = kinds(&events, &EventKind::TaskStarted);
    assert_eq!(starts.len(), 1, "one child, linked once");
    let start = &starts[0].payload;
    assert_eq!(start["taskId"], "agent-1");
    assert_eq!(start["awaited"], true);
    assert_eq!(start["description"], "Review");
    assert_eq!(start["nativeTask"]["nativeToolCallId"], "agent-1");
    assert_eq!(
        start["nativeTask"]["childNativeThreadIds"],
        json!(["child-1"])
    );

    let child_items: Vec<_> = events
        .iter()
        .filter(|event| event.payload.get("parentToolUseId") == Some(&json!("agent-1")))
        .collect();
    let ids: Vec<_> = child_items
        .iter()
        .map(|event| event.item_id.as_deref().unwrap())
        .collect();
    assert_eq!(ids, ["child-1/early", "child-1/t1", "child-1/final"]);
    assert!(
        events.iter().all(|event| {
            event.payload.get("delta") != Some(&json!("Unlinked output"))
                && event.payload.get("delta") != Some(&json!("Unrelated"))
        }),
        "unrelated and unlinked children stay out of the chat"
    );
    assert!(events
        .iter()
        .all(|event| event.kind != EventKind::ThreadTokenUsageUpdated));

    let completed = kinds(&events, &EventKind::TaskCompleted);
    assert_eq!(completed.len(), 1, "the child's own idle settles it once");
    assert_eq!(completed[0].payload["status"], "completed");
    assert_eq!(completed[0].payload["summary"], "Found the regression.");

    let turns = kinds(&events, &EventKind::TurnCompleted);
    assert_eq!(
        turns.len(),
        2,
        "the accepted prompt ends on idle, not on its response"
    );
    let wake = kinds(&events, &EventKind::TurnStarted);
    assert_eq!(wake.len(), 1);
    assert_eq!(
        wake[0].agent_started_turn_origin(),
        Some("backgroundContinuation")
    );
    assert_eq!(wake[0].turn_id, turns[1].turn_id);
    let fixing = events
        .iter()
        .find(|event| event.payload.get("delta") == Some(&json!("Fixing it.")))
        .unwrap();
    assert_eq!(fixing.turn_id, wake[0].turn_id);
    assert!(provider.subagent_capabilities().native_child_sessions);
}

#[tokio::test]
async fn stale_idle_before_acceptance_keeps_the_turn() {
    let mut frames = open_v2();
    frames.extend([
        state(ROOT, "idle", Some("end_turn")),
        accepted(),
        state(ROOT, "idle", Some("end_turn")),
    ]);
    let mut provider = started(frames).await;
    let events = drain(&mut provider).await;
    let turns = kinds(&events, &EventKind::TurnCompleted);
    assert_eq!(turns.len(), 1);
    assert_eq!(events.last().unwrap().kind, EventKind::TurnCompleted);
}

#[tokio::test]
async fn a_later_delegation_runs_the_child_again_with_its_prompt() {
    let mut frames = open_v2();
    frames.extend([
        accepted(),
        agent_call("agent-1"),
        child_state(ROOT, "child-1", "running"),
        delegation("child-1", ROOT, "agent-1", "Review the code"),
        state("child-1", "idle", Some("end_turn")),
        delegation("child-1", ROOT, "send-1", "Also check the docs"),
        state("child-1", "running", None),
        chunk("child-1", "again", "Docs are stale."),
        state("child-1", "idle", Some("error")),
    ]);
    let mut provider = started(frames).await;
    let events = drain(&mut provider).await;
    assert_eq!(kinds(&events, &EventKind::TaskStarted).len(), 2);
    let prompt = events
        .iter()
        .find(|event| event.item_id.as_deref() == Some("child-1/prompt:send-1"))
        .unwrap();
    assert_eq!(prompt.kind, EventKind::ItemCompleted);
    assert_eq!(prompt.payload["itemType"], "user_message");
    assert_eq!(prompt.payload["data"]["text"], "Also check the docs");
    assert_eq!(prompt.payload["parentToolUseId"], "agent-1");
    let completed = kinds(&events, &EventKind::TaskCompleted);
    assert_eq!(completed.len(), 2);
    assert_eq!(completed[1].payload["status"], "failed");
    assert_eq!(completed[1].payload["summary"], "Docs are stale.");
}

#[tokio::test]
async fn a_failed_root_turn_leaves_working_children_running() {
    let mut frames = open_v2();
    frames.extend([
        accepted(),
        agent_call("agent-1"),
        child_state(ROOT, "child-1", "running"),
        delegation("child-1", ROOT, "agent-1", "Review the code"),
        update(
            ROOT,
            json!({"sessionUpdate":"state_update","state":"idle","stopReason":"error","error":{"code":-32603,"message":"API Error: 529 overloaded"}}),
        ),
    ]);
    let mut provider = started(frames).await;
    let events = drain(&mut provider).await;
    let turn = kinds(&events, &EventKind::TurnCompleted)[0];
    assert_eq!(turn.payload["state"], "failed");
    assert_eq!(turn.payload["childTurnsContinue"], true);
    assert_eq!(turn.payload["errorMessage"], "API Error: 529 overloaded");
}

#[tokio::test]
async fn stopping_a_child_cancels_only_its_session() {
    let mut frames = open_v2();
    frames.extend([
        accepted(),
        agent_call("agent-1"),
        child_state(ROOT, "child-1", "running"),
        delegation("child-1", ROOT, "agent-1", "Review the code"),
    ]);
    let mut provider = started(frames).await;
    // Read up to the link; the agent stays open for the cancel.
    for _ in 0..4 {
        provider.next_event().await.unwrap().unwrap();
    }
    assert!(provider.subagent_capabilities().stop);
    assert!(matches!(
        provider.stop_subagent("stranger").await,
        Err(ProviderError::Validation(_))
    ));
    provider.stop_subagent("agent-1").await.unwrap();
    let cancel = provider
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone();
    assert_eq!(cancel["method"], "session/cancel");
    assert_eq!(cancel["params"]["sessionId"], "child-1");
}

#[tokio::test]
async fn agents_without_native_children_keep_todays_lifecycle() {
    for (native, v1) in [(false, false), (true, true)] {
        let mut frames = if v1 {
            vec![
                json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}}),
                json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":ROOT}}),
            ]
        } else {
            open_v2()
        };
        frames.extend([
            child_state(ROOT, "child-1", "running"),
            delegation("child-1", ROOT, "agent-1", "Review the code"),
            chunk("child-1", "m", "child text"),
            json!({"jsonrpc":"2.0","id":3,"result":{}}),
        ]);
        let mut provider = AcpProvider::with_transport(MockTransport::new(frames), config(native));
        provider
            .start_session(SessionStartInput::new("app-thread"))
            .await
            .unwrap();
        provider
            .send_turn(TurnInput::text("app-thread", "review"))
            .await
            .unwrap();
        let events = drain(&mut provider).await;
        assert!(kinds(&events, &EventKind::TaskStarted).is_empty());
        assert!(events
            .iter()
            .all(|event| event.payload.get("parentToolUseId").is_none()));
        assert_eq!(events.last().unwrap().kind, EventKind::TurnCompleted);
        assert!(!provider.subagent_capabilities().stop);
        assert!(matches!(
            provider.stop_subagent("agent-1").await,
            Err(ProviderError::Unsupported(_))
        ));
    }
}

#[tokio::test]
async fn a_childs_own_sub_agent_nests_under_the_childs_call() {
    let mut frames = open_v2();
    frames.extend([
        accepted(),
        agent_call("agent-1"),
        child_state(ROOT, "child-1", "running"),
        delegation("child-1", ROOT, "agent-1", "Review the code"),
        update(
            "child-1",
            json!({"sessionUpdate":"tool_call","toolCallId":"agent-2","name":"Agent","title":"Deep","kind":"think","status":"in_progress","rawInput":{"prompt":"Dig deeper","description":"Deep"}}),
        ),
        child_state("child-1", "grandchild", "running"),
        delegation("grandchild", "child-1", "agent-2", "Dig deeper"),
        chunk("grandchild", "g", "Deep result"),
        state("grandchild", "idle", Some("end_turn")),
    ]);
    let mut provider = started(frames).await;
    let events = drain(&mut provider).await;
    let call = events
        .iter()
        .find(|event| event.item_id.as_deref() == Some("child-1/agent-2"))
        .unwrap();
    assert_eq!(call.payload["parentToolUseId"], "agent-1");
    let starts = kinds(&events, &EventKind::TaskStarted);
    let nested = starts
        .iter()
        .find(|event| event.payload["taskId"] == "child-1/agent-2")
        .unwrap();
    assert_eq!(nested.payload["parentTaskId"], "agent-1");
    assert_eq!(nested.payload["description"], "Deep");
    let answer = events
        .iter()
        .find(|event| event.item_id.as_deref() == Some("grandchild/g"))
        .unwrap();
    assert_eq!(answer.payload["parentToolUseId"], "child-1/agent-2");
    let done = kinds(&events, &EventKind::TaskCompleted);
    assert_eq!(done[0].payload["taskId"], "child-1/agent-2");
    assert_eq!(done[0].payload["summary"], "Deep result");
}
