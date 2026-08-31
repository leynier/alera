use super::actor_test_harness::test_actor;
use super::ServerActor;
use alera_core::runtime::{CodexChatDeliveryState, CodexQueueEntry, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::{json, Value};
use std::collections::HashMap;

async fn fixture() -> (tempfile::TempDir, ServerActor, CodexChatDeliveryState) {
    let directory = tempfile::tempdir().unwrap();
    let actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: "workspace".into(),
            kind: "codex".into(),
            title: "Chat".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"codexThreadId": "thread", "codexSnapshot": {"timelineCells": []}}),
        })
        .await
        .unwrap();
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    for id in ["first", "second"] {
        state.messages.push(CodexQueueEntry {
            id: id.into(), revision: 0, status: "queued".into(), error: None, turn_id: None,
            payload: json!({"tabId": "tab", "expectedThreadId": "thread", "clientUserMessageId": id, "input": [{"type": "text", "text": id}], "model": "captured-model", "userMessage": {"text": id}}),
        });
    }
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    (directory, actor, state)
}

fn request(revision: u64, id: &str) -> Value {
    json!({"tabId": "tab", "expectedThreadId": "thread", "expectedRevision": revision, "messageId": id})
}

#[tokio::test]
async fn two_clients_cannot_remove_or_edit_a_stale_queue() {
    let (_directory, mut actor, state) = fixture().await;
    let removed = actor
        .handle_codex_queue_request("codex.queue.remove", &request(state.revision, "first"))
        .await
        .unwrap();
    let error = actor
        .handle_codex_queue_request("codex.queue.remove", &request(state.revision, "second"))
        .await
        .unwrap_err();
    assert!(error.wire_message().contains("queue changed"));
    assert_eq!(removed["messages"][0]["id"], "second");
    assert_eq!(
        actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap()
            .messages[1]
            .status,
        "queued"
    );
}

#[tokio::test]
async fn edit_preserves_order_and_captured_configuration() {
    let (_directory, mut actor, state) = fixture().await;
    let mut payload = request(state.revision, "first");
    payload["message"] = json!({"input": [{"type":"text","text":"corrected"}], "userMessage": {"text":"corrected"}, "model":"changed-model"});
    let queue = actor
        .handle_codex_queue_request("codex.queue.edit", &payload)
        .await
        .unwrap();
    assert_eq!(queue["messages"][0]["id"], "first");
    assert_eq!(queue["messages"][1]["id"], "second");
    assert_eq!(queue["messages"][0]["payload"]["model"], "captured-model");
}

#[tokio::test]
async fn steer_after_completion_preserves_the_message_and_pauses() {
    let (_directory, mut actor, state) = fixture().await;
    let mut payload = request(state.revision, "first");
    payload["turnId"] = json!("finished");
    assert!(actor
        .handle_codex_queue_request("codex.queue.steer", &payload)
        .await
        .is_err());
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert!(state.paused);
    assert_eq!(state.messages[0].status, "failed");
    assert!(actor
        .handle_codex_queue_request("codex.queue.resume", &request(state.revision, "first"))
        .await
        .is_err());
}

#[tokio::test]
async fn uncertain_delivery_is_retained_and_cannot_resume_or_cancel() {
    let (_directory, mut actor, mut state) = fixture().await;
    state.messages[0].status = "sending".into();
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    actor
        .finish_codex_queue_delivery(
            "tab",
            "thread",
            "first",
            Err(crate::terminal_host::host_error::HostError::state(
                "Codex timed out",
            )),
        )
        .await
        .unwrap();
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.messages[0].status, "uncertain");
    assert!(state.paused);
    for action in ["codex.queue.resume", "codex.queue.cancel"] {
        assert!(actor
            .handle_codex_queue_request(action, &request(state.revision, "first"))
            .await
            .is_err());
    }
}

#[tokio::test]
async fn duplicate_acceptance_does_not_replace_a_later_queue_revision() {
    let (_directory, mut actor, mut state) = fixture().await;
    state.messages[0].status = "sending".into();
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    actor
        .finish_codex_queue_delivery(
            "tab",
            "thread",
            "first",
            Ok(json!({"turn": {"id": "turn"}})),
        )
        .await
        .unwrap();
    let state = actor
        .runtime_store
        .codex_chat_state("thread")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.messages[0].status, "accepted");
    actor
        .finish_codex_queue_delivery(
            "tab",
            "thread",
            "first",
            Ok(json!({"turn": {"id": "turn"}})),
        )
        .await
        .unwrap();
    assert_eq!(
        actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap()
            .revision,
        state.revision
    );
}

#[tokio::test]
async fn close_cancellation_also_covers_paused_queues_from_previous_threads() {
    let (_directory, mut actor, state) = fixture().await;
    let mut other = state.clone();
    other.thread_id = "previous-thread".into();
    other.revision = 0;
    other.paused = true;
    actor.save_codex_delivery(&mut other).await.unwrap();
    let overview = actor
        .handle_codex_queue_request("codex.queue.get", &json!({"tabId":"tab"}))
        .await
        .unwrap();
    assert_eq!(overview["otherQueues"].as_array().unwrap().len(), 1);
    assert!(actor
        .handle_codex_queue_request("codex.queue.cancel", &request(state.revision, "first"))
        .await
        .is_err());
    let mut cancellation = request(state.revision, "first");
    cancellation["otherQueues"] = overview["otherQueues"].clone();
    actor
        .handle_codex_queue_request("codex.queue.cancel", &cancellation)
        .await
        .unwrap();
    assert!(actor
        .runtime_store
        .list_codex_chat_states()
        .await
        .unwrap()
        .iter()
        .all(|state| !state.has_pending()));
}
