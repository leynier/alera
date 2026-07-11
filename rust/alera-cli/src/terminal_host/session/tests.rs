use std::io::Write;

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

fn test_session() -> Session {
    Session {
        instance_id: next_session_instance_id(),
        id: "session-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        tab_id: "tab-1".to_string(),
        working_directory: "/repo".to_string(),
        clients: HashSet::new(),
        output_paused_clients: HashSet::new(),
        buffer: ScrollbackBuffer::new(1024, &[]),
        running: true,
        exit_code: None,
        ended_at: None,
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
    }
}

#[test]
fn output_batch_coalesces_until_flush() {
    let mut session = test_session();
    assert_eq!(session.append_output(b"ab"), (Some(0), Some(0)));
    assert_eq!(session.append_output(b"cd"), (None, None));
    assert!(session.output_batch_due(0));
    let batch = session.flush_output_batch().expect("batch");
    assert_eq!(batch.payload["sessionId"], "session-1");
    assert_eq!(
        batch.payload["dataBase64"],
        serde_json::Value::String(encode_bytes(b"abcd"))
    );
    assert_eq!(session.output_batch_len(), 0);
    assert!(!session.output_batch_due(0));
    let durable = session.flush_durable_output_batch().expect("durable batch");
    assert_eq!(durable.data, b"abcd");
    assert_eq!(durable.sequence, 0);
}

#[test]
fn output_batch_empty_flush_disarms_timer() {
    let mut session = test_session();
    assert_eq!(session.append_output(b"a"), (Some(0), Some(0)));
    assert!(session.flush_output_batch().is_some());
    assert!(session.flush_output_batch().is_none());
    assert_eq!(session.append_output(b"b"), (Some(1), None));
    assert!(!session.output_batch_due(0));
    assert!(session.output_batch_due(1));
    assert!(session.flush_output_batch().is_some());
    let durable = session.flush_durable_output_batch().expect("durable batch");
    assert_eq!(durable.data, b"ab");
    assert_eq!(durable.sequence, 0);
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
        })
        .unwrap();
    assert!(matches!(
        input_tx.try_send(PtyWrite {
            completion: PtyWriteCompletion::ClientRequest {
                client_id: 1,
                request_id: 12,
            },
            bytes: b"third".to_vec(),
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
