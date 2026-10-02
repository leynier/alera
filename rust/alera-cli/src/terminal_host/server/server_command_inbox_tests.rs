use super::*;

fn client_line(id: u64) -> ServerCommand {
    ServerCommand::ClientLine {
        id,
        line: "x".to_string(),
    }
}

fn pty_output(session_id: &str) -> ServerCommand {
    ServerCommand::Pty {
        session_id: session_id.to_string(),
        event: PtyEvent::Output(vec![1]),
        handled: std::sync::mpsc::sync_channel(0).0,
    }
}

#[test]
fn work_admission_is_bounded_by_count_and_bytes() {
    let (inbox, _receiver) = ServerInbox::channel();
    for _ in 0..SERVER_COMMAND_WORK_CAPACITY {
        inbox.send(pty_output("session")).expect("work admission");
    }
    assert_eq!(inbox.queued_counts().0, SERVER_COMMAND_WORK_CAPACITY);
    assert_eq!(
        inbox.send(pty_output("session")),
        Err(ServerInboxSendError::Full)
    );
    inbox.close();
    assert_eq!(
        inbox.send(client_line(1)),
        Err(ServerInboxSendError::Closed)
    );
}

#[test]
fn socket_commands_keep_control_admission_when_pty_work_is_full() {
    let (inbox, _receiver) = ServerInbox::channel();
    for _ in 0..SERVER_COMMAND_WORK_CAPACITY {
        inbox.send(pty_output("session")).expect("work admission");
    }
    inbox.pause_pty_session("session");
    inbox.send(client_line(9)).expect("socket admission");
    assert_eq!(inbox.queued_counts().2, 1);
}

#[test]
fn oversized_lines_are_rejected_before_admission() {
    let (inbox, _receiver) = ServerInbox::channel();
    assert_eq!(
        inbox.send(ServerCommand::ClientLine {
            id: 1,
            line: "x".repeat(SERVER_COMMAND_MAX_LINE_BYTES + 1),
        }),
        Err(ServerInboxSendError::Oversized)
    );
    assert_eq!(inbox.queued_counts(), (0, 0, 0));
}

#[test]
fn maximum_dictation_payload_uses_work_budget_and_preserves_control_capacity() {
    use base64::Engine;
    let (inbox, _receiver) = ServerInbox::channel();
    let audio = base64::engine::general_purpose::STANDARD.encode(vec![0; 25 * 1024 * 1024]);
    let line = serde_json::json!({"id": 1, "type": "aiDictation.mobileTranscribe", "payload": {"audioBase64": audio}}).to_string();
    assert!(line.len() > SERVER_COMMAND_CONTROL_BYTES);
    inbox
        .send(ServerCommand::ClientLine {
            id: 1,
            line: line.clone(),
        })
        .expect("valid audio must be admitted");
    assert_eq!(inbox.queued_counts().0, 1);
    assert_eq!(inbox.queued_counts().2, 0);
    assert_eq!(
        inbox.send(ServerCommand::ClientLine { id: 2, line }),
        Err(ServerInboxSendError::Full)
    );
    inbox
        .send(client_line(3))
        .expect("small controls must still be admitted");
    assert_eq!(inbox.queued_counts().2, 1);
}

#[test]
fn large_control_payloads_use_the_byte_budget() {
    let (inbox, _receiver) = ServerInbox::channel();
    assert_eq!(
        inbox.send(ServerCommand::CodexMessage {
            message: serde_json::json!("x".repeat(SERVER_COMMAND_CONTROL_BYTES)),
        }),
        Err(ServerInboxSendError::Oversized)
    );
}

#[tokio::test]
async fn oversized_completion_reports_an_error_instead_of_losing_the_request() {
    let (inbox, mut receiver) = ServerInbox::channel();
    inbox
        .send_wait(ServerCommand::HostToolFinished {
            client_id: 7,
            request_id: 42,
            result: Ok(
                serde_json::json!({"stdout": "\0".repeat(SERVER_COMMAND_CONTROL_BYTES / 4)}),
            ),
            operation_id: None,
            skill: None,
        })
        .await
        .expect("oversized completion must deliver a bounded failure");
    match receiver.recv().await.unwrap() {
        ServerCommand::HostToolFinished {
            client_id: 7,
            request_id: 42,
            result: Err(error),
            ..
        } => {
            assert!(error.to_string().contains("command inbox budget"));
        }
        _ => panic!("request identity and explicit failure must be retained"),
    }
    assert_eq!(inbox.queued_counts(), (0, 0, 0));
}

