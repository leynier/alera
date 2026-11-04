mod support;

use alera_provider_claude::ClaudeProviderConfig;
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use support::*;

fn assistant(id: &str, usage: Value, parent: Option<&str>, model: &str) -> Value {
    json!({
        "type": "assistant",
        "session_id": "native-session",
        "parent_tool_use_id": parent,
        "message": { "id": id, "model": model, "usage": usage, "content": [] }
    })
}

fn stream(event: Value) -> Value {
    json!({
        "type": "stream_event", "uuid": "s", "session_id": "native-session",
        "parent_tool_use_id": null, "event": event
    })
}

fn result_with_model_usage() -> Value {
    let mut result = result_message(false, None);
    result["modelUsage"] = json!({
        "claude-sonnet-4-6": {
            "inputTokens": 10, "outputTokens": 5, "cacheReadInputTokens": 2000,
            "cacheCreationInputTokens": 100, "contextWindow": 200000, "maxOutputTokens": 64000
        }
    });
    result
}

/// The live context reports and the terminal tokenUsage of each turn.
async fn turns(config: ClaudeProviderConfig, turns: Vec<Vec<Value>>) -> Vec<(Vec<Value>, Value)> {
    let mut incoming = vec![initialize_response()];
    let count = turns.len();
    for frames in turns {
        incoming.extend(frames);
    }
    let (mut provider, _handle) =
        started_provider_with_config(incoming, config, SessionStartInput::new("app-thread")).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let mut out = Vec::new();
    for _ in 0..count {
        provider
            .send_turn(TurnInput::text("app-thread", "run"))
            .await
            .unwrap();
        let mut reports = Vec::new();
        loop {
            let event = provider.next_event().await.unwrap().unwrap();
            event.validate().unwrap();
            if event.kind == EventKind::ThreadTokenUsageUpdated {
                reports.push(event.payload.clone());
            }
            if event.kind == EventKind::TurnCompleted {
                out.push((reports, event.payload["tokenUsage"].clone()));
                break;
            }
        }
    }
    out
}

fn contexts(reports: &[Value]) -> Vec<u64> {
    reports
        .iter()
        .map(|report| report["contextTokens"].as_u64().unwrap())
        .collect()
}

fn usage(input: u64, creation: u64, read: u64, output: u64) -> Value {
    json!({
        "input_tokens": input, "cache_creation_input_tokens": creation,
        "cache_read_input_tokens": read, "output_tokens": output
    })
}

#[tokio::test]
async fn root_snapshots_report_the_context_and_the_result_names_the_window() {
    let model = "claude-sonnet-4-6";
    let result = turns(
        isolated_config(),
        vec![
            vec![
                assistant("msg-1", usage(5, 100, 2000, 3), None, model),
                assistant("msg-1", usage(5, 100, 2000, 9), None, model),
                assistant("child", usage(999_999, 0, 0, 0), Some("child-tool"), model),
                assistant("synthetic", usage(999_999, 0, 0, 0), None, "<synthetic>"),
                result_with_model_usage(),
            ],
            vec![
                assistant("msg-2", usage(5, 100, 2100, 4), None, model),
                result_message(false, None),
            ],
        ],
    )
    .await;
    let (reports, usage) = &result[0];
    assert_eq!(contexts(reports), [2108]);
    assert!(reports[0].get("contextWindow").is_none());
    assert_eq!(usage["contextTokens"], 2108);
    assert_eq!(usage["contextWindow"], 200_000);
    let (reports, _) = &result[1];
    assert_eq!(contexts(reports), [2209]);
    assert_eq!(reports[0]["contextWindow"], 200_000);
    assert!(reports[0].get("autoCompactTokens").is_none());
}

#[tokio::test]
async fn stream_usage_merges_and_a_compaction_reports_its_size() {
    let model = "claude-sonnet-4-6";
    let result = turns(
        isolated_config(),
        vec![vec![
            stream(json!({ "type": "message_start", "message": {
                "id": "m1", "model": model, "usage": usage(0, 0, 0, 0)
            }})),
            assistant("m1", usage(11, 0, 1200, 0), None, model),
            stream(json!({ "type": "message_delta", "usage": { "output_tokens": 19 } })),
            json!({
                "type": "system", "subtype": "compact_boundary", "session_id": "native-session",
                "compact_metadata": { "trigger": "auto", "pre_tokens": 1230, "post_tokens": 400 }
            }),
            stream(json!({ "type": "message_delta", "usage": { "output_tokens": 50 } })),
            result_message(false, None),
        ]],
    )
    .await;
    assert_eq!(contexts(&result[0].0), [1211, 1230, 400]);
}

#[tokio::test]
async fn a_configured_auto_compact_window_sets_the_tick() {
    let mut config = isolated_config();
    config
        .options
        .env
        .insert("CLAUDE_CODE_AUTO_COMPACT_WINDOW".into(), "150000".into());
    let model = "claude-sonnet-4-6";
    let result = turns(
        config,
        vec![vec![
            assistant("msg-1", usage(5, 100, 2000, 3), None, model),
            result_with_model_usage(),
        ]],
    )
    .await;
    let (reports, usage) = &result[0];
    assert_eq!(reports[0]["autoCompactTokens"], 117_000);
    assert_eq!(usage["autoCompactTokens"], 117_000);
}
