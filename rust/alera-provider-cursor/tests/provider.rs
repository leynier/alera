use alera_provider_cursor::{CursorProvider, CursorProviderConfig};
use alera_provider_protocol::{
    Attachment, EventKind, Provider, RuntimeMode, SessionStartInput, TurnInput,
};
use cursor_agent_sdk::{encode_connect_frame, CursorClient, MockBridgeTransport};
use serde_json::json;
use std::path::PathBuf;

#[tokio::test]
async fn cursor_provider_maps_lifecycle_and_streamed_text() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1","model":{"id":"composer-2"}})));
    mock.push_stream(vec![
        encode_connect_frame(&json!({
            "sdkMessage": {"type":"assistant", "message":{"runId":"run-1","content":[{"text":"hello"}]}}
        }))
        .unwrap(),
        encode_connect_frame(&json!({"result":{"status":"finished"}})).unwrap(),
        encode_connect_frame(&json!({"done":{}})).unwrap(),
    ]);
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(
        client,
        CursorProviderConfig {
            bridge_bearer_token: "token".into(),
            model: Some("composer-2".into()),
            ..CursorProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    let delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(delta.kind, EventKind::ContentDelta);
    assert_eq!(delta.payload["delta"], "hello");
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "completed");
}

#[tokio::test]
async fn cursor_provider_rejects_overlapping_turns_and_approvals() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_stream(vec![]);
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(
        client,
        CursorProviderConfig {
            bridge_bearer_token: "token".into(),
            ..Default::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("thread", "one"))
        .await
        .unwrap();
    assert!(provider
        .send_turn(TurnInput::text("thread", "two"))
        .await
        .is_err());
    assert!(!provider.capabilities().approvals);
}

#[tokio::test]
async fn cursor_provider_rejects_unrepresentable_session_policy() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    let mut input = SessionStartInput::new("thread");
    input.runtime_mode = RuntimeMode::Auto;
    assert!(provider.start_session(input).await.is_err());
}

#[tokio::test]
async fn cursor_provider_sets_native_approval_policy() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let create = &mock.calls()[2].1;
    assert_eq!(
        create["options"]["local"]["sandboxOptions"]["enabled"],
        true
    );
    assert_eq!(create["options"]["local"]["autoReview"], true);
}

