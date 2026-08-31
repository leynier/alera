use super::*;
use alera_core::runtime::{CodexChatOperation, CodexQueueEntry};

#[tokio::test]
async fn fork_preserves_surviving_presentation_without_pending_delivery_or_active_state() {
    for first_only in [false, true] {
        let (_directory, mut actor, _backend, _rx) = fixture().await;
        let mut tab = actor.codex_tab("tab").await.unwrap();
        super::super::codex_user_messages::append_user_input(
            &mut tab,
            &json!([{"type":"text","text":"second"}]),
            Some(
                &json!({"text":"Visible stored","attachments":[{"path":"/stored/file.md","name":"file.md","isImage":false}]}),
            ),
            "second",
            Some("client-second"),
            false,
        );
        tab.payload["codexSnapshot"]["activeTurnId"] = json!("third");
        tab.payload["codexSnapshot"]["pendingRequests"] = json!([{"id":"pending"}]);
        actor
            .runtime_store
            .upsert_workspace_tab(tab.clone())
            .await
            .unwrap();
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.paused = true;
        state.messages.push(CodexQueueEntry {
            id: "client-first".into(), revision: 0,
            payload: json!({"turnId":"first","input":[{"type":"text","text":"first"}],"userMessage":{"text":"Visible receipt","attachments":[{"path":"/receipt/document.md","name":"document.md","isImage":false}]}}),
            status: "accepted".into(), error: None, turn_id: Some("first".into()),
        });
        state.messages.push(CodexQueueEntry {
            id: "queued".into(), revision: 0,
            payload: json!({"input":[{"type":"text","text":"Pending text"}],"userMessage":{"text":"Pending text"}}),
            status: "queued".into(), error: None, turn_id: None,
        });
        actor.save_codex_delivery(&mut state).await.unwrap();
        let mut request =
            json!({"tabId":"tab","expectedThreadId":"thread","operationId":"fork-presentation"});
        if first_only {
            request["lastTurnId"] = json!("first");
        }
        let fork = actor.fork_codex_history(&request).await.unwrap();
        let cells = fork["snapshot"]["timelineCells"].as_array().unwrap();
        let first = cells
            .iter()
            .find(|cell| cell["turnId"] == "first" && cell["kind"] == "userMessage")
            .unwrap();
        assert_eq!(first["markdownText"], "Visible receipt");
        assert_eq!(first["metadata"]["isSteering"], true);
        assert_eq!(
            first["metadata"]["attachments"][0]["path"],
            "/receipt/document.md"
        );
        let second = cells
            .iter()
            .find(|cell| cell["turnId"] == "second" && cell["kind"] == "userMessage");
        if first_only {
            assert!(second.is_none());
        } else {
            assert_eq!(second.unwrap()["markdownText"], "Visible stored");
            assert_eq!(
                second.unwrap()["metadata"]["attachments"][0]["path"],
                "/stored/file.md"
            );
        }
        assert!(cells
            .iter()
            .all(|cell| cell["turnId"] != "third" && cell["markdownText"] != "Pending text"));
        assert!(fork["snapshot"]["activeTurnId"].is_null());
        assert!(fork["snapshot"]["pendingRequests"]
            .as_array()
            .unwrap()
            .is_empty());
        assert!(actor
            .runtime_store
            .codex_chat_state("fork")
            .await
            .unwrap()
            .is_none());
        assert_eq!(actor.codex_tab("tab").await.unwrap().payload, tab.payload);
        assert_eq!(
            actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap()
                .messages
                .len(),
            2
        );
    }
}

#[tokio::test]
async fn completion_retains_running_edits_and_deliveries_even_with_a_paused_queue() {
    for (phase, delivery, retained) in [
        ("interrupting", "queued", true),
        ("rollingBack", "queued", true),
        ("resending", "queued", true),
        ("completed", "sending", true),
        ("uncertain", "queued", false),
        ("completed", "queued", false),
    ] {
        let (_directory, mut actor, _backend, _rx) = fixture().await;
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.paused = true;
        state.operations.push(CodexChatOperation {
            id: "edit".into(),
            kind: "edit".into(),
            phase: phase.into(),
            payload: json!({}),
            result: None,
        });
        state.messages.push(CodexQueueEntry {
            id: "queued".into(),
            revision: 0,
            payload: json!({}),
            status: delivery.into(),
            error: None,
            turn_id: None,
        });
        actor.save_codex_delivery(&mut state).await.unwrap();
        assert!(actor.codex_delivery_active.contains("tab"));
        actor.handle_codex_message(json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"third","status":"interrupted"}}})).await;
        assert_eq!(
            actor.codex_delivery_active.contains("tab"),
            retained,
            "phase={phase}, delivery={delivery}"
        );
        assert!(
            super::super::codex_state::active_turn_id(&super::super::codex_state::snapshot(
                &actor.codex_tab("tab").await.unwrap()
            ))
            .is_none()
        );
        state.operations[0].phase = "completed".into();
        state.messages[0].status = "accepted".into();
        actor.save_codex_delivery(&mut state).await.unwrap();
        assert!(!actor.codex_delivery_active.contains("tab"));
    }
}
