use alera_agent_transport::MockTransport;
use alera_provider_acp::{
    config_reasoning_efforts, default_config_reasoning_effort, AcpProvider, AcpProviderConfig,
};
use alera_provider_protocol::{Provider, ProviderError, SessionStartInput, TurnInput};
use serde_json::{json, Value};

fn options() -> Vec<Value> {
    vec![
        json!({"configId":"model-thought-budget","category":"thought_level","type":"select","currentValue":"low","options":[{"value":"low"},{"group":"deep","options":[{"value":"high"}]}]}),
    ]
}

fn initialize() -> Value {
    json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"capabilities":{"session":{}},"authMethods":[]}})
}
fn session(options: Vec<Value>) -> Value {
    json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native","configOptions":options}})
}

#[test]
fn efforts_and_default_require_native_advertisement() {
    assert_eq!(config_reasoning_efforts(&options()), vec!["low", "high"]);
    assert_eq!(
        default_config_reasoning_effort(&options()).as_deref(),
        Some("low")
    );
    assert!(config_reasoning_efforts(&[]).is_empty());
}

#[tokio::test]
async fn session_and_turn_effort_use_exact_config_id_and_values() {
    let transport = MockTransport::new([
        initialize(),
        session(options()),
        json!({"jsonrpc":"2.0","id":3,"result":{}}),
        json!({"jsonrpc":"2.0","id":4,"result":{}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
    let mut session = SessionStartInput::new("app");
    session
        .options
        .insert("reasoningEffort".into(), json!("low"));
    provider.start_session(session).await.unwrap();
    let mut turn = TurnInput::text("app", "hello");
    turn.options.insert("reasoningEffort".into(), json!("high"));
    provider.send_turn(turn).await.unwrap();
    let writes = provider.client().transport().writes();
    assert_eq!(writes[2]["method"], "session/set_config_option");
    assert_eq!(
        writes[2]["params"],
        json!({"sessionId":"native","configId":"model-thought-budget","type":"id","value":"low"})
    );
    assert_eq!(writes[3]["params"]["value"], "high");
    assert_eq!(writes[4]["method"], "session/prompt");
}

#[tokio::test]
async fn missing_effort_mapping_is_explicitly_unsupported() {
    let transport = MockTransport::new([initialize(), session(Vec::new())]);
    let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
    let mut session = SessionStartInput::new("app");
    session
        .options
        .insert("reasoningEffort".into(), json!("high"));
    assert!(matches!(
        provider.start_session(session).await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(!provider
        .client()
        .transport()
        .writes()
        .iter()
        .any(|frame| frame["method"] == "session/set_config_option"));
}
