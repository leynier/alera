use serde_json::json;

use super::super::agent_chat_settings_tests::settings_receipt;
use super::super::agent_chat_test_support::*;
use super::super::*;

#[tokio::test]
async fn read_cursors_are_shared_monotonic_and_only_settled_turns_become_unread() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = create_chat(&store, "ws", "tab").await;
    assert!(!store.agent_chat_attention(&id).await.unwrap().unread);
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["title"] = json!("Renamed");
    store
        .commit_agent_chat(&id, cursor, &next, &json!({"title": "Renamed"}), None)
        .await
        .unwrap();
    assert!(!store.agent_chat_attention(&id).await.unwrap().unread);
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    let turn = json!({"turnId": "turn", "status": "completed"});
    next["turns"] = json!([turn]);
    store
        .commit_agent_chat(&id, cursor, &next, &json!({"turns": [turn]}), None)
        .await
        .unwrap();
    assert!(store.agent_chat_attention(&id).await.unwrap().unread);
    let phone = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(phone.mark_agent_chat_read(&id, 2).await.unwrap(), 2);
    assert_eq!(store.mark_agent_chat_read(&id, 1).await.unwrap(), 2);
    assert!(!store.agent_chat_attention(&id).await.unwrap().unread);
    assert!(store.mark_agent_chat_read(&id, 3).await.is_err());
    assert!(store.mark_agent_chat_read(&id, -1).await.is_err());
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .agent_chat_attention(&id)
            .await
            .unwrap()
            .read_cursor,
        2
    );
    assert!(!reopened.agent_chat_attention(&id).await.unwrap().unread);
}

#[tokio::test]
async fn child_summary_counts_only_open_tasks_and_keeps_input_and_failure_signals() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = create_chat(&store, "ws", "tab").await;
    for (task, status) in [
        ("running", "running"),
        ("input", "needs_input"),
        ("failed", "failed"),
        ("done", "completed"),
    ] {
        sqlx::query("INSERT INTO chatOrchestrationTasks (taskId,kind,status,callerScope,rootTaskId,parentChatId,targetJson,brief,notify,createdAt,updatedAt) \
            VALUES (?,'delegate',?,'human',?,?,'{}','task','always','2026-01-01','2026-01-01')")
            .bind(task).bind(status).bind(task).bind(&id).execute(store.pool()).await.unwrap();
    }
    let summary = store.agent_chat_attention(&id).await.unwrap();
    assert_eq!(summary.open_child_task_count, 2);
    assert!(summary.child_needs_input);
    assert!(summary.child_failed);
    store.mark_agent_chat_read(&id, 0).await.unwrap();
    store.archive_agent_chat(&id).await.unwrap();
    sqlx::query("DELETE FROM agentChatSessions WHERE chatId = ?")
        .bind(&id)
        .execute(store.pool())
        .await
        .unwrap();
    let rows: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM agentChatReadCursors WHERE chatId = ?")
            .bind(&id)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(rows, 0);
}

#[tokio::test]
async fn parent_chat_is_the_first_delegation_and_ignores_messages() {
    let (_dir, store) = store_with_workspace("ws").await;
    let parent = create_chat(&store, "ws", "parent-tab").await;
    let other = create_chat(&store, "ws", "other-tab").await;
    let child = create_chat(&store, "ws", "child-tab").await;
    assert_eq!(
        store
            .agent_chat_attention(&child)
            .await
            .unwrap()
            .parent_chat_id,
        None
    );
    for (task, kind, from) in [
        ("message", "message", &other),
        ("first", "delegate", &parent),
        ("later", "delegate", &other),
    ] {
        sqlx::query("INSERT INTO chatOrchestrationTasks (taskId,kind,status,callerScope,rootTaskId,parentChatId,childChatId,targetJson,brief,notify,createdAt,updatedAt) \
            VALUES (?,?,'running','human',?,?,?,'{}','task','always','2026-01-01','2026-01-01')")
            .bind(task).bind(kind).bind(task).bind(from).bind(&child).execute(store.pool()).await.unwrap();
    }
    let summary = store.agent_chat_attention(&child).await.unwrap();
    assert_eq!(summary.parent_chat_id.as_deref(), Some(parent.as_str()));
    assert_eq!(
        store
            .agent_chat_attention(&parent)
            .await
            .unwrap()
            .parent_chat_id,
        None
    );
}

#[tokio::test]
async fn mark_read_receipt_conflicts_serialize_and_failed_receipts_roll_back() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = create_chat(&store, "ws", "tab").await;
    let phone = RuntimeStore::open(dir.path()).await.unwrap();
    let desktop_receipt = settings_receipt("read");
    let mut phone_receipt = desktop_receipt.clone();
    phone_receipt.digest = "different".into();
    let (desktop, phone_result) = tokio::join!(
        store.mark_agent_chat_read_with_receipt(&id, 0, &desktop_receipt),
        phone.mark_agent_chat_read_with_receipt(&id, 0, &phone_receipt),
    );
    assert!(matches!(
        (desktop.unwrap(), phone_result.unwrap()),
        (
            AgentChatReadOutcome::Applied(_),
            AgentChatReadOutcome::ReceiptConflict
        ) | (
            AgentChatReadOutcome::ReceiptConflict,
            AgentChatReadOutcome::Applied(_)
        )
    ));
    assert_eq!(store.agent_chat(&id).await.unwrap().unwrap().cursor, 0);
    sqlx::query("DELETE FROM agentChatReadCursors WHERE chatId = ?")
        .bind(&id)
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("CREATE TRIGGER rejectReadReceipt BEFORE INSERT ON agentChatReceipts BEGIN SELECT RAISE(ABORT, 'reject read'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .mark_agent_chat_read_with_receipt(&id, 0, &settings_receipt("read-failed"))
        .await
        .is_err());
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM agentChatReadCursors WHERE chatId = ?")
            .bind(&id)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(count, 0);
}
