mod support;

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::*;
use serde_json::{json, Value};

fn initialize() -> Value {
    json!({"id":1,"result":{}})
}
fn thread(history: &str) -> Value {
    json!({"id":2,"result":{"thread":{"id":"native","historyMode":history}}})
}
fn turn() -> Value {
    json!({"id":3,"result":{"turn":{"id":"native-turn"}}})
}

async fn active(incoming: impl IntoIterator<Item = Value>) -> CodexProvider<MockTransport> {
    let frames = [initialize(), thread("legacy"), turn()]
        .into_iter()
        .chain(incoming);
    let mut provider =
        CodexProvider::new(MockTransport::new(frames), CodexProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app", "first"))
        .await
        .unwrap();
    provider
}

#[tokio::test]
async fn steer_uses_exact_native_turn_and_keeps_it_active() {
    let mut provider = active([json!({"id":4,"result":{"turnId":"native-turn"}})]).await;
    provider
        .steer_turn(TurnInput::text("app", "follow up"), "native-turn")
        .await
        .unwrap();
    assert!(provider.capabilities().steer);
    assert_eq!(
        provider.transport().writes()[4],
        json!({"id":4,"method":"turn/steer","params":{"threadId":"native","expectedTurnId":"native-turn","input":[{"type":"text","text":"follow up"}]}})
    );
    assert_eq!(
        provider.session().unwrap().active_turn_id.as_deref(),
        Some("native-turn")
    );
}

#[tokio::test]
async fn stale_turn_and_attempted_wire_override_never_write() {
    let mut provider = active([]).await;
    let writes = provider.transport().writes().len();
    assert!(matches!(
        provider
            .steer_turn(TurnInput::text("app", "stale"), "other-turn")
            .await,
        Err(ProviderError::InvalidState(_))
    ));
    let mut injected = TurnInput::text("app", "override");
    injected
        .options
        .insert("expectedTurnId".into(), json!("other-turn"));
    assert!(matches!(
        provider.steer_turn(injected, "native-turn").await,
        Err(ProviderError::Unsupported(_))
    ));
    assert_eq!(provider.transport().writes().len(), writes);
}

#[tokio::test]
async fn steer_request_id_collision_retains_callback_and_correlates_response() {
    let mut provider = active([
        json!({"id":4,"method":"item/commandExecution/requestApproval","params":{"threadId":"native","turnId":"native-turn","itemId":"approval"}}),
        json!({"id":4,"result":{"turnId":"native-turn"}}),
    ]).await;
    provider
        .steer_turn(TurnInput::text("app", "follow up"), "native-turn")
        .await
        .unwrap();
    let event = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    let request = event.runtime_request.unwrap();
    provider
        .respond(RuntimeResponse::Approval {
            request_id: request.request_id,
            decision: ApprovalDecision::Accept,
            updated_input: None,
            feedback: None,
        })
        .await
        .unwrap();
    assert_eq!(provider.transport().writes().last().unwrap()["id"], 4);
}

#[tokio::test]
async fn failed_or_wrong_acknowledgement_cannot_report_steer_success() {
    let mut provider = active([json!({"id":4,"error":{"code":-32602,"message":"expected turn mismatch","data":{"activeTurnId":"another"}}})]).await;
    assert!(matches!(
        provider
            .steer_turn(TurnInput::text("app", "follow up"), "native-turn")
            .await,
        Err(ProviderError::Rpc { code: -32602, .. })
    ));
    assert_eq!(
        provider.session().unwrap().active_turn_id.as_deref(),
        Some("native-turn")
    );
    let mut provider = active([json!({"id":4,"result":{"turnId":"wrong"}})]).await;
    assert!(matches!(
        provider
            .steer_turn(TurnInput::text("app", "follow up"), "native-turn")
            .await,
        Err(ProviderError::Protocol(_))
    ));
}

#[tokio::test]
async fn native_fork_uses_inclusive_turn_boundary_and_a_fresh_identity() {
    let transport = MockTransport::new([
        initialize(),
        json!({"id":2,"result":{"thread":{"id":"forked-native","historyMode":"paginated"}}}),
    ]);
    let mut provider = CodexProvider::new(transport, CodexProviderConfig::default());
    let result = provider
        .fork_session(NativeForkInput {
            source_native_thread_id: "source-native".into(),
            session: SessionStartInput::new("target-app"),
            boundary: Some(NativeForkBoundary::Turn("last-included-native-turn".into())),
        })
        .await
        .unwrap();
    assert_eq!(result.native_thread_id.as_deref(), Some("forked-native"));
    let wire = &provider.transport().writes()[2];
    assert_eq!(wire["method"], "thread/fork");
    assert_eq!(wire["params"]["threadId"], "source-native");
    assert_eq!(wire["params"]["lastTurnId"], "last-included-native-turn");
    assert_eq!(provider.session().unwrap().thread_id, "target-app");
}

#[tokio::test]
async fn native_rollback_maps_legacy_count_and_paginated_exclusive_boundary() {
    for (history, boundary, method, field, value) in [
        (
            "legacy",
            NativeRollbackBoundary::RemoveTurns(2),
            "thread/rollback",
            "numTurns",
            json!(2),
        ),
        (
            "paginated",
            NativeRollbackBoundary::BeforeTurn("first-removed".into()),
            "thread/revert",
            "beforeTurnId",
            json!("first-removed"),
        ),
    ] {
        let transport = MockTransport::new([
            initialize(),
            thread(history),
            json!({"id":3,"result":{"thread":{"id":"native"}}}),
        ]);
        let mut provider = CodexProvider::new(transport, CodexProviderConfig::default());
        provider
            .start_session(SessionStartInput::new("app"))
            .await
            .unwrap();
        let result = provider
            .rollback_session(NativeRollbackInput {
                thread_id: "app".into(),
                boundary: boundary.clone(),
            })
            .await
            .unwrap();
        let wire = &provider.transport().writes()[3];
        assert_eq!(wire["method"], method);
        assert_eq!(wire["params"][field], value);
        assert_eq!(result.boundary, boundary);
    }
}

#[tokio::test]
async fn paginated_history_rejects_legacy_count_without_native_mutation() {
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize(), thread("paginated")]),
        CodexProviderConfig::default(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    assert!(matches!(
        provider
            .rollback_session(NativeRollbackInput {
                thread_id: "app".into(),
                boundary: NativeRollbackBoundary::RemoveTurns(1)
            })
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    assert_eq!(provider.transport().writes().len(), 3);
}

#[tokio::test]
async fn reasoning_effort_maps_session_turn_and_plan_without_overriding_selection() {
    let mut provider = CodexProvider::new(
        MockTransport::new([initialize(), thread("legacy"), turn()]),
        CodexProviderConfig::default(),
    );
    let mut session = SessionStartInput::new("app");
    session.model = Some("model".into());
    session
        .options
        .insert("reasoningEffort".into(), json!("low"));
    provider.start_session(session).await.unwrap();
    let mut turn = TurnInput::text("app", "plan");
    turn.interaction_mode = InteractionMode::Plan;
    turn.options.insert("reasoningEffort".into(), json!("high"));
    provider.send_turn(turn).await.unwrap();
    let writes = provider.transport().writes();
    assert_eq!(
        writes[2]["params"]["config"]["model_reasoning_effort"],
        "low"
    );
    assert!(writes[2]["params"].get("reasoningEffort").is_none());
    assert_eq!(writes[3]["params"]["effort"], "high");
    assert_eq!(
        writes[3]["params"]["collaborationMode"]["settings"]["reasoning_effort"],
        "high"
    );
    assert!(writes[3]["params"].get("reasoningEffort").is_none());
}

#[tokio::test]
async fn conflicting_effort_is_rejected_before_startup() {
    let mut provider = CodexProvider::new(MockTransport::new([]), CodexProviderConfig::default());
    let mut session = SessionStartInput::new("app");
    session
        .options
        .insert("reasoningEffort".into(), json!("high"));
    session
        .options
        .insert("config".into(), json!({"model_reasoning_effort":"low"}));
    assert!(matches!(
        provider.start_session(session).await,
        Err(ProviderError::Validation(_))
    ));
    assert!(provider.transport().writes().is_empty());
}

#[tokio::test]
async fn child_thread_completion_is_task_lineage_and_does_not_complete_parent() {
    let mut provider = active([
        json!({"method":"thread/started","params":{"thread":{"id":"child-native","source":{"subAgent":{"thread_spawn":{"parent_thread_id":"native","depth":1}}}}}}),
        json!({"method":"turn/completed","params":{"threadId":"child-native","turn":{"id":"child-turn","status":"completed"}}}),
    ]).await;
    let started = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(started.kind, EventKind::TaskStarted);
    assert_eq!(started.thread_id, "app");
    let task = started.native_task().unwrap().unwrap();
    assert_eq!(task.child_native_thread_ids, vec!["child-native"]);
    assert!(task.native_task_id.is_none());
    let completed = support::next_event(&mut provider).await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TaskCompleted);
    assert_eq!(
        completed.provider_refs.unwrap().provider_turn_id.as_deref(),
        Some("child-turn")
    );
    assert_eq!(
        provider.session().unwrap().active_turn_id.as_deref(),
        Some("native-turn")
    );
}
