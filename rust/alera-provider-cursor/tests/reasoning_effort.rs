use alera_provider_cursor::{
    default_model_reasoning_effort, model_reasoning_efforts, CursorProvider, CursorProviderConfig,
};
use alera_provider_protocol::{Provider, ProviderError, SessionStartInput, TurnInput};
use cursor_agent_sdk::{CursorClient, MockBridgeTransport, SdkModel};
use serde_json::{json, Value};

fn model() -> Value {
    json!({"id":"model","parameters":[{"id":"reasoning_effort","values":[{"value":"low"},{"value":"high"}]}],"variants":[{"isDefault":true,"params":[{"id":"reasoning_effort","value":"low"}]}]})
}

#[test]
fn supported_and_default_effort_come_from_native_model_parameters() {
    let model: SdkModel = serde_json::from_value(model()).unwrap();
    assert_eq!(model_reasoning_efforts(&model), vec!["low", "high"]);
    assert_eq!(
        default_model_reasoning_effort(&model).as_deref(),
        Some("low")
    );
}

#[tokio::test]
async fn effort_uses_advertised_parameter_id_in_create_and_send() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(json!({"protocolVersion":"sdk.v1"})));
    mock.push_unary(Ok(json!({"models":[model()]})));
    mock.push_unary(Ok(json!({"agentId":"native","model":{"id":"model"}})));
    mock.push_stream(Vec::new());
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(
        client,
        CursorProviderConfig {
            api_key: Some("mock-api-key".into()),
            model: Some("model".into()),
            ..Default::default()
        },
    );
    let mut session = SessionStartInput::new("app");
    session
        .options
        .insert("reasoningEffort".into(), json!("low"));
    provider.start_session(session).await.unwrap();
    let mut turn = TurnInput::text("app", "hello");
    turn.options.insert("reasoningEffort".into(), json!("high"));
    provider.send_turn(turn).await.unwrap();
    let calls = mock.calls();
    let create = calls
        .iter()
        .find(|(path, _)| path.ends_with("CreateAgent"))
        .unwrap();
    assert_eq!(
        create.1["options"]["model"]["params"],
        json!([{"id":"reasoning_effort","value":"low"}])
    );
    let send = calls
        .iter()
        .find(|(path, _)| path.ends_with("Send"))
        .unwrap();
    assert_eq!(
        send.1["options"]["model"]["params"],
        json!([{"id":"reasoning_effort","value":"high"}])
    );
}

#[tokio::test]
async fn unadvertised_effort_is_rejected_before_creating_agent() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(json!({"protocolVersion":"sdk.v1"})));
    mock.push_unary(Ok(json!({"models":[model()]})));
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(
        client,
        CursorProviderConfig {
            api_key: Some("mock-api-key".into()),
            model: Some("model".into()),
            ..Default::default()
        },
    );
    let mut session = SessionStartInput::new("app");
    session
        .options
        .insert("reasoningEffort".into(), json!("xhigh"));
    assert!(matches!(
        provider.start_session(session).await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(!mock
        .calls()
        .iter()
        .any(|(path, _)| path.ends_with("CreateAgent")));
}
