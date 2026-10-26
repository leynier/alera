use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp, ConfigureInput};
use super::super::AgentChatRuntime;
use super::fixture::*;

async fn skills(runtime: &AgentChatRuntime, chat: &str, refresh: bool) -> Value {
    runtime
        .skills(chat, refresh, CallerCtx::runtime())
        .await
        .unwrap()
}

async fn configure(runtime: &AgentChatRuntime, chat: &str, instance: &str) {
    runtime
        .command(
            chat,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some(instance.into()),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
}

async fn wait_for_session_skills(runtime: &AgentChatRuntime, chat: &str, expected: Value) {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let answer = skills(runtime, chat, false).await;
            if answer["source"] == "session" && answer["skills"] == expected {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("session skills did not become {expected}"));
}

#[tokio::test]
async fn a_draft_discovers_skills_for_its_agent_and_cwd() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    configure(&runtime, &chat, "claudeAgent").await;

    let answer = skills(&runtime, &chat, true).await;
    assert_eq!(
        answer,
        json!({
            "provider": "claudeAgent",
            "providerInstanceId": "claudeAgent",
            "skills": [{"name": "review", "path": "/skills/review/SKILL.md", "scope": "user", "enabled": true}],
            "source": "discovery",
            "status": "ready",
        })
    );
    let discoveries = factory.recorded.skill_discoveries.lock().unwrap().clone();
    assert_eq!(discoveries.len(), 1);
    assert_eq!(discoveries[0].0, "claudeAgent");
    assert!(
        discoveries[0].1.is_some(),
        "discovery runs in the chat's cwd"
    );
    assert!(discoveries[0].2, "refresh reaches the factory");

    configure(&runtime, &chat, "cursor").await;
    let failed = skills(&runtime, &chat, false).await;
    assert_eq!(failed["status"], "failed");
    assert_eq!(failed["skills"], json!([]));
    assert_eq!(failed["error"], "Cursor skill discovery was incomplete.");
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn session_reported_skills_win_and_leave_with_the_provider() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    // Codex lists skills from its session here; before one it is pending.
    let pending = skills(&runtime, &chat, false).await;
    assert_eq!(pending["status"], "pending");
    assert_eq!(pending["skills"], json!([]));

    send(&runtime, &chat, "first", "Hello").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.event(
        EventKind::SessionSkillsUpdated,
        1,
        json!({"skills": [
            {"name": "deploy", "path": "/a/SKILL.md", "enabled": true, "displayName": "Deploy"},
            {"name": "deploy", "path": "/b/SKILL.md", "enabled": true}
        ]}),
    );
    wait_for_session_skills(
        &runtime,
        &chat,
        json!([{"name": "deploy", "path": "/a/SKILL.md", "enabled": true, "displayName": "Deploy"}]),
    )
    .await;
    // An empty report is still the session's answer, not a reason to probe.
    control.event(EventKind::SessionSkillsUpdated, 1, json!({"skills": []}));
    wait_for_session_skills(&runtime, &chat, json!([])).await;
    finish_turn(&runtime, &factory, &chat, 1).await;
    let before_switch = factory.recorded.skill_discoveries.lock().unwrap().len();

    configure(&runtime, &chat, "claudeAgent").await;
    let switched = skills(&runtime, &chat, false).await;
    assert_eq!(switched["source"], "discovery");
    assert_eq!(switched["skills"][0]["name"], "review");
    assert_eq!(
        factory.recorded.skill_discoveries.lock().unwrap().len(),
        before_switch + 1
    );
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn an_unselected_draft_has_no_skills_yet() {
    let (harness, runtime, factory) = fixture().await;
    let created = runtime
        .create(
            super::super::CreateChatInput {
                workspace_id: "ws-a".into(),
                ..Default::default()
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let chat = created["chatId"].as_str().unwrap().to_owned();
    let answer = skills(&runtime, &chat, false).await;
    assert_eq!(
        answer,
        json!({"provider": null, "providerInstanceId": null, "skills": [], "status": "pending"})
    );
    assert!(factory
        .recorded
        .skill_discoveries
        .lock()
        .unwrap()
        .is_empty());
    runtime.shutdown().await;
    harness.finish().await;
}
