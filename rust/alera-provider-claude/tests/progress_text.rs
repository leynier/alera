mod support;

use alera_provider_protocol::{EventKind, Provider, TurnInput};
use serde_json::{json, Value};
use support::*;

fn snapshot(model: &str, message_id: &str, block: Value) -> Value {
    json!({
        "type": "assistant",
        "session_id": "native-session",
        "message": { "id": message_id, "model": model, "content": [block] }
    })
}

fn thinking(text: &str) -> Value {
    json!({ "type": "thinking", "thinking": text, "signature": "sig" })
}

fn tool_use() -> Value {
    json!({ "type": "tool_use", "id": "tool-1", "name": "Bash", "input": { "command": "ls" } })
}

/// The (streamKind, item id, delta) of each content event in one turn.
async fn deltas(model: &str, blocks: Vec<Value>) -> Vec<(String, String, String)> {
    let mut incoming = vec![initialize_response()];
    incoming.extend(
        blocks
            .into_iter()
            .map(|block| snapshot(model, "reply-message", block)),
    );
    incoming.push(result_message(false, None));
    let (mut provider, _handle) = started_provider(incoming).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "run"))
        .await
        .unwrap();
    let mut deltas = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        event.validate().unwrap();
        if event.kind == EventKind::TurnCompleted {
            return deltas;
        }
        if event.kind == EventKind::ContentDelta {
            deltas.push((
                event.payload["streamKind"].as_str().unwrap().to_owned(),
                event.item_id.clone().unwrap_or_default(),
                event.payload["delta"].as_str().unwrap().to_owned(),
            ));
        }
    }
}

fn kinds(deltas: &[(String, String, String)]) -> Vec<&str> {
    deltas.iter().map(|(kind, _, _)| kind.as_str()).collect()
}

#[tokio::test]
async fn a_progress_update_before_a_tool_call_is_assistant_text_on_claude_5_1_and_later() {
    for model in ["claude-opus-5-5", "claude-fable-5-1"] {
        let events = deltas(
            model,
            vec![thinking("plan"), thinking("update"), tool_use()],
        )
        .await;
        assert_eq!(
            events,
            vec![
                (
                    "reasoning_text".into(),
                    "reply-message:thinking:0".into(),
                    "plan".into()
                ),
                (
                    "assistant_text".into(),
                    "reply-message:thinking:1".into(),
                    "update".into()
                ),
            ],
            "{model}"
        );
    }
    for model in ["claude-opus-5", "claude-sonnet-4-6"] {
        let events = deltas(
            model,
            vec![thinking("plan"), thinking("update"), tool_use()],
        )
        .await;
        assert_eq!(
            kinds(&events),
            ["reasoning_text", "reasoning_text"],
            "{model}"
        );
    }
}

#[tokio::test]
async fn other_thinking_stays_reasoning() {
    let model = "claude-opus-5-5";
    let cases = [
        vec![thinking("plan"), tool_use()],
        vec![thinking("plan"), thinking(" \n "), tool_use()],
        vec![thinking(" \n "), thinking("update"), tool_use()],
        vec![
            thinking("plan"),
            thinking("update"),
            json!({ "type": "text", "text": "done" }),
        ],
        vec![thinking("plan"), thinking("update")],
    ];
    for blocks in cases {
        let events = deltas(model, blocks.clone()).await;
        let reasoning = events
            .iter()
            .filter(|(kind, _, _)| kind == "reasoning_text")
            .count();
        let thinking_blocks = blocks
            .iter()
            .filter(|block| block["type"] == "thinking")
            .count();
        assert_eq!(reasoning, thinking_blocks, "{blocks:?}");
    }
}

#[tokio::test]
async fn thinking_and_reply_of_one_message_are_separate_items() {
    let events = deltas(
        "claude-sonnet-4-6",
        vec![thinking("why"), json!({ "type": "text", "text": "answer" })],
    )
    .await;
    assert_eq!(events[0].1, "reply-message:thinking:0");
    assert_eq!(events[1].1, "reply-message");
}
