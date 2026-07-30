use std::collections::HashMap;

use crate::terminal_host::client::ClientHandle;

use super::actor_test_harness::{mobile_client, test_actor};

#[tokio::test]
async fn authoritative_subscription_sync_updates_lifecycle_and_waiter() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut out_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(7, mobile_client(handle, "phone"))]),
        HashMap::new(),
    )
    .await;
    actor.account_push.push_enabled = true;
    actor.account_push.subscription_sync_in_flight = true;
    actor.account_push.subscription_sync_waiters.push((7, 42));
    actor.account_push.cloud_jobs = 1;

    actor.handle_push_subscription_sync_finished(Ok(3));

    assert_eq!(actor.account_push.active_subscriptions, 3);
    assert!(!actor.account_push.subscription_sync_in_flight);
    assert_eq!(actor.account_push.cloud_jobs, 0);
    assert!(actor.account_push.subscription_sync_waiters.is_empty());
    let response = out_rx
        .try_recv()
        .expect("subscription sync response")
        .as_json()
        .expect("JSON response");
    assert_eq!(response["id"], 42);
    assert_eq!(response["payload"]["activeSubscriptions"], 3);
}

#[tokio::test]
async fn disabled_runtime_does_not_retain_authoritative_subscriptions() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.account_push.push_enabled = false;
    actor.account_push.subscription_sync_in_flight = true;
    actor.account_push.cloud_jobs = 1;

    actor.handle_push_subscription_sync_finished(Ok(2));

    assert_eq!(actor.account_push.active_subscriptions, 0);
    assert!(!actor.account_push.subscription_sync_in_flight);
    assert_eq!(actor.account_push.cloud_jobs, 0);
}
