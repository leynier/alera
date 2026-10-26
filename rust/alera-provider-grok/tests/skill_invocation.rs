#![cfg(unix)]

use alera_agent_transport::MockTransport;
use alera_provider_grok::{GrokProvider, GrokProviderConfig};
use alera_provider_protocol::{Provider, SessionStartInput, TurnInput};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

/// A session whose cwd holds an `inspect` stub run as `sh inspect --json`,
/// listing `review` as enabled and `internal` as agent-only.
async fn prompt_sent(name: &str, prompt: &str) -> String {
    let cwd = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join("grok-skill-invocation")
        .join(name);
    let _ = fs::remove_dir_all(&cwd);
    fs::create_dir_all(&cwd).unwrap();
    fs::write(
        cwd.join("inspect"),
        r#"printf '{"skills":[{"name":"review","source":{"type":"project","path":"/r/SKILL.md"}},{"name":"internal","source":{"type":"bundled","path":"/i/SKILL.md"},"userInvocable":false}]}'
"#,
    )
    .unwrap();
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "authMethods":[]
            }
        }),
        json!({
            "jsonrpc":"2.0","id":2,"result":{
                "sessionId":"grok-session",
                "configOptions":[{"id":"mode","type":"select","currentValue":"default","options":[]}]
            }
        }),
    ]);
    let config = GrokProviderConfig {
        executable: PathBuf::from("/bin/sh"),
        ..GrokProviderConfig::default()
    };
    let mut provider = GrokProvider::with_transport(transport, config).unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.cwd = Some(cwd);
    provider.start_session(input).await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", prompt))
        .await
        .unwrap();
    let writes = provider.inner().client().transport().writes();
    let prompt = writes
        .iter()
        .find(|write| write["method"] == "session/prompt")
        .expect("prompt request");
    prompt["params"]["prompt"][0]["text"]
        .as_str()
        .unwrap()
        .to_owned()
}

#[tokio::test]
async fn a_leading_enabled_skill_mention_becomes_a_slash_command() {
    assert_eq!(
        prompt_sent("leading", "  $review fix it, then $review again").await,
        "/review fix it, then $review again"
    );
}

#[tokio::test]
async fn other_mentions_are_sent_unchanged() {
    for (name, prompt) in [
        ("inner", "please $review this"),
        ("unknown", "$unknown fix it"),
        ("agent-only", "$internal run"),
        ("amount", "$25 budget"),
    ] {
        assert_eq!(prompt_sent(name, prompt).await, prompt);
    }
}
