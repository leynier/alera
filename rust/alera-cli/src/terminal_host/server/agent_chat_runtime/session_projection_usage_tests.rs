use std::time::Duration;

use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::{merge_token_usage, merge_usage_windows};
use crate::terminal_host::server::agent_chat_runtime::commands::{
    CallerCtx, ChatOp, ConfigureInput,
};
use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;

fn window(id: &str, used: u64) -> Value {
    json!({"id": id, "kind": "session", "label": id, "usedPercent": used})
}

#[test]
fn count_reports_keep_the_context_group() {
    let live =
        json!({"contextTokens": 50000, "contextWindow": 200000, "autoCompactTokens": 117000});
    let tokens = merge_token_usage(None, &live).unwrap();
    assert_eq!(
        tokens,
        json!({"context": 50000, "contextWindow": 200000, "autoCompact": 117000})
    );
    let turn = json!({"usageStatus": "complete", "inputTokens": 900, "outputTokens": 40});
    let tokens = merge_token_usage(Some(&tokens), &turn).unwrap();
    assert_eq!(
        tokens,
        json!({
            "input": 900, "output": 40,
            "context": 50000, "contextWindow": 200000, "autoCompact": 117000,
        })
    );
}

#[test]
fn counts_are_replaced_together() {
    let current = json!({"input": 900, "output": 40, "cached": 10, "reasoning": 5, "context": 7});
    let tokens = merge_token_usage(Some(&current), &json!({"inputTokens": 3})).unwrap();
    assert_eq!(tokens, json!({"input": 3, "context": 7}));
}

#[test]
fn a_context_tick_without_a_window_keeps_the_window() {
    let current =
        json!({"input": 1, "context": 50000, "contextWindow": 200000, "autoCompact": 117000});
    let tokens = merge_token_usage(Some(&current), &json!({"contextTokens": 60000})).unwrap();
    assert_eq!(
        tokens,
        json!({"input": 1, "context": 60000, "contextWindow": 200000, "autoCompact": 117000})
    );
    let tokens = merge_token_usage(
        Some(&tokens),
        &json!({"contextTokens": 61000, "autoCompactTokens": 100000}),
    )
    .unwrap();
    assert_eq!(tokens["autoCompact"], 100000);
    assert_eq!(tokens["contextWindow"], 200000);
}

#[test]
fn a_reported_window_replaces_the_context_group() {
    let current = json!({"context": 50000, "contextWindow": 200000, "autoCompact": 117000});
    let update = json!({"contextTokens": 1000, "contextWindow": 258400});
    let tokens = merge_token_usage(Some(&current), &update).unwrap();
    assert_eq!(tokens, json!({"context": 1000, "contextWindow": 258400}));
}

#[test]
fn reports_without_usable_fields_change_nothing() {
    let current = json!({"input": 1});
    assert!(merge_token_usage(Some(&current), &json!({})).is_none());
    assert!(merge_token_usage(Some(&current), &Value::Null).is_none());
    assert!(merge_token_usage(Some(&current), &json!({"usageStatus": "partial"})).is_none());
    let invalid = json!({"inputTokens": -1, "contextTokens": "x", "contextWindow": 1.5});
    assert!(merge_token_usage(Some(&current), &invalid).is_none());
}

#[test]
fn windows_merge_by_id_in_place() {
    let current = json!([window("primary", 50), window("secondary", 10)]);
    let merged = merge_usage_windows(Some(&current), &json!([window("primary", 60)])).unwrap();
    assert_eq!(
        merged,
        json!([window("primary", 60), window("secondary", 10)])
    );
    let merged = merge_usage_windows(Some(&merged), &json!([window("weekly", 3)])).unwrap();
    assert_eq!(
        merged,
        json!([
            window("primary", 60),
            window("secondary", 10),
            window("weekly", 3)
        ])
    );
    let merged = merge_usage_windows(None, &json!([window("primary", 1)])).unwrap();
    assert_eq!(merged, json!([window("primary", 1)]));
}

#[test]
fn empty_or_unusable_windows_change_nothing() {
    let current = json!([window("primary", 50)]);
    assert!(merge_usage_windows(Some(&current), &json!([])).is_none());
    assert!(merge_usage_windows(Some(&current), &Value::Null).is_none());
    assert!(merge_usage_windows(Some(&current), &json!({"id": "primary"})).is_none());
    let unnamed = json!([{"kind": "session", "usedPercent": 1}, {"id": "", "usedPercent": 2}]);
    assert!(merge_usage_windows(Some(&current), &unnamed).is_none());
}

async fn wait_for_usage(harness: &TestHarness, chat: &str, expected: Value) {
    let mut last = Value::Null;
    let reached = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            last = harness.runtime.snapshot(chat).await.unwrap()["usage"].clone();
            if last == expected {
                return;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await;
    assert!(reached.is_ok(), "usage stayed {last}, expected {expected}");
}

#[tokio::test]
async fn usage_parts_survive_each_other_and_reset_on_provider_switch() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness.send_human(&chat, "first", "Count the files").await;
    let control = harness.control(&chat).await;
    control.wait_turns(1).await;

    control.event(
        EventKind::ThreadTokenUsageUpdated,
        1,
        json!({"contextTokens": 50000, "contextWindow": 200000, "autoCompactTokens": 117000}),
    );
    control.event(
        EventKind::AccountRateLimitsUpdated,
        1,
        json!({"limits": {"windows": [window("primary", 50), window("secondary", 10)]}}),
    );
    control.event(
        EventKind::AccountRateLimitsUpdated,
        1,
        json!({"limits": {"windows": []}}),
    );
    control.event(
        EventKind::AccountRateLimitsUpdated,
        1,
        json!({"limits": {"windows": [window("primary", 60)]}}),
    );
    control.event(
        EventKind::TurnCompleted,
        1,
        json!({"state": "completed", "tokenUsage": {
            "usageStatus": "complete", "usageScope": "main_agent", "hasSubagents": false,
            "inputTokens": 900, "outputTokens": 40,
        }}),
    );
    wait_for_usage(
        &harness,
        &chat,
        json!({
            "tokens": {
                "input": 900, "output": 40,
                "context": 50000, "contextWindow": 200000, "autoCompact": 117000,
            },
            "windows": [window("primary", 60), window("secondary", 10)],
        }),
    )
    .await;

    harness
        .runtime
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
    wait_for_usage(&harness, &chat, Value::Null).await;
    harness.finish().await;
}
