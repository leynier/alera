use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::session::Session;
use std::collections::HashMap;

#[tokio::test]
async fn close_waits_for_history_and_duplicate_requests_do_not_multiply_retries() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::from([(
            "closing".to_string(),
            Session::driver_test_stub("closing", 80, 24),
        )]),
    )
    .await;
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox.clone();
    let (release, wait) = tokio::sync::oneshot::channel();
    actor
        .sessions
        .get_mut("closing")
        .unwrap()
        .begin_checkpoint_job(tokio::spawn(async move {
            wait.await.map_err(|error| error.to_string())
        }));
    let line =
        serde_json::json!({"id": 7, "type": "terminate", "payload": {"sessionId": "closing"}})
            .to_string();
    for _ in 0..100 {
        actor.handle_line(1, line.clone()).await;
    }
    assert_eq!(actor.pending_history_requests.len(), 1);
    assert!(actor.sessions["closing"].history_barrier_held());
    while let Ok(frame) = responses.try_recv() {
        assert_ne!(frame.as_json().unwrap()["id"], 7);
    }
    release.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while actor.sessions.contains_key("closing") {
            let command = inbox.recv(&mut commands).await.unwrap();
            actor.handle(command).await;
        }
    })
    .await
    .expect("close must complete after the durable checkpoint finishes");
    let mut replies = Vec::new();
    while let Ok(frame) = responses.try_recv() {
        let value = frame.as_json().unwrap();
        if value["id"] == 7 {
            replies.push(value);
        }
    }
    assert_eq!(replies.len(), 1);
    assert_eq!(replies[0]["ok"], true);
    assert!(actor.pending_history_requests.is_empty());
}

#[tokio::test]
async fn disconnect_releases_a_pending_history_barrier_without_closing_the_session() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([(
            "kept".to_string(),
            Session::driver_test_stub("kept", 80, 24),
        )]),
    )
    .await;
    actor.hold_history_barrier("kept");
    assert!(actor.defer_history_request(9, 1, "kept".to_string(), "{}".to_string()));
    actor
        .handle_history_request_retry(9, 1, "{}".to_string())
        .await;
    assert!(actor.pending_history_requests.is_empty());
    assert!(!actor.sessions["kept"].history_barrier_held());
}