#[test]
fn oversized_work_is_rejected_before_a_blocking_wait() {
    let (inbox, _receiver) = ServerInbox::channel();
    let result = inbox.send_blocking(ServerCommand::Pty {
        session_id: "session".to_string(),
        event: PtyEvent::Output(vec![0; SERVER_COMMAND_WORK_BYTES + 1]),
        handled: std::sync::mpsc::sync_channel(0).0,
    });
    assert_eq!(result, Err(ServerInboxSendError::Oversized));
}

#[test]
fn first_shutdown_request_wins_over_later_restart() {
    let (inbox, _receiver) = ServerInbox::channel();
    inbox.send(ServerCommand::RequestedShutdown).unwrap();
    inbox.send(ServerCommand::RequestedRestart).unwrap();
    let command = inbox.control_wake.take().expect("control wake");
    assert!(matches!(command, ServerCommand::RequestedShutdown));
    assert!(inbox.control_wake.take().is_none());
}

#[test]
fn first_restart_request_wins_over_later_shutdown() {
    let (inbox, _receiver) = ServerInbox::channel();
    inbox.send(ServerCommand::RequestedRestart).unwrap();
    inbox.send(ServerCommand::RequestedShutdown).unwrap();
    let command = inbox.control_wake.take().expect("control wake");
    assert!(matches!(command, ServerCommand::RequestedRestart));
    assert!(inbox.control_wake.take().is_none());
}

#[test]
fn closing_a_full_mailbox_wakes_a_blocked_pty_sender() {
    let (inbox, _receiver) = ServerInbox::channel();
    for _ in 0..SERVER_COMMAND_WORK_CAPACITY {
        inbox.send(pty_output("session")).expect("work admission");
    }
    let wait_started = std::sync::Arc::new(std::sync::Barrier::new(2));
    inbox.admission.set_blocking_wait_hook(wait_started.clone());
    let blocked = inbox.clone();
    let join = std::thread::spawn(move || blocked.send_blocking(pty_output("session")));
    wait_started.wait();
    inbox.close();
    assert_eq!(
        join.join().expect("blocked sender joins"),
        Err(ServerInboxSendError::Closed)
    );
}

#[tokio::test]
async fn required_admission_waits_for_a_slot_without_dropping_control() {
    let (inbox, mut receiver) = ServerInbox::channel();
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control admission");
    }
    let wait_started = inbox.admission.async_waiter().notified();
    let pending = {
        let inbox = inbox.clone();
        tokio::spawn(async move {
            inbox
                .send_wait(ServerCommand::ClientDisconnected { id: 999 })
                .await
        })
    };
    wait_started.await;
    assert!(!pending.is_finished());
    let first = inbox.recv(&mut receiver).await;
    assert!(matches!(
        first,
        Some(ServerCommand::ClientDisconnected { id: 0 })
    ));
    pending
        .await
        .expect("required sender joins")
        .expect("admitted");
}

#[tokio::test]
async fn dropping_the_receiver_closes_async_admission() {
    let (inbox, receiver) = ServerInbox::channel();
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control admission");
    }
    let wait_started = inbox.admission.async_waiter().notified();
    let pending = {
        let inbox = inbox.clone();
        tokio::spawn(async move {
            inbox
                .send_wait(ServerCommand::ClientDisconnected { id: 999 })
                .await
        })
    };
    wait_started.await;
    drop(receiver);
    assert_eq!(
        pending.await.expect("async sender joins"),
        Err(ServerInboxSendError::Closed)
    );
}

#[test]
fn paused_pty_session_resumes_without_blocking_socket_commands() {
    let (inbox, mut receiver) = ServerInbox::channel();
    inbox.pause_pty_session("session");
    let wait_started = std::sync::Arc::new(std::sync::Barrier::new(2));
    inbox.admission.set_blocking_wait_hook(wait_started.clone());
    let blocked = inbox.clone();
    let join = std::thread::spawn(move || blocked.send_blocking(pty_output("session")));
    wait_started.wait();
    inbox
        .send(client_line(9))
        .expect("socket work remains admitted");
    assert!(matches!(
        receiver.try_recv(),
        Ok(ServerCommand::ClientLine { id: 9, .. })
    ));
    inbox.resume_pty_session("session");
    assert_eq!(join.join().expect("pty sender joins"), Ok(()));
    assert!(matches!(
        receiver.try_recv(),
        Ok(ServerCommand::Pty { session_id, .. }) if session_id == "session"
    ));
}

