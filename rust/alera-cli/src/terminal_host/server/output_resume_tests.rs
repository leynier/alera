//! What a resuming client is served: the gap it missed, or a full snapshot
//! when the host can no longer place it in the output stream.

use std::collections::HashMap;

use crate::terminal_host::client::{ClientFrame, ClientHandle, CLIENT_TERMINAL_OUT_QUEUE_CAPACITY};
use crate::terminal_host::protocol::decode_bytes;
use crate::terminal_host::session::Session;

use super::actor_test_harness::{local_client, test_actor};
use super::ServerActor;

fn output(data: &[u8]) -> ClientFrame {
    ClientFrame::Output {
        session_id: "s1".to_string(),
        data: data.to_vec(),
    }
}

async fn actor_with_client(
    dir: &tempfile::TempDir,
    handle: ClientHandle,
    max_bytes: usize,
) -> ServerActor {
    let mut session = Session::driver_test_stub("s1", 120, 40);
    session.set_max_bytes(max_bytes);
    session.attach(2);
    test_actor(
        dir,
        HashMap::from([(2, local_client(handle))]),
        HashMap::from([("s1".to_string(), session)]),
    )
    .await
}

#[tokio::test]
async fn resume_serves_only_the_bytes_the_client_missed() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut terminal_rx) = ClientHandle::test_terminal_channels();
    let mut actor = actor_with_client(&dir, handle, 1024).await;

    actor
        .sessions
        .get_mut("s1")
        .unwrap()
        .append_output(b"hello");
    assert!(actor.send_terminal_output("s1", 2, output(b"hello")));
    actor
        .sessions
        .get_mut("s1")
        .unwrap()
        .set_output_paused(2, true);
    actor
        .sessions
        .get_mut("s1")
        .unwrap()
        .append_output(b" world");

    let payload = actor.resume_output_for_client("s1", 2);

    assert_eq!(payload["delta"], true);
    assert_eq!(payload["resumed"], true);
    assert_eq!(payload.get("snapshotBase64"), None);
    let _ = terminal_rx.try_recv().expect("the delivered hello");
    let missed = terminal_rx.try_recv().expect("the resume delta");
    assert!(matches!(missed, ClientFrame::Output { ref data, .. } if data == b" world"));
    let session = &actor.sessions["s1"];
    assert_eq!(session.delivered_output_cursor(2), Some(11));
    assert_eq!(session.output_clients(), vec![2]);
}

#[tokio::test]
async fn resume_falls_back_to_a_snapshot_once_the_ring_dropped_the_gap() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut terminal_rx) = ClientHandle::test_terminal_channels();
    let mut actor = actor_with_client(&dir, handle, 4).await;

    // Nothing was delivered, so the client sits at cursor 0 while the ring has
    // already trimmed its way past it.
    actor
        .sessions
        .get_mut("s1")
        .unwrap()
        .append_output(b"abcdefgh");

    let payload = actor.resume_output_for_client("s1", 2);

    assert_eq!(payload["delta"], false);
    assert_eq!(payload["resetInteractionModes"], true);
    assert_eq!(
        decode_bytes(payload.get("snapshotBase64")).unwrap(),
        b"efgh"
    );
    assert!(terminal_rx.try_recv().is_err());
    assert_eq!(
        actor.sessions["s1"].delivered_output_cursor(2),
        Some(8),
        "a snapshot puts the client at the head of the stream",
    );
}

#[tokio::test]
async fn a_dropped_output_frame_does_not_advance_the_delivery_cursor() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut actor = actor_with_client(&dir, handle, 1024).await;

    for _ in 0..CLIENT_TERMINAL_OUT_QUEUE_CAPACITY {
        actor.sessions.get_mut("s1").unwrap().append_output(b"ab");
        assert!(actor.send_terminal_output("s1", 2, output(b"ab")));
    }
    let filled = CLIENT_TERMINAL_OUT_QUEUE_CAPACITY as u64 * 2;
    assert_eq!(
        actor.sessions["s1"].delivered_output_cursor(2),
        Some(filled)
    );

    actor.sessions.get_mut("s1").unwrap().append_output(b"cd");
    assert!(!actor.send_terminal_output("s1", 2, output(b"cd")));

    assert_eq!(
        actor.sessions["s1"].delivered_output_cursor(2),
        Some(filled),
        "the dropped frame is exactly what the next resume has to resend",
    );
    let payload = actor.resume_output_for_client("s1", 2);
    assert_eq!(payload["delta"], true);
    assert_eq!(
        payload["resumed"], false,
        "the queue is still full, so the client stays paused for another try",
    );
}

#[tokio::test]
async fn a_snapshot_resend_is_capped_to_the_configured_restore_budget() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut actor = actor_with_client(&dir, handle, 1024).await;
    actor.config.restore_snapshot_bytes = 8;

    // No delivery cursor for client 9, so it takes the snapshot path.
    actor
        .sessions
        .get_mut("s1")
        .unwrap()
        .append_output(b"one\ntwo\nthree\nfour\n");

    let payload = actor.resume_output_for_client("s1", 9);

    assert_eq!(payload["delta"], false);
    assert_eq!(
        decode_bytes(payload.get("snapshotBase64")).unwrap(),
        b"four\n",
        "the tail is cut at a line break inside the budget",
    );
}

#[tokio::test]
async fn detaching_forgets_the_delivery_cursor() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut actor = actor_with_client(&dir, handle, 1024).await;

    let session = actor.sessions.get_mut("s1").unwrap();
    assert_eq!(session.delivered_output_cursor(2), Some(0));
    session.detach(2);

    assert_eq!(session.delivered_output_cursor(2), None);
}
