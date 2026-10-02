use super::*;

#[tokio::test]
async fn deferred_completion_survives_shutdown_admission_closure() {
    let (inbox, mut receiver) = ServerInbox::channel();
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control admission");
    }
    inbox.send(ServerCommand::RequestedShutdown).unwrap();
    inbox
        .send_wait(ServerCommand::AiAssistFinished {
            client_id: 7,
            request_id: 42,
            result: Ok(serde_json::json!({"ok": true})),
        })
        .await
        .expect("an already-started job must retain its completion");
    assert_eq!(inbox.completion_counts().0, 1);
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        assert!(matches!(
            receiver.recv().await,
            Some(ServerCommand::ClientDisconnected { id: actual }) if actual == id as u64
        ));
    }
    assert!(matches!(
        receiver.recv().await,
        Some(ServerCommand::AiAssistFinished {
            client_id: 7,
            request_id: 42,
            ..
        })
    ));
    assert_eq!(inbox.completion_counts(), (0, 0));
    assert!(matches!(
        receiver.recv().await,
        Some(ServerCommand::RequestedShutdown)
    ));
}

#[tokio::test]
async fn full_completion_lane_unblocks_when_receiver_is_dropped() {
    let (inbox, receiver) = ServerInbox::channel();
    for request_id in 0..SERVER_COMMAND_COMPLETION_CAPACITY as i64 {
        inbox
            .send(ServerCommand::AiAssistFinished {
                client_id: 1,
                request_id,
                result: Ok(serde_json::json!({"ok": true})),
            })
            .expect("completion admission");
    }
    let pending = {
        let inbox = inbox.clone();
        tokio::spawn(async move {
            inbox
                .send_wait(ServerCommand::AiAssistFinished {
                    client_id: 1,
                    request_id: 999,
                    result: Ok(serde_json::json!({"ok": true})),
                })
                .await
        })
    };
    inbox.admission.async_waiter().notified().await;
    drop(receiver);
    assert_eq!(
        tokio::time::timeout(std::time::Duration::from_secs(1), pending)
            .await
            .expect("completion sender must observe receiver closure")
            .expect("completion sender joins"),
        Err(ServerInboxSendError::Closed)
    );
}

#[test]
fn full_completion_lane_unblocks_blocking_producer_when_receiver_is_dropped() {
    let (inbox, receiver) = ServerInbox::channel();
    for request_id in 0..SERVER_COMMAND_COMPLETION_CAPACITY as i64 {
        inbox
            .send(ServerCommand::AiAssistFinished {
                client_id: 1,
                request_id,
                result: Ok(serde_json::json!({"ok": true})),
            })
            .expect("completion admission");
    }
    let wait_started = std::sync::Arc::new(std::sync::Barrier::new(2));
    inbox.admission.set_blocking_wait_hook(wait_started.clone());
    let blocked = inbox.clone();
    let join = std::thread::spawn(move || {
        blocked.send_blocking(ServerCommand::AiAssistFinished {
            client_id: 1,
            request_id: 999,
            result: Ok(serde_json::json!({"ok": true})),
        })
    });
    wait_started.wait();
    drop(receiver);
    assert_eq!(
        join.join().expect("completion sender joins"),
        Err(ServerInboxSendError::Closed)
    );
}

#[test]
fn realtime_audio_counts_pcm_bytes_against_work_budget() {
    let (inbox, _receiver) = ServerInbox::channel();
    inbox
        .send(ServerCommand::VoiceRealtime {
            generation: 1,
            event: super::super::voice_realtime::VoiceRealtimeEvent::Audio {
                pcm: vec![0; SERVER_COMMAND_WORK_BYTES / 2],
                sample_rate: 24_000,
                utterance_id: None,
            },
        })
        .expect("first audio frame fits");
    assert_eq!(inbox.queued_counts().0, 1);
    assert_eq!(
        inbox.send(ServerCommand::VoiceRealtime {
            generation: 1,
            event: super::super::voice_realtime::VoiceRealtimeEvent::Audio {
                pcm: vec![0; SERVER_COMMAND_WORK_BYTES / 2],
                sample_rate: 24_000,
                utterance_id: None,
            },
        }),
        Err(ServerInboxSendError::Full)
    );
}

#[test]
fn voice_turn_result_uses_completion_byte_budget() {
    let (inbox, _receiver) = ServerInbox::channel();
    let result = |request_id| ServerCommand::VoiceTurnFinished {
        client_id: 7,
        request_id,
        job_id: request_id as u64,
        session_generation: 1,
        from_realtime: false,
        cancel_home: None,
        result: Ok("x".repeat(SERVER_COMMAND_COMPLETION_BYTES / 2)),
    };
    inbox.send(result(1)).expect("first result fits");
    assert_eq!(inbox.completion_counts().0, 1);
    assert_eq!(inbox.send(result(2)), Err(ServerInboxSendError::Full));
}

#[test]
fn voice_synthesize_result_uses_completion_byte_budget() {
    let (inbox, _receiver) = ServerInbox::channel();
    let result = |request_id| ServerCommand::VoiceSynthesizeFinished {
        client_id: 7,
        request_id,
        job_id: request_id as u64,
        session_generation: 1,
        result: Ok(serde_json::json!({
            "audio": "x".repeat(SERVER_COMMAND_COMPLETION_BYTES / 2),
        })),
    };
    inbox.send(result(1)).expect("first result fits");
    assert_eq!(inbox.completion_counts().0, 1);
    assert_eq!(inbox.send(result(2)), Err(ServerInboxSendError::Full));
}

#[tokio::test]
async fn oversized_voice_metadata_becomes_an_explicit_error_event() {
    let (inbox, mut receiver) = ServerInbox::channel();
    inbox
        .send(ServerCommand::VoiceRealtime {
            generation: 1,
            event: super::super::voice_realtime::VoiceRealtimeEvent::UserTranscript {
                text: "x".repeat(SERVER_COMMAND_COMPLETION_BYTES + 1),
                is_final: true,
                item_id: Some("item-1".to_string()),
            },
        })
        .expect("oversized transcript is represented by a bounded error event");
    inbox
        .send(ServerCommand::VoiceRealtime {
            generation: 1,
            event: super::super::voice_realtime::VoiceRealtimeEvent::InputCommitted {
                item_id: "x".repeat(SERVER_COMMAND_COMPLETION_BYTES + 1),
            },
        })
        .expect("oversized commit is represented by a bounded error event");

    for _ in 0..2 {
        match receiver.recv().await {
            Some(ServerCommand::VoiceRealtime {
                event: super::super::voice_realtime::VoiceRealtimeEvent::Error { message },
                ..
            }) => assert_eq!(
                message,
                "Realtime event exceeds the 16 MiB command inbox budget"
            ),
            _ => panic!("unexpected voice event"),
        }
    }
}
