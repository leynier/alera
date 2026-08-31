use super::scans::{connect, response};
use super::*;
use alera_core::runtime::CodexQueueEntry;
use futures_util::FutureExt;
use tokio::sync::{mpsc::UnboundedReceiver, oneshot};

async fn pending(actor: &mut ServerActor, status: &str) {
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.messages.push(CodexQueueEntry {
        id: if status == "uncertain" {
            "client-first"
        } else {
            "queued"
        }
        .into(),
        revision: 0,
        payload: json!({"input":[{"type":"text","text":"queued"}]}),
        status: status.into(),
        error: None,
        turn_id: None,
    });
    actor.save_codex_delivery(&mut state).await.unwrap();
}

fn gate_startup(actor: &mut ServerActor) -> oneshot::Sender<Result<CodexAppServer, HostError>> {
    actor.codex = None;
    let (tx, rx) = oneshot::channel();
    actor.codex_starting = Some(async move { rx.await.unwrap() }.boxed().shared());
    tx
}

async fn finish_startup(actor: &mut ServerActor, rx: &mut UnboundedReceiver<ServerCommand>) {
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        let startup = matches!(command, ServerCommand::CodexQueueStartupFinished { .. });
        actor.handle(command).await;
        if startup {
            return;
        }
    }
}

async fn wait_for_status(
    actor: &mut ServerActor,
    rx: &mut UnboundedReceiver<ServerCommand>,
    status: &str,
) {
    loop {
        if actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap()
            .messages[0]
            .status
            == status
        {
            return;
        }
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
}

#[tokio::test]
async fn startup_recovery_serves_clients_while_sharing_one_pending_initialization() {
    for status in ["queued", "uncertain"] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        backend.lock().unwrap().turns[2]["status"] = json!("completed");
        pending(&mut actor, status).await;
        let server = actor.codex.clone().unwrap();
        let gate = gate_startup(&mut actor);
        let startup = actor.codex_starting.clone().unwrap();
        tokio::time::timeout(
            std::time::Duration::from_secs(1),
            actor.restore_codex_queues(),
        )
        .await
        .unwrap()
        .unwrap();
        assert!(actor.codex.is_none());
        assert!(actor.codex_history_scans.contains("tab"));
        assert!(actor.codex_delivery_active.contains("tab"));
        assert!(actor.codex_server_startup(None).ptr_eq(&startup));
        let mut outbound = connect(&mut actor, 1);
        tokio::time::timeout(
            std::time::Duration::from_secs(1),
            actor.handle_line(
                1,
                json!({"id":1,"type":"tab.find","payload":{"id":"tab"}}).to_string(),
            ),
        )
        .await
        .unwrap();
        assert_eq!(response(&mut outbound, 1).unwrap()["ok"], true);
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
        let token = server.instance_token();
        gate.send(Ok(server)).ok().unwrap();
        finish_startup(&mut actor, &mut rx).await;
        assert!(actor.codex.as_ref().unwrap().matches_instance(&token));
        wait_for_status(&mut actor, &mut rx, "accepted").await;
        let calls = &backend.lock().unwrap().calls;
        assert_eq!(
            calls
                .iter()
                .filter(|(method, _)| method == "turn/start")
                .count(),
            usize::from(status == "queued")
        );
        assert_eq!(
            calls
                .iter()
                .filter(|(method, _)| method == "thread/resume")
                .count(),
            usize::from(status == "queued")
        );
        assert!(!actor.codex_history_scans.contains("tab"));
    }
}

#[tokio::test]
async fn failed_startup_pauses_queued_delivery_without_losing_its_input() {
    let (_dir, mut actor, _backend, mut rx) = fixture().await;
    pending(&mut actor, "queued").await;
    let gate = gate_startup(&mut actor);
    actor.restore_codex_queues().await.unwrap();
    gate.send(Err(HostError::state("Initialization failed")))
        .ok()
        .unwrap();
    finish_startup(&mut actor, &mut rx).await;
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert!(state.paused);
    assert_eq!(state.messages[0].status, "failed");
    assert_eq!(state.messages[0].payload["input"][0]["text"], "queued");
    assert!(!actor.codex_history_scans.contains("tab"));
    assert!(actor.codex_starting.is_none());
}

