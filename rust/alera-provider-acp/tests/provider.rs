use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, Provider, ProviderKind, RuntimeResponse, SessionStartInput,
    TurnInput,
};
use serde_json::json;
use std::collections::BTreeMap;
use std::time::Duration;

fn fixture() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("CARGO_BIN_EXE_acp-jsonl-fixture").unwrap())
}

fn config() -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("grok".into()),
        provider_instance_id: "test".into(),
        flavor: AcpFlavor::Grok,
        request_timeout: Duration::from_secs(1),
        ..AcpProviderConfig::default()
    }
}

#[tokio::test]
async fn session_turn_permission_and_terminal_update_round_trip() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{"resume":{}}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"native-session","update":{"sessionUpdate":"agent_message_chunk","messageId":"m1","content":{"type":"text","text":"hello"}}}}),
        json!({"jsonrpc":"2.0","id":9,"method":"session/request_permission","params":{"sessionId":"native-session","title":"Run command","subject":{"type":"command","command":"echo hi","cwd":"/tmp"},"options":[{"optionId":"once","kind":"allow_once","name":"Allow once"},{"optionId":"cancel","kind":"reject_once","name":"Reject"}]}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"native-session","update":{"sessionUpdate":"state_update","state":"idle","stopReason":"end_turn"}}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(session.native_thread_id, "native-session");
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    let delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(delta.kind, EventKind::ContentDelta);
    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::RequestOpened);
    let request_id = request.runtime_request.unwrap().request_id;
    provider
        .respond(RuntimeResponse::Approval {
            request_id,
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    let writes = provider.client().transport().writes();
    let response = writes.last().unwrap();
    assert_eq!(response["result"]["outcome"]["outcome"], "selected");
    assert_eq!(response["result"]["outcome"]["optionId"], "once");
    let resolved = provider.next_event().await.unwrap().unwrap();
    assert_eq!(resolved.kind, EventKind::RequestResolved);
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert!(terminal.turn_id.is_some());
}

#[tokio::test]
async fn prompt_response_alone_terminalizes_the_turn() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":2}}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(terminal.turn_id.as_deref(), Some(turn.turn_id.as_str()));
    assert_eq!(
        provider.session().unwrap().status,
        alera_provider_protocol::SessionStatus::Ready
    );
}

#[tokio::test]
async fn unknown_peer_request_gets_json_rpc_method_not_found() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({"jsonrpc":"2.0","id":77,"method":"future/request","params":{"x":1}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert!(matches!(event.kind, EventKind::Unknown(_)));
    assert_eq!(provider.pending_request_count(), 0);
    let response = provider
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone();
    assert_eq!(response["id"], 77);
    assert_eq!(response["error"]["code"], -32601);
}

#[tokio::test]
async fn grok_prompt_metadata_uses_logical_ids_separate_from_rpc_id() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let prompt = provider.client().transport().writes().last().unwrap();
    assert_eq!(prompt["id"], 3);
    assert_eq!(prompt["params"]["_meta"]["promptId"], turn.turn_id);
    assert_eq!(prompt["params"]["_meta"]["requestId"], turn.turn_id);
}

#[tokio::test]
async fn grok_launch_mode_does_not_use_session_config_mutation() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
    ]);
    let mut provider_config = config();
    provider_config.process.args = vec!["--permission-mode".into(), "auto".into()];
    let mut provider = AcpProvider::with_transport(transport, provider_config);
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = alera_provider_protocol::RuntimeMode::Auto;
    provider.start_session(input).await.unwrap();
    let writes = provider.client().transport().writes();
    assert!(writes
        .iter()
        .all(|write| write["method"] != "session/set_config_option"));
}

#[tokio::test]
async fn grok_session_approval_requires_the_native_session_option() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({"jsonrpc":"2.0","id":9,"method":"session/request_permission","params":{"sessionId":"native-session","subject":{"type":"command"},"options":[{"optionId":"project","kind":"allow_always","name":"Always"}]}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    let error = provider
        .respond(RuntimeResponse::Approval {
            request_id: request.runtime_request.unwrap().request_id,
            decision: ApprovalDecision::AcceptForSession,
            updated_input: None,
        })
        .await
        .unwrap_err();
    assert!(matches!(
        error,
        alera_provider_protocol::ProviderError::Validation(_)
    ));
    assert_eq!(provider.pending_request_count(), 1);
}

#[tokio::test]
async fn subprocess_handshake_resume_and_interrupt_keep_native_wire_ids() {
    let mut process = config();
    process.process.executable = fixture();
    let mut provider = AcpProvider::spawn(process.clone()).await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    let request_id = request.runtime_request.unwrap().request_id;
    provider
        .respond(RuntimeResponse::Approval {
            request_id,
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();

    let mut resumed = AcpProvider::spawn(process).await.unwrap();
    let mut input = SessionStartInput::new("resumed-thread");
    input.resume_thread_id = Some("fixture-session".into());
    resumed.start_session(input).await.unwrap();
    let _ = resumed.next_event().await.unwrap();
    resumed
        .send_turn(TurnInput::text("resumed-thread", "hello"))
        .await
        .unwrap();
    let _ = resumed.next_event().await.unwrap();
    resumed
        .interrupt(alera_provider_protocol::InterruptInput {
            thread_id: "resumed-thread".into(),
            turn_id: None,
        })
        .await
        .unwrap();
    let pending = resumed.next_event().await.unwrap().unwrap();
    let pending_id = pending.runtime_request.unwrap().request_id;
    resumed
        .respond(RuntimeResponse::Approval {
            request_id: pending_id,
            decision: ApprovalDecision::Cancel,
            updated_input: None,
        })
        .await
        .unwrap();
    let _ = resumed.next_event().await.unwrap();
    let terminal = resumed.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
}

#[tokio::test]
async fn xai_question_response_preserves_native_request_and_answer_shape() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({
            "jsonrpc":"2.0","id":10,"method":"x.ai/ask_user_question",
            "params":{"sessionId":"native-session","toolCallId":"tool-1","questions":[{"id":"choice","question":"Pick one","options":[{"label":"A","id":"a"}]}]}
        }),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "choose"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::UserInputRequested);
    assert_eq!(
        request
            .provider_refs
            .unwrap()
            .provider_request_id
            .as_deref(),
        Some("10")
    );
    let request_id = request.runtime_request.unwrap().request_id;
    provider
        .respond(RuntimeResponse::UserInput {
            request_id,
            answers: BTreeMap::from([(String::from("choice"), json!("a"))]),
        })
        .await
        .unwrap();
    let writes = provider.client().transport().writes();
    let response = writes.last().unwrap();
    assert_eq!(response["id"], 10);
    assert_eq!(response["result"]["outcome"], "accepted");
    assert_eq!(response["result"]["answers"]["Pick one"], json!(["A"]));
}

#[tokio::test]
async fn xai_prompt_completion_requires_matching_prompt_id() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({
            "jsonrpc":"2.0","method":"x.ai/session_notification",
            "params":{"sessionId":"native-session","update":{"sessionUpdate":"turn_completed","promptId":"3","stopReason":"end_turn"}}
        }),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(
        terminal.raw.unwrap().method.as_deref(),
        Some("x.ai/session_notification")
    );
}
