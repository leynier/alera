mod support;

use alera_provider_claude::{ClaudeProvider, ClaudeProviderConfig};
use alera_provider_protocol::*;
use serde_json::json;
use support::{initialize_response, result_message, ScriptedTransport};

#[tokio::test]
async fn fork_does_not_claim_source_identity_and_rejects_turn_boundary() {
    let (transport, _) = ScriptedTransport::new([initialize_response()]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    let bad = NativeForkInput {
        source_native_thread_id: "parent-native".into(),
        session: SessionStartInput::new("child-app"),
        boundary: Some(NativeForkBoundary::Turn("host-turn".into())),
    };
    assert!(matches!(
        provider.fork_session(bad).await,
        Err(ProviderError::Unsupported(_))
    ));
    let result = provider
        .fork_session(NativeForkInput {
            source_native_thread_id: "parent-native".into(),
            session: SessionStartInput::new("child-app"),
            boundary: Some(NativeForkBoundary::Message(
                "assistant-transcript-uuid".into(),
            )),
        })
        .await
        .unwrap();
    assert!(result.native_thread_id.is_none());
    assert_ne!(result.session.native_thread_id, "parent-native");
    assert_eq!(result.session.thread_id, "child-app");
    assert!(provider.capabilities().fork);
    assert!(!provider.capabilities().rollback);
    assert!(matches!(
        provider
            .rollback_session(NativeRollbackInput {
                thread_id: "child-app".into(),
                boundary: NativeRollbackBoundary::RemoveTurns(1)
            })
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    provider.close().await.unwrap();
}

#[tokio::test]
async fn filesystem_rewind_is_separate_and_requires_launch_checkpointing() {
    let (transport, handle) = ScriptedTransport::new([
        initialize_response(),
        json!({"type":"system","subtype":"init","session_id":"native-session"}),
        json!({"type":"control_response","response":{"subtype":"success","request_id":"req_2","response":{}}}),
    ]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app");
    input
        .options
        .insert("enableFileCheckpointing".into(), json!(true));
    provider.start_session(input).await.unwrap();
    for _ in 0..3 {
        provider.next_event().await.unwrap();
    }
    let result = provider
        .rewind_files(NativeRewindFilesInput {
            thread_id: "app".into(),
            native_user_message_id: "checkpoint-uuid".into(),
        })
        .await
        .unwrap();
    assert_eq!(result.native_user_message_id, "checkpoint-uuid");
    assert_eq!(result.can_rewind, None);
    assert_eq!(result.files_changed, None);
    assert_eq!(result.native_response, json!({}));
    let writes = handle.writes.lock().unwrap().clone();
    assert_eq!(
        writes.last().unwrap()["request"],
        json!({"subtype":"rewind_files","user_message_id":"checkpoint-uuid"})
    );
    assert!(!provider.capabilities().rollback);
    provider.close().await.unwrap();

    let (transport, _) = ScriptedTransport::new([initialize_response()]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    assert!(matches!(
        provider
            .rewind_files(NativeRewindFilesInput {
                thread_id: "app".into(),
                native_user_message_id: "checkpoint".into()
            })
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    provider.close().await.unwrap();
}

#[tokio::test]
async fn native_task_refs_transcript_uuid_and_terminal_patch_are_preserved() {
    let frames = [
        initialize_response(),
        json!({"type":"system","subtype":"task_started","task_id":"native-task","session_id":"native-session","tool_use_id":"native-tool","description":"child"}),
        json!({"type":"system","subtype":"task_updated","task_id":"native-task","patch":{"status":"failed"}}),
        json!({"type":"assistant","session_id":"native-session","uuid":"transcript-uuid","parent_tool_use_id":"native-tool","message":{"id":"content-id","model":"model","content":[{"type":"text","text":"hello"}]}}),
        result_message(false, None),
    ];
    let (transport, _) = ScriptedTransport::new(frames);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let started = loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::TaskStarted {
            break event;
        }
    };
    let task = started.native_task().unwrap().unwrap();
    assert_eq!(task.native_task_id.as_deref(), Some("native-task"));
    assert_eq!(task.native_tool_call_id.as_deref(), Some("native-tool"));
    assert!(task.child_native_thread_ids.is_empty());
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TaskCompleted);
    assert_eq!(completed.payload["status"], "failed");
    let assistant = provider.next_event().await.unwrap().unwrap();
    assert_eq!(assistant.payload["nativeMessageId"], "transcript-uuid");
    assert_eq!(assistant.item_id.as_deref(), Some("content-id"));
    assert_ne!(
        assistant.item_id.as_deref(),
        assistant.payload["nativeMessageId"].as_str()
    );
    provider.close().await.unwrap();
}

#[tokio::test]
async fn missing_native_task_id_stays_a_warning_without_invented_lineage() {
    let (transport, _) = ScriptedTransport::new([
        initialize_response(),
        json!({"type":"system","subtype":"task_started","description":"unknown"}),
    ]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    for _ in 0..2 {
        provider.next_event().await.unwrap();
    }
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RuntimeWarning);
    assert!(event.native_task().unwrap().is_none());
    provider.close().await.unwrap();
}

#[tokio::test]
async fn session_effort_is_supported_and_per_turn_effort_is_explicitly_unsupported() {
    let (transport, _) = ScriptedTransport::new([initialize_response()]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut session = SessionStartInput::new("app");
    session
        .options
        .insert("reasoningEffort".into(), json!("high"));
    provider.start_session(session).await.unwrap();
    assert!(provider.reasoning_effort_capabilities().session);
    assert!(!provider.reasoning_effort_capabilities().turn);
    let mut turn = TurnInput::text("app", "hello");
    turn.options.insert("reasoningEffort".into(), json!("low"));
    assert!(matches!(
        provider.send_turn(turn).await,
        Err(ProviderError::Unsupported(_))
    ));
    provider.close().await.unwrap();
}

#[tokio::test]
async fn launched_checkpoint_capability_and_rewind_result_preserve_native_refusal() {
    let (transport, _) = ScriptedTransport::new([
        initialize_response(),
        json!({"type":"system","subtype":"init","session_id":"native-session"}),
        json!({"type":"control_response","response":{"subtype":"success","request_id":"req_2","response":{"canRewind":false,"error":"checkpoint unavailable","filesChanged":[],"insertions":0,"deletions":0,"skippedLinks":2}}}),
    ]);
    let mut config = ClaudeProviderConfig::default();
    config.options.enable_file_checkpointing = true;
    let mut provider = ClaudeProvider::with_transport(transport, config).unwrap();
    assert!(provider.native_history_capabilities().file_checkpointing);
    assert!(!provider.native_history_capabilities().rewind_files);
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    assert!(provider.native_history_capabilities().rewind_files);
    for _ in 0..3 {
        provider.next_event().await.unwrap();
    }
    let result = provider
        .rewind_files(NativeRewindFilesInput {
            thread_id: "app".into(),
            native_user_message_id: "12345678-1234-4234-8234-123456789abc".into(),
        })
        .await
        .unwrap();
    assert_eq!(result.can_rewind, Some(false));
    assert_eq!(result.error.as_deref(), Some("checkpoint unavailable"));
    assert_eq!(result.files_changed, Some(Vec::new()));
    assert_eq!(
        (result.insertions, result.deletions, result.skipped_links),
        (Some(0), Some(0), Some(2))
    );
    provider.close().await.unwrap();
    assert!(!provider.native_history_capabilities().rewind_files);
}

#[tokio::test]
async fn explicit_checkpoint_disable_overrides_configured_enabled_capability() {
    let (transport, _) = ScriptedTransport::new([initialize_response()]);
    let mut config = ClaudeProviderConfig::default();
    config.options.enable_file_checkpointing = true;
    let mut provider = ClaudeProvider::with_transport(transport, config).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app");
    input
        .options
        .insert("enableFileCheckpointing".into(), json!(false));
    provider.start_session(input).await.unwrap();
    assert!(provider.native_history_capabilities().file_checkpointing);
    assert!(!provider.native_history_capabilities().rewind_files);
    provider.close().await.unwrap();
}
