use super::{fixture, CodexChatDeliveryState};
use alera_core::runtime::CodexChatOperation;
use serde_json::json;

#[tokio::test]
async fn retry_rejects_changed_correction_without_mutating_or_resending() {
    for phase in [
        "interrupting",
        "rollingBack",
        "rolledBack",
        "resendFailed",
        "completed",
        "uncertain",
    ] {
        let (_directory, mut actor, backend, _rx) = fixture().await;
        let mut state = CodexChatDeliveryState::new("tab", "thread");
        state.paused = true;
        state.operations.push(CodexChatOperation {
            id: "edit".into(), kind: "edit".into(), phase: phase.into(),
            payload: json!({"userMessage":{"text":"Original correction"},"editTargetTurnId":"second","editTargetItemId":"user-second"}),
            result: Some(json!({"thread":{"id":"thread","turns":[]}})),
        });
        actor
            .runtime_store
            .save_codex_chat_state(&mut state)
            .await
            .unwrap();
        let before = serde_json::to_value(&state).unwrap();
        for (key, value) in [
            ("text", "Revised correction"),
            ("turnId", "first"),
            ("itemId", "user-first"),
        ] {
            let mut request =
                json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit"});
            request[key] = json!(value);
            let error = actor.edit_codex_history(&request).await.unwrap_err();
            assert!(
                error.wire_message().contains("different correction"),
                "{phase}: {error:?}"
            );
            let after = actor
                .runtime_store
                .codex_chat_state("thread")
                .await
                .unwrap()
                .unwrap();
            assert_eq!(serde_json::to_value(after).unwrap(), before);
            assert!(backend.lock().unwrap().calls.is_empty());
        }
    }
}

#[tokio::test]
async fn completed_retry_accepts_identical_content_or_no_content_without_resending() {
    let (_directory, mut actor, backend, _rx) = fixture().await;
    let mut state = CodexChatDeliveryState::new("tab", "thread");
    state.operations.push(CodexChatOperation {
        id: "edit".into(), kind: "edit".into(), phase: "completed".into(),
        payload: json!({"userMessage":{"text":"Correction"},"editTargetTurnId":"second","editTargetItemId":"user-second"}),
        result: None,
    });
    actor
        .runtime_store
        .save_codex_chat_state(&mut state)
        .await
        .unwrap();
    for content in [
        json!({}),
        json!({"text":"Correction","turnId":"second","itemId":"user-second"}),
    ] {
        let mut request = json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit"});
        request
            .as_object_mut()
            .unwrap()
            .extend(content.as_object().unwrap().clone());
        assert_eq!(
            actor.edit_codex_history(&request).await.unwrap(),
            state.snapshot()
        );
        assert!(backend.lock().unwrap().calls.is_empty());
    }
}
