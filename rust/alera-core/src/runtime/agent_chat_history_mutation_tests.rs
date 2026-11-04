use serde_json::{json, Value};

use super::super::agent_chat_settings_tests::settings_receipt;
use super::super::agent_chat_test_support::*;
use super::super::*;

async fn history(store: &RuntimeStore, count: usize) -> String {
    let id = new_chat_id();
    let mut initial = snapshot(&id, "ws", "tab", 0);
    let mut items = Vec::new();
    let mut turns = Vec::new();
    for index in 0..count {
        let turn = format!("turn-{index}");
        turns.push(json!({"turnId": turn, "status": "completed"}));
        let mut user = item(
            &format!("user-{index}"),
            "user_message",
            &format!("prompt {index}"),
        );
        user["turnId"] = json!(turn);
        user["clientMessageId"] = json!(format!("client-{index}"));
        user["attachments"] = json!([{"name": "image.png", "path": "/tmp/image.png"}]);
        let mut answer = item(
            &format!("answer-{index}"),
            "assistant_message",
            &"answer".repeat(512),
        );
        answer["turnId"] = json!(turn);
        items.push(user);
        items.push(answer);
    }
    initial["turns"] = json!(turns);
    initial["items"] = json!(items);
    store
        .create_agent_chat(
            &record(&id, "ws", "tab", initial),
            &tab(&id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    id
}

fn fresh_fork(id: &str) -> (AgentChatRecord, WorkspaceTabRecord) {
    let mut initial = snapshot(id, "ws", "fork", 0);
    initial["session"] = session("stopped");
    let mut record = record(id, "ws", "fork", initial);
    record.native_thread_id = None;
    (record, tab(id, "ws", "fork"))
}

async fn stopped_header(store: &RuntimeStore, id: &str) -> Value {
    let (_, mut header) = next_snapshot(store, id).await;
    header["turns"] = json!([]);
    header["session"]["status"] = json!("stopped");
    header.as_object_mut().unwrap().remove("usage");
    header.as_object_mut().unwrap().remove("recovery");
    header
}

#[tokio::test]
async fn fork_copies_history_outside_the_snapshot_and_replays_without_native_ids() {
    let (dir, store) = store_with_workspace("ws").await;
    let source = history(&store, 130).await;
    assert!(
        store.agent_chat(&source).await.unwrap().unwrap().snapshot["historyBefore"]
            .as_i64()
            .is_some()
    );
    assert!(
        store.agent_chat(&source).await.unwrap().unwrap().snapshot["items"]
            .as_array()
            .unwrap()
            .iter()
            .all(|item| item["turnId"] != "turn-3")
    );
    let new_id = new_chat_id();
    let (mut fork, tab) = fresh_fork(&new_id);
    fork.metadata = Some(json!({"nativeFork": {"boundary": "native-turn"}}));
    let receipt = settings_receipt("fork");
    let outcome = store
        .fork_agent_chat_through_turn(&source, 0, "turn-3", &fork, &tab, Some(&receipt))
        .await
        .unwrap();
    let AgentChatCreateOutcome::Created(created) = outcome else {
        panic!("fork was not created");
    };
    assert_eq!(created.snapshot["items"].as_array().unwrap().len(), 8);
    assert_eq!(created.snapshot["turns"].as_array().unwrap().len(), 4);
    assert!(created.native_thread_id.is_none());
    assert_eq!(created.generation, 1);
    assert!(store
        .agent_chat_native_id(&new_id, "thread", "anything")
        .await
        .unwrap()
        .is_none());
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened.agent_chat(&new_id).await.unwrap().unwrap(),
        *created
    );
    assert!(
        matches!(store.fork_agent_chat_through_turn(&source, 0, "turn-3", &fork, &tab, Some(&receipt)).await.unwrap(),
        AgentChatCreateOutcome::Replay(value) if value["operationKind"] == "nativeForkDeferred" && value["filesystemChangesReverted"] == false)
    );
}

#[tokio::test]
async fn rewind_clears_native_generation_pending_fork_and_requires_snapshot_reload() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = history(&store, 4).await;
    store.set_agent_chat_metadata(&id, Some(&json!({"nativeFork": {"thread": "later"}, "nativeHistory": {}, "originKind": "fork"}))).await.unwrap();
    store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: id.clone(),
            generation: 1,
            kind: "turn@1".into(),
            native_id: json!("native-turn"),
            app_id: Some("turn-2".into()),
        })
        .await
        .unwrap();
    let header = stopped_header(&store, &id).await;
    let receipt = settings_receipt("rewind");
    let outcome = store
        .rewind_agent_chat_before_turn(&id, 0, "turn-2", &header, Some(&receipt))
        .await
        .unwrap();
    let AgentChatRewindOutcome::Rewound {
        record,
        event,
        prompt,
    } = outcome
    else {
        panic!("rewind did not apply");
    };
    assert_eq!(record.generation, 2);
    assert!(record.native_thread_id.is_none());
    assert_eq!(record.snapshot["items"].as_array().unwrap().len(), 4);
    assert_eq!(record.snapshot["turns"].as_array().unwrap().len(), 2);
    assert!(record
        .metadata
        .as_ref()
        .unwrap()
        .get("nativeFork")
        .is_none());
    assert!(record
        .metadata
        .as_ref()
        .unwrap()
        .get("nativeHistory")
        .is_none());
    assert_eq!(record.metadata.as_ref().unwrap()["originKind"], "fork");
    assert_eq!(prompt["text"], "prompt 2");
    assert_eq!(prompt["attachments"][0]["name"], "image.png");
    assert!(store
        .is_agent_chat_message_cancelled(&id, "client-2")
        .await
        .unwrap());
    assert!(store
        .is_agent_chat_message_cancelled(&id, "client-3")
        .await
        .unwrap());
    assert!(!store
        .is_agent_chat_message_cancelled(&id, "client-1")
        .await
        .unwrap());
    assert_eq!(event.delta["snapshotRequired"], true);
    assert!(
        store
            .agent_chat_events(&id, 0, 500)
            .await
            .unwrap()
            .snapshot_required
    );
    assert!(store
        .agent_chat_turn(&id, "turn-2")
        .await
        .unwrap()
        .is_none());
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(reopened.agent_chat(&id).await.unwrap().unwrap(), *record);
    assert!(
        matches!(store.rewind_agent_chat_before_turn(&id, 0, "turn-2", &header, Some(&receipt)).await.unwrap(),
        AgentChatRewindOutcome::Replay(value) if value["nativeRollback"] == false && value["operationKind"] == "transcriptRewind"
            && value["prompt"] == "prompt 2" && value["attachments"][0]["name"] == "image.png"
            && value["promptItem"]["clientMessageId"] == "client-2")
    );
}

