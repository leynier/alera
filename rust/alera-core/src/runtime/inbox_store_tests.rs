use serde_json::json;
use sqlx::Row;

use super::inbox_store::sqlite_timestamp;
use super::inbox_test_support::*;
use super::*;

#[tokio::test]
async fn migration_adds_inbox_columns_idempotently() {
    let dir = tempfile::tempdir().unwrap();
    let first = RuntimeStore::open(dir.path()).await.unwrap();
    drop(first);
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let columns: Vec<String> = sqlx::query("PRAGMA table_info(orchestrationMessages)")
        .fetch_all(store.pool())
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.get::<String, _>("name"))
        .collect();
    assert!(columns.contains(&"reply_to_id".to_string()));
    assert!(columns.contains(&"external_meta".to_string()));
    assert_eq!(store.inbox_revision().await.unwrap(), 0);
}

#[tokio::test]
async fn question_defaults_to_five_hours_and_validates_its_inputs() {
    let (_dir, store) = store().await;
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let expected = sqlite_timestamp(chrono::Utc::now() + chrono::Duration::hours(5));
    let expires_at = asked.expires_at.clone().unwrap();
    assert!(expires_at <= expected && expires_at.as_str() > &expected[..15]);
    assert_eq!(asked.message_type, OrchestrationMessageType::DecisionGate);
    assert_eq!(
        asked.external_meta.as_ref().unwrap()["origin"]["surface"],
        "cli"
    );

    for (inbox, recipient) in [
        ("ci", "agent"),
        ("ext:", "agent"),
        ("ext:CI", "agent"),
        ("ext:-ci", "agent"),
        ("ext:ci", "@all"),
        ("ext:ci", "ext:other"),
    ] {
        assert!(store
            .insert_inbox_question(question(inbox, recipient))
            .await
            .is_err());
    }
    let mut short = question("ext:ci", "agent");
    short.expires_in_seconds = Some(10);
    assert!(store.insert_inbox_question(short).await.is_err());
    let mut long = question("ext:ci", "agent");
    long.expires_in_seconds = Some(INBOX_MAX_EXPIRY_SECONDS + 1);
    assert!(store.insert_inbox_question(long).await.is_err());
}

#[tokio::test]
async fn follow_ups_stay_on_the_same_recipient_and_inbox() {
    let (_dir, store) = store().await;
    let root = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let mut follow_up = question("ext:ci", "agent");
    follow_up.thread_id = Some(root.id.clone());
    let follow_up = store.insert_inbox_question(follow_up).await.unwrap();
    assert_eq!(follow_up.thread_id.as_deref(), Some(root.id.as_str()));

    let mut other_recipient = question("ext:ci", "other");
    other_recipient.thread_id = Some(root.id.clone());
    assert!(store.insert_inbox_question(other_recipient).await.is_err());
    let mut other_inbox = question("ext:user", "agent");
    other_inbox.thread_id = Some(root.id.clone());
    assert!(store.insert_inbox_question(other_inbox).await.is_err());
    let mut nested = question("ext:ci", "agent");
    nested.thread_id = Some(follow_up.id.clone());
    assert!(store.insert_inbox_question(nested).await.is_err());

    let detail = store.inbox_thread(&root.id).await.unwrap().unwrap();
    assert_eq!(detail.thread.question_count, 2);
}

