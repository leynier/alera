use serde_json::json;

use super::super::agent_chat_settings_tests::settings_receipt;
use super::super::agent_chat_test_support::*;
use super::super::*;

async fn draft(store: &RuntimeStore) -> String {
    let id = new_chat_id();
    let mut initial = snapshot(&id, "ws", "tab", 0);
    initial["session"] = session("stopped");
    let mut record = record(&id, "ws", "tab", initial);
    record.native_thread_id = None;
    store
        .create_agent_chat(
            &record,
            &tab(&id, "ws", "tab"),
            Some(&settings_receipt("create")),
        )
        .await
        .unwrap();
    id
}

#[tokio::test]
async fn discarded_draft_leaves_no_rows_and_receipts_survive_reopen() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = draft(&store).await;
    let receipt = settings_receipt("close");
    assert_eq!(
        store
            .discard_agent_chat_if_never_sent(&id, 0, Some(&receipt))
            .await
            .unwrap(),
        AgentChatDeleteOutcome::Deleted
    );
    assert!(store.agent_chat(&id).await.unwrap().is_none());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_none());
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert!(
        matches!(reopened.discard_agent_chat_if_never_sent(&id, 0, Some(&receipt)).await.unwrap(), AgentChatDeleteOutcome::Replay(value) if value["discarded"] == true)
    );
    assert!(matches!(
        store
            .check_agent_chat_receipt("desktop", "create", &settings_receipt("create").digest)
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(_)
    ));
    let mut conflict = receipt;
    conflict.digest = "other".into();
    assert_eq!(
        store
            .discard_agent_chat_if_never_sent(&id, 0, Some(&conflict))
            .await
            .unwrap(),
        AgentChatDeleteOutcome::ReceiptConflict
    );
}

#[tokio::test]
async fn a_sent_message_and_a_queued_message_each_block_discard() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = draft(&store).await;
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["queue"] = json!([{"clientMessageId": "queued", "text": "keep this"}]);
    store
        .commit_agent_chat(&id, cursor, &next, &json!({"queue": next["queue"]}), None)
        .await
        .unwrap();
    assert_eq!(
        store
            .discard_agent_chat_if_never_sent(&id, 1, None)
            .await
            .unwrap(),
        AgentChatDeleteOutcome::NotNeverSent
    );
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["queue"] = json!([]);
    store
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"queue": [], "items": [item("sent", "user_message", "keep this too")]}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .discard_agent_chat_if_never_sent(&id, 2, None)
            .await
            .unwrap(),
        AgentChatDeleteOutcome::NotNeverSent
    );
    let closed = store
        .close_agent_chat_with_receipt(&id, &settings_receipt("archive"))
        .await
        .unwrap();
    assert!(matches!(
        closed,
        AgentChatCloseOutcome::Closed {
            archived: true,
            discarded: false,
            ..
        }
    ));
    assert_eq!(
        store.agent_chat(&id).await.unwrap().unwrap().snapshot["items"][0]["text"],
        "keep this too"
    );
}

#[tokio::test]
async fn racing_send_and_discard_never_lose_an_admitted_message() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = draft(&store).await;
    let other = RuntimeStore::open(dir.path()).await.unwrap();
    let (cursor, next) = next_snapshot(&store, &id).await;
    let delta = json!({"items": [item("sent", "user_message", "durable") ]});
    let (sent, discarded) = tokio::join!(
        store.commit_agent_chat(&id, cursor, &next, &delta, None),
        other.discard_agent_chat_if_never_sent(&id, cursor, None)
    );
    match discarded.unwrap() {
        AgentChatDeleteOutcome::Deleted => {
            assert!(sent.is_err());
            assert!(store.agent_chat(&id).await.unwrap().is_none());
        }
        AgentChatDeleteOutcome::NotNeverSent => {
            assert!(matches!(
                sent.unwrap(),
                AgentChatCommitOutcome::Committed(_)
            ));
            assert_eq!(
                store.agent_chat_item(&id, "sent").await.unwrap().unwrap()["text"],
                "durable"
            );
        }
        other => panic!("unexpected discard result: {other:?}"),
    }
}

#[tokio::test]
async fn failed_close_receipt_rolls_back_tab_and_session_deletion() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = draft(&store).await;
    sqlx::query("CREATE TRIGGER rejectClose BEFORE INSERT ON agentChatReceipts BEGIN SELECT RAISE(ABORT, 'reject close'); END").execute(store.pool()).await.unwrap();
    assert!(store
        .discard_agent_chat_if_never_sent(&id, 0, Some(&settings_receipt("close")))
        .await
        .is_err());
    assert!(store.agent_chat(&id).await.unwrap().is_some());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_some());
    assert!(!store.agent_chat(&id).await.unwrap().unwrap().archived);
}

#[tokio::test]
async fn archived_delete_blocks_active_tasks_and_keeps_settled_lineage() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = create_chat(&store, "ws", "tab").await;
    store.archive_agent_chat(&id).await.unwrap();
    sqlx::query("INSERT INTO chatOrchestrationTasks (taskId,kind,status,callerScope,rootTaskId,parentChatId,targetJson,brief,notify,createdAt,updatedAt) \
        VALUES ('task','delegate','running','human','task',?,'{}','task','always','2026-01-01','2026-01-01')")
        .bind(&id).execute(store.pool()).await.unwrap();
    assert_eq!(
        store
            .delete_archived_agent_chat(&id, 0, None)
            .await
            .unwrap(),
        AgentChatArchivedDeleteOutcome::ReferencedByTasks
    );
    sqlx::query("UPDATE chatOrchestrationTasks SET status = 'completed' WHERE taskId = 'task'")
        .execute(store.pool())
        .await
        .unwrap();
    let receipt = settings_receipt("delete");
    assert_eq!(
        store
            .delete_archived_agent_chat(&id, 0, Some(&receipt))
            .await
            .unwrap(),
        AgentChatArchivedDeleteOutcome::Deleted
    );
    let tasks: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM chatOrchestrationTasks WHERE taskId = 'task'")
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(tasks, 1);
    assert!(
        matches!(store.delete_archived_agent_chat(&id, 0, Some(&receipt)).await.unwrap(), AgentChatArchivedDeleteOutcome::Replay(value) if value["deleted"] == true)
    );
}
