mod skill_fixtures;
mod support;

use alera_provider_claude::{
    claude_user_message_content, plan_claude_skill_dispatch, ClaudeProvider, ClaudeSkillDispatch,
};
use alera_provider_protocol::{Provider, ProviderSkill, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use skill_fixtures::*;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use support::{initialize_response, ScriptedTransport};

fn skill_path(name: &str) -> String {
    format!("/home/me/.claude/skills/{name}/SKILL.md")
}

fn skill(name: &str, user_invocation_only: bool) -> ProviderSkill {
    ProviderSkill::from_native(name, &skill_path(name), true)
        .unwrap()
        .with_invocation(user_invocation_only, true)
}

fn skill_map(names: &[&str]) -> HashMap<String, ProviderSkill> {
    names
        .iter()
        .map(|name| (name.to_string(), skill(name, false)))
        .collect()
}

fn skills() -> HashMap<String, ProviderSkill> {
    skill_map(&["2spec", "implement", "review", "re-release-version"])
}

fn dispatch(leading: Option<&str>, command: &str, name: &str) -> Option<ClaudeSkillDispatch> {
    Some(ClaudeSkillDispatch {
        leading_text: leading.map(str::to_owned),
        command_text: command.into(),
        skill_name: name.into(),
    })
}

#[test]
fn leaves_a_prompt_without_a_known_skill_untouched() {
    assert_eq!(plan_claude_skill_dispatch("fix the build", &skills()), None);
    assert_eq!(
        plan_claude_skill_dispatch("echo $HOME then $unknown", &skills()),
        None
    );
}

#[test]
fn keeps_the_whole_request_ahead_of_a_mid_prompt_slash_command() {
    assert_eq!(
        plan_claude_skill_dispatch("ok, now $implement all the tickets", &skills()),
        dispatch(
            Some("ok, now /implement all the tickets"),
            "/implement all the tickets",
            "implement"
        )
    );
}

#[test]
fn keeps_a_mention_that_opens_the_prompt_as_a_single_command_block() {
    assert_eq!(
        plan_claude_skill_dispatch("$review\nfocus on auth", &skills()),
        dispatch(None, "/review\nfocus on auth", "review")
    );
}

#[test]
fn dispatches_the_last_mention_and_rewrites_earlier_ones_inline() {
    assert_eq!(
        plan_claude_skill_dispatch("$review the diff, then $implement the fixes", &skills()),
        dispatch(
            Some("/review the diff, then /implement the fixes"),
            "/implement the fixes",
            "implement"
        )
    );
}

#[test]
fn dispatches_currency_prefixed_mentions_and_preserves_their_source_boundaries() {
    for symbol in ["€", "£", "¥", "₹", "₩", "₿", "𑿝"] {
        assert_eq!(
            plan_claude_skill_dispatch(
                &format!("{symbol}review the diff, then {symbol}implement the fixes"),
                &skills()
            ),
            dispatch(
                Some("/review the diff, then /implement the fixes"),
                "/implement the fixes",
                "implement"
            )
        );
        assert_eq!(
            plan_claude_skill_dispatch(&format!("{symbol}2spec for this"), &skills()),
            dispatch(None, "/2spec for this", "2spec")
        );
        assert_eq!(
            plan_claude_skill_dispatch(&format!("5{symbol}review {symbol}unknown"), &skills()),
            None
        );
    }
}

#[test]
fn ignores_currency_amounts_and_compact_monetary_expressions() {
    let with_currency = skill_map(&[
        "2spec",
        "implement",
        "review",
        "re-release-version",
        "20",
        "20k",
        "100M",
        "1e6",
    ]);
    for symbol in ["$", "€", "£", "¥", "₹", "₩", "₿", "𑿝"] {
        assert_eq!(
            plan_claude_skill_dispatch(
                &format!("pay {symbol}20 {symbol}20k {symbol}100M {symbol}1e6 tomorrow"),
                &with_currency
            ),
            None
        );
    }
}

#[test]
fn bounds_notes_for_repeated_user_only_skills_and_leaves_the_native_dispatch_unannotated() {
    let skills = HashMap::from([
        ("interrogate".to_string(), skill("interrogate", true)),
        ("implement".to_string(), skill("implement", true)),
    ]);
    assert_eq!(
        plan_claude_skill_dispatch(
            "$interrogate then $interrogate then $implement and $implement the fixes",
            &skills
        ),
        dispatch(
            Some(&format!(
                "/interrogate [The user invoked this skill. Follow the instructions at: {}] then /interrogate then /implement and /implement the fixes",
                skill_path("interrogate")
            )),
            "/implement the fixes",
            "implement"
        )
    );
}

#[test]
fn trailing_white_space_is_trimmed_from_both_blocks() {
    assert_eq!(
        plan_claude_skill_dispatch("  please $review  \n", &skills()),
        dispatch(Some("  please /review"), "/review", "review")
    );
}

fn image() -> Value {
    json!({"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "AAAA"}})
}

#[test]
fn content_is_a_string_without_a_dispatch_and_blocks_with_one() {
    let skills = skills();
    assert_eq!(
        claude_user_message_content("fix the build", None, &skills),
        json!("fix the build")
    );
    assert_eq!(
        claude_user_message_content("$review fix it", None, &skills),
        json!([{"type": "text", "text": "/review fix it"}])
    );
    assert_eq!(
        claude_user_message_content("please $review", None, &skills),
        json!([
            {"type": "text", "text": "please /review"},
            {"type": "text", "text": "/review"}
        ])
    );
    assert_eq!(
        claude_user_message_content("$review the diff, then $implement the fixes", None, &skills),
        json!([
            {"type": "text", "text": "/review the diff, then /implement the fixes"},
            {"type": "text", "text": "/implement the fixes"}
        ])
    );
}

#[test]
fn media_precede_the_command_block() {
    let skills = skills();
    assert_eq!(
        claude_user_message_content("look at this and $review it", Some(vec![image()]), &skills),
        json!([
            {"type": "text", "text": "look at this and /review it"},
            image(),
            {"type": "text", "text": "/review it"}
        ])
    );
    assert_eq!(
        claude_user_message_content("$review", Some(vec![image()]), &skills),
        json!([image(), {"type": "text", "text": "/review"}])
    );
    assert_eq!(
        claude_user_message_content("what is this", Some(vec![image()]), &skills),
        json!([image(), {"type": "text", "text": "what is this"}])
    );
    assert_eq!(
        claude_user_message_content("", Some(vec![image()]), &skills),
        json!([image()])
    );
}

/// The content of the user frame a turn writes, and the session workspace.
async fn sent_content(prompt: &str, configure: impl FnOnce(&Path, &Path)) -> (Value, PathBuf) {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    mkdir(&workspace);
    configure(&config_dir, &workspace);
    // The session cwd, not the configured one, decides the project skills.
    let (transport, handle) = ScriptedTransport::new([initialize_response()]);
    let mut provider =
        ClaudeProvider::with_transport(transport, config(&config_dir, None)).unwrap();
    provider.initialize().await.unwrap();
    let mut session = SessionStartInput::new("app-thread");
    session.cwd = Some(workspace.clone());
    provider.start_session(session).await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", prompt))
        .await
        .unwrap();
    let writes = handle.writes.lock().unwrap();
    let user = writes
        .iter()
        .find(|frame| frame["type"] == "user")
        .expect("user frame written");
    assert_eq!(user["message"]["role"], "user");
    (user["message"]["content"].clone(), workspace)
}

fn review_skills(config_dir: &Path, workspace: &Path) {
    write_skill(&config_dir.join("skills"), "review", "# Review");
    write_skill(
        &workspace.join(".claude/skills"),
        "implement",
        "---\ndisable-model-invocation: true\n---\n",
    );
    write_skill(
        &config_dir.join("skills"),
        "agent-only",
        "---\nuser-invocable: false\n---\n",
    );
    write_skill(&config_dir.join("skills"), "switched-off", "# Off");
    write(
        &config_dir.join("settings.json"),
        r#"{"skillOverrides":{"switched-off":"off"}}"#,
    );
}

#[tokio::test]
async fn the_sdk_user_message_carries_the_dispatched_blocks() {
    assert_eq!(
        sent_content("$review fix it", review_skills).await.0,
        json!([{"type": "text", "text": "/review fix it"}])
    );
    assert_eq!(
        sent_content("please $review", review_skills).await.0,
        json!([
            {"type": "text", "text": "please /review"},
            {"type": "text", "text": "/review"}
        ])
    );
    let (content, workspace) =
        sent_content("$implement first, then $review it", review_skills).await;
    let implement = workspace.join(".claude/skills/implement/SKILL.md");
    assert_eq!(
        content,
        json!([
            {"type": "text", "text": format!(
                "/implement [The user invoked this skill. Follow the instructions at: {}] first, then /review it",
                implement.display()
            )},
            {"type": "text", "text": "/review it"}
        ])
    );
}

#[tokio::test]
async fn unknown_agent_only_and_disabled_skills_leave_the_prompt_as_text() {
    for prompt in [
        "$agent-only now",
        "$switched-off now",
        "$missing now",
        "pay $20",
    ] {
        assert_eq!(sent_content(prompt, review_skills).await.0, json!(prompt));
    }
}
