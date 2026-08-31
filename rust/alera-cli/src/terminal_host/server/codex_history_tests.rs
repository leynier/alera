use super::actor_test_harness::test_actor;
use super::codex_app_server::CodexAppServer;
use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::HostError;
use alera_core::runtime::{CodexChatDeliveryState, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

#[path = "codex_history_availability_tests.rs"]
mod availability;
#[path = "codex_history_delivery_recovery_tests.rs"]
mod delivery_recovery;
#[path = "codex_fork_job_tests.rs"]
mod fork_jobs;
#[path = "codex_history_fork_retention_tests.rs"]
mod fork_retention;
#[path = "codex_history_legacy_event_tests.rs"]
mod legacy_events;
#[path = "codex_history_persistence_tests.rs"]
mod persistence;
#[path = "codex_queue_startup_tests.rs"]
mod queue_startup;
#[path = "codex_history_reconciliation_race_tests.rs"]
mod reconciliation_races;
#[path = "codex_history_recovery_tests.rs"]
mod recovery;
#[path = "codex_history_retry_identity_tests.rs"]
mod retry_identity;
#[path = "codex_history_scan_tests.rs"]
mod scans;
#[path = "codex_history_transport_recovery_tests.rs"]
mod transport_recovery;

struct Backend {
    turns: Vec<Value>,
    calls: Vec<(String, Value)>,
    reject_interrupt: bool,
    reject_rollback: bool,
    reject_send: bool,
    fork_error: Option<String>,
    paginated: bool,
}

async fn fixture() -> (
    tempfile::TempDir,
    ServerActor,
    Arc<Mutex<Backend>>,
    tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
) {
    let directory = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;
    let now = Utc::now();
    actor.runtime_store.upsert_project(serde_json::from_value(json!({"id":"project","name":"Project","repoPath":directory.path(),"createdAt":now,"updatedAt":now,"kind":"folder"})).unwrap()).await.unwrap();
    actor.runtime_store.upsert_workspace(serde_json::from_value(json!({"id":"workspace","instanceId":"instance","hostId":"local","projectId":"project","name":"Workspace","path":directory.path(),"createdAt":now,"updatedAt":now,"kind":"main","status":"active","reusesExistingBranch":false})).unwrap()).await.unwrap();
    actor.runtime_store.upsert_workspace_tab(WorkspaceTabRecord {
        id:"tab".into(),workspace_id:"workspace".into(),kind:"codex".into(),title:"Original".into(),created_at:now,updated_at:now,
        payload:json!({"codexThreadId":"thread","codexCwd":directory.path(),"codexSnapshot":{"activeTurnId":"third","timelineCells":[]}}),
    }).await.unwrap();
    let backend = Arc::new(Mutex::new(Backend { turns: ["first","second","third"].iter().enumerate().map(|(i,id)| json!({"id":id,"status":if i == 2 {"inProgress"} else {"completed"},"items":[{"type":"userMessage","id":format!("user-{id}"),"clientId":format!("client-{id}"),"content":[{"type":"text","text":id}]}]})).collect(), calls:Vec::new(), reject_interrupt:false, reject_rollback:false, reject_send:false, fork_error:None, paginated:false }));
    let shared = backend.clone();
    actor.codex = Some(CodexAppServer::mock(move |method, params| {
        let mut backend = shared.lock().unwrap();
        backend.calls.push((method.into(), params.clone()));
        match method {
            "thread/turns/list" => {
                if backend.paginated && params["itemsView"] == "full" {
                    return Err(HostError::state("Paginated threads require summary items"));
                }
                let offset = params["cursor"]
                    .as_str()
                    .unwrap_or("0")
                    .parse::<usize>()
                    .unwrap();
                let page: Vec<_> = backend.turns.iter().skip(offset).take(1).cloned().collect();
                Ok(
                    json!({"data":page,"nextCursor":if offset+1 < backend.turns.len() {Some((offset+1).to_string())} else {None}}),
                )
            }
            "thread/read" | "thread/resume" => Ok(
                json!({"thread":{"id":"thread","turns":backend.turns,"historyMode":if backend.paginated {"paginated"} else {"full"}}}),
            ),
            "thread/items/list" => Ok(
                json!({"data":backend.turns.iter().flat_map(|turn| turn["items"].as_array().unwrap().iter().map(|item| json!({"turnId":turn["id"],"item":item}))).collect::<Vec<_>>(),"nextCursor":null}),
            ),
            "turn/interrupt" => {
                if backend.reject_interrupt {
                    return Err(HostError::state("Interrupt rejected"));
                }
                for turn in &mut backend.turns {
                    if turn["status"] == "inProgress" {
                        turn["status"] = json!("interrupted");
                    }
                }
                Ok(json!({}))
            }
            "thread/rollback" => {
                if backend.reject_rollback {
                    return Err(HostError::state("Rollback rejected"));
                }
                let length = backend.turns.len() - params["numTurns"].as_u64().unwrap() as usize;
                backend.turns.truncate(length);
                Ok(json!({"thread":{"id":"thread","turns":backend.turns}}))
            }
            "turn/start" => {
                if backend.reject_send {
                    return Err(HostError::state("Send rejected"));
                }
                Ok(json!({"turn":{"id":"corrected","status":"inProgress"}}))
            }
            "turn/steer" => Ok(json!({"turnId":params["expectedTurnId"]})),
            "thread/fork" => {
                if let Some(error) = &backend.fork_error {
                    return Err(HostError::state(error));
                }
                let index = backend
                    .turns
                    .iter()
                    .position(|turn| turn["id"] == params["lastTurnId"])
                    .unwrap();
                Ok(json!({"thread":{"id":"fork","turns":backend.turns[..=index]}}))
            }
            _ => Err(HostError::state(format!("Unexpected method {method}"))),
        }
    }));
    let tab = actor.codex_tab("tab").await.unwrap();
    actor
        .codex
        .as_ref()
        .unwrap()
        .record_thread_hydration(
            "tab",
            "thread",
            directory.path().to_str().unwrap(),
            tab.updated_at,
            None,
        )
        .await;
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = tx;
    (directory, actor, backend, rx)
}

async fn complete_edit(
    actor: &mut ServerActor,
    rx: &mut tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
) -> CodexChatDeliveryState {
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        if matches!(
            command,
            ServerCommand::CodexEditFinished { .. } | ServerCommand::CodexQueueDelivered { .. }
        ) {
            actor.handle_codex_command(command).await;
            let state = actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap();
            if state.operations.iter().any(|op| {
                matches!(
                    op.phase.as_str(),
                    "completed" | "failed" | "resendFailed" | "uncertain"
                )
            }) {
                return state;
            }
        }
    }
}

