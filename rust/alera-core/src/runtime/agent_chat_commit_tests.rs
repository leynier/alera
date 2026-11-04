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

fn running_session(turn_id: &str) -> Value {
    let mut session = session("running");
    session["activeTurnId"] = json!(turn_id);
    session
}

#[tokio::test]
async fn a_commit_moves_header_items_journal_and_receipt_together() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["session"] = running_session("turn-1");
    next["turns"] = json!([{"turnId": "turn-1", "status": "running"}]);
    let delta = json!({
        "session": next["session"],
        "turns": next["turns"],
        "items": [item("u1", "user_message", "Hi"), item("a1", "assistant_message", "")],
        "textAppends": [{"itemId": "a1", "stream": "text", "offset": 0, "text": "Hello"}],
    });
    let send = receipt("send-1", json!({"text": "Hi"}));
    let outcome = store
        .commit_agent_chat(&chat_id, cursor, &next, &delta, Some(&send))
        .await
        .unwrap();
    let AgentChatCommitOutcome::Committed(event) = outcome else {
        panic!("expected a commit");
    };
    assert_eq!(event.cursor, 1);
    assert_eq!(event.delta["textAppends"][0]["text"], "Hello");
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(chat.cursor, 1);
    assert_eq!(chat.snapshot["session"]["activeTurnId"], "turn-1");
    assert_eq!(chat.snapshot["items"][1]["text"], "Hello");
    assert_eq!(
        store
            .agent_chat_item(&chat_id, "a1")
            .await
            .unwrap()
            .unwrap()["text"],
        "Hello"
    );

    // The exact retry replays, even though the cursor has moved on.
    let replay = store
        .commit_agent_chat(&chat_id, cursor, &next, &delta, Some(&send))
        .await
        .unwrap();
    assert_eq!(
        replay,
        AgentChatCommitOutcome::Replay(json!({"accepted": "send-1"}))
    );
    let changed = receipt("send-1", json!({"text": "Different"}));
    let conflict = store
        .commit_agent_chat(&chat_id, 1, &next, &delta, Some(&changed))
        .await
        .unwrap();
    assert_eq!(conflict, AgentChatCommitOutcome::ReceiptConflict);
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 1);
    assert_eq!(
        store
            .check_agent_chat_receipt("desktop", "send-1", &send.digest)
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(json!({"accepted": "send-1"}))
    );
}

#[tokio::test]
async fn a_stale_cursor_is_reported_without_writing() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .unwrap();
    let stale = store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"items": [item("x", "user_message", "lost")]}),
            Some(&receipt("r", json!(1))),
        )
        .await
        .unwrap();
    assert_eq!(stale, AgentChatCommitOutcome::CursorConflict { current: 1 });
    assert!(store
        .agent_chat_item(&chat_id, "x")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .check_agent_chat_receipt("desktop", "r", &agent_chat_command_digest(&json!(1)))
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    let mut wrong_cursor = next.clone();
    wrong_cursor["cursor"] = json!(5);
    assert!(store
        .commit_agent_chat(&chat_id, 1, &wrong_cursor, &json!({}), None)
        .await
        .is_err());
}

#[tokio::test]
async fn a_failing_commit_rolls_back_items_header_and_receipt() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["title"] = json!("Changed");
    let delta = json!({
        "title": "Changed",
        "items": [item("a", "assistant_message", "abc")],
        "textAppends": [{"itemId": "a", "stream": "text", "offset": 9, "text": "gap"}],
    });
    let send = receipt("r", json!("payload"));
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &delta, Some(&send))
        .await
        .is_err());
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(
        (chat.cursor, chat.snapshot["title"].as_str()),
        (0, Some("New Chat"))
    );
    assert!(store
        .agent_chat_item(&chat_id, "a")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .check_agent_chat_receipt("desktop", "r", &send.digest)
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    assert!(store
        .agent_chat_events(&chat_id, 0, 10)
        .await
        .unwrap()
        .events
        .is_empty());
}

