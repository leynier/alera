use super::*;
use alera_core::runtime::CodexQueueEntry;

const OUTPUT_FAILURE: &str = "Codex app-server output failed: stream did not contain valid UTF-8";

fn queued_entry(status: &str) -> CodexQueueEntry {
    CodexQueueEntry {
        id: "queued".into(),
        revision: 0,
        payload: json!({"clientUserMessageId":"queued","input":[{"type":"text","text":"Queued"}],"userMessage":{"text":"Queued"}}),
        status: status.into(),
        error: None,
        turn_id: None,
    }
}

#[tokio::test]
async fn output_transport_failure_never_retries_an_unconfirmed_fork() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    backend.lock().unwrap().fork_error = Some(OUTPUT_FAILURE.into());
    let request =
        json!({"tabId":"tab","expectedThreadId":"thread","operationId":"fork-output-failure"});
    assert!(actor.fork_codex_history(&request).await.is_err());
    assert!(actor.fork_codex_history(&request).await.is_err());
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.operations[0].phase, "uncertain");
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
async fn output_failure_before_process_exit_preserves_uncertain_delivery() {
    let (_directory, mut actor, _backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.messages.push(queued_entry("sending"));
    actor.save_codex_delivery(&mut state).await.unwrap();
    actor
        .finish_codex_queue_delivery(
            "tab",
            "thread",
            "queued",
            Err(HostError::state(OUTPUT_FAILURE)),
        )
        .await
        .unwrap();
    for exited in [false, true] {
        if exited {
            actor
                .handle_codex_process_exited(OUTPUT_FAILURE.into())
                .await;
        }
        let current = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert!(current.paused);
        assert_eq!(current.messages[0].status, "uncertain");
        assert!(actor.handle_codex_queue_request("codex.queue.resume", &json!({"tabId":"tab","expectedThreadId":"thread","expectedRevision":current.revision,"operationId":format!("resume-{exited}")})).await.is_err());
    }
}

async fn resume_after_exit(actor: &mut ServerActor) {
    let current = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    actor.handle_codex_queue_request("codex.queue.resume", &json!({"tabId":"tab","expectedThreadId":"thread","expectedRevision":current.revision,"operationId":"resume"})).await.unwrap();
    actor.advance_codex_queue("tab").await;
}

#[tokio::test]
async fn resume_queue_loads_the_native_thread_after_exit_without_an_application() {
    let (directory, mut actor, _backend, mut rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.messages.push(queued_entry("queued"));
    actor.save_codex_delivery(&mut state).await.unwrap();
    actor
        .handle_codex_process_exited("Codex exited".into())
        .await;
    let calls = Arc::new(Mutex::new(Vec::<String>::new()));
    let observed = calls.clone();
    actor.codex = Some(CodexAppServer::mock(move |method, _params| {
        observed.lock().unwrap().push(method.into());
        match method {
            "thread/resume" => Ok(json!({"thread":{"id":"thread","turns":[]}})),
            "turn/start" => Ok(json!({"turn":{"id":"queued-turn","status":"inProgress"}})),
            _ => Err(HostError::state(format!("Unexpected method {method}"))),
        }
    }));
    resume_after_exit(&mut actor).await;
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
    assert_eq!(*calls.lock().unwrap(), ["thread/resume", "turn/start"]);
    let current = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.messages[0].status, "accepted");
    let server = actor.codex.as_ref().unwrap();
    let tab = actor.codex_tab("tab").await.unwrap();
    let cwd = directory.path().to_str().unwrap();
    server
        .take_thread_hydration("tab", "thread", cwd, tab.updated_at)
        .await;
    assert!(server.has_loaded_thread("tab", "thread", cwd).await);
    assert!(!server.has_loaded_thread("tab", "other", cwd).await);
    assert!(
        !server
            .has_loaded_thread("tab", "thread", "/different")
            .await
    );
    server.forget_thread_hydration("tab").await;
    assert!(!server.has_loaded_thread("tab", "thread", cwd).await);
    assert!(actor.clients.is_empty());
}

#[tokio::test]
async fn queue_resume_does_not_send_over_a_resumed_active_turn_or_missing_rollout() {
    for (missing, materialized) in [(false, false), (true, false), (true, true)] {
        let (_directory, mut actor, _backend, _rx) = fixture().await;
        if materialized {
            let mut tab = actor.codex_tab("tab").await.unwrap();
            tab.payload["codexSnapshot"]["timelineCells"] = json!([{"id":"user-third","kind":"userMessage","turnId":"third","markdownText":"Original request"}]);
            actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
        }
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.messages.push(queued_entry("queued"));
        actor.save_codex_delivery(&mut state).await.unwrap();
        actor
            .handle_codex_process_exited("Codex exited".into())
            .await;
        let calls = Arc::new(Mutex::new(Vec::<String>::new()));
        let observed = calls.clone();
        actor.codex = Some(CodexAppServer::mock(move |method, _params| {
            observed.lock().unwrap().push(method.into());
            match method {
                "thread/resume" if missing => {
                    Err(HostError::state("no rollout found for thread id thread"))
                }
                "thread/resume" => Ok(
                    json!({"thread":{"id":"thread","turns":[{"id":"third","status":"inProgress","items":[]}]}}),
                ),
                _ => Err(HostError::state(format!("Unexpected method {method}"))),
            }
        }));
        resume_after_exit(&mut actor).await;
        assert_eq!(*calls.lock().unwrap(), ["thread/resume"]);
        let current = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            current.messages[0].status,
            if missing { "failed" } else { "queued" }
        );
        assert_eq!(current.paused, missing);
        assert_eq!(
            actor.codex_tab("tab").await.unwrap().payload["codexThreadId"],
            if missing && !materialized {
                Value::Null
            } else {
                json!("thread")
            }
        );
    }
}

#[tokio::test]
async fn steer_revalidates_the_captured_turn_after_native_loading() {
    let (_directory, mut actor, _backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.messages.push(queued_entry("queued"));
    actor.save_codex_delivery(&mut state).await.unwrap();
    let calls = Arc::new(Mutex::new(Vec::<String>::new()));
    let observed = calls.clone();
    actor.codex = Some(CodexAppServer::mock(move |method, _params| {
        observed.lock().unwrap().push(method.into());
        match method {
            "thread/resume" => Ok(
                json!({"thread":{"id":"thread","turns":[{"id":"third","status":"completed","items":[]}]}}),
            ),
            _ => Err(HostError::state(format!("Unexpected method {method}"))),
        }
    }));
    actor
        .deliver_codex_queue_entry(state, 0, Some("third".into()))
        .await
        .unwrap();
    assert_eq!(*calls.lock().unwrap(), ["thread/resume"]);
    let current = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.messages[0].status, "failed");
    assert!(current.messages[0]
        .error
        .as_deref()
        .unwrap()
        .contains("original turn ended"));
}