#[tokio::test]
async fn fork_uses_complete_paginated_history_and_never_copies_active_execution() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let before = actor.codex_tab("tab").await.unwrap();
    let request = json!({"tabId":"tab","expectedThreadId":"thread","operationId":"fork-operation"});
    let result = actor.fork_codex_history(&request).await.unwrap();
    assert_eq!(result["workspaceId"], "workspace");
    assert_ne!(result["tabId"], "tab");
    assert!(result["snapshot"]["activeTurnId"].is_null());
    assert_eq!(
        actor.codex_tab("tab").await.unwrap().payload,
        before.payload
    );
    assert!(actor
        .runtime_store
        .codex_chat_state("fork")
        .await
        .unwrap()
        .is_none());
    assert_eq!(actor.fork_codex_history(&request).await.unwrap(), result);
    let backend = backend.lock().unwrap();
    let forks: Vec<_> = backend
        .calls
        .iter()
        .filter(|(method, _)| method == "thread/fork")
        .collect();
    assert_eq!(forks.len(), 1);
    assert_eq!(forks[0].1["lastTurnId"], "second");
    assert!(!backend
        .calls
        .iter()
        .any(|(method, _)| method == "turn/start"));
}

#[tokio::test]
async fn first_turn_edit_waits_for_interrupt_and_retry_does_not_repeat_rollback() {
    let (_directory, mut actor, backend, mut rx) = fixture().await;
    backend.lock().unwrap().reject_send = true;
    actor.edit_codex_history(&json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit","turnId":"first","itemId":"user-first","text":"Correction","expectedHistoryRevision":0})).await.unwrap();
    let state = complete_edit(&mut actor, &mut rx).await;
    assert!(state.paused);
    assert_eq!(state.operations[0].phase, "resendFailed");
    assert_eq!(state.history_revision, 1);
    assert_eq!(backend.lock().unwrap().turns.len(), 0);
    backend.lock().unwrap().reject_send = false;
    actor
        .edit_codex_history(
            &json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit"}),
        )
        .await
        .unwrap();
    let state = complete_edit(&mut actor, &mut rx).await;
    assert_eq!(state.operations[0].phase, "completed");
    assert!(state.paused);
    let calls = &backend.lock().unwrap().calls;
    assert_eq!(
        calls
            .iter()
            .filter(|(method, _)| method == "thread/rollback")
            .count(),
        1
    );
    assert!(
        calls
            .iter()
            .position(|(method, _)| method == "turn/interrupt")
            .unwrap()
            < calls
                .iter()
                .position(|(method, _)| method == "thread/rollback")
                .unwrap()
    );
}

#[tokio::test]
async fn rejected_interrupt_or_rollback_never_sends_a_correction() {
    for interrupt in [true, false] {
        let (_directory, mut actor, backend, mut rx) = fixture().await;
        backend.lock().unwrap().reject_interrupt = interrupt;
        backend.lock().unwrap().reject_rollback = !interrupt;
        actor.edit_codex_history(&json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit","turnId":"second","text":"Correction","expectedHistoryRevision":0})).await.unwrap();
        let state = complete_edit(&mut actor, &mut rx).await;
        assert_eq!(state.operations[0].phase, "failed");
        assert!(state.paused);
        assert_eq!(state.history_revision, 0);
        assert_eq!(backend.lock().unwrap().turns.len(), 3);
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
    }
}

#[tokio::test]
async fn runtime_delivers_a_persisted_queue_with_no_connected_application() {
    let (_directory, mut actor, backend, mut rx) = fixture().await;
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexSnapshot"]["activeTurnId"] = Value::Null;
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let queued = actor.handle_codex_queue_request("codex.queue.add", &json!({"tabId":"tab","expectedThreadId":"thread","clientUserMessageId":"message","input":[{"type":"text","text":"Queued"}],"userMessage":{"text":"Queued"}})).await.unwrap();
    assert_eq!(queued["messages"][0]["status"], "queued");
    assert!(actor.clients.is_empty());
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "turn/start"));
    actor.advance_codex_queue("tab").await;
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        if let ServerCommand::CodexQueueDelivered {
            tab_id,
            thread_id,
            message_id,
            result,
        } = command
        {
            actor
                .finish_codex_queue_delivery(&tab_id, &thread_id, &message_id, result)
                .await
                .unwrap();
            break;
        }
    }
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.messages[0].status, "accepted");
    assert!(actor.codex_delivery_active.contains("tab"));
    actor.handle_codex_message(json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"corrected","status":"completed"}}})).await;
    assert!(!actor.codex_delivery_active.contains("tab"));
}

