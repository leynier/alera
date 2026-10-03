use std::collections::HashMap;
use std::time::Duration;

use super::super::actor_test_harness::{local_client, test_actor};
use super::super::OUTPUT_BATCH_DELAY;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::session::{PtyEvent, Session};

async fn attached_actor(
    dir: &tempfile::TempDir,
) -> (
    super::ServerActor,
    tokio::sync::mpsc::Receiver<crate::terminal_host::client::ClientFrame>,
) {
    let (handle, terminal_rx) = ClientHandle::test_terminal_channels();
    let mut session = Session::driver_test_stub("echo", 80, 24);
    session.attach(1);
    let actor = test_actor(
        dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::from([("echo".to_string(), session)]),
    )
    .await;
    (actor, terminal_rx)
}

#[tokio::test]
async fn first_output_after_a_quiet_stream_is_delivered_without_the_batch_delay() {
    let dir = tempfile::tempdir().unwrap();
    let (mut actor, mut terminal_rx) = attached_actor(&dir).await;
    tokio::time::sleep(OUTPUT_BATCH_DELAY + Duration::from_millis(2)).await;

    actor
        .handle_pty_event("echo".to_string(), PtyEvent::Output(b"a".to_vec()))
        .await;

    terminal_rx
        .try_recv()
        .expect("a keystroke echo must not wait for the coalescing timer");
}

#[tokio::test]
async fn output_that_keeps_streaming_is_still_coalesced() {
    let dir = tempfile::tempdir().unwrap();
    let (mut actor, mut terminal_rx) = attached_actor(&dir).await;
    tokio::time::sleep(OUTPUT_BATCH_DELAY + Duration::from_millis(2)).await;

    actor
        .handle_pty_event("echo".to_string(), PtyEvent::Output(b"a".to_vec()))
        .await;
    terminal_rx.try_recv().unwrap();
    actor
        .handle_pty_event("echo".to_string(), PtyEvent::Output(b"b".to_vec()))
        .await;
    actor
        .handle_pty_event("echo".to_string(), PtyEvent::Output(b"c".to_vec()))
        .await;

    assert!(
        terminal_rx.try_recv().is_err(),
        "a busy stream must wait for the batch timer"
    );
    // The leading-edge flush advanced the batch generation once.
    let generation = 1;
    actor.handle_output_batch_tick("echo".to_string(), generation);
    terminal_rx
        .try_recv()
        .expect("the timer delivers the coalesced chunks");
    assert!(terminal_rx.try_recv().is_err());
}
