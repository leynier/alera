use std::io::Write;
use std::sync::mpsc::TrySendError;

use super::*;

struct BlockingWriter {
    started_tx: std::sync::mpsc::Sender<()>,
    release_rx: std::sync::mpsc::Receiver<()>,
}

impl Write for BlockingWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.started_tx.send(()).unwrap();
        self.release_rx.recv().unwrap();
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct FailingWriter;

impl Write for FailingWriter {
    fn write(&mut self, _bytes: &[u8]) -> std::io::Result<usize> {
        Err(std::io::Error::other("writer failed"))
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct RecordingWriter {
    bytes: Arc<std::sync::Mutex<Vec<u8>>>,
}

impl Write for RecordingWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.bytes.lock().unwrap().extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn test_session() -> Session {
    Session {
        instance_id: next_session_instance_id(),
        id: "session-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        tab_id: "tab-1".to_string(),
        working_directory: "/repo".to_string(),
        clients: HashSet::new(),
        driver: SessionDriver::Idle,
        desktop_dims: None,
        current_dims: (80, 24),
        output_paused_clients: HashSet::new(),
        output_resync_pending_clients: HashSet::new(),
        buffer: ScrollbackBuffer::new(1024, &[]),
        running: true,
        exit_code: None,
        ended_at: None,
        shell_pid: None,
        master: None,
        input_tx: None,
        killer: None,
        terminated: false,
        checkpoint_gen: 0,
        checkpoint_armed: false,
        output_batch: Vec::new(),
        output_batch_gen: 0,
        output_batch_armed: false,
        durable_output_batch: Vec::new(),
        durable_output_batch_gen: 0,
        durable_output_batch_armed: false,
        durable_output_batch_sequence: 0,
        output_stream_bytes: 0,
        title_tracker: TerminalTitleTracker::default(),
    }
}

#[test]
fn output_batch_coalesces_until_flush() {
    let mut session = test_session();
    assert_eq!(session.append_output(b"ab"), (Some(0), Some(0), None));
    assert_eq!(session.append_output(b"cd"), (None, None, None));
    assert!(session.output_batch_due(0));
    let batch = session.flush_output_batch().expect("batch");
    // Raw bytes, not an encoded payload: whether these go out as a binary
    // frame or as base64 inside JSON is the writer's decision, per client.
    assert_eq!(batch.data, b"abcd");
    assert_eq!(session.output_batch_len(), 0);
    assert!(!session.output_batch_due(0));
    let durable = session.flush_durable_output_batch().expect("durable batch");
    assert_eq!(durable.data, b"abcd");
    assert_eq!(durable.sequence, 0);
}

#[test]
fn output_backpressure_pauses_only_the_slow_client_until_resumed() {
    let mut session = test_session();
    session.attach(1);
    session.attach(2);

    assert!(session.mark_output_backpressured(1));
    assert!(!session.mark_output_backpressured(1));
    assert_eq!(session.output_clients(), vec![2]);
    assert!(session.output_resync_pending(1));

    session.mark_output_resync_sent(1);
    assert!(!session.output_resync_pending(1));
    assert_eq!(session.output_clients(), vec![2]);

    session.set_output_paused(1, false);
    let mut clients = session.output_clients();
    clients.sort_unstable();
    assert_eq!(clients, vec![1, 2]);
}

#[test]
fn output_batch_empty_flush_disarms_timer() {
    let mut session = test_session();
    assert_eq!(session.append_output(b"a"), (Some(0), Some(0), None));
    assert!(session.flush_output_batch().is_some());
    assert!(session.flush_output_batch().is_none());
    assert_eq!(session.append_output(b"b"), (Some(1), None, None));
    assert!(!session.output_batch_due(0));
    assert!(session.output_batch_due(1));
    assert!(session.flush_output_batch().is_some());
    let durable = session.flush_durable_output_batch().expect("durable batch");
    assert_eq!(durable.data, b"ab");
    assert_eq!(durable.sequence, 0);
}

#[test]
fn output_stream_range_remains_monotonic_when_scrollback_trims() {
    let mut session = test_session();
    session.set_max_bytes(4);
    session.append_output(b"abcd");
    assert_eq!(session.output_stream_range(), (0, 4));

    session.append_output(b"ef");
    assert_eq!(session.buffer.to_bytes(), b"cdef");
    assert_eq!(session.output_stream_range(), (2, 6));
}

#[test]
fn remint_keeps_the_persisted_absolute_stream_position() {
    assert_eq!(resumed_output_stream_bytes(10, 4), 10);
    assert_eq!(resumed_output_stream_bytes(0, 4), 4);
}

#[test]
fn session_reports_title_changes_from_pty_output() {
    let mut session = test_session();

    let (_, _, title_change) = session.append_output(b"\x1b]2;Review Tests\x07");

    assert_eq!(title_change.as_deref(), Some("Review Tests"));
    assert_eq!(session.runtime_title(), Some("Review Tests"));
}

#[tokio::test]
async fn restored_output_stream_range_keeps_absolute_cursor() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store
        .upsert(TerminalHostCheckpoint {
            session_id: "restored".to_string(),
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            working_directory: "/repo".to_string(),
            running: false,
            exit_code: Some(0),
            ended_at: Some(Utc::now()),
            output_stream_bytes: 10,
            updated_at: Utc::now(),
            buffer: Vec::new(),
        })
        .await
        .unwrap();
    store.append_output("restored", 0, b"tail").await.unwrap();

    let session = Session::restore_exited(
        "restored".to_string(),
        "workspace-1".to_string(),
        "tab-1".to_string(),
        &store,
        4,
    )
    .await
    .unwrap();

    assert_eq!(session.output_stream_range(), (6, 10));
}

#[tokio::test]
async fn restored_session_recovers_the_latest_title_from_scrollback() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    store
        .upsert(TerminalHostCheckpoint {
            session_id: "restored-title".to_string(),
            workspace_id: "workspace-1".to_string(),
            tab_id: "tab-1".to_string(),
            working_directory: "/repo".to_string(),
            running: false,
            exit_code: Some(0),
            ended_at: Some(Utc::now()),
            output_stream_bytes: 0,
            updated_at: Utc::now(),
            buffer: Vec::new(),
        })
        .await
        .unwrap();
    store
        .append_output("restored-title", 0, b"\x1b]0;Restored Task\x07")
        .await
        .unwrap();

