use super::actor_test_harness::{local_client, mobile_client, test_actor};
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn deferred_mobile_status_rechecks_presence_after_overlay_detection() {
    let dir = tempfile::tempdir().unwrap();
    let (control_tx, mut control_rx) = tokio::sync::mpsc::unbounded_channel();
    let (terminal_tx, _terminal_rx) = tokio::sync::mpsc::channel(1);
    let desktop = local_client(ClientHandle::new(control_tx, terminal_tx));
    let (handle, _mobile_rx) = ClientHandle::test_terminal_channels();
    let mut mobile = mobile_client(handle, "phone-1");
    mobile.relay_client_id = Some("cloud-phone-1".into());
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, desktop), (2, mobile)]),
        HashMap::new(),
    )
    .await;
    let snapshot = actor
        .mobile_access_snapshot(&json!({"includeNetworkStatus": false}))
        .await
        .unwrap();
    assert_eq!(
        snapshot["connectedRelayDevices"].as_array().unwrap().len(),
        1
    );
    actor.clients.remove(&2);
    actor.finish_mobile_network_snapshot(1, 7, snapshot);
    let response = control_rx.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 7);
    assert_eq!(response["payload"]["connectedRelayDevices"], json!([]));
    assert!(actor
        .try_start_deferred_request(99, 8, "mobile.status.get", &json!({}))
        .await
        .is_err());
}
use serde_json::json;
use std::collections::HashMap;

#[tokio::test]
async fn relay_presence_is_live_and_never_grants_local_pairing_access() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut client = mobile_client(handle, "phone-1");
    client.relay_client_id = Some("cloud-phone-1".into());
    let mut actor = test_actor(&dir, HashMap::from([(2, client)]), HashMap::new()).await;
    let status = actor
        .mobile_access_snapshot(&json!({"includeNetworkStatus": false}))
        .await
        .unwrap();
    assert_eq!(status["connectedRelayDevices"][0]["id"], "cloud-phone-1");
    assert_eq!(status["devices"], json!([]));
    assert!(status.get("tailscale").is_none());
    assert!(status.get("netbird").is_none());
    assert!(actor
        .runtime_store
        .list_mobile_devices(true)
        .await
        .unwrap()
        .is_empty());
    actor.dispose_client(2).await;
    let status = actor
        .mobile_access_snapshot(&json!({"includeNetworkStatus": false}))
        .await
        .unwrap();
    assert_eq!(status["connectedRelayDevices"], json!([]));
}

#[tokio::test]
async fn relay_presence_excludes_peers_that_have_not_authenticated() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut client = mobile_client(handle, "phone-1");
    client.relay_client_id = Some("cloud-phone-1".into());
    client.authenticated = false;
    let actor = test_actor(&dir, HashMap::from([(2, client)]), HashMap::new()).await;
    let status = actor
        .mobile_access_snapshot(&json!({"includeNetworkStatus": false}))
        .await
        .unwrap();
    assert_eq!(status["connectedRelayDevices"], json!([]));
}
