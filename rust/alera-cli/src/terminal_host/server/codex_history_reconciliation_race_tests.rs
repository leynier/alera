use super::scans::{connect, response};
use super::*;
use alera_core::runtime::{CodexChatOperation, CodexQueueEntry};
use tokio::sync::mpsc::UnboundedReceiver;

async fn scanned(rx: &mut UnboundedReceiver<ServerCommand>) -> ServerCommand {
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        if matches!(command, ServerCommand::CodexHistoryScanFinished { .. }) {
            return command;
        }
    }
}

async fn pending_state(actor: &mut ServerActor) -> CodexChatDeliveryState {
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexSnapshot"]["pendingRequests"] = json!([
        {"id":91,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread"},"turnId":"third"},
        {"id":92,"method":"item/tool/requestUserInput","params":{"threadId":"thread","isBlocking":true},"turnId":"third"},
        {"id":93,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread"},"turnId":"second"},
        {"id":94,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread"}}
    ]);
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    state.messages.push(CodexQueueEntry {
        id:"client-first".into(), revision:0,
        payload:json!({"input":[{"type":"text","text":"first"}],"userMessage":{"text":"Visible first"}}),
        status:"uncertain".into(), error:None, turn_id:None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    state
}

#[tokio::test]
async fn reconciliation_rejects_live_changes_after_history_scan() {
    for change in [
        "completion",
        "resolved",
        "request",
        "delta",
        "presentation",
        "goal",
        "goal-cleared",
    ] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        let mut outbound = connect(&mut actor, 1);
        let state = pending_state(&mut actor).await;
        if change.starts_with("goal") {
            actor.handle_codex_message(json!({"method":"thread/goal/updated","params":{"threadId":"thread","goal":{"objective":"Original goal","status":"active"}}})).await;
        }
        actor.handle_line(1, json!({"id":1,"type":"codex.queue.reconcile","payload":{
            "tabId":"tab","expectedThreadId":"thread","operationId":"reconcile","expectedRevision":state.revision
        }}).to_string()).await;
        let finished = scanned(&mut rx).await;
        match change {
            "completion" => {
                backend.lock().unwrap().turns[2]["status"] = json!("completed");
                actor.handle_codex_message(json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"third","status":"completed"}}})).await;
            }
            "resolved" => actor.handle_codex_message(json!({"method":"serverRequest/resolved","params":{"threadId":"thread","requestId":91}})).await,
            "request" => actor.handle_codex_message(json!({"id":95,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread","turnId":"third","command":"ls"}})).await,
            "delta" => {
                actor.handle_codex_message(json!({"method":"item/agentMessage/delta","params":{"threadId":"thread","turnId":"third","itemId":"fresh","delta":"Fresh progress"}})).await;
                assert!(actor.codex_pending_messages.contains_key("tab"));
            }
            "presentation" => actor.persist_codex_user_input("tab", &json!([{"type":"text","text":"New presentation"}]), None, "third", Some("new-client"), true).await,
            "goal" => actor.handle_codex_message(json!({"method":"thread/goal/updated","params":{"threadId":"thread","goal":{"objective":"Updated goal","status":"paused"}}})).await,
            "goal-cleared" => actor.handle_codex_message(json!({"method":"thread/goal/cleared","params":{"threadId":"thread"}})).await,
            _ => unreachable!(),
        }
        let before = actor.codex_tab("tab").await.unwrap().payload;
        actor.handle_codex_command(finished).await;
        assert_eq!(response(&mut outbound, 1).unwrap()["ok"], false, "{change}");
        let after = actor.codex_tab("tab").await.unwrap().payload;
        if change == "delta" {
            assert!(!actor.codex_pending_messages.contains_key("tab"));
            assert!(after["codexSnapshot"]["timelineCells"]
                .as_array()
                .unwrap()
                .iter()
                .any(|cell| cell["markdownText"] == "Fresh progress"));
        } else {
            assert_eq!(after, before, "{change}");
        }
        assert_eq!(
            actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap()
                .messages[0]
                .status,
            "uncertain"
        );
        assert!(!actor.codex_history_scans.contains("tab"));
        if change == "completion" {
            assert!(after["codexSnapshot"]["activeTurnId"].is_null());
            assert!(!actor.codex_delivery_active.contains("tab"));
            actor.handle_line(1, json!({"id":2,"type":"codex.queue.reconcile","payload":{
                "tabId":"tab","expectedThreadId":"thread","operationId":"retry","expectedRevision":state.revision
            }}).to_string()).await;
            actor.handle_codex_command(scanned(&mut rx).await).await;
            assert_eq!(response(&mut outbound, 2).unwrap()["ok"], true);
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
            assert!(!actor.codex_delivery_active.contains("tab"));
        }
    }
}

#[tokio::test]
async fn reconciliation_preserves_the_current_goal_on_both_clients() {
    for status in ["active", "paused", "cleared"] {
        let (_dir, mut actor, _backend, _rx) = fixture().await;
        let state = pending_state(&mut actor).await;
        let goal = json!({"objective":"Keep this goal","status":status,"tokenBudget":1000,"tokensUsed":25});
        actor
            .handle_codex_message(
                json!({"method":"thread/goal/updated","params":{"threadId":"thread","goal":goal}}),
            )
            .await;
        if status == "cleared" {
            actor
                .handle_codex_message(
                    json!({"method":"thread/goal/cleared","params":{"threadId":"thread"}}),
                )
                .await;
        }
        let before = actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["goal"].clone();
        let mut first = connect(&mut actor, 1);
        let mut second = connect(&mut actor, 2);
        actor.reconcile_codex_queue(state).await.unwrap();
        assert_eq!(
            actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["goal"],
            before
        );
        for outbound in [&mut first, &mut second] {
            let mut snapshot = None;
            while let Ok(frame) = outbound.try_recv() {
                if let Some(event) = frame.as_json() {
                    if event["event"] == "codexThreadChanged" {
                        snapshot = Some(event["payload"]["snapshot"].clone());
                    }
                }
            }
            assert_eq!(snapshot.unwrap()["goal"], before);
        }
    }
}

#[tokio::test]
async fn fork_scan_accepts_live_progress_without_replacing_its_source() {
    let (_dir, mut actor, backend, mut rx) = fixture().await;
    let mut outbound = connect(&mut actor, 1);
    actor
        .handle_line(
            1,
            json!({"id":1,"type":"codex.thread.fork","payload":{
                "tabId":"tab","expectedThreadId":"thread","operationId":"fork"
            }})
            .to_string(),
        )
        .await;
    let finished = scanned(&mut rx).await;
    actor.handle_codex_message(json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"third","status":"completed"}}})).await;
    let before = actor.codex_tab("tab").await.unwrap().payload;
    actor.handle_codex_command(finished).await;
    super::scans::finish_scan(&mut actor, &mut rx).await;
    assert_eq!(response(&mut outbound, 1).unwrap()["ok"], true);
    assert_eq!(actor.codex_tab("tab").await.unwrap().payload, before);
    assert_eq!(
        backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .find(|(method, _)| method == "thread/fork")
            .unwrap()
            .1["lastTurnId"],
        "second"
    );
}