#[tokio::test]
async fn text_appends_use_utf16_offsets_and_replay_idempotently() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let commit = |delta: Value| {
        let store = store.clone();
        let chat_id = chat_id.clone();
        async move {
            let (cursor, next) = next_snapshot(&store, &chat_id).await;
            store
                .commit_agent_chat(&chat_id, cursor, &next, &delta, None)
                .await
        }
    };
    commit(json!({"items": [item("a", "assistant_message", "😀")]}))
        .await
        .unwrap();
    // The emoji is two UTF-16 units; offset 1 would split it.
    assert!(commit(
        json!({"textAppends": [{"itemId": "a", "stream": "text", "offset": 1, "text": "x"}]})
    )
    .await
    .is_err());
    commit(json!({"textAppends": [
        {"itemId": "a", "stream": "text", "offset": 2, "text": " ok"},
        {"itemId": "a", "stream": "reasoningText", "offset": 0, "text": "think"},
        {"itemId": "a", "stream": "output", "offset": 0, "text": "out"},
    ]}))
    .await
    .unwrap();
    // Replaying the same append, or a longer one overlapping it, is safe.
    commit(json!({"textAppends": [{"itemId": "a", "stream": "text", "offset": 2, "text": " ok"}]}))
        .await
        .unwrap();
    commit(
        json!({"textAppends": [{"itemId": "a", "stream": "text", "offset": 2, "text": " okay"}]}),
    )
    .await
    .unwrap();
    assert!(commit(
        json!({"textAppends": [{"itemId": "a", "stream": "text", "offset": 2, "text": " no"}]})
    )
    .await
    .is_err());
    assert!(commit(
        json!({"textAppends": [{"itemId": "missing", "stream": "text", "offset": 0, "text": "x"}]})
    )
    .await
    .is_err());
    let stored = store.agent_chat_item(&chat_id, "a").await.unwrap().unwrap();
    assert_eq!(stored["text"], "😀 okay");
    assert_eq!(stored["reasoningText"], "think");
    assert_eq!(stored["output"], "out");
    commit(json!({"removedItemIds": ["a"]})).await.unwrap();
    assert!(store
        .agent_chat_item(&chat_id, "a")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn the_delta_must_explain_every_header_change() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["session"] = session("running");
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .is_err());
    let mut next = next_snapshot(&store, &chat_id).await.1;
    next["pendingRequests"] = json!([{"requestId": "q1", "kind": "toolUserInput"}]);
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .is_err());
    assert!(store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"requests": [{"requestId": "q2", "kind": "toolUserInput"}]}),
            None
        )
        .await
        .is_err());
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"requests": next["pendingRequests"]}),
            None,
        )
        .await
        .unwrap();
    // Host fields outside the canonical ones travel in the delta too.
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["queuedInputs"] = json!([{"clientMessageId": "c1", "text": "later"}]);
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .is_err());
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"queuedInputs": next["queuedInputs"]}),
            None,
        )
        .await
        .unwrap();
    // Usage and recovery clear with an explicit null.
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["usage"] = json!({"inputTokens": 5});
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"usage": {"inputTokens": 5}}),
            None,
        )
        .await
        .unwrap();
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next.as_object_mut().unwrap().remove("usage");
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .is_err());
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"usage": null}), None)
        .await
        .unwrap();
    assert!(store
        .agent_chat(&chat_id)
        .await
        .unwrap()
        .unwrap()
        .snapshot
        .get("usage")
        .is_none());
}

#[tokio::test]
async fn projection_omissions_keep_durable_turn_history() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["turns"] = json!([{"turnId": "t1", "status": "completed"}]);
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .is_err());
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"turns": next["turns"]}),
            None,
        )
        .await
        .unwrap();
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["turns"] = json!([]);
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .unwrap();
    assert_eq!(
        store
            .agent_chat_turn(&chat_id, "t1")
            .await
            .unwrap()
            .unwrap()["status"],
        "completed"
    );
}

