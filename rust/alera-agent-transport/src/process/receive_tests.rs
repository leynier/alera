use std::future::Future;
use std::sync::{Arc, Mutex};
use std::task::Poll;
use std::time::Duration;

use tokio::sync::mpsc;

use super::{JsonLineProcess, StderrTail, STDOUT_QUEUE_CAPACITY};
use crate::{JsonTransport, TransportError};

#[tokio::test]
async fn cancelled_failure_cleanup_retains_the_original_receive_error() {
    let (sender, messages) = mpsc::channel(STDOUT_QUEUE_CAPACITY + 1);
    sender
        .send(Err(TransportError::OutputQueueFull {
            capacity: STDOUT_QUEUE_CAPACITY,
        }))
        .await
        .unwrap();
    let mut transport = JsonLineProcess {
        child: None,
        stdin: None,
        pending_frame: None,
        pending_error: None,
        messages,
        stdout_task: None,
        stderr_task: Some(tokio::spawn(std::future::pending())),
        stderr_tail: Arc::new(Mutex::new(StderrTail::default())),
        closed: false,
        exit_success: None,
        exit_code: None,
        max_frame_bytes: 1024,
        shutdown_timeout: Duration::from_secs(1),
    };

    {
        let mut receive = std::pin::pin!(transport.recv());
        std::future::poll_fn(|context| {
            assert!(receive.as_mut().poll(context).is_pending());
            Poll::Ready(())
        })
        .await;
    }
    assert!(transport.closed);
    assert!(matches!(
        transport.send(serde_json::json!({})).await,
        Err(TransportError::Closed)
    ));

    transport.stderr_task.as_ref().unwrap().abort();
    assert!(matches!(
        transport.recv().await,
        Err(TransportError::OutputQueueFull {
            capacity: STDOUT_QUEUE_CAPACITY
        })
    ));
    assert!(transport.stderr_task.is_none());
    assert!(transport.pending_error.is_none());
    assert!(matches!(
        transport.recv().await,
        Err(TransportError::Closed)
    ));
}