    let session = Session::restore_exited(
        "restored-title".to_string(),
        "workspace-1".to_string(),
        "tab-1".to_string(),
        &store,
        1024,
    )
    .await
    .unwrap();

    assert_eq!(session.runtime_title(), Some("Restored Task"));
}

#[test]
fn exiting_clears_the_shell_pid() {
    let mut session = test_session();
    session.shell_pid = Some(4242);
    assert_eq!(session.shell_pid(), Some(4242));

    session.handle_exit(0);

    // The OS recycles PIDs, so keeping the old value would let the resource
    // sampler attribute an unrelated process to this session.
    assert_eq!(session.shell_pid(), None);
}

#[tokio::test]
async fn terminating_clears_the_shell_pid() {
    let dir = tempfile::tempdir().unwrap();
    let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
    let mut session = test_session();
    session.shell_pid = Some(4242);

    session.terminate(true, &store).await;

    assert_eq!(session.shell_pid(), None);
}

#[test]
fn a_session_without_a_pty_has_no_shell_pid() {
    // Stubs and restored checkpoints have no process behind them, so there is
    // nothing to sample.
    let session = Session::driver_test_stub("stub", 80, 24);
    assert_eq!(session.shell_pid(), None);
}

#[test]
fn blocked_writer_applies_local_backpressure_without_blocking_sender() {
    let (input_tx, input_rx) = sync_channel(1);
    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let (event_tx, event_rx) = std::sync::mpsc::channel();
    let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(move |event| {
        event_tx.send(event).unwrap();
    });
    spawn_writer(
        Box::new(BlockingWriter {
            started_tx,
            release_rx,
        }),
        input_rx,
        on_event,
    );
    input_tx
        .try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 10,
            },
            bytes: b"first".to_vec(),
            deferred: None,
        })
        .unwrap();
    started_rx
        .recv_timeout(std::time::Duration::from_secs(1))
        .unwrap();
    input_tx
        .try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 11,
            },
            bytes: b"second".to_vec(),
            deferred: None,
        })
        .unwrap();
    assert!(matches!(
        input_tx.try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 12,
            },
            bytes: b"third".to_vec(),
            deferred: None,
        }),
        Err(TrySendError::Full(_))
    ));
    release_tx.send(()).unwrap();
    assert!(matches!(
        event_rx
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap(),
        PtyEvent::InputWritten {
            completion: PtyWriteCompletion::ClientRequest { request_id: 10, .. },
            error: None,
        }
    ));
    started_rx
        .recv_timeout(std::time::Duration::from_secs(1))
        .unwrap();
    release_tx.send(()).unwrap();
    assert!(matches!(
        event_rx
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap(),
        PtyEvent::InputWritten {
            completion: PtyWriteCompletion::ClientRequest { request_id: 11, .. },
            error: None,
        }
    ));
}

