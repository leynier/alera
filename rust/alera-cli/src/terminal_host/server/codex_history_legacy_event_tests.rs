use super::*;
use alera_core::runtime::CodexQueueEntry;

#[tokio::test]
async fn all_terminal_notifications_advance_queues_and_refresh_runtime_activity() {
    for method in [
        "turn/completed",
        "turn/failed",
        "turn/aborted",
        "turn/interrupted",
        "codex/event/task_complete",
        "codex/event/task_failed",
        "codex/event/turn_aborted",
        "codex/event/turn_interrupted",
    ] {
        for paused in [false, true] {
            let (_dir, mut actor, backend, mut rx) = fixture().await;
            let mut state = CodexChatDeliveryState::new("tab", "thread");
            state.paused = paused;
            state.messages.push(CodexQueueEntry {
                id:"queued".into(), revision:0,
                payload:json!({"clientUserMessageId":"queued","input":[{"type":"text","text":"Queued"}],"userMessage":{"text":"Queued"}}),
                status:"queued".into(), error:None, turn_id:None,
            });
            actor.save_codex_delivery(&mut state).await.unwrap();
            assert!(actor.clients.is_empty());
            assert!(actor.codex_delivery_active.contains("tab"));
            let params = if method.starts_with("codex/event/") {
                json!({"msg":{"thread_id":"thread","turn_id":"third"}})
            } else {
                json!({"threadId":"thread","turn":{"id":"third","status":"completed"}})
            };
            actor
                .handle_codex_message(json!({"method":method,"params":params}))
                .await;
            assert_eq!(
                actor.codex_delivery_active.contains("tab"),
                !paused,
                "{method}"
            );
            let mut advanced = false;
            loop {
                let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
                    .await
                    .unwrap()
                    .unwrap();
                if matches!(command, ServerCommand::CodexQueueAdvance { .. }) {
                    advanced = true;
                    actor.handle_codex_command(command).await;
                    if paused {
                        break;
                    }
                } else if matches!(command, ServerCommand::CodexQueueDelivered { .. }) {
                    actor.handle_codex_command(command).await;
                    break;
                }
            }
            assert!(advanced, "{method}");
            let state = actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap();
            assert_eq!(
                state.messages[0].status,
                if paused { "queued" } else { "accepted" }
            );
            assert_eq!(
                backend
                    .lock()
                    .unwrap()
                    .calls
                    .iter()
                    .filter(|(method, _)| method == "turn/start")
                    .count(),
                usize::from(!paused)
            );
        }
    }
}

#[tokio::test]
async fn discarded_legacy_and_item_notifications_cannot_change_corrected_history() {
    let (_dir, mut actor, _backend, mut rx) = fixture().await;
    actor.edit_codex_history(&json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit","turnId":"second","text":"Correction","expectedHistoryRevision":0})).await.unwrap();
    assert_eq!(
        complete_edit(&mut actor, &mut rx).await.operations[0].phase,
        "completed"
    );
    while rx.try_recv().is_ok() {}
    let before = actor.codex_tab("tab").await.unwrap().payload;
    assert_eq!(before["codexSnapshot"]["activeTurnId"], "corrected");
    for message in [
        json!({"method":"codex/event/task_complete","params":{"msg":{"thread_id":"thread","turn_id":"third"}}}),
        json!({"method":"codex/event/agent_message","params":{"msg":{"thread_id":"thread","turn_id":"third","message":"Discarded response"}}}),
        json!({"method":"codex/event/task_failed","params":{"msg":{"threadId":"thread","turnId":"third"}}}),
        json!({"method":"item/completed","params":{"threadId":"thread","item":{"type":"agentMessage","id":"discarded-response","turn_id":"third","text":"Discarded response"}}}),
        json!({"method":"turn/completed","params":{"threadId":"thread","turn_id":"third"}}),
        json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"third","status":"completed"}}}),
    ] {
        actor.handle_codex_message(message).await;
        assert_eq!(actor.codex_tab("tab").await.unwrap().payload, before);
        assert!(actor.codex_delivery_active.contains("tab"));
        while let Ok(command) = rx.try_recv() {
            assert!(!matches!(command, ServerCommand::CodexQueueAdvance { .. }));
        }
    }
    actor.handle_codex_message(json!({"method":"codex/event/task_complete","params":{"msg":{"thread_id":"thread","turn_id":"corrected"}}})).await;
    assert!(!actor.codex_delivery_active.contains("tab"));
}

