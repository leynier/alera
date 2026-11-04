//! Model discovery from a short-lived Antigravity ACP session.

use alera_agent_transport::MockTransport;
use alera_provider_antigravity::{
    probe_models, AntigravityProvider, AntigravityProviderConfig, AntigravityThinking,
};
use serde_json::{json, Value};
use std::path::Path;
use std::time::Duration;

fn model_option(current: &str) -> Value {
    json!({"id":"model","type":"select","currentValue":current,"options":[
        {"value":"gemini-3.8-flash","name":"Gemini 3.8 Flash"},
        {"value":"claude-sonnet","name":"Claude Sonnet"},
        {"value":"gpt-5","name":"GPT-5"}
    ]})
}

fn thinking(current: &str, levels: &[&str]) -> Value {
    let options: Vec<Value> = levels.iter().map(|level| json!({"value": level})).collect();
    json!({"id":"thought_level","category":"thought_level","type":"select","currentValue":current,"options":options})
}

fn opening(options: Value) -> Vec<Value> {
    vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},
            "authMethods":[{"id":"oauth-personal","name":"Personal OAuth"}]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
        json!({"jsonrpc":"2.0","id":3,"result":{"sessionId":"agy-probe","configOptions":options}}),
    ]
}

fn provider(frames: Vec<Value>) -> AntigravityProvider<MockTransport> {
    let config = AntigravityProviderConfig {
        request_timeout: Duration::from_millis(200),
        ..Default::default()
    };
    AntigravityProvider::with_transport(MockTransport::new(frames), config).unwrap()
}

fn methods(provider: &AntigravityProvider<MockTransport>) -> Vec<String> {
    provider
        .inner()
        .client()
        .transport()
        .writes()
        .iter()
        .map(|write| write["method"].as_str().unwrap_or("response").to_owned())
        .collect()
}

fn levels(levels: &[&str], default: Option<&str>) -> AntigravityThinking {
    AntigravityThinking {
        levels: levels.iter().map(|level| level.to_string()).collect(),
        default: default.map(str::to_owned),
    }
}

#[tokio::test]
async fn the_probe_walks_every_model_and_ends_on_the_current_one() {
    let mut frames = opening(json!([
        model_option("gemini-3.8-flash"),
        thinking("high", &["low", "high"])
    ]));
    frames.extend([
        json!({"jsonrpc":"2.0","id":4,"result":{"configOptions":[model_option("claude-sonnet"), thinking("medium", &["none", "medium"])]}}),
        json!({"jsonrpc":"2.0","id":5,"error":{"code":-32602,"message":"model unavailable"}}),
        json!({"jsonrpc":"2.0","id":6,"result":{"configOptions":[model_option("gemini-3.8-flash"), thinking("high", &["low", "high"])]}}),
    ]);
    let mut provider = provider(frames);
    let cwd = Path::new("/tmp/alera-antigravity-probe-test");
    let (models, session) = probe_models(&mut provider, cwd).await.unwrap();
    assert_eq!(session.as_deref(), Some("agy-probe"));
    let summary: Vec<_> = models
        .iter()
        .map(|model| {
            (
                model.id.as_str(),
                model.provider_default,
                model.thinking.clone(),
            )
        })
        .collect();
    assert_eq!(
        summary,
        vec![
            (
                "gemini-3.8-flash",
                true,
                levels(&["low", "high"], Some("high"))
            ),
            (
                "claude-sonnet",
                false,
                levels(&["none", "medium"], Some("medium"))
            ),
            ("gpt-5", false, levels(&[], None)),
        ]
    );
    let writes = provider.inner().client().transport().writes();
    assert_eq!(writes[2]["method"], "session/new");
    assert_eq!(writes[2]["params"]["cwd"], cwd.to_str().unwrap());
    let selected: Vec<_> = writes[3..]
        .iter()
        .map(|write| write["params"]["value"].clone())
        .collect();
    assert_eq!(
        selected,
        vec![
            json!("claude-sonnet"),
            json!("gpt-5"),
            json!("gemini-3.8-flash")
        ]
    );
    assert!(provider.inner().client().transport().is_closed());
}

#[tokio::test]
async fn a_runtime_without_a_thinking_option_is_not_walked() {
    let mut provider = provider(opening(json!([model_option("gpt-5")])));
    let (models, _) = probe_models(&mut provider, Path::new("/tmp/probe"))
        .await
        .unwrap();
    assert_eq!(
        methods(&provider),
        vec!["initialize", "authenticate", "session/new"]
    );
    assert_eq!(models.len(), 3);
    assert!(models.iter().all(|model| model.thinking.levels.is_empty()));
    assert!(models[2].provider_default);
    assert!(provider.inner().client().transport().is_closed());
}
