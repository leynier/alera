use serde_json::json;

use super::*;

#[test]
fn ordinary_nonsecret_data_and_normalized_fields_are_unchanged() {
    let data = json!({"command":["git","status"], "cwd":"/work", "result":{"ok":true}});
    let projection = project_item_data("command_execution", &data, &[]);
    assert_eq!(projection.data, Some(data.clone()));
    assert_eq!(
        projection.normalized,
        normalized_fields("command_execution", &data)
    );
    assert!(projection.payload.is_none());
}

#[test]
fn oversized_normalized_fields_have_a_preview_and_full_payload_reference() {
    let data = json!({"input":{"query":"\u{0}\"\\🙂".repeat(90_000)}, "result":"x".repeat(90_000)});
    let projection = project_item_data("mcp_tool_call", &data, &[]);
    assert!(projection.data.is_none());
    for value in projection.normalized.values() {
        assert!(value.to_string().len() <= NORMALIZED_FIELD_MAX_BYTES);
    }
    assert!(serde_json::to_vec(&projection.normalized).unwrap().len() <= 16 * 1024);
    assert_eq!(
        serde_json::from_str::<Value>(projection.payload.as_deref().unwrap()).unwrap(),
        data
    );
}

#[test]
fn native_tool_data_below_the_row_budget_keeps_full_normalized_fields() {
    let data = json!({"result":"x".repeat(10_000)});
    let projection = project_item_data("mcp_tool_call", &data, &[]);
    assert_eq!(projection.data, Some(data.clone()));
    assert!(projection.payload.is_none());
    assert_eq!(
        projection.normalized,
        normalized_fields("mcp_tool_call", &data)
    );
}

#[test]
fn secrets_environment_and_mcp_configuration_are_removed_before_string_storage() {
    let data = json!({
        "input": {"query":"x".repeat(90_000), "api_key":"secret-a", "nested":{"password":"secret-b"}},
        "result":r#"{"credentials":"secret-c","safe":true}"#,
        "env":{"SAFE":"also-private"}, "MCP-Servers":[{"command":"private"}],
        "mcpConfig":{"other":"private"}, "authorization":"secret-d"
    });
    let projection = project_item_data("mcp_tool_call", &data, &[]);
    let text = projection.payload.unwrap();
    assert!(!text.contains("secret-"));
    assert!(!text.contains("private"));
    let retained: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(retained["result"], r#"{"safe":true}"#);
    assert_eq!(retained["input"]["query"], "x".repeat(90_000));
}

#[test]
fn canonical_fields_are_excluded_only_when_the_caller_has_retained_them() {
    let data =
        json!({"text":"keep exactly\u{0}🙂", "output":"command log", "input":"x".repeat(90_000)});
    let retained = project_item_data("assistant_message", &data, &["text"]);
    let retained: Value = serde_json::from_str(retained.payload.as_deref().unwrap()).unwrap();
    assert!(retained.get("text").is_none());
    assert_eq!(retained["output"], data["output"]);
}

#[test]
fn hidden_payload_rows_reconstruct_the_full_redacted_json_within_the_core_limit() {
    let data =
        json!({"input":"\u{0}\"\\🙂".repeat(90_000), "password":"remove", "result":{"ok":true}});
    let projection = project_item_data("mcp_tool_call", &data, &[]);
    let head = ChatItem::new(
        "parent".into(),
        "mcp_tool_call",
        "2026-10-12T12:00:00.000Z",
        2,
    );
    let items = payload_items(&head, projection.payload.as_deref().unwrap()).unwrap();
    assert!(items.len() > 1);
    for (index, item) in items.iter().enumerate() {
        assert_eq!(item.item_id, format!("parent:payload:{}", index + 1));
        assert_eq!(item.item_type, "payload");
        assert_eq!(item.normalized["hidden"], true);
        assert_eq!(item.normalized["payloadOf"], "parent");
        assert!(!item.normalized.contains_key("continuationOf"));
        assert!(
            super::super::serialized_item_bytes(item).unwrap()
                <= alera_core::runtime::AGENT_CHAT_ITEM_MAX_BYTES
        );
    }
    let text: String = items
        .iter()
        .filter_map(|item| item.text.as_deref())
        .collect();
    let retained: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(retained["input"], data["input"]);
    assert_eq!(retained["result"], data["result"]);
    assert!(retained.get("password").is_none());
}
