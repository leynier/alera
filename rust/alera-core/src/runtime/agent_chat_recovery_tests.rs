use serde_json::json;

use super::super::agent_chat_test_support::*;
use super::super::*;

/// Leaves a chat mid-turn: a running turn, an open request, a streaming
/// reply, a queued user message, and a host-owned queue field.
async fn leave_running(store: &RuntimeStore, chat_id: &str) {
    let (cursor, mut next) = next_snapshot(store, chat_id).await;
    next["session"] = session("waiting");
    next["session"]["activeTurnId"] = json!("t2");
    next["session"]["capabilities"]["resume"] = json!(true);
    next["turns"] = json!([
        {"turnId": "t1", "status": "completed"},
        {"turnId": "t2", "status": "running"},
    ]);
    next["pendingRequests"] =
        json!([{"requestId": "q1", "kind": "commandExecutionApproval", "turnId": "t2"}]);
    next["queuedInputs"] = json!([{"clientMessageId": "c9", "text": "after this"}]);
    let mut streaming = item("a2", "assistant_message", "partial");
    streaming["status"] = json!("inProgress");
    streaming["streaming"] = json!(true);
    streaming["turnId"] = json!("t2");
    let mut queued = item("u3", "user_message", "after this");
    queued["status"] = json!("inProgress");
    queued["clientMessageId"] = json!("c9");
    let delta = json!({
        "session": next["session"],
        "turns": next["turns"],
        "requests": next["pendingRequests"],
        "queuedInputs": next["queuedInputs"],
        "items": [item("u1", "user_message", "first"), streaming, queued],
    });
    store
        .commit_agent_chat(chat_id, cursor, &next, &delta, None)
        .await
        .unwrap();
}

