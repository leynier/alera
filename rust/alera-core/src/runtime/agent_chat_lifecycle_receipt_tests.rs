use serde_json::{json, Value};

use super::agent_chat_test_support::*;
use super::{AgentChatReceipt, AgentChatRestoreOutcome, RuntimeStore};

#[tokio::test]
async fn reopen_clears_the_persisted_archive_header_and_replays_the_open_snapshot() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "closed-tab").await;
    let (cursor, mut closed) = next_snapshot(&store, &chat_id).await;
    closed["archived"] = json!(true);
    closed["session"]["status"] = json!("stopped");
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &closed,
            &json!({
                "archived": true,
                "session": closed["session"],
                "items": [item("kept", "user_message", "keep this transcript")],
            }),
            None,
        )
        .await
        .unwrap();
    let archived = store.archive_agent_chat(&chat_id).await.unwrap();
    assert!(archived.archived);
    assert_eq!(archived.snapshot["archived"], true);

    let receipt = AgentChatReceipt {
        caller_scope: "desktop:agentChat.reopen".into(),
        request_id: "reopen".into(),
        digest: "digest".into(),
        receipt: json!({}),
    };
    let AgentChatRestoreOutcome::Restored(open) = store
        .restore_agent_chat_with_receipt(
            &chat_id,
            &tab(&chat_id, "ws", "reopened-tab"),
            Some(&receipt),
        )
        .await
        .unwrap()
    else {
        panic!("chat was not reopened");
    };
    assert!(!open.archived);
    assert!(open.archived_at.is_none());
    assert_eq!(open.snapshot["archived"], false);
    assert_eq!(open.snapshot["items"][0]["text"], "keep this transcript");
    assert_eq!(open.cursor, 2);
    let (archived_sql, header): (i64, String) =
        sqlx::query_as("SELECT archived, snapshotJson FROM agentChatSessions WHERE chatId = ?")
            .bind(&chat_id)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(archived_sql, 0);
    assert_eq!(
        serde_json::from_str::<Value>(&header).unwrap()["archived"],
        false
    );
    let journal = store.agent_chat_events(&chat_id, 1, 10).await.unwrap();
    assert_eq!(
        journal.events[0].delta,
        json!({"tabId": "reopened-tab", "archived": false})
    );

    store.pool().close().await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let current = reopened.agent_chat(&chat_id).await.unwrap().unwrap();
    assert!(!current.archived);
    assert_eq!(current.snapshot["archived"], false);
    let AgentChatRestoreOutcome::Replay(replay) = reopened
        .restore_agent_chat_with_receipt(
            &chat_id,
            &tab(&chat_id, "ws", "unused-retry-tab"),
            Some(&receipt),
        )
        .await
        .unwrap()
    else {
        panic!("reopen receipt did not replay");
    };
    assert_eq!(
        replay,
        json!({"chatId": chat_id, "tabId": "reopened-tab", "snapshot": open.snapshot})
    );
    assert_eq!(replay["snapshot"]["archived"], false);
    assert!(reopened
        .find_workspace_tab("unused-retry-tab")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        reopened.agent_chat(&chat_id).await.unwrap().unwrap().cursor,
        2
    );
}
