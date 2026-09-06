use super::*;
use crate::terminal_host::client::{ClientFrame, ClientHandle};
use alera_core::runtime::CodexQueueEntry;
use tokio::sync::mpsc::UnboundedReceiver;

pub(super) fn connect(actor: &mut ServerActor, id: u64) -> UnboundedReceiver<ClientFrame> {
    let (handle, outbound) = ClientHandle::test_channels();
    let mut client = super::super::actor_test_harness::local_client(handle);
    client.supports_codex_tab_kind = true;
    actor.clients.insert(id, client);
    outbound
}

pub(super) fn response(outbound: &mut UnboundedReceiver<ClientFrame>, id: i64) -> Option<Value> {
    while let Ok(frame) = outbound.try_recv() {
        if let Some(value) = frame.as_json() {
            if value["id"] == id {
                return Some(value);
            }
        }
    }
    None
}

pub(super) async fn finish_scan(
    actor: &mut ServerActor,
    rx: &mut UnboundedReceiver<ServerCommand>,
) {
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        let finished = matches!(
            command,
            ServerCommand::CodexHistoryScanFinished { .. }
                | ServerCommand::CodexForkProjected { .. }
        );
        if matches!(
            command,
            ServerCommand::CodexHistoryScanFinished { .. }
                | ServerCommand::CodexQueueStartupFinished { .. }
                | ServerCommand::CodexForkCreated { .. }
                | ServerCommand::CodexForkProjected { .. }
        ) {
            actor.handle_codex_command(command).await;
        }
        if finished && !actor.codex_history_scans.contains("tab") {
            return;
        }
    }
}

#[tokio::test]
async fn history_actions_defer_the_full_scan_and_keep_other_clients_responsive() {
    for kind in [
        "codex.thread.fork",
        "codex.thread.edit",
        "codex.queue.reconcile",
    ] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        let mut first = connect(&mut actor, 1);
        let mut second = connect(&mut actor, 2);
        actor
            .handle_line(
                1,
                json!({"id":1,"type":kind,"payload":{
                    "tabId":"tab","expectedThreadId":"thread","operationId":"operation",
                    "turnId":"first","itemId":"user-first","text":"Correction",
                    "expectedHistoryRevision":0,"expectedRevision":0
                }})
                .to_string(),
            )
            .await;
        assert!(actor.codex_history_scans.contains("tab"), "{kind}");
        assert!(actor.codex_delivery_active.contains("tab"));
        assert!(response(&mut first, 1).is_none());
        actor
            .handle_line(
                2,
                json!({"id":2,"type":"codex.queue.get","payload":{"tabId":"tab"}}).to_string(),
            )
            .await;
        assert_eq!(response(&mut second, 2).unwrap()["ok"], true);
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| matches!(
                method.as_str(),
                "thread/fork" | "thread/rollback" | "turn/start"
            )));
        finish_scan(&mut actor, &mut rx).await;
        assert!(!actor.codex_history_scans.contains("tab"));
        assert_eq!(response(&mut first, 1).unwrap()["ok"], true, "{kind}");
        if kind == "codex.thread.edit" {
            assert_eq!(
                complete_edit(&mut actor, &mut rx).await.operations[0].phase,
                "completed"
            );
        }
    }
}

#[tokio::test]
async fn scans_reject_changed_context_before_mutating_history() {
    for changed in ["thread", "queue", "history", "server", "stop"] {
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
        assert!(actor.codex_history_scans.contains("tab"));
        match changed {
            "thread" => {
                let mut tab = actor.codex_tab("tab").await.unwrap();
                tab.payload["codexThreadId"] = json!("replacement");
                actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
            }
            "queue" | "history" => {
                let mut state = actor
                    .codex_delivery_state(&actor.codex_tab("tab").await.unwrap())
                    .await
                    .unwrap();
                if changed == "history" {
                    state.history_revision += 1;
                }
                actor.save_codex_delivery(&mut state).await.unwrap();
            }
            "server" => {
                actor.codex = Some(CodexAppServer::mock(|_, _| {
                    panic!("must not call replacement")
                }));
            }
            "stop" => {
                actor
                    .handle_line(
                        1,
                        json!({"id":2,"type":"codex.turn.interrupt","payload":{
                            "tabId":"tab","expectedThreadId":"thread","turnId":"third"
                        }})
                        .to_string(),
                    )
                    .await;
                assert_eq!(response(&mut outbound, 2).unwrap()["ok"], true);
            }
            _ => unreachable!(),
        }
        finish_scan(&mut actor, &mut rx).await;
        let result = response(&mut outbound, 1).unwrap();
        assert_eq!(result["ok"], false, "{changed}: {result}");
        assert!(!actor.codex_history_scans.contains("tab"));
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "thread/fork"));
    }
}

