#[tokio::test]
async fn terminal_reclaim_treats_a_missing_session_as_already_released() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([(
            1,
            crate::terminal_host::server::actor_test_harness::local_client(handle),
        )]),
        std::collections::HashMap::new(),
    )
    .await;

    actor
        .handle_line(
            1,
            serde_json::json!({
                "id": 1,
                "type": "terminal.reclaim",
                "payload": {"sessionId": "stale-session"},
            })
            .to_string(),
        )
        .await;

    let response = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 1);
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["restored"], false);
}

#[tokio::test]
async fn terminal_pulse_status_is_local_only() {
    let dir = tempfile::tempdir().unwrap();
    let (mobile_handle, mut mobile_receiver) =
        crate::terminal_host::client::ClientHandle::test_channels();
    let (local_handle, mut local_receiver) =
        crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([
            (
                1,
                crate::terminal_host::server::actor_test_harness::mobile_client(
                    mobile_handle,
                    "phone-1",
                ),
            ),
            (
                2,
                crate::terminal_host::server::actor_test_harness::local_client(local_handle),
            ),
        ]),
        std::collections::HashMap::new(),
    )
    .await;
    let request = |id| {
        serde_json::json!({
            "id": id,
            "type": "terminal.pulse.status",
            "payload": {"sessionId": "missing-session"},
        })
        .to_string()
    };

    actor.handle_line(1, request(1)).await;
    actor.handle_line(2, request(2)).await;

    let mobile = mobile_receiver.recv().await.unwrap().as_json().unwrap();
    let local = local_receiver.recv().await.unwrap().as_json().unwrap();
    assert!(mobile["error"]
        .as_str()
        .unwrap()
        .contains("Mobile clients cannot call"));
    assert!(local["error"]
        .as_str()
        .unwrap()
        .contains("Terminal session is not attached"));
}
