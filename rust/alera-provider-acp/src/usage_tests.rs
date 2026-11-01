use super::{context_usage, per_turn_prompt_usage};
use serde_json::json;

#[test]
fn per_turn_usage_clamps_subsets_and_drops_unset_counters() {
    let usage = json!({
        "inputTokens": 100, "outputTokens": 40, "totalTokens": 140,
        "cachedReadTokens": 150, "cachedWriteTokens": 30, "thoughtTokens": 50
    });
    assert_eq!(
        per_turn_prompt_usage(Some(&usage), false, true),
        json!({
            "usageScope":"main_agent","usageStatus":"complete","hasSubagents":false,
            "inputTokens":100,"outputTokens":40,
            "cachedInputTokens":100,"cacheCreationTokens":0,"reasoningTokens":40
        })
    );
    let partial = json!({"inputTokens": 10, "outputTokens": 2, "cachedReadTokens": 4, "cachedWriteTokens": 9});
    assert_eq!(
        per_turn_prompt_usage(Some(&partial), true, false),
        json!({
            "usageScope":"main_agent","usageStatus":"partial","hasSubagents":true,
            "inputTokens":10,"outputTokens":2,"cachedInputTokens":4,"cacheCreationTokens":6
        })
    );
}

#[test]
fn per_turn_usage_without_counters_is_unavailable() {
    for usage in [
        None,
        Some(json!({"inputTokens": 3})),
        Some(json!({"inputTokens": -1, "outputTokens": 2})),
        Some(json!({"inputTokens": 1.5, "outputTokens": 2})),
    ] {
        assert_eq!(
            per_turn_prompt_usage(usage.as_ref(), false, true),
            json!({"usageScope":"main_agent","usageStatus":"unavailable","hasSubagents":false})
        );
    }
}

#[test]
fn usage_updates_report_context_window_and_cost() {
    assert_eq!(
        context_usage(
            &json!({"used": 1200, "size": 200000, "cost": {"amount": 0.42, "currency": " USD "}})
        ),
        Some(
            json!({"contextTokens":1200,"contextWindow":200000,"cost":{"amount":0.42,"currency":"USD"}})
        )
    );
    assert_eq!(
        context_usage(&json!({"used": 5, "size": 0})),
        Some(json!({"contextTokens":5}))
    );
    assert_eq!(context_usage(&json!({"size": 10})), None);
}
