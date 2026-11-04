//! Thinking levels reach Antigravity's `thought_level` option after the
//! model, at start and per turn.

use alera_agent_transport::MockTransport;
use alera_provider_antigravity::{AntigravityProvider, AntigravityProviderConfig};
use alera_provider_protocol::{Provider, ProviderError, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use std::time::Duration;

fn options(model: &str, levels: &[&str]) -> Value {
    let mut options = vec![
        json!({"id":"model","type":"select","currentValue":model,"options":[
            {"value":"gemini-3.8-flash"},{"value":"claude-sonnet"}
        ]}),
    ];
    if !levels.is_empty() {
        let values: Vec<Value> = levels.iter().map(|level| json!({"value": level})).collect();
        options.push(json!({"id":"thought_level","category":"thought_level","type":"select","currentValue":levels[0],"options":values}));
    }
    json!(options)
}

fn provider(frames: Vec<Value>) -> AntigravityProvider<MockTransport> {
    let mut all = vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},
            "authMethods":[{"id":"oauth-personal","name":"Personal OAuth"}]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
    ];
    all.extend(frames);
    let config = AntigravityProviderConfig {
        request_timeout: Duration::from_millis(200),
        ..Default::default()
    };
    AntigravityProvider::with_transport(MockTransport::new(all), config).unwrap()
}

fn start(model: &str, effort: &str) -> SessionStartInput {
    let mut input = SessionStartInput::new("app");
    input.model = Some(model.into());
    input
        .options
        .insert("reasoningEffort".into(), json!(effort));
    input
}

#[tokio::test]
async fn the_model_is_set_before_its_thinking_level_at_start_and_per_turn() {
    let mut provider = provider(vec![
        json!({"jsonrpc":"2.0","id":3,"result":{"sessionId":"agy","configOptions":options("gemini-3.8-flash", &["low", "high"])}}),
        json!({"jsonrpc":"2.0","id":4,"result":{"configOptions":options("claude-sonnet", &["none", "max"])}}),
        json!({"jsonrpc":"2.0","id":5,"result":{}}),
        json!({"jsonrpc":"2.0","id":6,"result":{}}),
    ]);
    assert!(provider.reasoning_effort_capabilities().turn);
    provider
        .start_session(start("claude-sonnet", "max"))
        .await
        .unwrap();
    let mut turn = TurnInput::text("app", "think");
    turn.options.insert("reasoningEffort".into(), json!("none"));
    provider.send_turn(turn).await.unwrap();
    let writes = provider.inner().client().transport().writes();
    let configured: Vec<_> = writes[3..6]
        .iter()
        .map(|write| {
            (
                write["params"]["configId"].clone(),
                write["params"]["value"].clone(),
            )
        })
        .collect();
    assert_eq!(
        configured,
        vec![
            (json!("model"), json!("claude-sonnet")),
            (json!("thought_level"), json!("max")),
            (json!("thought_level"), json!("none")),
        ]
    );
    assert_eq!(writes[6]["method"], "session/prompt");
    assert_eq!(
        provider.reasoning_effort_capabilities().values,
        vec!["none", "max"]
    );
}

#[tokio::test]
async fn a_model_without_thinking_levels_refuses_one() {
    let mut provider = provider(vec![
        json!({"jsonrpc":"2.0","id":3,"result":{"sessionId":"agy","configOptions":options("gemini-3.8-flash", &["low"])}}),
        json!({"jsonrpc":"2.0","id":4,"result":{"configOptions":options("claude-sonnet", &[])}}),
    ]);
    let error = provider
        .start_session(start("claude-sonnet", "low"))
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Unsupported(_)), "{error:?}");
}