#[tokio::test]
async fn pending_limit_counts_only_undelivered_external_questions() {
    let (_dir, store) = store().await;
    let mut ids = Vec::new();
    for _ in 0..INBOX_PENDING_LIMIT {
        ids.push(
            store
                .insert_inbox_question(question("ext:ci", "agent"))
                .await
                .unwrap()
                .id,
        );
    }
    store
        .insert_orchestration_message(message("coord", "agent", OrchestrationMessageType::Status))
        .await
        .unwrap();
    let refused = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap_err();
    assert!(refused.to_string().starts_with("inbox_pending_limit"));
    store
        .insert_inbox_question(question("ext:ci", "someone-else"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_delivered(&ids[..1])
        .await
        .unwrap();
    store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
}

#[tokio::test]
async fn question_status_covers_every_state() {
    let (_dir, store) = store().await;
    let pending = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    assert_eq!(
        status_of(&store, &pending.id, &pending.id).await,
        InboxQuestionStatus::Pending
    );

    let delivered = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&delivered.id))
        .await
        .unwrap();
    assert_eq!(
        status_of(&store, &delivered.id, &delivered.id).await,
        InboxQuestionStatus::Delivered
    );

    let received = store
        .insert_inbox_question(question("ext:ci", "coordinator"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_read(std::slice::from_ref(&received.id))
        .await
        .unwrap();
    assert_eq!(
        status_of(&store, &received.id, &received.id).await,
        InboxQuestionStatus::Received
    );

    reply(&store, &delivered).await;
    assert_eq!(
        status_of(&store, &delivered.id, &delivered.id).await,
        InboxQuestionStatus::Answered
    );

    let expired = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    set_column(
        &store,
        &expired.id,
        "expires_at = datetime('now', '-1 minute')",
    )
    .await;
    assert_eq!(
        status_of(&store, &expired.id, &expired.id).await,
        InboxQuestionStatus::Expired
    );

    let cancelled = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let cancelled = store
        .cancel_inbox_question(&cancelled.id, json!({"surface": "desktop"}))
        .await
        .unwrap();
    assert_eq!(cancelled.state, "obsolete");
    assert_eq!(
        cancelled.external_meta.as_ref().unwrap()["cancellation"]["surface"],
        "desktop"
    );
    assert_eq!(
        status_of(&store, &cancelled.id, &cancelled.id).await,
        InboxQuestionStatus::Cancelled
    );
}

#[tokio::test]
async fn only_undelivered_questions_can_be_cancelled() {
    let (_dir, store) = store().await;
    let delivered = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&delivered.id))
        .await
        .unwrap();
    let refused = store
        .cancel_inbox_question(&delivered.id, json!({}))
        .await
        .unwrap_err();
    assert!(refused.to_string().starts_with("inbox_not_cancellable"));
    let agent = store
        .insert_orchestration_message(message("coord", "agent", OrchestrationMessageType::Status))
        .await
        .unwrap();
    assert!(store
        .cancel_inbox_question(&agent.id, json!({}))
        .await
        .unwrap_err()
        .to_string()
        .starts_with("inbox_question_not_found"));
}

