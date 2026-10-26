mod support;

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    Attachment, InteractionMode, Provider, ProviderError, RuntimeMode, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};

fn initialize_response(id: i64) -> Value {
    json!({
        "id": id,
        "result": {
            "codexHome": "/tmp/codex",
            "platformFamily": "unix",
            "platformOs": "linux",
            "userAgent": "test",
        }
    })
}

fn thread_response(id: i64, native_id: &str) -> Value {
    json!({ "id": id, "result": { "thread": { "id": native_id } } })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-regression".into(),
        ..CodexProviderConfig::default()
    }
}

#[tokio::test]
async fn runtime_mode_maps_exact_thread_and_turn_policy_shapes() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-policy"),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn-policy" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let mut session_input = SessionStartInput::new("app-policy");
    session_input.model = Some("gpt-5".into());
    session_input.runtime_mode = RuntimeMode::FullAccess;
    provider.start_session(session_input).await.unwrap();
    provider
        .send_turn(TurnInput::text("app-policy", "run"))
        .await
        .unwrap();

    let writes = provider.transport().writes();
    assert_eq!(writes[2]["params"]["approvalPolicy"], "never");
    assert_eq!(writes[2]["params"]["sandbox"], "danger-full-access");
    assert_eq!(writes[2]["params"]["approvalsReviewer"], "user");
    assert_eq!(writes[3]["params"]["approvalPolicy"], "never");
    assert_eq!(writes[3]["params"]["approvalsReviewer"], "user");
    assert_eq!(
        writes[3]["params"]["sandboxPolicy"],
        json!({ "type": "dangerFullAccess" })
    );
}

#[tokio::test]
async fn plan_turn_includes_required_collaboration_settings() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-plan"),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn-plan" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let mut session_input = SessionStartInput::new("app-plan");
    session_input.model = Some("gpt-5".into());
    provider.start_session(session_input).await.unwrap();
    let mut turn = TurnInput::text("app-plan", "plan");
    turn.interaction_mode = InteractionMode::Plan;
    provider.send_turn(turn).await.unwrap();
    assert_eq!(
        provider.transport().writes()[3]["params"]["collaborationMode"],
        json!({
            "mode": "plan",
            "settings": { "model": "gpt-5" }
        })
    );
}

#[tokio::test]
async fn every_turn_states_its_collaboration_mode_so_leaving_plan_resets_it() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-mode"),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn-plan" } } }),
        json!({ "method": "turn/completed", "params": { "threadId": "native-mode", "turn": { "id": "native-turn-plan", "status": "completed" } } }),
        json!({ "id": 4, "result": { "turn": { "id": "native-turn-default" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let mut session_input = SessionStartInput::new("app-mode");
    session_input.model = Some("gpt-6-astra".into());
    provider.start_session(session_input).await.unwrap();
    let mut plan = TurnInput::text("app-mode", "plan");
    plan.interaction_mode = InteractionMode::Plan;
    provider.send_turn(plan).await.unwrap();
    while support::next_event(&mut provider)
        .await
        .unwrap()
        .is_some_and(|event| {
            !matches!(
                event.kind,
                alera_provider_protocol::EventKind::TurnCompleted
            )
        })
    {}
    provider
        .send_turn(TurnInput::text("app-mode", "build"))
        .await
        .unwrap();
    let writes = provider.transport().writes();
    let modes: Vec<_> = writes
        .iter()
        .filter(|write| write["method"] == "turn/start")
        .map(|write| write["params"]["collaborationMode"].clone())
        .collect();
    assert_eq!(
        modes,
        vec![
            json!({ "mode": "plan", "settings": { "model": "gpt-6-astra", "reasoning_effort": "medium" } }),
            json!({ "mode": "default", "settings": { "model": "gpt-6-astra", "reasoning_effort": "medium" } }),
        ]
    );
}

#[tokio::test]
async fn default_turn_without_a_model_omits_collaboration_mode() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-unknown"),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-unknown"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app-unknown", "hi"))
        .await
        .unwrap();
    assert!(provider.transport().writes()[3]["params"]
        .get("collaborationMode")
        .is_none());
}

#[tokio::test]
async fn unsupported_file_attachment_fails_before_turn_start() {
    let transport = MockTransport::new([initialize_response(1), thread_response(2, "native-file")]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-file"))
        .await
        .unwrap();
    let mut turn = TurnInput::text("app-file", "attach");
    turn.attachments.push(Attachment::File {
        path: "/tmp/file.txt".into(),
    });
    assert!(matches!(
        provider.send_turn(turn).await,
        Err(ProviderError::Unsupported(_))
    ));
    assert_eq!(provider.transport().writes().len(), 3);
}