#[tokio::test]
async fn stale_startup_cannot_overwrite_stop_or_replace_a_new_server() {
    for changed in ["stop", "server", "thread"] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        backend.lock().unwrap().turns[2]["status"] = json!("completed");
        pending(&mut actor, "queued").await;
        let server = actor.codex.clone().unwrap();
        let gate = gate_startup(&mut actor);
        actor.restore_codex_queues().await.unwrap();
        match changed {
            "stop" => {
                let mut state = actor
                    .runtime_store
                    .codex_chat_state("thread")
                    .await
                    .unwrap()
                    .unwrap();
                state.paused = true;
                actor.save_codex_delivery(&mut state).await.unwrap();
            }
            "server" => {
                actor.codex_starting = None;
                actor.codex = Some(CodexAppServer::mock(|_, _| {
                    panic!("must not use replacement")
                }));
            }
            "thread" => {
                let mut tab = actor.codex_tab("tab").await.unwrap();
                tab.payload["codexThreadId"] = json!("replacement");
                actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
            }
            _ => unreachable!(),
        }
        let before = actor.codex_tab("tab").await.unwrap();
        gate.send(Ok(server)).ok().unwrap();
        finish_startup(&mut actor, &mut rx).await;
        assert_eq!(
            actor.codex_tab("tab").await.unwrap().payload,
            before.payload
        );
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
        assert!(!actor.codex_history_scans.contains("tab"));
    }
}

#[tokio::test]
async fn canceling_the_last_removal_reawakens_delivery_without_clients() {
    use crate::terminal_host::emulator::EmulatorManager;
    let (dir, mut actor, backend, mut rx) = fixture().await;
    let _first = connect(&mut actor, 1);
    let _second = connect(&mut actor, 2);
    pending(&mut actor, "queued").await;
    let manager = Arc::new(tokio::sync::Mutex::new(
        EmulatorManager::new(dir.path()).await.unwrap(),
    ));
    actor.emulators = Some(manager.clone());
    let guard = manager.lock().await;
    actor.queue_emulator_park_all();
    for client in [1, 2] {
        actor
            .handle_line(
                client,
                json!({"id":1,"type":"tab.remove","payload":{"id":format!("unrelated-{client}")}})
                    .to_string(),
            )
            .await;
    }
    assert!(actor.emulator_requests.has_runtime_mutations());
    actor.handle_codex_message(json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"third","status":"completed"}}})).await;
    while let Ok(command) = rx.try_recv() {
        actor.handle(command).await;
    }
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "turn/start"));
    actor.dispose_client(1).await;
    assert!(actor.emulator_requests.has_runtime_mutations());
    while let Ok(command) = rx.try_recv() {
        assert!(!matches!(command, ServerCommand::CodexQueueAdvance { .. }));
        actor.handle(command).await;
    }
    actor.dispose_client(2).await;
    assert!(!actor.emulator_requests.has_runtime_mutations());
    assert!(actor.clients.is_empty());
    wait_for_status(&mut actor, &mut rx, "accepted").await;
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
    drop(guard);
}