#[test]
fn deferred_write_keeps_its_suffix_ahead_of_queued_input() {
    let (input_tx, input_rx) = sync_channel(2);
    let recorded = Arc::new(std::sync::Mutex::new(Vec::new()));
    let (event_tx, event_rx) = std::sync::mpsc::channel();
    let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(move |event| {
        event_tx.send(event).unwrap();
    });
    spawn_writer(
        Box::new(RecordingWriter {
            bytes: Arc::clone(&recorded),
        }),
        input_rx,
        on_event,
    );
    input_tx
        .try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 10,
            },
            bytes: b"A".to_vec(),
            deferred: Some(PtyDeferredWrite {
                delay: std::time::Duration::from_millis(10),
                bytes: b"\r".to_vec(),
            }),
        })
        .unwrap();
    input_tx
        .try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 2,
                request_id: 11,
            },
            bytes: b"B".to_vec(),
            deferred: None,
        })
        .unwrap();

    assert!(matches!(
        event_rx
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap(),
        PtyEvent::InputWritten {
            completion: PtyWriteCompletion::ClientRequest { request_id: 10, .. },
            error: None,
        }
    ));
    assert!(recorded.lock().unwrap().starts_with(b"A\r"));
    assert!(matches!(
        event_rx
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap(),
        PtyEvent::InputWritten {
            completion: PtyWriteCompletion::ClientRequest { request_id: 11, .. },
            error: None,
        }
    ));
    assert_eq!(*recorded.lock().unwrap(), b"A\rB");
}

#[test]
fn failed_writer_completes_every_queued_request_with_the_same_error() {
    let (input_tx, input_rx) = sync_channel(3);
    for request_id in 10..13 {
        input_tx
            .try_send(PtyWrite {
                completion: PtyWriteCompletion::ClientRequest {
                    client_id: 1,
                    request_id,
                },
                bytes: vec![request_id as u8],
                deferred: None,
            })
            .unwrap();
    }
    let (event_tx, event_rx) = std::sync::mpsc::channel();
    let on_event: Arc<dyn Fn(PtyEvent) + Send + Sync> = Arc::new(move |event| {
        event_tx.send(event).unwrap();
    });
    spawn_writer(Box::new(FailingWriter), input_rx, on_event);
    for request_id in 10..13 {
        assert!(matches!(
            event_rx
                .recv_timeout(std::time::Duration::from_secs(1))
                .unwrap(),
            PtyEvent::InputWritten {
                completion: PtyWriteCompletion::ClientRequest {
                    request_id: actual,
                    ..
                },
                error: Some(ref message),
            } if actual == request_id && message == "writer failed"
        ));
    }
}

#[test]
fn exited_session_rejects_input_instead_of_leaving_request_pending() {
    let mut session = test_session();
    session.running = false;
    let error = session
        .queue_write(
            PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 10,
            },
            b"input",
        )
        .expect_err("exited session should reject input");
    assert!(error.wire_message().contains("not running"));
}
