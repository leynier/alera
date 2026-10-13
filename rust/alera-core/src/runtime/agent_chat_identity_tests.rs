use serde_json::{json, Value};

use super::agent_chat_test_support::*;
use super::*;

fn receipt(request_id: &str, payload: Value) -> AgentChatReceipt {
    AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: request_id.into(),
        digest: agent_chat_command_digest(&payload),
        receipt: json!({"accepted": request_id}),
    }
}

#[tokio::test]
async fn native_ids_keep_their_json_type() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let input = |native_id: Value, app_id: Option<&str>| AgentChatNativeIdInput {
        chat_id: chat_id.clone(),
        generation: 1,
        kind: "request".into(),
        native_id,
        app_id: app_id.map(str::to_string),
    };
    let integer = store
        .map_agent_chat_native_id(&input(json!(1), None))
        .await
        .unwrap();
    let string = store
        .map_agent_chat_native_id(&input(json!("1"), None))
        .await
        .unwrap();
    assert_ne!(integer, string);
    assert_eq!(
        store
            .map_agent_chat_native_id(&input(json!(1), None))
            .await
            .unwrap(),
        integer
    );
    assert_eq!(
        store
            .agent_chat_app_id(&chat_id, 1, "request", &json!("1"))
            .await
            .unwrap(),
        Some(string.clone())
    );
    assert_eq!(
        store
            .agent_chat_native_id(&chat_id, "request", &integer)
            .await
            .unwrap()
            .unwrap()
            .native_id,
        json!(1)
    );
    assert_eq!(
        store
            .agent_chat_native_id(&chat_id, "request", &string)
            .await
            .unwrap()
            .unwrap()
            .native_id,
        json!("1")
    );
    // Adopting an app id another native id holds, or re-pointing one, conflicts.
    assert!(store
        .map_agent_chat_native_id(&input(json!(2), Some(&integer)))
        .await
        .is_err());
    assert!(store
        .map_agent_chat_native_id(&input(json!(1), Some("other")))
        .await
        .is_err());
    for bad in [json!(1.5), json!(null), json!({"id": 1}), json!("")] {
        assert!(store
            .map_agent_chat_native_id(&input(bad, None))
            .await
            .is_err());
    }
}

#[tokio::test]
async fn standalone_receipts_replay_and_conflict() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let interrupt = receipt("interrupt-1", json!({"turnId": "t1"}));
    assert_eq!(
        store
            .record_agent_chat_receipt(Some(&chat_id), &interrupt)
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    assert_eq!(
        store
            .record_agent_chat_receipt(Some(&chat_id), &interrupt)
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(json!({"accepted": "interrupt-1"}))
    );
    let other = receipt("interrupt-1", json!({"turnId": "t2"}));
    assert_eq!(
        store
            .record_agent_chat_receipt(Some(&chat_id), &other)
            .await
            .unwrap(),
        AgentChatReceiptCheck::Conflict
    );
    assert!(store
        .record_agent_chat_receipt(Some(&new_chat_id()), &receipt("x", json!(0)))
        .await
        .is_err());
}