#[tokio::test]
async fn rewind_refuses_ambiguous_steering_and_receipt_failure_rolls_back_everything() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = history(&store, 3).await;
    let before = store.agent_chat(&id).await.unwrap().unwrap();
    let mut steering = item("steer", "user_message", "do this too");
    steering["turnId"] = json!("turn-1");
    let json = steering.to_string();
    sqlx::query("INSERT INTO agentChatItems (chatId,itemId,seq,turnId,itemJson,byteSize,updatedCursor) VALUES (?,'steer',100,'turn-1',?,?,0)")
        .bind(&id).bind(&json).bind(json.len() as i64).execute(store.pool()).await.unwrap();
    let header = stopped_header(&store, &id).await;
    assert!(store
        .rewind_agent_chat_before_turn(&id, 0, "turn-1", &header, None)
        .await
        .unwrap_err()
        .to_string()
        .contains("exactly one user message"));
    sqlx::query("DELETE FROM agentChatItems WHERE chatId = ? AND itemId = 'steer'")
        .bind(&id)
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("CREATE TRIGGER rejectRewind BEFORE INSERT ON agentChatReceipts BEGIN SELECT RAISE(ABORT, 'reject rewind'); END").execute(store.pool()).await.unwrap();
    assert!(store
        .rewind_agent_chat_before_turn(&id, 0, "turn-1", &header, Some(&settings_receipt("rewind")))
        .await
        .is_err());
    assert_eq!(store.agent_chat(&id).await.unwrap().unwrap(), before);
    assert!(!store
        .is_agent_chat_message_cancelled(&id, "client-1")
        .await
        .unwrap());
}

#[tokio::test]
async fn native_boundary_lookup_only_uses_current_generation_and_rejects_conflicts() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = create_chat(&store, "ws", "tab").await;
    for (kind, native) in [
        ("turn@1", "first"),
        ("turn@2", "first"),
        ("turn@3", "different"),
    ] {
        store
            .map_agent_chat_native_id(&AgentChatNativeIdInput {
                chat_id: id.clone(),
                generation: 1,
                kind: kind.into(),
                native_id: json!(native),
                app_id: Some("boundary".into()),
            })
            .await
            .unwrap();
    }
    assert!(store
        .agent_chat_native_id_for_app(&id, 1, "turn", "boundary")
        .await
        .is_err());
    assert!(store
        .agent_chat_native_id_for_app(&id, 2, "turn", "boundary")
        .await
        .unwrap()
        .is_none());
    assert!(store
        .agent_chat_native_id_for_app(&id, 1, "item", "boundary")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn fork_receipt_failure_rolls_back_copied_prefix_chat_and_tab() {
    let (_dir, store) = store_with_workspace("ws").await;
    let source = history(&store, 3).await;
    let id = new_chat_id();
    let (fork, tab) = fresh_fork(&id);
    sqlx::query("CREATE TRIGGER rejectFork BEFORE INSERT ON agentChatReceipts BEGIN SELECT RAISE(ABORT, 'reject fork'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .fork_agent_chat_through_turn(
            &source,
            0,
            "turn-1",
            &fork,
            &tab,
            Some(&settings_receipt("fork"))
        )
        .await
        .is_err());
    assert!(store.agent_chat(&id).await.unwrap().is_none());
    assert!(store.find_workspace_tab("fork").await.unwrap().is_none());
    let rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM agentChatItems WHERE chatId = ?")
        .bind(&id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(rows, 0);
    assert!(store
        .agent_chat_turn(&source, "turn-2")
        .await
        .unwrap()
        .is_some());
}
