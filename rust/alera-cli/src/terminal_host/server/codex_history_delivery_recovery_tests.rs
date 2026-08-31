use super::*;
use alera_core::runtime::CodexQueueEntry;

#[tokio::test]
async fn reconciliation_restores_receipt_presentation_once_and_preserves_native_activity() {
    for steering in [false, true] {
        for status in ["sending", "uncertain"] {
            let (_directory, mut actor, backend, _rx) = fixture().await;
            let mut state = CodexChatDeliveryState::new("tab", "thread");
            state.paused = true;
            let mut payload = json!({"input":[{"type":"text","text":"Native first"}],"userMessage":{"text":"Visible first","attachments":[{"path":"/receipt/image.png","name":"image.png","isImage":true}]}});
            if steering {
                payload["turnId"] = json!("first");
            }
            state.messages.push(CodexQueueEntry {
                id: "client-first".into(),
                revision: 0,
                payload,
                status: status.into(),
                error: None,
                turn_id: None,
            });
            actor.save_codex_delivery(&mut state).await.unwrap();
            for _ in 0..2 {
                actor.reconcile_codex_queue(state).await.unwrap();
                state = actor
                    .runtime_store
                    .codex_chat_state("thread")
                    .await
                    .unwrap()
                    .unwrap();
                let tab = actor.codex_tab("tab").await.unwrap();
                let snapshot = &tab.payload["codexSnapshot"];
                assert_eq!(snapshot["activeTurnId"], "third");
                let messages: Vec<_> = snapshot["timelineCells"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .filter(|cell| cell["kind"] == "userMessage" && cell["turnId"] == "first")
                    .collect();
                assert_eq!(messages.len(), 1);
                assert_eq!(messages[0]["markdownText"], "Visible first");
                assert_eq!(
                    messages[0]["metadata"]["attachments"][0]["path"],
                    "/receipt/image.png"
                );
                assert_eq!(
                    messages[0]["metadata"]["isSteering"]
                        .as_bool()
                        .unwrap_or(false),
                    steering
                );
                assert_eq!(state.messages[0].status, "accepted");
            }
            state.discarded_turn_ids.push("first".into());
            let turns = backend.lock().unwrap().turns[1..].to_vec();
            actor
                .replace_codex_history_snapshot(
                    &state,
                    &json!({"thread":{"id":"thread","turns":turns}}),
                )
                .await
                .unwrap();
            let tab = actor.codex_tab("tab").await.unwrap();
            assert!(tab.payload["codexSnapshot"]["timelineCells"]
                .as_array()
                .unwrap()
                .iter()
                .all(|cell| cell["turnId"] != "first"));
        }
    }
}

#[tokio::test]
async fn interrupt_pauses_the_latest_queue_without_a_client_revision_and_checks_identity_first() {
    for pending in [false, true] {
        let (_directory, mut actor, backend, _rx) = fixture().await;
        let (handle, _outbound) = crate::terminal_host::client::ClientHandle::test_channels();
        let mut client = super::super::actor_test_harness::local_client(handle);
        client.supports_codex_tab_kind = true;
        actor.clients.insert(1, client);
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        if pending {
            state.messages.push(CodexQueueEntry {
                id: "queued".into(),
                revision: 0,
                payload: json!({}),
                status: "queued".into(),
                error: None,
                turn_id: None,
            });
        }
        actor.save_codex_delivery(&mut state).await.unwrap();
        actor.save_codex_delivery(&mut state).await.unwrap();
        let error = actor
            .handle_codex_request(
                1,
                "codex.turn.interrupt",
                &json!({"tabId":"tab","expectedThreadId":"wrong","turnId":"third"}),
            )
            .await;
        assert!(error.is_err());
        assert!(
            !actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap()
                .paused
        );
        backend.lock().unwrap().reject_interrupt = true;
        let result=actor.handle_codex_request(1,"codex.turn.interrupt",&json!({"tabId":"tab","expectedThreadId":"thread","turnId":"third","expectedRevision":0})).await;
        assert!(result.is_err());
        assert!(
            actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap()
                .paused
        );
        assert!(backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, params)| method == "turn/interrupt"
                && params["threadId"] == "thread"
                && params["turnId"] == "third"));
    }
}

#[tokio::test]
async fn cancel_old_queues_after_recovery_uses_a_null_current_thread() {
    let (_directory, mut actor, _backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    state.messages.push(CodexQueueEntry {
        id: "queued".into(),
        revision: 0,
        payload: json!({}),
        status: "queued".into(),
        error: None,
        turn_id: None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    let mut tab = actor.codex_tab("tab").await.unwrap();
    super::super::codex_tab_lifecycle::clear_thread_identity(&mut tab);
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let queue = actor
        .handle_codex_queue_request("codex.queue.get", &json!({"tabId":"tab"}))
        .await
        .unwrap();
    assert_eq!(queue["threadId"], "");
    assert_eq!(queue["otherQueues"][0]["threadId"], "thread");
    actor.handle_codex_queue_request("codex.queue.cancel",&json!({"tabId":"tab","expectedThreadId":null,"expectedRevision":queue["revision"],"otherQueues":queue["otherQueues"]})).await.unwrap();
    assert!(!actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap()
        .has_pending());
}
