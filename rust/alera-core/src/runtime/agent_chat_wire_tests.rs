use serde_json::json;

use super::agent_chat_test_support::*;
use super::*;

#[tokio::test]
async fn an_oversized_item_is_refused_with_a_typed_error_and_nothing_is_written() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    let huge = item(
        "out",
        "command_execution",
        &"x".repeat(AGENT_CHAT_ITEM_MAX_BYTES),
    );
    let error = store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"items": [huge]}), None)
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref(),
        Some(AgentChatStoreError::ItemTooLarge { item_id, limit, .. })
            if item_id == "out" && *limit == AGENT_CHAT_ITEM_MAX_BYTES
    ));
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 0);
    // Appends that would push a stored item over the limit fail the same way.
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"items": [item("out", "command_execution", "")]}),
            None,
        )
        .await
        .unwrap();
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    let append = json!({"textAppends": [{"itemId": "out", "stream": "output", "offset": 0, "text": "y".repeat(AGENT_CHAT_ITEM_MAX_BYTES)}]});
    let error = store
        .commit_agent_chat(&chat_id, cursor, &next, &append, None)
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref(),
        Some(AgentChatStoreError::ItemTooLarge { .. })
    ));
}

#[test]
fn turn_reason_reads_the_legacy_spelling_and_writes_reason() {
    let turn: AgentChatTurn = serde_json::from_value(
        json!({"turnId": "t", "status": "interrupted", "interruptReason": "runtimeRestarted"}),
    )
    .unwrap();
    assert_eq!(turn.reason.as_deref(), Some("runtimeRestarted"));
    let wire = serde_json::to_value(&turn).unwrap();
    assert_eq!(wire["reason"], "runtimeRestarted");
    assert!(wire.get("interruptReason").is_none());
}
