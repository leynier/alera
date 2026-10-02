use super::*;

#[test]
fn failed_durable_batches_are_restored_in_sequence_order() {
    let mut session = Session::driver_test_stub("history", 80, 24);
    session.restore_durable_output_batch(DurableOutputBatch {
        sequence: 3,
        data: b"third".to_vec(),
    });
    session.restore_durable_output_batch(DurableOutputBatch {
        sequence: 2,
        data: b"second".to_vec(),
    });
    session.restore_durable_output_batch(DurableOutputBatch {
        sequence: 4,
        data: b"fourth".to_vec(),
    });

    assert_eq!(session.durable_output_failure_count(), 3);
    assert_eq!(session.flush_durable_output_batch().unwrap().sequence, 2);
    assert_eq!(session.flush_durable_output_batch().unwrap().sequence, 3);
    assert_eq!(session.flush_durable_output_batch().unwrap().sequence, 4);
    assert!(session.flush_durable_output_batch().is_none());
}

#[test]
fn pty_ack_stays_held_until_durable_history_is_unblocked() {
    let mut session = Session::driver_test_stub("history", 80, 24);
    let (ack_tx, ack_rx) = std::sync::mpsc::sync_channel(1);
    session.restore_durable_output_batch(DurableOutputBatch {
        sequence: 0,
        data: b"blocked".to_vec(),
    });
    session.hold_pty_ack(ack_tx);
    assert!(session.take_pty_ack_if_unblocked(64).is_none());

    assert_eq!(session.flush_durable_output_batch().unwrap().sequence, 0);
    let ack = session
        .take_pty_ack_if_unblocked(64)
        .expect("recovery releases the paused PTY");
    ack.send(()).expect("ack receiver remains available");
    ack_rx.recv().expect("paused reader resumes");
}

#[test]
fn durable_flush_splits_a_chunk_at_the_fixed_batch_limit() {
    let mut session = Session::driver_test_stub("history", 80, 24);
    let first = vec![b'a'; DURABLE_OUTPUT_BATCH_MAX_BYTES - 1];
    let second = vec![b'b'; DURABLE_OUTPUT_BATCH_MAX_BYTES];
    session.append_output(&first);
    session.append_output(&second);

    let first_batch = session
        .flush_durable_output_batch()
        .expect("first bounded batch");
    assert_eq!(first_batch.data.len(), DURABLE_OUTPUT_BATCH_MAX_BYTES);
    assert_eq!(first_batch.data[DURABLE_OUTPUT_BATCH_MAX_BYTES - 1], b'b');
    let second_batch = session
        .flush_durable_output_batch()
        .expect("ordered tail batch");
    assert_eq!(second_batch.data.len(), DURABLE_OUTPUT_BATCH_MAX_BYTES - 1);
    assert!(second_batch.data.iter().all(|byte| *byte == b'b'));
    assert!(session.flush_durable_output_batch().is_none());
}

#[tokio::test]
async fn checkpoint_poll_does_not_wait_for_a_hung_storage_job() {
    let mut session = Session::driver_test_stub("history", 80, 24);
    let job = tokio::spawn(std::future::pending::<Result<(), String>>());
    assert!(session.begin_checkpoint_job(job));
    assert!(session.checkpoint_output_blocked());

    let result = tokio::time::timeout(
        std::time::Duration::from_millis(20),
        session.poll_checkpoint_job(),
    )
    .await
    .expect("checkpoint polling must not await storage");
    assert!(result.is_none());
    assert!(session.checkpoint_job_active());
}
