use alera_agent_transport::MockTransport;
use alera_provider_grok::{GrokProvider, GrokProviderConfig};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};
use serde_json::json;

#[tokio::test]
async fn launch_mode_mismatch_is_rejected_before_initialize() {
    let transport = MockTransport::new([]);
    let config = GrokProviderConfig {
        runtime_mode: alera_provider_protocol::RuntimeMode::FullAccess,
        ..Default::default()
    };
    let mut provider = GrokProvider::with_transport(transport, config).expect("valid config");
    let error = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .expect_err("approval mode cannot be served by always-approve process");
    assert!(matches!(
        error,
        alera_provider_protocol::ProviderError::Unsupported(_)
    ));
    assert!(provider.inner().client().transport().writes().is_empty());
}

#[tokio::test]
async fn matching_full_access_launch_mode_maps_native_mode() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "authMethods":[]
            }
        }),
        json!({
            "jsonrpc":"2.0",
            "id":2,
            "result":{
                "sessionId":"grok-session",
                "configOptions":[{"id":"mode","type":"select","currentValue":"default","options":[]}]
            }
        }),
        json!({"jsonrpc":"2.0","id":3,"result":{}}),
    ]);
    let config = GrokProviderConfig {
        runtime_mode: alera_provider_protocol::RuntimeMode::FullAccess,
        ..Default::default()
    };
    let mut provider = GrokProvider::with_transport(transport, config).expect("valid config");
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = alera_provider_protocol::RuntimeMode::FullAccess;
    provider.start_session(input).await.expect("session");
    let writes = provider.inner().client().transport().writes();
    assert!(writes
        .iter()
        .all(|write| write["params"]["configId"] != "mode"));
}

#[tokio::test]
async fn provider_delegates_acp_handshake_session_turn_and_request() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "authMethods":[]
            }
        }),
        json!({
            "jsonrpc":"2.0",
            "id":2,
            "result":{
                "sessionId":"grok-session",
                "configOptions":[
                    {"id":"model","type":"select","currentValue":"default","options":[]},
                    {"id":"mode","type":"select","currentValue":"default","options":[]}
                ]
            }
        }),
        json!({"jsonrpc":"2.0","id":3,"result":{}}),
        json!({
            "jsonrpc":"2.0","id":4,"method":"session/request_permission",
            "params":{"subject":{"type":"command","toolCallId":"tool-1"},"options":[{"kind":"allow_once","optionId":"yes"}]}
        }),
    ]);
    let config = GrokProviderConfig {
        model: Some("grok-4".into()),
        runtime_mode: alera_provider_protocol::RuntimeMode::ApprovalRequired,
        ..Default::default()
    };
    let mut provider = GrokProvider::with_transport(transport, config).expect("valid config");
    let mut input = SessionStartInput::new("app-thread");
    input.resume_thread_id = Some("grok-session".into());
    let session = provider.start_session(input).await.expect("session");
    assert_eq!(session.native_thread_id, "grok-session");
    assert_eq!(session.model.as_deref(), Some("grok-4"));
    assert!(provider
        .inner()
        .client()
        .transport()
        .writes()
        .iter()
        .all(|write| write["params"]["configId"] != "mode"));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );

    let turn = provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .expect("turn");
    assert!(turn.turn_id.starts_with("turn:"));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    let request = event.runtime_request.expect("permission request");
    provider
        .respond(alera_provider_protocol::RuntimeResponse::Approval {
            request_id: request.request_id,
            decision: alera_provider_protocol::ApprovalDecision::Accept,
            updated_input: None,
            feedback: None,
        })
        .await
        .expect("permission response");
}