#[tokio::test]
async fn discarded_turn_notifications_cannot_restore_edited_history() {
    let (_directory, mut actor, _backend, mut rx) = fixture().await;
    actor.edit_codex_history(&json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit","turnId":"second","text":"Correction","expectedHistoryRevision":0})).await.unwrap();
    let state = complete_edit(&mut actor, &mut rx).await;
    assert_eq!(state.operations[0].phase, "completed");
    let before = actor.codex_tab("tab").await.unwrap().payload;
    actor.handle_codex_message(json!({"method":"item/completed","params":{"threadId":"thread","turnId":"third","item":{"type":"agentMessage","id":"discarded-response","text":"Old response"}}})).await;
    assert_eq!(actor.codex_tab("tab").await.unwrap().payload, before);
}

#[tokio::test]
async fn recovered_rollback_replaces_snapshot_and_never_rolls_back_twice() {
    let (_directory, mut actor, backend, mut rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    state.operations.push(alera_core::runtime::CodexChatOperation {
        id: "edit-recovered".into(), kind: "edit".into(), phase: "uncertain".into(),
        payload: json!({"tabId":"tab","expectedThreadId":"thread","clientUserMessageId":"edit-recovered","input":[{"type":"text","text":"Correction"}],"uncertainPhase":"rollingBack","editTargetTurnId":"second","editOriginalTurnIds":["first","second","third"]}), result:None,
    });
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    backend.lock().unwrap().turns.truncate(1);
    actor
        .reconcile_codex_history_edit("tab", "edit-recovered")
        .await
        .unwrap();
    let tab = actor.codex_tab("tab").await.unwrap();
    assert_eq!(tab.payload["codexHistoryRevision"], 1);
    assert_eq!(
        tab.payload["codexDiscardedTurnIds"],
        json!(["second", "third"])
    );
    assert!(tab.payload["codexSnapshot"]["activeTurnId"].is_null());
    actor
        .edit_codex_history(
            &json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit-recovered"}),
        )
        .await
        .unwrap();
    let state = complete_edit(&mut actor, &mut rx).await;
    assert_eq!(state.operations[0].phase, "completed");
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "thread/rollback"));
}

