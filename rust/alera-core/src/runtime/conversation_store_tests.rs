use super::inbox_test_support::*;
use super::*;

async fn send(
    store: &RuntimeStore,
    from: &str,
    to: &str,
    thread_id: Option<&str>,
    message_type: OrchestrationMessageType,
) -> OrchestrationMessage {
    let mut new = message(from, to, message_type);
    new.thread_id = thread_id.map(str::to_string);
    store.insert_orchestration_message(new).await.unwrap()
}

#[tokio::test]
async fn threads_group_agent_messages_and_skip_task_control() {
    let (_dir, store) = store().await;
    let asked = send(
        &store,
        "worker",
        "coord",
        None,
        OrchestrationMessageType::DecisionGate,
    )
    .await;
    send(
        &store,
        "coord",
        "worker",
        Some(&asked.id),
        OrchestrationMessageType::Status,
    )
    .await;
    for member in ["a", "b"] {
        send(
            &store,
            "coord",
            member,
            Some("thread_group"),
            OrchestrationMessageType::Status,
        )
        .await;
    }
    send(
        &store,
        "worker",
        "coord",
        None,
        OrchestrationMessageType::Escalation,
    )
    .await;
    send(
        &store,
        "worker",
        "coord",
        None,
        OrchestrationMessageType::Heartbeat,
    )
    .await;
    store
        .insert_inbox_question(question("ext:ci", "worker"))
        .await
        .unwrap();

    let page = store
        .conversation_threads(ConversationFilter {
            limit: 50,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(page.items.len(), 2);
    let group = &page.items[0];
    assert!(group.group);
    assert_eq!(group.message_count, 2);
    assert_eq!(group.participants, ["coord", "a", "b"]);
    let ask = &page.items[1];
    assert!(!ask.group);
    assert_eq!(ask.thread_id, asked.id);
    assert_eq!(ask.started_by, "worker");
    assert_eq!(ask.message_count, 2);

    let worker_only = store
        .conversation_threads(ConversationFilter {
            participant: Some("a".to_string()),
            limit: 50,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(worker_only.items.len(), 1);
    let messages = store.conversation_thread("thread_group").await.unwrap();
    assert_eq!(messages.len(), 2);
}

#[tokio::test]
async fn revision_moves_only_for_agent_conversation() {
    let (_dir, store) = store().await;
    let start = store.conversation_revision().await.unwrap();
    send(
        &store,
        "worker",
        "coord",
        None,
        OrchestrationMessageType::Heartbeat,
    )
    .await;
    store
        .insert_inbox_question(question("ext:ci", "worker"))
        .await
        .unwrap();
    assert_eq!(store.conversation_revision().await.unwrap(), start);
    send(&store, "a", "b", None, OrchestrationMessageType::Status).await;
    assert!(store.conversation_revision().await.unwrap() > start);
    assert!(store.take_conversation_change().await.unwrap().is_some());
    assert_eq!(store.take_conversation_change().await.unwrap(), None);
}

#[tokio::test]
async fn pruning_keeps_unread_recent_and_active_task_conversations() {
    let (_dir, store) = store().await;
    let old = send(&store, "a", "b", None, OrchestrationMessageType::Status).await;
    let unread = send(&store, "a", "coord", None, OrchestrationMessageType::Status).await;
    let recent_root = send(&store, "a", "b", None, OrchestrationMessageType::Status).await;
    let recent_reply = send(
        &store,
        "b",
        "a",
        Some(&recent_root.id),
        OrchestrationMessageType::Status,
    )
    .await;
    let control = send(
        &store,
        "a",
        "coord",
        None,
        OrchestrationMessageType::Escalation,
    )
    .await;
    let task = store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "work".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: None,
            run_id: None,
            workspace_id: "workspace_1".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    let mut scoped = message("coord", "worker", OrchestrationMessageType::Status);
    scoped.task_id = Some(task.id.clone());
    let scoped = store.insert_orchestration_message(scoped).await.unwrap();
    let read = vec![
        old.id.clone(),
        recent_root.id.clone(),
        scoped.id.clone(),
        control.id.clone(),
    ];
    store.mark_orchestration_messages_read(&read).await.unwrap();
    for id in [
        &old.id,
        &unread.id,
        &recent_root.id,
        &scoped.id,
        &control.id,
    ] {
        set_column(&store, id, "created_at = datetime('now', '-8 days')").await;
    }
    assert_eq!(
        recent_reply.thread_id.as_deref(),
        Some(recent_root.id.as_str())
    );

    assert_eq!(store.prune_conversation_history().await.unwrap(), 1);
    assert!(store
        .orchestration_message_by_id(&old.id)
        .await
        .unwrap()
        .is_none());
    for kept in [&unread.id, &recent_root.id, &scoped.id, &control.id] {
        assert!(
            store
                .orchestration_message_by_id(kept)
                .await
                .unwrap()
                .is_some(),
            "{kept}"
        );
    }
}

#[tokio::test]
async fn participant_filter_orders_by_the_whole_thread() {
    let (_dir, store) = store().await;
    let group = send(
        &store,
        "a",
        "c",
        Some("thread_g"),
        OrchestrationMessageType::Status,
    )
    .await;
    send(&store, "c", "d", None, OrchestrationMessageType::Status).await;
    let latest = send(
        &store,
        "b",
        "a",
        Some("thread_g"),
        OrchestrationMessageType::Status,
    )
    .await;
    let page = store
        .conversation_threads(ConversationFilter {
            participant: Some("c".to_string()),
            limit: 1,
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(page.items[0].thread_id, "thread_g");
    assert_eq!(page.items[0].last_sequence, latest.sequence);
    assert_eq!(page.next_before, Some(latest.sequence));
    assert!(group.sequence < latest.sequence);
}