#[tokio::test]
async fn restart_recovery_interrupts_turns_and_expires_requests_once() {
    let dir = tempfile::tempdir().unwrap();
    let (chat_id, idle_id) = {
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        add_workspace(&store, "ws").await;
        let chat_id = create_chat(&store, "ws", "tab").await;
        leave_running(&store, &chat_id).await;
        let idle_id = create_chat(&store, "ws", "tab-idle").await;
        let (cursor, mut stopped) = next_snapshot(&store, &idle_id).await;
        stopped["session"] = session("stopped");
        store
            .commit_agent_chat(
                &idle_id,
                cursor,
                &stopped,
                &json!({"session": stopped["session"]}),
                None,
            )
            .await
            .unwrap();
        store.pool().close().await;
        (chat_id, idle_id)
    };
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let outcomes = store.recover_agent_chats().await.unwrap();
    assert_eq!(outcomes.len(), 1);
    let outcome = &outcomes[0];
    assert_eq!(outcome.chat_id, chat_id);
    assert_eq!(outcome.cursor, 2);
    assert_eq!(outcome.interrupted_turn_ids, ["t2"]);
    assert_eq!(outcome.expired_request_ids, ["q1"]);
    assert!(outcome.can_resume && outcome.can_restart);

    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    let snapshot = &chat.snapshot;
    assert_eq!(snapshot["session"]["status"], "stopped");
    assert!(snapshot["session"].get("activeTurnId").is_none());
    assert_eq!(snapshot["turns"][0]["status"], "completed");
    assert_eq!(snapshot["turns"][1]["status"], "interrupted");
    assert_eq!(
        snapshot["turns"][1]["reason"],
        AGENT_CHAT_INTERRUPT_RUNTIME_RESTARTED
    );
    assert!(snapshot["turns"][1].get("interruptReason").is_none());
    assert_eq!(snapshot["pendingRequests"], json!([]));
    assert_eq!(snapshot["queuedInputs"][0]["clientMessageId"], "c9");
    assert_eq!(snapshot["recovery"]["kind"], AGENT_CHAT_RECOVERY_RESUMABLE);
    assert!(snapshot["recovery"]["message"]
        .as_str()
        .unwrap()
        .contains("runtime restarted"));
    assert_eq!(snapshot["recovery"]["canResume"], true);
    assert_eq!(snapshot["recovery"]["canRestart"], true);
    assert_eq!(snapshot["recovery"]["reason"], "runtimeRestarted");
    assert_eq!(snapshot["recovery"]["previousStatus"], "waiting");
    assert!(snapshot["recovery"].get("nativeThreadId").is_none());
    assert!(!serde_json::to_string(snapshot)
        .unwrap()
        .contains("native-thread"));
    let items = snapshot["items"].as_array().unwrap();
    let by_id = |id: &str| {
        items
            .iter()
            .find(|item| item["itemId"] == id)
            .unwrap()
            .clone()
    };
    assert_eq!(by_id("a2")["status"], "failed");
    assert_eq!(by_id("a2")["streaming"], false);
    assert_eq!(by_id("a2")["text"], "partial");
    assert_eq!(by_id("u3")["status"], "inProgress");
    assert_eq!(by_id("u3")["text"], "after this");

    let events = store.agent_chat_events(&chat_id, 1, 10).await.unwrap();
    let delta = &events.events[0].delta;
    assert_eq!(delta["requests"], json!([]));
    assert_eq!(delta["session"]["status"], "stopped");
    assert_eq!(delta["turns"][0]["turnId"], "t2");
    assert_eq!(delta["recovery"]["kind"], AGENT_CHAT_RECOVERY_RESUMABLE);
    assert_eq!(
        delta["turns"][0]["reason"],
        AGENT_CHAT_INTERRUPT_RUNTIME_RESTARTED
    );
    assert_eq!(store.agent_chat(&idle_id).await.unwrap().unwrap().cursor, 1);

    assert!(store.recover_agent_chats().await.unwrap().is_empty());
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 2);

    // The host clears the notice once the user resumes.
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next.as_object_mut().unwrap().remove("recovery");
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"recovery": null}), None)
        .await
        .unwrap();
    assert!(store
        .agent_chat(&chat_id)
        .await
        .unwrap()
        .unwrap()
        .snapshot
        .get("recovery")
        .is_none());
}

#[tokio::test]
async fn archived_chats_are_recovered_and_unbound_threads_are_not_resumable() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    leave_running(&store, &chat_id).await;
    store
        .bind_agent_chat_native_thread(&chat_id, 1, None)
        .await
        .unwrap();
    store.archive_agent_chat(&chat_id).await.unwrap();
    let outcomes = store.recover_agent_chats().await.unwrap();
    assert_eq!(outcomes.len(), 1);
    assert!(!outcomes[0].can_resume && outcomes[0].can_restart);
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert!(chat.archived);
    assert_eq!(
        chat.snapshot["recovery"]["kind"],
        AGENT_CHAT_RECOVERY_NOT_RESUMABLE
    );
    assert_eq!(chat.snapshot["recovery"]["canResume"], false);
    assert_eq!(chat.snapshot["session"]["status"], "stopped");
}

#[tokio::test]
async fn an_errored_session_keeps_its_status_through_recovery() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    let mut streaming = item("a", "assistant_message", "cut");
    streaming["streaming"] = json!(true);
    streaming["status"] = json!("inProgress");
    next["session"] = session("error");
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"session": next["session"], "items": [streaming]}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(store.recover_agent_chats().await.unwrap().len(), 1);
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(chat.snapshot["session"]["status"], "error");
    // A native thread alone is not enough: the provider never declared resume.
    assert!(chat.native_thread_id.is_some());
    assert_eq!(
        chat.snapshot["recovery"]["kind"],
        AGENT_CHAT_RECOVERY_NOT_RESUMABLE
    );
    assert_eq!(chat.snapshot["recovery"]["canResume"], false);
    assert_eq!(chat.snapshot["items"][0]["status"], "failed");
}
