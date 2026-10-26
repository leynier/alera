use alera_provider_cursor::{rewrite_cursor_skill_mentions, CursorProvider, CursorProviderConfig};
use alera_provider_protocol::{Provider, SessionStartInput, TurnInput};
use cursor_agent_sdk::{CursorClient, MockBridgeTransport};
use serde_json::json;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

fn workspace(name: &str) -> PathBuf {
    let root = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join("cursor-skill-invocation")
        .join(name);
    let _ = fs::remove_dir_all(&root);
    let home = root.join("home");
    fs::create_dir_all(&home).unwrap();
    // Every test in this binary points the user roots at an empty home.
    std::env::set_var("HOME", &home);
    std::env::set_var("USERPROFILE", &home);
    let cwd = root.join("workspace");
    for (name, frontmatter) in [
        ("review", "name: review"),
        ("agent-only", "user-invocable: false"),
    ] {
        let directory = cwd.join(".cursor/skills").join(name);
        fs::create_dir_all(&directory).unwrap();
        fs::write(
            directory.join("SKILL.md"),
            format!("---\n{frontmatter}\n---\n"),
        )
        .unwrap();
    }
    cwd
}

async fn sent_text(cwd: PathBuf, prompt: &str) -> Vec<String> {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    let mut input = SessionStartInput::new("thread");
    input.cwd = Some(cwd);
    provider.start_session(input).await.unwrap();
    mock.push_stream(vec![]);
    provider
        .send_turn(TurnInput::text("thread", prompt))
        .await
        .unwrap();
    mock.calls()
        .into_iter()
        .filter(|(_, body)| body["message"]["text"].is_string())
        .map(|(_, body)| body["message"]["text"].as_str().unwrap().to_owned())
        .collect()
}

#[tokio::test]
async fn known_skill_mentions_reach_cursor_as_slash_commands() {
    let cwd = workspace("known");
    let sent = sent_text(
        cwd,
        "$review fix the bug, then $unknown and $agent-only $25",
    )
    .await;
    assert_eq!(
        sent,
        vec!["/review fix the bug, then $unknown and $agent-only $25"]
    );
}

#[tokio::test]
async fn prompts_without_mentions_are_sent_unchanged() {
    let cwd = workspace("plain");
    let sent = sent_text(cwd, "costs $25 and a$review").await;
    assert_eq!(sent, vec!["costs $25 and a$review"]);
}

#[test]
fn rewrite_touches_only_known_names_at_mention_boundaries() {
    let names = HashSet::from(["review".to_owned(), "plugin:deploy".to_owned()]);
    assert_eq!(
        rewrite_cursor_skill_mentions("$review\n€plugin:deploy now $other x$review", &names),
        "/review\n/plugin:deploy now $other x$review"
    );
}