#[tokio::test]
async fn reconciliation_keeps_only_requests_of_the_surviving_active_turn_on_both_clients() {
    for native_active in ["third", "second", "none"] {
        let (_dir, mut actor, backend, _rx) = fixture().await;
        let state = pending_state(&mut actor).await;
        let mut first = connect(&mut actor, 1);
        let mut second = connect(&mut actor, 2);
        for turn in &mut backend.lock().unwrap().turns {
            turn["status"] = json!(if turn["id"] == native_active {
                "inProgress"
            } else {
                "completed"
            });
        }
        actor.reconcile_codex_queue(state).await.unwrap();
        let expected = if native_active == "third" {
            vec![91, 92, 94]
        } else {
            vec![]
        };
        let tab = actor.codex_tab("tab").await.unwrap();
        assert_eq!(
            tab.payload["codexSnapshot"]["pendingRequests"]
                .as_array()
                .unwrap()
                .iter()
                .map(|r| r["id"].as_i64().unwrap())
                .collect::<Vec<_>>(),
            expected
        );
        for outbound in [&mut first, &mut second] {
            let mut snapshot = None;
            while let Ok(frame) = outbound.try_recv() {
                if let Some(event) = frame.as_json() {
                    if event["event"] == "codexThreadChanged" {
                        snapshot = Some(event["payload"]["snapshot"].clone());
                    }
                }
            }
            assert_eq!(
                snapshot.unwrap()["pendingRequests"],
                tab.payload["codexSnapshot"]["pendingRequests"]
            );
        }
    }
}

#[tokio::test]
async fn accepted_edit_reconciliation_keeps_requests_but_a_new_rollback_clears_them() {
    let (_dir, mut actor, _backend, mut rx) = fixture().await;
    let mut state = pending_state(&mut actor).await;
    state.messages.clear();
    state.operations.push(CodexChatOperation {
        id:"client-third".into(), kind:"edit".into(), phase:"uncertain".into(),
        payload:json!({"input":[{"type":"text","text":"third"}],"userMessage":{"text":"third"},"uncertainPhase":"resending"}), result:None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    actor
        .reconcile_codex_history_edit("tab", "client-third")
        .await
        .unwrap();
    assert_eq!(
        actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["pendingRequests"]
            .as_array()
            .unwrap()
            .len(),
        3
    );
    actor.edit_codex_history(&json!({"tabId":"tab","expectedThreadId":"thread","operationId":"new-edit","turnId":"second","text":"Correction","expectedHistoryRevision":0})).await.unwrap();
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        if matches!(command, ServerCommand::CodexEditFinished { .. }) {
            actor.handle_codex_command(command).await;
            break;
        }
    }
    assert!(
        actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["pendingRequests"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}
