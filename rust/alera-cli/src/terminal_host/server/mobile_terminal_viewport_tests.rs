//! What a mobile attach does to the live PTY's size.
//!
//! A phone claims the viewport driver seat when it attaches, and the host
//! applies whatever size it claims to the running session. A phone that has
//! not laid its terminal out yet has no size to state, and the host must leave
//! the session alone rather than substitute 80x24.

use std::collections::HashMap;

use serde_json::json;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::session::Session;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::ServerActor;

async fn actor_with_mobile_session(dir: &tempfile::TempDir) -> ServerActor {
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut session = Session::driver_test_stub("s1", 213, 54);
    session.attach(2);
    test_actor(
        dir,
        HashMap::from([(2, mobile_client(handle, "phone-1"))]),
        HashMap::from([("s1".to_string(), session)]),
    )
    .await
}

#[tokio::test]
async fn an_attach_without_a_measured_viewport_leaves_the_session_size_alone() {
    // Defaulting to 80x24 here resized the live session twice per tab open:
    // once to a size nobody was looking at, and again to the real one a layout
    // later. A full-screen agent redrew itself into the scrollback at both.
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_mobile_session(&dir).await;
    let mut attachment = json!({});

    actor.claim_mobile_terminal_viewport(2, "s1", &json!({ "tabId": "t1" }), &mut attachment);

    assert_eq!(actor.sessions.get("s1").unwrap().current_dims, (213, 54));
    // The seat is still claimed; only the resize is withheld.
    assert_eq!(attachment["driver"]["kind"], "mobile");
}

#[tokio::test]
async fn an_attach_that_states_a_viewport_resizes_the_session() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_mobile_session(&dir).await;
    let mut attachment = json!({});

    actor.claim_mobile_terminal_viewport(
        2,
        "s1",
        &json!({ "tabId": "t1", "cols": 45, "rows": 30 }),
        &mut attachment,
    );

    assert_eq!(actor.sessions.get("s1").unwrap().current_dims, (45, 30));
}

#[tokio::test]
async fn a_half_stated_viewport_is_not_a_viewport() {
    // Neither half alone describes a terminal, and taking the stated one with a
    // default for the other is the same wrong resize under a different name.
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_mobile_session(&dir).await;
    let mut attachment = json!({});

    actor.claim_mobile_terminal_viewport(
        2,
        "s1",
        &json!({ "tabId": "t1", "cols": 45 }),
        &mut attachment,
    );

    assert_eq!(actor.sessions.get("s1").unwrap().current_dims, (213, 54));
}

#[tokio::test]
async fn a_desktop_client_never_claims_the_mobile_seat() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut session = Session::driver_test_stub("s1", 213, 54);
    session.attach(2);
    let mut actor = test_actor(
        &dir,
        HashMap::from([(2, local_client(handle))]),
        HashMap::from([("s1".to_string(), session)]),
    )
    .await;
    let mut attachment = json!({});

    actor.claim_mobile_terminal_viewport(
        2,
        "s1",
        &json!({ "tabId": "t1", "cols": 45, "rows": 30 }),
        &mut attachment,
    );

    assert_eq!(actor.sessions.get("s1").unwrap().current_dims, (213, 54));
}