#[tokio::test]
async fn delivered_inbox_questions_do_not_expire_but_agent_messages_still_do() {
    let (_dir, store) = store().await;
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let mut agent = message("coord", "agent", OrchestrationMessageType::Status);
    agent.expires_at = Some("2000-01-01 00:00:00".to_string());
    let agent = store.insert_orchestration_message(agent).await.unwrap();
    let ids = vec![asked.id.clone(), agent.id.clone()];
    store
        .mark_orchestration_messages_delivered(&ids)
        .await
        .unwrap();
    set_column(&store, &asked.id, "expires_at = '2000-01-01 00:00:00'").await;

    store.inbox_summary().await.unwrap();
    let asked = store
        .orchestration_message_by_id(&asked.id)
        .await
        .unwrap()
        .unwrap();
    let agent = store
        .orchestration_message_by_id(&agent.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(asked.state, "delivered");
    assert_eq!(agent.state, "expired");
}

#[tokio::test]
async fn only_explicit_references_answer_a_question() {
    let (_dir, store) = store().await;
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let mut loose = message("agent", "ext:ci", OrchestrationMessageType::Status);
    loose.thread_id = Some(asked.id.clone());
    store.insert_orchestration_message(loose).await.unwrap();
    let mut stranger = message("other", "ext:ci", OrchestrationMessageType::Status);
    stranger.thread_id = Some(asked.id.clone());
    stranger.reply_to_id = Some(asked.id.clone());
    store.insert_orchestration_message(stranger).await.unwrap();

    let detail = store.inbox_thread(&asked.id).await.unwrap().unwrap();
    assert_eq!(detail.thread.status, InboxQuestionStatus::Pending);
    assert_eq!(store.inbox_summary().await.unwrap()[0].pending_count, 1);
    let kinds: Vec<_> = detail.messages.iter().map(|entry| entry.kind).collect();
    assert_eq!(
        kinds,
        [
            InboxMessageKind::Question,
            InboxMessageKind::Message,
            InboxMessageKind::Message
        ]
    );

    reply(&store, &asked).await;
    let detail = store.inbox_thread(&asked.id).await.unwrap().unwrap();
    assert_eq!(detail.thread.status, InboxQuestionStatus::Answered);
    assert_eq!(detail.thread.reply_count, 3);
    assert_eq!(detail.messages[3].kind, InboxMessageKind::Reply);
    // Answered before it was pasted, so it no longer counts as pending.
    let summary = store.inbox_summary().await.unwrap();
    assert_eq!(summary[0].pending_count, 0);
}

#[tokio::test]
async fn revision_moves_with_inbox_rows_only() {
    let (_dir, store) = store().await;
    let start = store.inbox_revision().await.unwrap();
    store
        .insert_orchestration_message(message("coord", "agent", OrchestrationMessageType::Status))
        .await
        .unwrap();
    assert_eq!(store.inbox_revision().await.unwrap(), start);

    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let after_ask = store.inbox_revision().await.unwrap();
    assert!(after_ask > start);
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&asked.id))
        .await
        .unwrap();
    let after_delivery = store.inbox_revision().await.unwrap();
    assert!(after_delivery > after_ask);
    let answer = reply(&store, &asked).await;
    let after_reply = store.inbox_revision().await.unwrap();
    assert!(after_reply > after_delivery);
    assert_eq!(
        store
            .mark_inbox_messages_read(std::slice::from_ref(&answer.id))
            .await
            .unwrap(),
        1
    );
    let after_read = store.inbox_revision().await.unwrap();
    assert!(after_read > after_reply);

    let expiring = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    set_column(&store, &expiring.id, "expires_at = '2000-01-01 00:00:00'").await;
    let before_expiry = store.inbox_revision().await.unwrap();
    store.inbox_summary().await.unwrap();
    assert!(store.take_inbox_change().await.unwrap().is_some());
    assert!(store.inbox_revision().await.unwrap() > before_expiry);
    assert_eq!(store.take_inbox_change().await.unwrap(), None);
}

#[tokio::test]
async fn read_marks_only_messages_addressed_to_an_inbox() {
    let (_dir, store) = store().await;
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let answer = reply(&store, &asked).await;
    let ids = vec![asked.id.clone(), answer.id.clone()];
    assert_eq!(store.mark_inbox_messages_read(&ids).await.unwrap(), 1);
    let asked = store
        .orchestration_message_by_id(&asked.id)
        .await
        .unwrap()
        .unwrap();
    assert!(!asked.read);
}

#[tokio::test]
async fn expiring_reports_the_inboxes_that_changed() {
    let (_dir, store) = store().await;
    assert!(store.expire_inbox_questions().await.unwrap().is_empty());
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    store
        .insert_inbox_question(question("ext:user", "agent"))
        .await
        .unwrap();
    set_column(
        &store,
        &asked.id,
        "expires_at = datetime('now', '-1 minute')",
    )
    .await;
    assert_eq!(store.expire_inbox_questions().await.unwrap(), ["ext:ci"]);
    let asked = store
        .orchestration_message_by_id(&asked.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(asked.state, "expired");
    assert!(store.expire_inbox_questions().await.unwrap().is_empty());
}

#[tokio::test]
async fn a_question_that_expires_while_being_pasted_counts_as_delivered() {
    let (_dir, store) = store().await;
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    set_column(
        &store,
        &asked.id,
        "expires_at = datetime('now', '-1 minute')",
    )
    .await;
    store.expire_inbox_questions().await.unwrap();
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&asked.id))
        .await
        .unwrap();
    let asked = store
        .orchestration_message_by_id(&asked.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(asked.state, "delivered");
    let summary = store.inbox_summary().await.unwrap();
    assert_eq!(summary[0].awaiting_reply_count, 1);
}
