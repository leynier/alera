use super::inbox_test_support::*;
use super::*;

#[tokio::test]
async fn summary_and_listing_reflect_threads() {
    let (_dir, store) = store().await;
    let pending = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let answered = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&answered.id))
        .await
        .unwrap();
    reply(&store, &answered).await;
    let awaiting = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&awaiting.id))
        .await
        .unwrap();
    let mut elsewhere = question("ext:user", "agent");
    elsewhere.workspace_id = Some("workspace_2".to_string());
    store.insert_inbox_question(elsewhere).await.unwrap();

    let summary = store.inbox_summary().await.unwrap();
    let ci = summary
        .iter()
        .find(|entry| entry.inbox == "ext:ci")
        .unwrap();
    assert_eq!(ci.thread_count, 3);
    assert_eq!(ci.pending_count, 1);
    assert_eq!(ci.awaiting_reply_count, 1);
    assert_eq!(ci.unread_reply_count, 1);
    assert_eq!(summary.len(), 2);

    let all = store
        .inbox_threads(InboxThreadFilter {
            limit: 50,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(all.items.len(), 4);
    assert_eq!(all.next_before, None);
    let answered_only = store
        .inbox_threads(InboxThreadFilter {
            inbox: Some("ext:ci".to_string()),
            status: Some(InboxQuestionStatus::Answered),
            limit: 50,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(answered_only.items.len(), 1);
    assert_eq!(answered_only.items[0].thread_id, answered.id);
    let workspace = store
        .inbox_threads(InboxThreadFilter {
            workspace_id: Some("workspace_2".to_string()),
            limit: 50,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(workspace.items.len(), 1);
    let first_page = store
        .inbox_threads(InboxThreadFilter {
            limit: 2,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(first_page.items.len(), 2);
    let second_page = store
        .inbox_threads(InboxThreadFilter {
            limit: 2,
            before_sequence: first_page.next_before,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(second_page.items.len(), 2);
    assert_eq!(second_page.items[1].thread_id, pending.id);
    assert!(store.inbox_thread("missing").await.unwrap().is_none());
}

#[tokio::test]
async fn purge_removes_an_inbox_and_its_threads() {
    let (_dir, store) = store().await;
    let asked = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    reply(&store, &asked).await;
    let kept = store
        .insert_inbox_question(question("ext:user", "agent"))
        .await
        .unwrap();
    let agent = store
        .insert_orchestration_message(message("coord", "agent", OrchestrationMessageType::Status))
        .await
        .unwrap();
    assert_eq!(store.purge_inbox("ext:ci").await.unwrap(), 2);
    assert!(store.inbox_thread(&asked.id).await.unwrap().is_none());
    assert!(store.inbox_thread(&kept.id).await.unwrap().is_some());
    assert!(store
        .orchestration_message_by_id(&agent.id)
        .await
        .unwrap()
        .is_some());
    assert!(store.purge_inbox("coord").await.is_err());
}

#[tokio::test]
async fn pruning_keeps_recent_and_pending_conversations() {
    let (_dir, store) = store().await;
    let old = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&old.id))
        .await
        .unwrap();
    let old_reply = reply(&store, &old).await;
    let recent_reply_thread = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let recent_reply = reply(&store, &recent_reply_thread).await;
    let waiting = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    let mut loose = message("agent", "ext:ci", OrchestrationMessageType::Status);
    loose.thread_id = None;
    let loose = store.insert_orchestration_message(loose).await.unwrap();
    let agent = store
        .insert_orchestration_message(message("coord", "agent", OrchestrationMessageType::Status))
        .await
        .unwrap();
    for id in [
        &old.id,
        &old_reply.id,
        &recent_reply_thread.id,
        &waiting.id,
        &loose.id,
        &agent.id,
    ] {
        set_column(&store, id, "created_at = datetime('now', '-8 days')").await;
    }
    set_column(
        &store,
        &waiting.id,
        "expires_at = datetime('now', '+1 hour')",
    )
    .await;
    assert_eq!(
        recent_reply.thread_id.as_deref(),
        Some(recent_reply_thread.id.as_str())
    );

    assert_eq!(store.prune_inbox_history().await.unwrap(), 3);
    assert!(store.inbox_thread(&old.id).await.unwrap().is_none());
    assert!(store
        .inbox_thread(&recent_reply_thread.id)
        .await
        .unwrap()
        .is_some());
    assert!(store.inbox_thread(&waiting.id).await.unwrap().is_some());
    assert!(store
        .orchestration_message_by_id(&loose.id)
        .await
        .unwrap()
        .is_none());
    assert!(store
        .orchestration_message_by_id(&agent.id)
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn threads_page_by_latest_activity_and_filter_before_the_limit() {
    let (_dir, store) = store().await;
    let oldest = store
        .insert_inbox_question(question("ext:ci", "agent"))
        .await
        .unwrap();
    for _ in 0..3 {
        store
            .insert_inbox_question(question("ext:ci", "other"))
            .await
            .unwrap();
    }
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&oldest.id))
        .await
        .unwrap();
    reply(&store, &oldest).await;

    let first = store
        .inbox_threads(InboxThreadFilter {
            limit: 1,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(
        first.items[0].thread_id, oldest.id,
        "a new reply moves the thread up"
    );
    assert!(first.next_before.is_some());

    let answered = store
        .inbox_threads(InboxThreadFilter {
            status: Some(InboxQuestionStatus::Pending),
            limit: 2,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(answered.items.len(), 2, "the filter runs before the limit");
    let rest = store
        .inbox_threads(InboxThreadFilter {
            status: Some(InboxQuestionStatus::Pending),
            limit: 2,
            before_sequence: answered.next_before,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(rest.items.len(), 1);
    assert_eq!(rest.next_before, None);
}
