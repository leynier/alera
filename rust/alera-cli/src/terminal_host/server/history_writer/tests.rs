use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::anyhow;

use super::*;

#[derive(Clone, Default)]
struct FakeSink {
    writes: RecordedWrites,
    fail: bool,
    delay: Option<Duration>,
}

type RecordedWrites = Arc<Mutex<Vec<(i64, Vec<u8>)>>>;

#[derive(Clone, Default)]
struct HungSink;

impl HistoryOutputSink for HungSink {
    fn append_output<'a>(
        &'a self,
        _session_id: &'a str,
        _sequence: i64,
        _data: &'a [u8],
    ) -> AppendFuture<'a> {
        Box::pin(std::future::pending())
    }
}

impl HistoryOutputSink for FakeSink {
    fn append_output<'a>(
        &'a self,
        _session_id: &'a str,
        sequence: i64,
        data: &'a [u8],
    ) -> AppendFuture<'a> {
        let writes = Arc::clone(&self.writes);
        let fail = self.fail;
        let delay = self.delay;
        Box::pin(async move {
            if let Some(delay) = delay {
                tokio::time::sleep(delay).await;
            }
            if fail {
                return Err(anyhow!("injected history failure"));
            }
            writes
                .lock()
                .expect("fake history lock")
                .push((sequence, data.to_vec()));
            Ok(())
        })
    }
}

#[tokio::test]
async fn queued_writes_are_serial_and_slow_storage_stays_bounded() {
    let sink = FakeSink {
        delay: Some(Duration::from_millis(20)),
        ..Default::default()
    };
    let writes = Arc::clone(&sink.writes);
    let (inbox, _receiver) = ServerInbox::channel();
    let mut writer = OrderedHistoryWriter::new(sink, "session".to_string(), inbox);
    let started = tokio::time::Instant::now();
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 0,
                data: b"first".to_vec(),
            },
        )
        .expect("first enqueue");
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 1,
                data: b"second".to_vec(),
            },
        )
        .expect("second enqueue");
    assert!(writer.pending.len() <= HISTORY_WRITER_MAX_PENDING);
    let failures = writer.drain().await;
    assert!(failures.is_empty());
    assert!(started.elapsed() >= Duration::from_millis(40));
    assert_eq!(
        writes.lock().expect("fake history lock").as_slice(),
        &[(0, b"first".to_vec()), (1, b"second".to_vec())]
    );
}

#[tokio::test]
async fn failed_storage_returns_every_accepted_batch_for_recovery() {
    let sink = FakeSink {
        fail: true,
        ..Default::default()
    };
    let (inbox, _receiver) = ServerInbox::channel();
    let mut writer = OrderedHistoryWriter::new(sink, "session".to_string(), inbox);
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 0,
                data: b"retain me".to_vec(),
            },
        )
        .expect("first enqueue");
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 1,
                data: b"retain this too".to_vec(),
            },
        )
        .expect("second enqueue");
    let failures = writer.drain().await;
    assert_eq!(failures.len(), 2);
    assert_eq!(failures[0].batch.data, b"retain me");
    assert_eq!(failures[1].batch.data, b"retain this too");
}

#[tokio::test]
async fn full_queue_returns_the_new_batch_without_losing_older_failures() {
    let sink = FakeSink {
        fail: true,
        delay: Some(Duration::from_millis(20)),
        ..Default::default()
    };
    let (inbox, _receiver) = ServerInbox::channel();
    let mut writer = OrderedHistoryWriter::new(sink, "session".to_string(), inbox);
    let mut returned_batch = None;
    for sequence in 0..=(HISTORY_WRITER_MAX_PENDING as i64 + 1) {
        match writer.try_enqueue(
            "session",
            DurableOutputBatch {
                sequence,
                data: vec![sequence as u8],
            },
        ) {
            Ok(()) => {}
            Err(failure) => {
                assert_eq!(failure.error.to_string(), "history writer queue is full");
                returned_batch = Some(failure.batch);
                break;
            }
        }
    }
    let returned_batch = returned_batch.expect("the bounded writer must return a full-queue batch");
    let failures = writer.drain().await;
    assert_eq!(failures.len(), returned_batch.sequence as usize);
    assert_eq!(failures.first().unwrap().batch.sequence, 0);
    assert_eq!(
        failures.last().unwrap().batch.sequence + 1,
        returned_batch.sequence
    );
}

#[tokio::test]
async fn drain_finishes_when_readiness_wake_is_under_control_pressure() {
    let (inbox, mut receiver) = ServerInbox::channel();
    for id in 0..super::super::server_command_inbox::SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control admission");
    }
    let mut writer = OrderedHistoryWriter::new(FakeSink::default(), "session".to_string(), inbox);
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 0,
                data: b"accepted".to_vec(),
            },
        )
        .expect("enqueue");

    let failures = tokio::time::timeout(Duration::from_secs(1), writer.drain())
        .await
        .expect("drain must not wait for a full readiness lane");
    assert!(failures.is_empty());
    assert!(receiver.try_recv().is_ok());
}

#[tokio::test]
async fn polling_a_hung_storage_future_returns_without_waiting() {
    let (inbox, _receiver) = ServerInbox::channel();
    let mut writer = OrderedHistoryWriter::new(HungSink, "session".to_string(), inbox);
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 0,
                data: b"retain while storage is hung".to_vec(),
            },
        )
        .expect("enqueue");

    let polled = tokio::time::timeout(Duration::from_millis(20), async { writer.poll_completed() })
        .await
        .expect("completion polling must not await storage");
    assert!(polled.is_empty());
    assert_eq!(writer.pending_len(), 1);
}

#[tokio::test]
async fn sequence_gap_is_rejected_before_storage() {
    let sink = FakeSink::default();
    let (inbox, _receiver) = ServerInbox::channel();
    let mut writer = OrderedHistoryWriter::new(sink, "session".to_string(), inbox);
    writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 4,
                data: b"first".to_vec(),
            },
        )
        .expect("first sequence may start at any persisted value");
    let failure = writer
        .try_enqueue(
            "session",
            DurableOutputBatch {
                sequence: 6,
                data: b"gap".to_vec(),
            },
        )
        .expect_err("sequence gap");
    assert_eq!(failure.batch.sequence, 6);
    assert!(writer.drain().await.is_empty());
}