#[tokio::test]
async fn cursor_provider_maps_connect_result_envelope_and_native_run_reference() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_stream(vec![
        encode_connect_frame(&json!({
            "interactionUpdate": {
                "type": "text-delta",
                "update": {"delta": "hello", "contentIndex": 0}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!({
            "result": {
                "runId": "run-42",
                "status": "RUN_LIFECYCLE_STATUS_ERROR",
                "errorCode": "UPSTREAM_ERROR",
                "result": {"errorMessage": "boom", "stopReason": "error"}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!({"done":{"runId":"run-42"}})).unwrap(),
    ]);
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(
        delta
            .raw
            .as_ref()
            .and_then(|raw| raw.message_type.as_deref()),
        Some("text-delta")
    );
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.payload["state"], "failed");
    assert_eq!(completed.payload["errorMessage"], "boom");
    assert_eq!(completed.payload["errorCode"], "UPSTREAM_ERROR");
    assert_eq!(
        completed
            .provider_refs
            .as_ref()
            .and_then(|refs| refs.provider_turn_id.as_deref()),
        Some("run-42")
    );
}

#[tokio::test]
async fn cursor_provider_maps_native_delta_kinds_and_deduplicates_final_assistant() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_stream(vec![
        encode_connect_frame(&json!({
            "interactionUpdate": {
                "type": "thinking-delta",
                "update": {"delta": "think", "itemId": "item-1"}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!({
            "interactionUpdate": {
                "type": "shell-output-delta",
                "update": {"output": "stdout", "itemId": "item-2"}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!({
            "interactionUpdate": {
                "type": "token-delta",
                "update": {"delta": "token", "itemId": "item-3"}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!({
            "interactionUpdate": {
                "type": "text-delta",
                "update": {"delta": "hello", "itemId": "item-4"}
            },
            "sdkMessage": {
                "type": "assistant",
                "message": {"content": [{"text": "hello"}]}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!({"result":{"status":"finished"}})).unwrap(),
    ]);
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let thinking = provider.next_event().await.unwrap().unwrap();
    assert_eq!(thinking.payload["streamKind"], "reasoning_text");
    assert_eq!(
        thinking
            .raw
            .as_ref()
            .and_then(|raw| raw.message_type.as_deref()),
        Some("thinking-delta")
    );
    let shell = provider.next_event().await.unwrap().unwrap();
    assert_eq!(shell.payload["streamKind"], "command_output");
    assert_eq!(shell.payload["delta"], "stdout");
    let token = provider.next_event().await.unwrap().unwrap();
    assert_eq!(token.payload["streamKind"], "unknown");
    let text = provider.next_event().await.unwrap().unwrap();
    assert_eq!(text.payload["delta"], "hello");
    assert_eq!(
        text.raw
            .as_ref()
            .and_then(|raw| raw.message_type.as_deref()),
        Some("text-delta")
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnCompleted
    );
    assert!(provider.next_event().await.unwrap().is_none());
}

#[tokio::test]
async fn cursor_provider_recovers_stream_failure_with_wait_live_run() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_unary(Ok(json!({
        "result": {
            "runId": "run-1",
            "status": "RUN_LIFECYCLE_STATUS_FINISHED",
            "result": "recovered"
        }
    })));
    mock.push_stream(vec![
        encode_connect_frame(&json!({
            "sdkMessage": {
                "type": "status",
                "message": {"runId": "run-1", "status": "running"}
            }
        }))
        .unwrap(),
        encode_connect_frame(&json!("malformed-envelope")).unwrap(),
    ]);
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let status = provider.next_event().await.unwrap().unwrap();
    assert_eq!(status.kind, EventKind::ThreadStateChanged);
    let recovered = provider.next_event().await.unwrap().unwrap();
    assert_eq!(recovered.kind, EventKind::ContentDelta);
    assert_eq!(recovered.payload["delta"], "recovered");
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(terminal.payload["state"], "completed");
    assert!(provider.next_event().await.unwrap().is_none());
    assert_eq!(mock.calls()[4].0, "sdk.v1.SdkAgentService/WaitLiveRun");
}

#[tokio::test]
async fn cursor_provider_loads_local_images_and_rejects_remote_urls() {
    let path = std::env::temp_dir().join(format!(
        "cursor-provider-image-{}-{}.png",
        std::process::id(),
        1
    ));
    std::fs::write(&path, [0_u8, 1, 2]).unwrap();
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_stream(vec![]);
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let mut remote = TurnInput::text("thread", "");
    remote.attachments = vec![Attachment::Image {
        url: "https://example.invalid/image.png".into(),
    }];
    assert!(provider.send_turn(remote).await.is_err());
    let mut input = TurnInput::text("thread", "");
    input.attachments = vec![Attachment::LocalImage {
        path: PathBuf::from(&path),
    }];
    provider.send_turn(input).await.unwrap();
    let request = &mock.calls()[3].1;
    assert_eq!(request["message"]["images"][0]["data"]["data"], "AAEC");
    assert_eq!(
        request["message"]["images"][0]["data"]["mimeType"],
        "image/png"
    );
    let _ = std::fs::remove_file(path);
}

#[tokio::test]
async fn cursor_provider_emits_session_exit_after_close() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider.close().await.unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::SessionExited
    );
}

#[tokio::test]
async fn cursor_provider_interrupt_cancels_then_waits_for_native_terminal_state() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_unary(Ok(json!({})));
    mock.push_unary(Ok(json!({"status":"RUN_LIFECYCLE_STATUS_CANCELLED"})));
    mock.push_stream(vec![encode_connect_frame(&json!({
        "sdkMessage": {
            "type": "status",
            "message": {"runId": "run-1", "status": "running"}
        }
    }))
    .unwrap()]);
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .interrupt(alera_provider_protocol::InterruptInput {
            thread_id: "thread".into(),
            turn_id: None,
        })
        .await
        .unwrap();
    let calls = mock.calls();
    assert_eq!(calls[4].0, "sdk.v1.SdkAgentService/CancelRun");
    assert_eq!(calls[5].0, "sdk.v1.SdkAgentService/WaitLiveRun");
}

#[tokio::test]
async fn cursor_provider_emits_result_text_when_no_delta_was_streamed() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_unary(Ok(
        json!({"bridgeVersion":"1.0.35","protocolVersion":"sdk.v1"}),
    ));
    mock.push_unary(Ok(json!({"agentId":"agent-1"})));
    mock.push_stream(vec![encode_connect_frame(&json!({
        "result": {
            "runId": "run-2",
            "status": "FINISHED",
            "result": {"result": "final answer"}
        }
    }))
    .unwrap()]);
    let client = CursorClient::with_transport(mock, "token").unwrap();
    let mut provider = CursorProvider::new(client, CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let final_delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(final_delta.kind, EventKind::ContentDelta);
    assert_eq!(final_delta.payload["delta"], "final answer");
    assert_eq!(
        final_delta
            .raw
            .as_ref()
            .and_then(|raw| raw.message_type.as_deref()),
        Some("result")
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnCompleted
    );
}