#[tokio::test]
async fn client_scans_cannot_create_work_after_removal_captures_cleanup() {
    for kind in ["codex.thread.fork", "codex.thread.edit"] {
        for removal in ["tab.remove", "workspace.remove"] {
            let (_dir, mut actor, backend, mut rx) = fixture().await;
            let mut outbound = connect(&mut actor, 1);
            actor.park_runtime_mutations();
            actor
                .handle_line(
                    1,
                    json!({"id":1,"type":kind,"payload":{
                        "tabId":"tab","expectedThreadId":"thread","operationId":"operation",
                        "turnId":"first","itemId":"user-first","text":"Correction",
                        "expectedHistoryRevision":0
                    }})
                    .to_string(),
                )
                .await;
            assert!(actor.codex_history_scans.contains("tab"));
            let target = if removal == "tab.remove" {
                "tab"
            } else {
                "workspace"
            };
            actor
                .handle_line(
                    1,
                    json!({"id":2,"type":removal,"payload":{"id":target}}).to_string(),
                )
                .await;
            assert!(actor.mutation_queue.has_runtime_mutations());
            assert!(response(&mut outbound, 2).is_none());
            finish_scan(&mut actor, &mut rx).await;
            let result = response(&mut outbound, 1).unwrap();
            assert_eq!(result["ok"], false, "{kind}/{removal}: {result}");
            assert!(result["error"]
                .as_str()
                .unwrap()
                .contains("runtime mutation"));
            assert!(!actor.codex_history_scans.contains("tab"));
            let tab = actor.codex_tab("tab").await.unwrap();
            assert!(actor
                .codex_delivery_state(&tab)
                .await
                .unwrap()
                .operations
                .is_empty());
            assert_eq!(
                actor
                    .runtime_store
                    .list_workspace_tabs("workspace")
                    .await
                    .unwrap()
                    .len(),
                1
            );
            assert!(!backend.lock().unwrap().calls.iter().any(|(method, _)| {
                matches!(
                    method.as_str(),
                    "thread/fork" | "turn/interrupt" | "thread/rollback" | "turn/start"
                )
            }));

            actor.unpark_runtime_mutations();
            loop {
                let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
                    .await
                    .unwrap()
                    .unwrap();
                actor.handle(command).await;
                if let Some(result) = response(&mut outbound, 2) {
                    assert_eq!(result["ok"], true, "{kind}/{removal}: {result}");
                    break;
                }
            }
            assert!(actor.codex_tab("tab").await.is_err());
            assert!(actor
                .runtime_store
                .list_workspace_tabs("workspace")
                .await
                .unwrap()
                .is_empty());
        }
    }
}

#[tokio::test]
async fn startup_reconciliation_runs_without_clients_and_clears_stale_activity() {
    for status in ["sending", "uncertain"] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        backend.lock().unwrap().turns[2]["status"] = json!("completed");
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.paused = true;
        state.messages.push(CodexQueueEntry {
            id: "client-first".into(),
            revision: 0,
            payload: json!({"input":[{"type":"text","text":"first"}]}),
            status: status.into(),
            error: None,
            turn_id: None,
        });
        actor.save_codex_delivery(&mut state).await.unwrap();
        assert!(actor.codex_delivery_active.contains("tab"));
        actor.restore_codex_queues().await.unwrap();
        assert!(actor.codex_history_scans.contains("tab"));
        assert!(actor.clients.is_empty());
        finish_scan(&mut actor, &mut rx).await;
        assert!(!actor.codex_history_scans.contains("tab"));
        assert!(!actor.codex_delivery_active.contains("tab"));
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(state.messages[0].status, "accepted");
        assert!(state.paused);
        assert!(
            actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["activeTurnId"]
                .is_null()
        );
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
    }
}

#[tokio::test]
async fn failed_history_scan_releases_an_idle_runtime() {
    let (_dir, mut actor, _backend, mut rx) = fixture().await;
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexSnapshot"]["activeTurnId"] = Value::Null;
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    actor.codex = Some(CodexAppServer::mock(|_, _| {
        Err(HostError::state("Read failed"))
    }));
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
    assert!(actor.codex_delivery_active.contains("tab"));
    finish_scan(&mut actor, &mut rx).await;
    assert_eq!(response(&mut outbound, 1).unwrap()["ok"], false);
    assert!(!actor.codex_history_scans.contains("tab"));
    assert!(!actor.codex_delivery_active.contains("tab"));
}

#[tokio::test]
async fn unrelated_removal_does_not_discard_startup_reconciliation() {
    let (_dir, mut actor, backend, mut rx) = fixture().await;
    backend.lock().unwrap().turns[2]["status"] = json!("completed");
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    state.messages.push(CodexQueueEntry {
        id: "client-first".into(),
        revision: 0,
        payload: json!({"input":[{"type":"text","text":"first"}]}),
        status: "uncertain".into(),
        error: None,
        turn_id: None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
    actor.restore_codex_queues().await.unwrap();
    assert!(actor.codex_history_scans.contains("tab"));
    let mut outbound = connect(&mut actor, 1);
    actor.park_runtime_mutations();
    actor
        .handle_line(
            1,
            json!({"id":1,"type":"tab.remove","payload":{"id":"unrelated"}}).to_string(),
        )
        .await;
    assert!(actor.mutation_queue.has_runtime_mutations());
    finish_scan(&mut actor, &mut rx).await;
    assert!(!actor.codex_history_scans.contains("tab"));
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.messages[0].status, "accepted");
    assert!(state.paused);
    assert!(!actor.codex_delivery_active.contains("tab"));
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "turn/start"));
    actor.unpark_runtime_mutations();
    while response(&mut outbound, 1).is_none() {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
    assert!(actor.codex_tab("tab").await.is_ok());
}