#[test]
fn closing_a_paused_pty_session_wakes_blocking_sender() {
    let (inbox, _receiver) = ServerInbox::channel();
    inbox.pause_pty_session("session");
    let wait_started = std::sync::Arc::new(std::sync::Barrier::new(2));
    inbox.admission.set_blocking_wait_hook(wait_started.clone());
    let blocked = inbox.clone();
    let join = std::thread::spawn(move || blocked.send_blocking(pty_output("session")));
    wait_started.wait();
    inbox.close();
    assert_eq!(
        join.join().expect("paused sender joins"),
        Err(ServerInboxSendError::Closed)
    );
}

#[tokio::test]
async fn oversized_work_is_rejected_before_async_wait() {
    let (inbox, _receiver) = ServerInbox::channel();
    let result = tokio::time::timeout(
        std::time::Duration::from_millis(100),
        inbox.send_wait(ServerCommand::ClientLine {
            id: 1,
            line: "x".repeat(SERVER_COMMAND_MAX_LINE_BYTES + 1),
        }),
    )
    .await
    .expect("oversized command must not wait");
    assert_eq!(result, Err(ServerInboxSendError::Oversized));
}

#[tokio::test]
async fn paused_pty_session_resumes_async_sender_without_blocking_control() {
    let (inbox, mut receiver) = ServerInbox::channel();
    inbox.pause_pty_session("session");
    let wait_started = inbox.admission.async_waiter().notified();
    let pending = {
        let inbox = inbox.clone();
        tokio::spawn(async move { inbox.send_wait(pty_output("session")).await })
    };
    wait_started.await;
    inbox
        .send(ServerCommand::ClientDisconnected { id: 7 })
        .expect("control remains admitted");
    assert!(matches!(
        receiver.recv().await,
        Some(ServerCommand::ClientDisconnected { id: 7 })
    ));
    inbox.resume_pty_session("session");
    assert_eq!(pending.await.expect("async pty sender joins"), Ok(()));
    assert!(matches!(
        receiver.recv().await,
        Some(ServerCommand::Pty { session_id, .. }) if session_id == "session"
    ));
}

#[tokio::test]
async fn accepted_work_drains_before_first_control_request() {
    for (first, second, shutdown_expected) in [
        (
            ServerCommand::RequestedShutdown,
            ServerCommand::RequestedRestart,
            true,
        ),
        (
            ServerCommand::RequestedRestart,
            ServerCommand::RequestedShutdown,
            false,
        ),
    ] {
        let (inbox, mut receiver) = ServerInbox::channel();
        inbox.send(client_line(1)).expect("first queued command");
        inbox.send(client_line(2)).expect("second queued command");
        inbox.send(first).expect("first control wake");
        inbox.send(second).expect("duplicate control wake");
        assert_eq!(
            inbox.send(client_line(3)),
            Err(ServerInboxSendError::Closed)
        );
        assert!(matches!(
            receiver.recv().await,
            Some(ServerCommand::ClientLine { id: 1, .. })
        ));
        assert!(matches!(
            receiver.recv().await,
            Some(ServerCommand::ClientLine { id: 2, .. })
        ));
        let control = receiver.recv().await;
        assert!(if shutdown_expected {
            matches!(control, Some(ServerCommand::RequestedShutdown))
        } else {
            matches!(control, Some(ServerCommand::RequestedRestart))
        });
    }
}

#[tokio::test]
async fn reserved_relay_disconnect_survives_full_control_admission() {
    let (inbox, mut receiver) = ServerInbox::channel();
    let disconnect = inbox.reserve_client_disconnect(999).await.unwrap();
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY - 1 {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .unwrap();
    }
    assert_eq!(
        inbox.send(ServerCommand::ClientDisconnected { id: 1000 }),
        Err(ServerInboxSendError::Full)
    );
    drop(disconnect);
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY - 1 {
        assert!(
            matches!(receiver.try_recv().unwrap(), ServerCommand::ClientDisconnected { id: actual } if actual == id as u64)
        );
    }
    assert!(matches!(
        receiver.try_recv().unwrap(),
        ServerCommand::ClientDisconnected { id: 999 }
    ));
    assert_eq!(inbox.queued_counts(), (0, 0, 0));
}
