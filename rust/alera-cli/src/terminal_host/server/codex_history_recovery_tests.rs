use super::*;
use alera_core::runtime::CodexQueueEntry;

#[tokio::test]
async fn edit_preserves_uncertain_delivery_evidence_until_reconciliation() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    state.messages.push(CodexQueueEntry {
        id: "client-second".into(),
        revision: 0,
        status: "uncertain".into(),
        error: Some("Response lost".into()),
        turn_id: None,
        payload: json!({"input":[{"type":"text","text":"Second"}]}),
    });
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    let request = json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit-uncertain","turnId":"first","text":"Correction","expectedHistoryRevision":0});
    let error = actor.edit_codex_history(&request).await.unwrap_err();
    assert!(error.wire_message().contains("Reconcile uncertain"));
    assert!(backend.lock().unwrap().calls.is_empty());
    assert_eq!(backend.lock().unwrap().turns.len(), 3);
    actor.reconcile_codex_queue(state).await.unwrap();
    let reconciled = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(reconciled.messages[0].status, "accepted");
    assert!(reconciled.operations.is_empty());
    assert_eq!(reconciled.history_revision, 0);
}

#[tokio::test]
async fn rejected_initial_queue_submission_releases_copies_on_every_retry() {
    let (directory, mut actor, backend, _rx) = fixture().await;
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexThreadId"] = Value::Null;
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let image = directory.path().join("upload.png");
    std::fs::write(&image, b"image bytes").unwrap();
    let request = json!({"tabId":"tab","expectedThreadId":null,"clientUserMessageId":"initial","input":[{"type":"localImage","path":image}],"userMessage":{"attachments":[{"path":image,"isImage":true}]}});
    for _ in 0..2 {
        assert!(actor
            .handle_codex_queue_request("codex.queue.add", &request)
            .await
            .is_err());
        assert_eq!(
            std::fs::read_dir(actor.runtime_dir.join("codex-attachments"))
                .unwrap()
                .count(),
            0
        );
        assert_eq!(std::fs::read(&image).unwrap(), b"image bytes");
    }
    assert_eq!(
        backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .filter(|(method, _)| method == "thread/start")
            .count(),
        2
    );
}

#[tokio::test]
async fn definitive_fork_failure_can_retry_once_with_the_same_identity() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let request = json!({"tabId":"tab","expectedThreadId":"thread","operationId":"retry-fork"});
    backend.lock().unwrap().fork_error = Some("Fork rejected".into());
    assert!(actor.fork_codex_history(&request).await.is_err());
    backend.lock().unwrap().fork_error = None;
    let result = actor.fork_codex_history(&request).await.unwrap();
    assert_eq!(actor.fork_codex_history(&request).await.unwrap(), result);
    assert_eq!(
        backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .filter(|(method, _)| method == "thread/fork")
            .count(),
        2
    );
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.operations.len(), 1);
    assert_eq!(state.operations[0].phase, "completed");
}

#[tokio::test]
async fn uncertain_fork_is_not_retried_with_the_same_identity() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let request = json!({"tabId":"tab","expectedThreadId":"thread","operationId":"uncertain-fork"});
    backend.lock().unwrap().fork_error = Some("Codex timed out".into());
    assert!(actor.fork_codex_history(&request).await.is_err());
    backend.lock().unwrap().fork_error = None;
    assert!(actor.fork_codex_history(&request).await.is_err());
    assert_eq!(
        backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .filter(|(method, _)| method == "thread/fork")
            .count(),
        1
    );
}

