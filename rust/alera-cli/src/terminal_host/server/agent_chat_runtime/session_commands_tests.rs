use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp, ConfigureInput};
use super::super::AgentChatRuntime;
use super::fixture::*;

async fn wait_for_commands(runtime: &AgentChatRuntime, chat: &str, expected: Value) {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = runtime.snapshot(chat).await.unwrap();
            let commands = snapshot["session"]
                .get("commands")
                .cloned()
                .unwrap_or(Value::Null);
            if commands == expected {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("session commands did not become {expected}"));
}

#[tokio::test]
async fn provider_commands_reach_the_session_and_leave_with_the_provider() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Hello").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.event(
        EventKind::SessionCommandsUpdated,
        1,
        json!({"commands": [
            {"name": "compact", "description": "Summarize the conversation", "input": {"hint": "focus"}},
            {"name": "COMPACT", "description": "duplicate"},
            {"name": "init"}
        ]}),
    );
    wait_for_commands(
        &runtime,
        &chat,
        json!([
            {"name": "compact", "description": "Summarize the conversation", "input": {"hint": "focus"}},
            {"name": "init"}
        ]),
    )
    .await;

    // Each update replaces the list; an empty one removes the field.
    control.event(
        EventKind::SessionCommandsUpdated,
        1,
        json!({"commands": []}),
    );
    wait_for_commands(&runtime, &chat, Value::Null).await;
    control.event(
        EventKind::SessionCommandsUpdated,
        1,
        json!({"commands": [{"name": "review"}]}),
    );
    wait_for_commands(&runtime, &chat, json!([{"name": "review"}])).await;
    finish_turn(&runtime, &factory, &chat, 1).await;

    runtime
        .command(
            &chat,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some("claudeAgent".into()),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    wait_for_commands(&runtime, &chat, Value::Null).await;
    runtime.shutdown().await;
    harness.finish().await;
}