#[tokio::test]
async fn fork_recovers_its_native_result_without_creating_another_thread() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state
        .operations
        .push(alera_core::runtime::CodexChatOperation {
            id: "fork-recovered".into(),
            kind: "fork".into(),
            phase: "forkCreated".into(),
            payload: json!({"forkTabId":"fork-tab"}),
            result: Some(
                json!({"thread":{"id":"fork","turns":[backend.lock().unwrap().turns[0].clone()]}}),
            ),
        });
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    let result = actor
        .fork_codex_history(
            &json!({"tabId":"tab","expectedThreadId":"thread","operationId":"fork-recovered"}),
        )
        .await
        .unwrap();
    assert_eq!(result["tabId"], "fork-tab");
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "thread/fork"));
}

#[tokio::test]
async fn cancel_releases_pending_copies_but_keeps_accepted_history_files() {
    let (directory, mut actor, _backend, _rx) = fixture().await;
    let source = directory.path().join("attachment.png");
    std::fs::write(&source, b"image bytes").unwrap();
    let payload = super::codex_queue_attachments::retain_attachments(
        directory.path(),
        json!({"input":[{"type":"localImage","path":source}]}),
    )
    .await
    .unwrap();
    let copy = payload["input"][0]["path"].as_str().unwrap();
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.messages.push(alera_core::runtime::CodexQueueEntry {
        id: "pending".into(),
        revision: 0,
        payload: payload.clone(),
        status: "queued".into(),
        error: None,
        turn_id: None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    actor.release_codex_attachments(&payload).await.unwrap();
    assert!(std::path::Path::new(copy).exists());
    actor
        .handle_codex_queue_request(
            "codex.queue.cancel",
            &json!({"tabId":"tab","expectedRevision":state.revision}),
        )
        .await
        .unwrap();
    assert!(!std::path::Path::new(copy).exists());
    let accepted = super::codex_queue_attachments::retain_attachments(
        directory.path(),
        json!({"input":[{"type":"localImage","path":source}]}),
    )
    .await
    .unwrap();
    actor
        .protect_accepted_codex_attachments(&accepted)
        .await
        .unwrap();
    actor.release_codex_attachments(&accepted).await.unwrap();
    assert!(std::path::Path::new(accepted["input"][0]["path"].as_str().unwrap()).exists());
}

#[tokio::test]
async fn paginated_edit_is_unavailable_before_interrupt_but_fork_can_hydrate_items() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    backend.lock().unwrap().paginated = true;
    let request = json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit-paginated","turnId":"first","text":"Correction","expectedHistoryRevision":0});
    assert!(actor
        .edit_codex_history(&request)
        .await
        .unwrap_err()
        .wire_message()
        .contains("paginated"));
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert!(state.history_edit_unavailable.is_some());
    assert!(state.operations.is_empty());
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "turn/interrupt" || method == "thread/rollback"));
    let fork = actor
        .fork_codex_history(
            &json!({"tabId":"tab","expectedThreadId":"thread","operationId":"fork-paginated"}),
        )
        .await
        .unwrap();
    assert_ne!(fork["tabId"], "tab");
    assert!(backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "thread/items/list"));
}