#[tokio::test]
async fn persisted_steer_intent_never_becomes_a_new_turn() {
    for active in [true, false] {
        let (_directory, mut actor, backend, mut rx) = fixture().await;
        let mut tab = actor.codex_tab("tab").await.unwrap();
        if !active {
            tab.payload["codexSnapshot"]["activeTurnId"] = Value::Null;
            actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
        }
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.messages.push(CodexQueueEntry {
            id: "normal".into(),
            revision: 0,
            status: "queued".into(),
            error: None,
            turn_id: None,
            payload: json!({"input":[{"type":"text","text":"After the turn"}]}),
        });
        state.messages.push(CodexQueueEntry {
            id: "persisted-steer".into(),
            revision: 0,
            status: "queued".into(),
            error: None,
            turn_id: None,
            payload: json!({"turnId":"third","input":[{"type":"text","text":"Correction"}]}),
        });
        actor
            .runtime_store
            .save_codex_chat_state(&mut state)
            .await
            .unwrap();
        actor.advance_codex_queue("tab").await;
        if active {
            loop {
                let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
                    .await
                    .unwrap()
                    .unwrap();
                if matches!(command, ServerCommand::CodexQueueDelivered { .. }) {
                    actor.handle_codex_command(command).await;
                    break;
                }
            }
        }
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            state.messages[1].status,
            if active { "accepted" } else { "failed" }
        );
        assert_eq!(state.paused, !active);
        assert_eq!(state.messages[0].status, "queued");
        let backend = backend.lock().unwrap();
        assert!(!backend
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
        let steers: Vec<_> = backend
            .calls
            .iter()
            .filter(|(method, _)| method == "turn/steer")
            .collect();
        assert_eq!(steers.len(), usize::from(active));
        if active {
            assert_eq!(steers[0].1["expectedTurnId"], "third");
            assert_eq!(steers[0].1["clientUserMessageId"], "persisted-steer");
        }
    }
}

#[tokio::test]
async fn process_exit_releases_accepted_turn_liveness_and_pauses_pending_delivery() {
    for status in ["accepted", "queued", "sending"] {
        let (_directory, mut actor, backend, _rx) = fixture().await;
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.messages.push(CodexQueueEntry {
            id: "message".into(),
            revision: 0,
            status: status.into(),
            error: None,
            turn_id: Some("third".into()),
            payload: json!({"input":[]}),
        });
        actor.save_codex_delivery(&mut state).await.unwrap();
        assert!(actor.codex_delivery_active.contains("tab"));
        actor
            .handle_codex_process_exited("Codex exited".into())
            .await;
        assert!(actor.codex_delivery_active.is_empty());
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(state.paused, status != "accepted");
        assert_eq!(
            state.messages[0].status,
            if status == "sending" {
                "uncertain"
            } else {
                status
            }
        );
        actor.advance_codex_queue("tab").await;
        assert!(backend.lock().unwrap().calls.is_empty());
    }
}

#[tokio::test]
async fn process_exit_preserves_uncertain_history_phase_without_retaining_host() {
    for phase in ["interrupting", "rollingBack", "resending"] {
        let (_directory, mut actor, _backend, _rx) = fixture().await;
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state
            .operations
            .push(alera_core::runtime::CodexChatOperation {
                id: "edit".into(),
                kind: "edit".into(),
                phase: phase.into(),
                payload: json!({"text":"Correction"}),
                result: None,
            });
        actor.save_codex_delivery(&mut state).await.unwrap();
        actor
            .handle_codex_process_exited("Codex exited".into())
            .await;
        assert!(actor.codex_delivery_active.is_empty());
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert!(state.paused);
        assert_eq!(state.operations[0].phase, "uncertain");
        assert_eq!(state.operations[0].payload["uncertainPhase"], phase);
        assert_eq!(state.operations[0].payload["text"], "Correction");
    }
}

#[tokio::test]
async fn missing_rollout_recovery_resets_history_revision_before_next_submission() {
    let (_directory, mut actor, _backend, _rx) = fixture().await;
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexSnapshot"]["activeTurnId"] = Value::Null;
    tab.payload["codexHistoryRevision"] = json!(5);
    tab.payload["codexDiscardedTurnIds"] = json!(["discarded"]);
    tab.payload["codexCompletedTurnIds"] = json!(["first", "second"]);
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let (handle, _outbound) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut client = super::super::actor_test_harness::local_client(handle);
    client.supports_codex_tab_kind = true;
    actor.clients.insert(1, client);
    let recovered = actor
        .handle_codex_request(
            1,
            "codex.thread.recover",
            &json!({"tabId":"tab","expectedThreadId":"thread"}),
        )
        .await
        .unwrap();
    assert_eq!(recovered["historyRevision"], 0);
    let tab = actor.codex_tab("tab").await.unwrap();
    let revision = tab
        .payload
        .get("codexHistoryRevision")
        .cloned()
        .unwrap_or(json!(0));
    assert_eq!(revision, 0);
    assert!(tab.payload.get("codexDiscardedTurnIds").is_none());
    assert!(tab.payload.get("codexCompletedTurnIds").is_none());
    actor.codex = Some(CodexAppServer::mock(|method, _| {
        assert_eq!(method, "thread/start");
        Ok(json!({"thread":{"id":"recovered"}}))
    }));
    let queue = actor.handle_codex_queue_request("codex.queue.add", &json!({"tabId":"tab","expectedThreadId":null,"expectedHistoryRevision":revision,"clientUserMessageId":"after-recovery","input":[{"type":"text","text":"Continue"}]})).await.unwrap();
    assert_eq!(queue["threadId"], "recovered");
    assert_eq!(queue["historyRevision"], 0);
    assert_eq!(queue["messages"][0]["id"], "after-recovery");
}

