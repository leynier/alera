#![cfg(unix)]

mod support;

use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use support::*;

/// A config whose task output root holds [output] for task-1, when given.
fn config_with_output(output: Option<&str>) -> alera_provider_claude::ClaudeProviderConfig {
    let mut config = isolated_config();
    let tmp = std::path::PathBuf::from(format!("{}-tmp", config.options.env["CLAUDE_CONFIG_DIR"]));
    // SAFETY: getuid has no preconditions and cannot fail.
    let uid = unsafe { libc::getuid() };
    let tasks = tmp
        .join(format!("claude-{uid}"))
        .join("proj")
        .join("native-session")
        .join("tasks");
    std::fs::create_dir_all(&tasks).unwrap();
    if let Some(output) = output {
        std::fs::write(tasks.join("task-1.output"), output).unwrap();
    }
    config.options.env.insert(
        "CLAUDE_CODE_TMPDIR".into(),
        tmp.to_string_lossy().into_owned(),
    );
    config
}

fn frames(backgrounded: bool, is_error: bool) -> Vec<Value> {
    vec![
        initialize_response(),
        json!({
            "type": "assistant", "session_id": "native-session",
            "message": {"id": "m1", "content": [
                {"type": "tool_use", "id": "toolu_1", "name": "Bash", "input": {"command": "make"}}
            ]}
        }),
        json!({
            "type": "system", "subtype": "task_started", "session_id": "native-session",
            "task_id": "task-1", "tool_use_id": "toolu_1", "task_type": "local_bash",
            "is_backgrounded": backgrounded
        }),
        json!({
            "type": "user", "session_id": "native-session",
            "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "toolu_1", "content": "line 1\nline 2", "is_error": is_error}
            ]},
            "tool_use_result": {"stdout": "line 1\nline 2", "stderr": ""}
        }),
        result_message(false, None),
    ]
}

async fn turn(output: Option<&str>, backgrounded: bool, is_error: bool) -> Vec<ProviderEvent> {
    let (mut provider, _handle) = started_provider_with_config(
        frames(backgrounded, is_error),
        config_with_output(output),
        SessionStartInput::new("app-thread"),
    )
    .await;
    provider
        .send_turn(TurnInput::text("app-thread", "build"))
        .await
        .unwrap();
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        let done = event.kind == EventKind::TurnCompleted;
        events.push(event);
        if done {
            return events;
        }
    }
}

fn output_deltas(events: &[ProviderEvent]) -> Vec<(usize, String)> {
    events
        .iter()
        .enumerate()
        .filter(|(_, event)| {
            event.kind == EventKind::ContentDelta && event.payload["streamKind"] == "command_output"
        })
        .map(|(index, event)| (index, event.payload["delta"].as_str().unwrap().to_owned()))
        .collect()
}

fn completion(events: &[ProviderEvent]) -> (usize, &ProviderEvent) {
    events
        .iter()
        .enumerate()
        .find(|(_, event)| {
            event.kind == EventKind::ItemCompleted && event.item_id.as_deref() == Some("toolu_1")
        })
        .expect("the Bash item completes from its tool result")
}

#[tokio::test]
async fn a_foreground_command_streams_its_output_before_it_completes() {
    let events = turn(Some("line 1\nline 2\n"), false, false).await;
    let deltas = output_deltas(&events);
    assert_eq!(
        deltas
            .iter()
            .map(|(_, text)| text.as_str())
            .collect::<String>(),
        "line 1\nline 2\n"
    );
    let (index, completed) = completion(&events);
    assert!(deltas.iter().all(|(delta, _)| *delta < index));
    assert_eq!(completed.payload["status"], "completed");
    assert!(completed.payload.get("title").is_none());
    assert_eq!(completed.payload["data"]["output"], "line 1\nline 2");
}

#[tokio::test]
async fn background_missing_or_failed_commands_still_complete() {
    let events = turn(Some("line 1\n"), true, false).await;
    assert!(output_deltas(&events).is_empty());
    let events = turn(None, false, false).await;
    assert!(output_deltas(&events).is_empty());
    assert_eq!(
        completion(&events).1.payload["data"]["output"],
        "line 1\nline 2"
    );
    let events = turn(None, false, true).await;
    assert_eq!(completion(&events).1.payload["status"], "failed");
}