#[tokio::test]
async fn old_terminal_events_do_not_dispatch_over_a_new_active_turn() {
    let (_dir, mut actor, backend, mut rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.messages.push(CodexQueueEntry {
        id: "queued".into(),
        revision: 0,
        payload: json!({"input":[{"type":"text","text":"Queued"}]}),
        status: "queued".into(),
        error: None,
        turn_id: None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    for method in [
        "turn/completed",
        "codex/event/task_complete",
        "codex/event/task_failed",
        "codex/event/turn_aborted",
        "codex/event/turn_interrupted",
    ] {
        actor
            .handle_codex_message(
                json!({"method":method,"params":{"threadId":"thread","turnId":"second"}}),
            )
            .await;
        while let Ok(command) = rx.try_recv() {
            if matches!(command, ServerCommand::CodexQueueAdvance { .. }) {
                actor.handle_codex_command(command).await;
            }
        }
        assert_eq!(
            actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["activeTurnId"],
            "third"
        );
        assert!(actor.codex_delivery_active.contains("tab"));
        assert_eq!(
            actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap()
                .messages[0]
                .status,
            "queued"
        );
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
    }
    actor
        .handle_codex_message(
            json!({"method":"codex/event/task_complete","params":{"msg":{"thread_id":"thread"}}}),
        )
        .await;
    assert!(
        actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["activeTurnId"].is_null()
    );
}

#[tokio::test]
async fn legacy_completion_before_delivery_ack_does_not_reactivate_a_finished_turn() {
    for method in [
        "codex/event/task_complete",
        "codex/event/task_failed",
        "codex/event/turn_aborted",
        "codex/event/turn_interrupted",
    ] {
        let (_dir, mut actor, _backend, _rx) = fixture().await;
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.messages.push(CodexQueueEntry {
            id:"queued".into(), revision:0,
            payload:json!({"input":[{"type":"text","text":"Queued"}],"userMessage":{"text":"Queued"}}),
            status:"sending".into(), error:None, turn_id:None,
        });
        actor.save_codex_delivery(&mut state).await.unwrap();
        actor
            .handle_codex_message(
                json!({"method":method,"params":{"msg":{"thread_id":"thread","turn_id":"third"}}}),
            )
            .await;
        actor
            .finish_codex_queue_delivery(
                "tab",
                "thread",
                "queued",
                Ok(json!({"turn":{"id":"third","status":"inProgress"}})),
            )
            .await
            .unwrap();
        assert!(
            actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["activeTurnId"]
                .is_null()
        );
        assert!(!actor.codex_delivery_active.contains("tab"));
        assert_eq!(
            actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap()
                .messages[0]
                .status,
            "accepted"
        );
    }
}

#[tokio::test]
async fn idless_completion_before_ack_advances_the_next_queue_entry_once() {
    for method in [
        "turn/completed",
        "turn/failed",
        "turn/aborted",
        "turn/interrupted",
        "codex/event/task_complete",
        "codex/event/task_failed",
        "codex/event/turn_aborted",
        "codex/event/turn_interrupted",
    ] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        for (id, status) in [("first-send", "sending"), ("next-send", "queued")] {
            state.messages.push(CodexQueueEntry {
                id: id.into(), revision: 0,
                payload: json!({"clientUserMessageId":id,"input":[{"type":"text","text":id}],"userMessage":{"text":id}}),
                status: status.into(), error: None, turn_id: None,
            });
        }
        actor.save_codex_delivery(&mut state).await.unwrap();
        actor.handle_codex_message(json!({"method":method,"params":{"threadId":"thread","msg":{"thread_id":"thread"}}})).await;
        actor
            .finish_codex_queue_delivery(
                "tab",
                "thread",
                "first-send",
                Ok(json!({"turn":{"id":"third","status":"inProgress"}})),
            )
            .await
            .unwrap();
        let tab = actor.codex_tab("tab").await.unwrap();
        assert!(
            tab.payload["codexSnapshot"]["activeTurnId"].is_null(),
            "{method}"
        );
        assert!(tab.payload["codexCompletedTurnIds"]
            .as_array()
            .unwrap()
            .contains(&json!("third")));
        assert!(actor.codex_delivery_active.contains("tab"));
        loop {
            let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
                .await
                .unwrap()
                .unwrap();
            let delivered = matches!(command, ServerCommand::CodexQueueDelivered { .. });
            if matches!(command, ServerCommand::CodexQueueAdvance { .. }) || delivered {
                actor.handle_codex_command(command).await;
            }
            if delivered {
                break;
            }
        }
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert!(state
            .messages
            .iter()
            .all(|entry| entry.status == "accepted"));
        assert_eq!(
            backend
                .lock()
                .unwrap()
                .calls
                .iter()
                .filter(|(method, _)| method == "turn/start")
                .count(),
            1
        );
    }
}

#[tokio::test]
async fn batched_idless_completion_records_the_turn_started_inside_the_batch() {
    let (_dir, mut actor, _backend, _rx) = fixture().await;
    actor.codex_pending_messages.insert("tab".into(), vec![
        json!({"method":"turn/started","params":{"threadId":"thread","turn":{"id":"fourth","status":"inProgress"}}}),
        json!({"method":"codex/event/task_complete","params":{"msg":{"thread_id":"thread"}}}),
    ]);
    actor.handle_codex_force_flush("tab").await;
    let tab = actor.codex_tab("tab").await.unwrap();
    assert_eq!(tab.payload["codexCompletedTurnIds"], json!(["fourth"]));
    actor
        .persist_codex_user_input(
            "tab",
            &json!([{"type":"text","text":"Late acknowledgement"}]),
            None,
            "fourth",
            Some("late"),
            false,
        )
        .await;
    assert!(
        actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["activeTurnId"].is_null()
    );
}