#[tokio::test]
async fn deferred_rollback_failure_preserves_process_exit_uncertainty() {
    let (_directory, mut actor, _backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.operations.push(alera_core::runtime::CodexChatOperation {
        id: "edit".into(), kind: "edit".into(), phase: "rollingBack".into(),
        payload: json!({"text":"Correction","editTargetTurnId":"second","editOriginalTurnIds":["first","second","third"]}), result: None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    actor
        .handle_codex_process_exited("Codex exited".into())
        .await;
    actor
        .finish_codex_history_edit("tab", "edit", Err(HostError::state("Codex closed")))
        .await;
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert!(state.paused);
    assert!(state.history_locked());
    assert_eq!(state.operations[0].phase, "uncertain");
    assert_eq!(state.operations[0].payload["uncertainPhase"], "rollingBack");
    actor.codex = Some(CodexAppServer::mock(|method, _| {
        assert_eq!(method, "thread/turns/list");
        Ok(json!({"data":[{"id":"first","status":"completed","items":[]}],"nextCursor":null}))
    }));
    actor
        .reconcile_codex_history_edit("tab", "edit")
        .await
        .unwrap();
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.operations[0].phase, "rolledBack");
    assert_eq!(state.history_revision, 1);
}

#[tokio::test]
async fn history_replacement_keeps_surviving_presentation_without_reviving_discarded_turns() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexSnapshot"]["timelineCells"] = json!([
        {"id":"item-user-first","itemId":"user-first","turnId":"first","kind":"userMessage","markdownText":"Visible attachment prompt","metadata":{"clientUserMessageId":"client-first","attachments":[{"path":"/retained/image.png","isImage":true}]}},
        {"id":"item-steer-first","itemId":"steer-first","turnId":"first","kind":"userMessage","markdownText":"Visible steer","metadata":{"clientUserMessageId":"client-steer","isSteering":true}},
        {"id":"item-user-second","itemId":"user-second","turnId":"second","kind":"userMessage","markdownText":"Discarded","metadata":{"clientUserMessageId":"client-second","attachments":[{"path":"/discarded.png"}]}}
    ]);
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let mut first = backend.lock().unwrap().turns[0].clone();
    first["items"].as_array_mut().unwrap().push(json!({"type":"userMessage","id":"steer-first","clientId":"client-steer","content":[{"type":"text","text":"Native steer"}]}));
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.history_revision = 1;
    state.discarded_turn_ids = vec!["second".into(), "third".into()];
    actor
        .replace_codex_history_snapshot(&state, &json!({"thread":{"id":"thread","turns":[first]}}))
        .await
        .unwrap();
    let tab = actor.codex_tab("tab").await.unwrap();
    let cells = tab.payload["codexSnapshot"]["timelineCells"]
        .as_array()
        .unwrap();
    assert!(cells.iter().all(|cell| cell["turnId"] == "first"));
    let prompt = cells
        .iter()
        .find(|cell| cell["itemId"] == "user-first")
        .unwrap();
    assert_eq!(prompt["markdownText"], "Visible attachment prompt");
    assert_eq!(
        prompt["metadata"]["attachments"][0]["path"],
        "/retained/image.png"
    );
    let steer = cells
        .iter()
        .find(|cell| cell["itemId"] == "steer-first")
        .unwrap();
    assert_eq!(steer["markdownText"], "Visible steer");
    assert_eq!(steer["metadata"]["isSteering"], true);
}
