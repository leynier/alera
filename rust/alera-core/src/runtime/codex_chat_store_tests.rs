use super::{
    CodexChatDeliveryState, CodexChatOperation, CodexQueueEntry, RuntimeStore, WorkspaceTabRecord,
};
use chrono::Utc;
use serde_json::json;

#[tokio::test]
async fn queue_survives_restart_and_tab_payload_updates() {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = Utc::now();
    let mut tab = WorkspaceTabRecord {
        id: "tab".into(),
        workspace_id: "workspace".into(),
        kind: "codex".into(),
        title: "Chat".into(),
        created_at: now,
        updated_at: now,
        payload: json!({}),
    };
    store.upsert_workspace_tab(tab.clone()).await.unwrap();
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.paused = true;
    state.messages.push(CodexQueueEntry {
        id: "message".into(),
        revision: 0,
        payload: json!({"input": [{"type": "text", "text": "hello"}]}),
        status: "queued".into(),
        error: None,
        turn_id: None,
    });
    store.save_codex_chat_state(&mut state).await.unwrap();
    tab.payload = json!({"codexSnapshot": {"title": "Renamed"}});
    store.upsert_workspace_tab(tab).await.unwrap();
    drop(store);
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let restored = store.codex_chat_state("thread").await.unwrap().unwrap();
    assert!(restored.paused);
    assert_eq!(restored.messages[0].id, "message");
    assert_eq!(restored.messages[0].payload["input"][0]["text"], "hello");
    store.remove_workspace_tab("tab").await.unwrap();
    assert!(store.codex_chat_state("thread").await.unwrap().is_none());
}

#[tokio::test]
async fn concurrent_writers_cannot_overwrite_another_revision() {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let mut initial = CodexChatDeliveryState::new("tab", "thread");
    store.save_codex_chat_state(&mut initial).await.unwrap();
    let mut first = initial.clone();
    let mut second = initial;
    first.paused = true;
    let (first_result, second_result) = tokio::join!(
        store.save_codex_chat_state(&mut first),
        store.save_codex_chat_state(&mut second)
    );
    assert_ne!(first_result.is_ok(), second_result.is_ok());
    assert_eq!(
        store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap()
            .revision,
        2
    );
}

#[test]
fn partial_edit_keeps_history_locked_and_retains_correction() {
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.operations.push(CodexChatOperation {
        id: "edit".into(),
        kind: "edit".into(),
        phase: "resendFailed".into(),
        payload: json!({"text": "correction"}),
        result: Some(json!({"thread": {"turns": []}})),
    });
    assert!(state.history_locked());
    assert_eq!(state.operations[0].payload["text"], "correction");
    assert!(state.snapshot()["editOperation"]["result"]
        .get("thread")
        .is_none());
    state.operations[0].phase = "completed".into();
    assert!(!state.history_locked());
}