struct ResumeRelease(Arc<(Mutex<bool>, std::sync::Condvar)>);
impl Drop for ResumeRelease {
    fn drop(&mut self) {
        *self.0 .0.lock().unwrap() = true;
        self.0 .1.notify_all();
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn delayed_native_resume_keeps_the_actor_responsive() {
    let (_dir, mut actor, _backend, mut rx) = fixture().await;
    pending(&mut actor, "queued").await;
    let released = Arc::new((Mutex::new(false), std::sync::Condvar::new()));
    let release = ResumeRelease(released.clone());
    let (entered_tx, entered_rx) = oneshot::channel();
    let entered = Mutex::new(Some(entered_tx));
    actor.codex = Some(CodexAppServer::mock(move |method, _| {
        assert_eq!(method, "thread/resume");
        if let Some(sender) = entered.lock().unwrap().take() {
            let _ = sender.send(());
        }
        let (mutex, condvar) = &*released;
        let mut ready = mutex.lock().unwrap();
        while !*ready {
            ready = condvar.wait(ready).unwrap();
        }
        Ok(
            json!({"thread":{"id":"thread","turns":[{"id":"first","status":"completed","items":[]}]}}),
        )
    }));
    actor.restore_codex_queues().await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(1), entered_rx)
        .await
        .unwrap()
        .unwrap();
    let mut outbound = connect(&mut actor, 1);
    tokio::time::timeout(
        std::time::Duration::from_secs(1),
        actor.handle_line(
            1,
            json!({"id":1,"type":"tab.find","payload":{"id":"tab"}}).to_string(),
        ),
    )
    .await
    .unwrap();
    assert_eq!(response(&mut outbound, 1).unwrap()["ok"], true);
    assert!(actor.codex_history_scans.contains("tab"));
    drop(release);
    finish_startup(&mut actor, &mut rx).await;
    assert!(!actor.codex_history_scans.contains("tab"));
    assert!(
        actor.codex_tab("tab").await.unwrap().payload["codexSnapshot"]["activeTurnId"].is_null()
    );
}

#[tokio::test]
async fn live_snapshot_changes_restart_pending_recovery_without_sending_twice() {
    let (_dir, mut actor, backend, mut rx) = fixture().await;
    backend.lock().unwrap().turns[2]["status"] = json!("completed");
    pending(&mut actor, "queued").await;
    let server = actor.codex.clone().unwrap();
    let gate = gate_startup(&mut actor);
    actor.restore_codex_queues().await.unwrap();
    let mut tab = actor.codex_tab("tab").await.unwrap();
    tab.payload["codexSnapshot"]["activeTurnId"] = Value::Null;
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    gate.send(Ok(server)).ok().unwrap();
    finish_startup(&mut actor, &mut rx).await;
    assert!(actor.codex_history_scans.contains("tab"));
    assert!(!backend
        .lock()
        .unwrap()
        .calls
        .iter()
        .any(|(method, _)| method == "turn/start"));
    finish_startup(&mut actor, &mut rx).await;
    wait_for_status(&mut actor, &mut rx, "accepted").await;
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

#[tokio::test]
async fn persisted_rollback_projection_is_deferred_and_checks_its_captured_context() {
    for phase in ["rolledBack", "resendFailed"] {
        for stale in [false, true] {
            let (_dir, mut actor, backend, mut rx) = fixture().await;
            let rollback = json!({"thread":{"id":"thread","turns":[backend.lock().unwrap().turns[0].clone()]}});
            let mut state = CodexChatDeliveryState::new("tab", "thread");
            state.history_revision = 1;
            state.discarded_turn_ids = vec!["second".into(), "third".into()];
            state
                .operations
                .push(alera_core::runtime::CodexChatOperation {
                    id: "edit".into(),
                    kind: "edit".into(),
                    phase: phase.into(),
                    payload: json!({"input":[{"type":"text","text":"Correction"}]}),
                    result: Some(rollback),
                });
            actor.save_codex_delivery(&mut state).await.unwrap();
            let server = actor.codex.clone().unwrap();
            let gate = gate_startup(&mut actor);
            tokio::time::timeout(
                std::time::Duration::from_secs(1),
                actor.restore_codex_queues(),
            )
            .await
            .unwrap()
            .unwrap();
            assert!(actor.codex_history_scans.contains("tab"));
            let mut outbound = connect(&mut actor, 1);
            actor
                .handle_line(
                    1,
                    json!({"id":1,"type":"tab.find","payload":{"id":"tab"}}).to_string(),
                )
                .await;
            assert_eq!(response(&mut outbound, 1).unwrap()["ok"], true);
            if stale {
                let mut current = actor
                    .runtime_store
                    .codex_chat_state("thread")
                    .await
                    .unwrap()
                    .unwrap();
                current.history_revision += 1;
                actor.save_codex_delivery(&mut current).await.unwrap();
            }
            let before = actor.codex_tab("tab").await.unwrap().payload;
            gate.send(Ok(server)).ok().unwrap();
            finish_startup(&mut actor, &mut rx).await;
            let after = actor.codex_tab("tab").await.unwrap().payload;
            if stale {
                assert_eq!(after, before);
            } else {
                assert_eq!(after["codexHistoryRevision"], 1);
                assert!(after["codexSnapshot"]["activeTurnId"].is_null());
                assert!(after["codexSnapshot"]["timelineCells"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .all(|cell| cell["turnId"] == "first"));
                assert!(!after["codexSnapshot"]["timelineCells"]
                    .as_array()
                    .unwrap()
                    .is_empty());
            }
            let state = actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap();
            assert!(state.paused);
            assert_eq!(state.operations[0].phase, phase);
            assert_eq!(
                state.operations[0].payload["input"][0]["text"],
                "Correction"
            );
            assert!(!backend
                .lock()
                .unwrap()
                .calls
                .iter()
                .any(|(method, _)| matches!(
                    method.as_str(),
                    "turn/start" | "thread/rollback" | "thread/resume"
                )));
            assert!(!actor.codex_history_scans.contains("tab"));
        }
    }
}
