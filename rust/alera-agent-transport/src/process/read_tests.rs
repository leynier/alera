use std::time::Duration;

use serde_json::json;
use tokio::sync::mpsc;

use super::{drain_stdout, FrameResult, STDOUT_QUEUE_CAPACITY};
use crate::TransportError;

fn burst() -> Vec<u8> {
    (0..100)
        .flat_map(|n| format!("{{\"n\":{n}}}\n").into_bytes())
        .collect()
}

#[tokio::test]
async fn a_waiting_receiver_consumes_a_buffered_burst_without_overflow() {
    let (sender, mut receiver) = mpsc::channel::<FrameResult>(STDOUT_QUEUE_CAPACITY + 1);
    let bytes = burst();
    let receive = async {
        for n in 0..100 {
            assert_eq!(
                receiver.recv().await.unwrap().unwrap(),
                Some(json!({"n": n}))
            );
        }
        assert_eq!(receiver.recv().await.unwrap().unwrap(), None);
        assert!(receiver.recv().await.is_none());
    };

    tokio::time::timeout(Duration::from_secs(1), async {
        tokio::join!(
            receive,
            drain_stdout(bytes.as_slice(), sender, 1024, Duration::from_secs(1))
        );
    })
    .await
    .unwrap();
}

#[tokio::test(start_paused = true)]
async fn a_stalled_receiver_gets_an_explicit_error_in_the_reserved_slot() {
    let (sender, mut receiver) = mpsc::channel::<FrameResult>(STDOUT_QUEUE_CAPACITY + 1);
    let bytes = burst();
    let timeout = Duration::from_millis(50);
    let started = tokio::time::Instant::now();

    drain_stdout(bytes.as_slice(), sender, 1024, timeout).await;

    assert_eq!(started.elapsed(), timeout);
    assert_eq!(receiver.len(), STDOUT_QUEUE_CAPACITY + 1);
    for n in 0..STDOUT_QUEUE_CAPACITY {
        assert_eq!(
            receiver.recv().await.unwrap().unwrap(),
            Some(json!({"n": n}))
        );
    }
    assert!(matches!(
        receiver.recv().await,
        Some(Err(TransportError::OutputQueueFull {
            capacity: STDOUT_QUEUE_CAPACITY
        }))
    ));
    assert!(receiver.recv().await.is_none());
}
