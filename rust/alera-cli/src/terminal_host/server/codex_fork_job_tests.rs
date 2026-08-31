use super::scans::{connect, response};
use super::*;
use crate::terminal_host::client::ClientFrame;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::sync::{mpsc::UnboundedReceiver, oneshot};

struct ReleaseFork(Arc<(Mutex<bool>, std::sync::Condvar)>);
impl Drop for ReleaseFork {
    fn drop(&mut self) {
        *self.0 .0.lock().unwrap() = true;
        self.0 .1.notify_all();
    }
}

async fn next_matching(
    rx: &mut UnboundedReceiver<ServerCommand>,
    predicate: fn(&ServerCommand) -> bool,
) -> ServerCommand {
    loop {
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        if predicate(&command) {
            return command;
        }
    }
}
async fn request_fork(actor: &mut ServerActor, rx: &mut UnboundedReceiver<ServerCommand>) {
    actor.handle_line(1, json!({"id":1,"type":"codex.thread.fork","payload":{"tabId":"tab","expectedThreadId":"thread","operationId":"fork"}}).to_string()).await;
    let command = next_matching(rx, |command| {
        matches!(command, ServerCommand::CodexHistoryScanFinished { .. })
    })
    .await;
    actor.handle_codex_command(command).await;
}
async fn finish_fork(
    actor: &mut ServerActor,
    rx: &mut UnboundedReceiver<ServerCommand>,
    out: &mut UnboundedReceiver<ClientFrame>,
    id: i64,
) -> Value {
    loop {
        if let Some(result) = response(out, id) {
            return result;
        }
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), rx.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn native_fork_and_projection_keep_other_requests_and_stop_responsive() {
    for stage in ["create", "project"] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        let turns = backend.lock().unwrap().turns.clone();
        let released = Arc::new((Mutex::new(false), std::sync::Condvar::new()));
        let release = ReleaseFork(released.clone());
        let (entered_tx, entered_rx) = oneshot::channel();
        let entered = Mutex::new(Some(entered_tx));
        let calls = Arc::new(AtomicUsize::new(0));
        let observed = calls.clone();
        let server = CodexAppServer::mock(move |method, _| match method {
            "thread/turns/list" => Ok(json!({"data":turns,"nextCursor":null})),
            "thread/fork" => {
                observed.fetch_add(1, Ordering::SeqCst);
                if let Some(sender) = entered.lock().unwrap().take() {
                    let _ = sender.send(());
                }
                if stage == "create" {
                    let (mutex, condvar) = &*released;
                    let mut ready = mutex.lock().unwrap();
                    while !*ready {
                        ready = condvar.wait(ready).unwrap();
                    }
                }
                Ok(json!({"thread":{"id":"forked","turns":turns[..2]}}))
            }
            "turn/interrupt" => Ok(json!({})),
            _ => panic!("Unexpected native call {method}"),
        });
        actor.codex = Some(server.clone());
        let history_guard = if stage == "project" {
            Some(server.thread_history.lock().await)
        } else {
            None
        };
        let mut first = connect(&mut actor, 1);
        let mut second = connect(&mut actor, 2);
        request_fork(&mut actor, &mut rx).await;
        tokio::time::timeout(std::time::Duration::from_secs(1), entered_rx)
            .await
            .unwrap()
            .unwrap();
        if stage == "project" {
            let created = next_matching(&mut rx, |command| {
                matches!(command, ServerCommand::CodexForkCreated { .. })
            })
            .await;
            actor.handle_codex_command(created).await;
            let state = actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap();
            assert_eq!(state.operations[0].phase, "forkCreated");
            assert_eq!(
                state.operations[0].result.as_ref().unwrap()["thread"]["id"],
                "forked"
            );
        }
        assert!(response(&mut first, 1).is_none());
        actor
            .handle_line(
                2,
                json!({"id":2,"type":"tab.find","payload":{"id":"tab"}}).to_string(),
            )
            .await;
        assert_eq!(response(&mut second, 2).unwrap()["ok"], true);
        actor
            .handle_line(
                2,
                json!({"id":3,"type":"tab.remove","payload":{"id":"tab"}}).to_string(),
            )
            .await;
        assert_eq!(response(&mut second, 3).unwrap()["ok"], false);
        actor.handle_line(2, json!({"id":4,"type":"codex.turn.interrupt","payload":{"tabId":"tab","expectedThreadId":"thread","turnId":"third"}}).to_string()).await;
        assert_eq!(response(&mut second, 4).unwrap()["ok"], true);
        let source = actor.codex_tab("tab").await.unwrap().payload;
        drop(release);
        drop(history_guard);
        let result = finish_fork(&mut actor, &mut rx, &mut first, 1).await;
        assert_eq!(result["ok"], true, "{stage}: {result}");
        assert_eq!(actor.codex_tab("tab").await.unwrap().payload, source);
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert!(state.paused);
        assert!(state.messages.is_empty());
        assert_eq!(state.operations[0].phase, "completed");
        assert!(actor
            .runtime_store
            .codex_chat_state("forked")
            .await
            .unwrap()
            .is_none());
        assert_eq!(
            actor
                .runtime_store
                .list_workspace_tabs("workspace")
                .await
                .unwrap()
                .len(),
            2
        );
        assert!(!actor.codex_history_scans.contains("tab"));
        actor.handle_line(1, json!({"id":5,"type":"codex.thread.fork","payload":{"tabId":"tab","expectedThreadId":"thread","operationId":"fork"}}).to_string()).await;
        assert_eq!(
            response(&mut first, 5).unwrap()["payload"],
            result["payload"]
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}

#[tokio::test]
async fn stale_fork_results_keep_receipts_without_installing_into_changed_context() {
    for changed in ["history", "thread", "server"] {
        let (_dir, mut actor, backend, mut rx) = fixture().await;
        let mut outbound = connect(&mut actor, 1);
        let original_server = actor.codex.clone().unwrap();
        request_fork(&mut actor, &mut rx).await;
        let created = next_matching(&mut rx, |command| {
            matches!(command, ServerCommand::CodexForkCreated { .. })
        })
        .await;
        match changed {
            "history" => {
                let mut state = actor
                    .runtime_store
                    .codex_chat_state("thread")
                    .await
                    .unwrap()
                    .unwrap();
                state.history_revision += 1;
                actor.save_codex_delivery(&mut state).await.unwrap();
            }
            "thread" => {
                let mut tab = actor.codex_tab("tab").await.unwrap();
                tab.payload["codexThreadId"] = json!("replacement");
                actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
            }
            "server" => {
                actor.codex = Some(CodexAppServer::mock(|_, _| {
                    panic!("must not use replacement")
                }))
            }
            _ => unreachable!(),
        }
        actor.handle_codex_command(created).await;
        assert_eq!(response(&mut outbound, 1).unwrap()["ok"], false);
        assert_eq!(
            actor
                .runtime_store
                .list_workspace_tabs("workspace")
                .await
                .unwrap()
                .len(),
            1
        );
        assert!(!actor.codex_history_scans.contains("tab"));
        let state = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(state.operations[0].phase, "forkCreated");
        assert!(state.operations[0].result.is_some());
        actor.codex = Some(original_server);
        let mut tab = actor.codex_tab("tab").await.unwrap();
        tab.payload["codexThreadId"] = json!("thread");
        actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
        actor.handle_line(1, json!({"id":2,"type":"codex.thread.fork","payload":{"tabId":"tab","expectedThreadId":"thread","operationId":"fork"}}).to_string()).await;
        let result = finish_fork(&mut actor, &mut rx, &mut outbound, 2).await;
        assert_eq!(result["ok"], true, "{changed}: {result}");
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
}
