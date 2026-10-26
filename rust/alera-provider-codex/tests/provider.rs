use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::transport::JsonTransport;
use alera_provider_protocol::{
    ApprovalDecision, EventKind, Provider, RequestId, RuntimeResponse, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::path::PathBuf;

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

fn turn_response(id: i64, native_id: &str) -> Value {
    json!({ "id": id, "result": { "turn": { "id": native_id } } })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-test".into(),
        ..CodexProviderConfig::default()
    }
}

#[tokio::test]
async fn lifecycle_uses_initialize_before_initialized_and_preserves_native_ids() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-thread-1"),
        turn_response(3, "native-turn-1"),
        json!({ "id": 4, "result": {} }),
    ]);
    let mut provider = CodexProvider::new(transport, config());

    let session = provider
        .start_session(SessionStartInput::new("app-thread-1"))
        .await
        .unwrap();
    assert_eq!(session.thread_id, "app-thread-1");
    assert_eq!(session.native_thread_id, "native-thread-1");

    let turn = provider
        .send_turn(TurnInput::text("app-thread-1", "List files"))
        .await
        .unwrap();
    assert_eq!(turn.turn_id, "native-turn-1");
    provider
        .interrupt(alera_provider_protocol::InterruptInput {
            thread_id: "app-thread-1".into(),
            turn_id: Some("native-turn-1".into()),
        })
        .await
        .unwrap();

    let writes = provider.transport().writes();
    assert_eq!(writes[0]["method"], "initialize");
    assert!(writes[0].get("jsonrpc").is_none());
    assert_eq!(writes[1], json!({ "method": "initialized", "params": {} }));
    assert_eq!(writes[2]["method"], "thread/start");
    assert_eq!(writes[2]["id"], 2);
    assert_eq!(writes[3]["method"], "turn/start");
    assert_eq!(writes[3]["params"]["threadId"], "native-thread-1");
    assert_eq!(
        writes[4],
        json!({
            "id": 4,
            "method": "turn/interrupt",
            "params": { "threadId": "native-thread-1", "turnId": "native-turn-1" }
        })
    );
}

#[tokio::test]
async fn resume_uses_native_thread_id_and_turn_input_supports_attachments() {
    let transport = MockTransport::new([
        initialize_response(1),
        json!({ "id": 2, "result": { "thread": { "id": "native-resumed" } } }),
        turn_response(3, "native-turn-2"),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let mut input = SessionStartInput::new("app-thread-2");
    input.resume_thread_id = Some("native-resumed".into());
    input.cwd = Some(PathBuf::from("/workspace"));
    provider.start_session(input).await.unwrap();

    let mut turn = TurnInput::text("app-thread-2", "Review");
    turn.attachments
        .push(alera_provider_protocol::Attachment::Image {
            url: "https://example.test/image.png".into(),
        });
    provider.send_turn(turn).await.unwrap();

    let writes = provider.transport().writes();
    assert_eq!(writes[2]["method"], "thread/resume");
    assert_eq!(writes[2]["params"]["threadId"], "native-resumed");
    assert_eq!(
        writes[3]["params"]["input"][1],
        json!({
            "type": "image",
            "url": "https://example.test/image.png"
        })
    );
}

#[tokio::test]
async fn notifications_are_normalized_and_approval_response_keeps_integer_id() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-thread-3"),
        json!({
            "id": 77,
            "method": "item/commandExecution/requestApproval",
            "params": {
                "itemId": "item-1",
                "threadId": "native-thread-3",
                "turnId": "turn-3",
                "command": "cargo test"
            }
        }),
        json!({
            "method": "item/agentMessage/delta",
            "params": {
                "itemId": "item-1",
                "threadId": "native-thread-3",
                "turnId": "turn-3",
                "delta": "hello"
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread-3"))
        .await
        .unwrap();

    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::RequestOpened);
    assert_eq!(request.thread_id, "app-thread-3");
    assert_eq!(request.request_id.as_deref(), Some("item-1"));
    assert_eq!(
        request.runtime_request.as_ref().unwrap().request_id,
        RequestId::String("item-1".into())
    );
    assert_eq!(
        request.provider_refs.as_ref().unwrap().provider_request_id,
        Some("item-1".into())
    );
    assert_eq!(request.raw.as_ref().unwrap().payload["id"], 77);

    provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::String("item-1".into()),
            decision: ApprovalDecision::AcceptForSession,
            updated_input: None,
            feedback: None,
        })
        .await
        .unwrap();
    let delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(delta.kind, EventKind::ContentDelta);
    assert_eq!(
        delta.payload,
        json!({ "streamKind": "assistant_text", "delta": "hello" })
    );
    delta.validate().unwrap();

    let writes = provider.transport().writes();
    assert_eq!(
        writes[3],
        json!({
            "id": 77,
            "result": { "decision": "acceptForSession" }
        })
    );
}

#[tokio::test]
async fn user_input_response_uses_codex_question_map_shape() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-thread-4"),
        json!({
            "id": "input-1",
            "method": "item/tool/requestUserInput",
            "params": {
                "itemId": "item-4",
                "threadId": "native-thread-4",
                "turnId": "turn-4",
                "isBlocking": true,
                "questions": [{
                    "id": "choice",
                    "header": "Choose",
                    "question": "Which?",
                    "options": [{ "label": "A", "description": "first" }]
                }]
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread-4"))
        .await
        .unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::UserInputRequested);
    assert_eq!(request.runtime_request.unwrap().questions[0].id, "choice");

    let mut answers = std::collections::BTreeMap::new();
    answers.insert("choice".into(), json!(["A"]));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: RequestId::String("item-4".into()),
            answers,
        })
        .await
        .unwrap();
    assert_eq!(
        provider.transport().writes()[3],
        json!({
            "id": "input-1",
            "result": { "answers": { "choice": { "answers": ["A"] } } }
        })
    );
}

#[tokio::test]
async fn fake_subprocess_exercises_the_real_json_lines_boundary() {
    let mut config = config();
    config.executable = PathBuf::from(env!("CARGO_BIN_EXE_codex-app-server-fixture"));
    config.args.clear();
    let mut provider = CodexProvider::spawn(config).await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-process-thread"))
        .await
        .unwrap();
    let originator = provider.next_event().await.unwrap().unwrap();
    assert_eq!(
        originator.raw.unwrap().payload["params"]["originator"],
        "alera"
    );
    provider
        .send_turn(TurnInput::text("app-process-thread", "ping"))
        .await
        .unwrap();
    provider
        .interrupt(alera_provider_protocol::InterruptInput {
            thread_id: "app-process-thread".into(),
            turn_id: Some("native-turn-fixture".into()),
        })
        .await
        .unwrap();
    provider.close().await.unwrap();
}

#[tokio::test]
async fn explicit_originator_environment_override_wins() {
    let mut config = config();
    config.executable = PathBuf::from(env!("CARGO_BIN_EXE_codex-app-server-fixture"));
    config.args.clear();
    config.env.insert(
        std::ffi::OsString::from("CODEX_INTERNAL_ORIGINATOR_OVERRIDE"),
        std::ffi::OsString::from("custom-codex-client"),
    );
    let mut provider = CodexProvider::spawn(config).await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-process-custom-originator"))
        .await
        .unwrap();
    let originator = provider.next_event().await.unwrap().unwrap();
    assert_eq!(
        originator.raw.unwrap().payload["params"]["originator"],
        "custom-codex-client"
    );
    provider.close().await.unwrap();
}

#[allow(dead_code)]
fn _transport_is_send<T: JsonTransport + Send>() {}
