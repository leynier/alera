use serde_json::json;

use super::*;

pub(super) async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

pub(super) fn message(
    from: &str,
    to: &str,
    message_type: OrchestrationMessageType,
) -> NewOrchestrationMessage {
    NewOrchestrationMessage {
        from_handle: from.to_string(),
        to_handle: to.to_string(),
        subject: "subject".to_string(),
        body: "body".to_string(),
        message_type,
        priority: OrchestrationMessagePriority::Normal,
        thread_id: None,
        payload: None,
        run_id: None,
        workspace_id: Some("workspace_1".to_string()),
        task_id: None,
        dispatch_id: None,
        expires_at: None,
        reply_to_id: None,
        external_meta: None,
    }
}

pub(super) fn question(inbox: &str, recipient: &str) -> NewInboxQuestion {
    NewInboxQuestion {
        inbox: inbox.to_string(),
        recipient: recipient.to_string(),
        subject: "Migration risk".to_string(),
        body: "What could break?".to_string(),
        priority: OrchestrationMessagePriority::High,
        thread_id: None,
        workspace_id: Some("workspace_1".to_string()),
        payload: None,
        expires_in_seconds: None,
        external_meta: json!({"version": 1, "origin": {"surface": "cli"}}),
    }
}

pub(super) async fn reply(store: &RuntimeStore, to: &OrchestrationMessage) -> OrchestrationMessage {
    let mut reply = message(
        &to.to_handle,
        &to.from_handle,
        OrchestrationMessageType::Status,
    );
    reply.thread_id = Some(to.thread_id.clone().unwrap_or_else(|| to.id.clone()));
    reply.reply_to_id = Some(to.id.clone());
    store.insert_orchestration_message(reply).await.unwrap()
}

pub(super) async fn status_of(store: &RuntimeStore, thread: &str, id: &str) -> InboxQuestionStatus {
    let detail = store.inbox_thread(thread).await.unwrap().unwrap();
    detail
        .messages
        .iter()
        .find(|entry| entry.message.id == id)
        .and_then(|entry| entry.status)
        .unwrap()
}

pub(super) async fn set_column(store: &RuntimeStore, id: &str, assignment: &str) {
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "UPDATE orchestrationMessages SET {assignment} WHERE id = ?"
    )))
    .bind(id)
    .execute(store.pool())
    .await
    .unwrap();
}