#[tokio::test]
async fn a_provider_switch_starts_a_generation_and_keeps_history() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["session"] = running_session("t1");
    next["turns"] = json!([{"turnId": "t1", "status": "running"}]);
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"session": next["session"], "turns": next["turns"], "items": [item("a", "assistant_message", "old")]}), None)
        .await
        .unwrap();
    let mapped = |generation: i64, native_id: Value, app_id: Option<&str>| AgentChatNativeIdInput {
        chat_id: chat_id.clone(),
        generation,
        kind: "turn".into(),
        native_id,
        app_id: app_id.map(str::to_string),
    };
    let t1 = store
        .map_agent_chat_native_id(&mapped(1, json!(7), Some("t1")))
        .await
        .unwrap();
    assert_eq!(t1, "t1");

    let switch = |status: &str, turns: Value| {
        let mut snapshot = next.clone();
        snapshot["cursor"] = json!(2);
        snapshot["provider"] = json!("claude");
        snapshot["providerInstanceId"] = json!("claude-work");
        snapshot["session"] = session(status);
        snapshot["turns"] = turns;
        snapshot
    };
    let blocked = switch("starting", next["turns"].clone());
    let delta = json!({"provider": "claude", "providerInstanceId": "claude-work", "session": blocked["session"]});
    let error = store
        .commit_agent_chat(&chat_id, 1, &blocked, &delta, None)
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref(),
        Some(AgentChatStoreError::ProviderSwitchBlocked { .. })
    ));

    let (cursor, mut idle) = next_snapshot(&store, &chat_id).await;
    idle["session"] = session("ready");
    idle["turns"] = json!([{"turnId": "t1", "status": "completed"}]);
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &idle,
            &json!({"session": idle["session"], "turns": idle["turns"]}),
            None,
        )
        .await
        .unwrap();
    let mut switched = switch("starting", idle["turns"].clone());
    switched["cursor"] = json!(3);
    // Changing provider in the snapshot alone is refused.
    assert!(store
        .commit_agent_chat(
            &chat_id,
            2,
            &switched,
            &json!({"session": switched["session"]}),
            None
        )
        .await
        .is_err());
    let delta = json!({"provider": "claude", "providerInstanceId": "claude-work", "session": switched["session"]});
    store
        .commit_agent_chat(&chat_id, 2, &switched, &delta, None)
        .await
        .unwrap();

    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(
        (
            chat.generation,
            chat.provider.as_str(),
            chat.native_thread_id.as_deref()
        ),
        (2, "claude", None)
    );
    assert_eq!(chat.snapshot["turns"][0]["turnId"], "t1");
    assert_eq!(chat.snapshot["items"][0]["text"], "old");
    let tab = store.find_workspace_tab("tab").await.unwrap().unwrap();
    assert_eq!(tab.payload["provider"], "claude");
    assert_eq!(tab.payload["providerInstanceId"], "claude-work");
    assert_eq!(tab.payload["model"], "gpt-5.5");

    // The same native id in the new generation is a different turn; the old
    // mapping stays readable but the old generation cannot mint new ids.
    let t2 = store
        .map_agent_chat_native_id(&mapped(2, json!(7), None))
        .await
        .unwrap();
    assert_ne!(t2, t1);
    assert_eq!(
        store
            .agent_chat_native_id(&chat_id, "turn", "t1")
            .await
            .unwrap()
            .unwrap()
            .generation,
        1
    );
    assert_eq!(
        store
            .map_agent_chat_native_id(&mapped(1, json!(7), None))
            .await
            .unwrap(),
        "t1"
    );
    assert!(store
        .map_agent_chat_native_id(&mapped(1, json!(8), None))
        .await
        .is_err());
    assert!(store
        .bind_agent_chat_native_thread(&chat_id, 1, Some("late"))
        .await
        .is_err());
    store
        .bind_agent_chat_native_thread(&chat_id, 2, Some("claude-session"))
        .await
        .unwrap();
    assert_eq!(
        store
            .agent_chat(&chat_id)
            .await
            .unwrap()
            .unwrap()
            .native_thread_id
            .as_deref(),
        Some("claude-session")
    );
}
