use serde_json::{json, Value};

async fn mobile_settings_update(payload: Value) -> (tempfile::TempDir, Value, bool) {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([(
            1,
            crate::terminal_host::server::actor_test_harness::mobile_client(handle, "phone"),
        )]),
        std::collections::HashMap::new(),
    )
    .await;
    actor
        .handle_line(
            1,
            json!({"id": 1, "type": "mobile.runtimeSettings.update", "payload": payload})
                .to_string(),
        )
        .await;
    let mut response = None;
    while let Some(frame) = receiver.recv().await {
        let value = frame.as_json().unwrap();
        if value.get("id") == Some(&json!(1)) {
            response = Some(value);
            break;
        }
    }
    let stored = actor
        .runtime_store
        .delete_agent_sessions_on_workspace_removal()
        .await
        .unwrap();
    (
        dir,
        response.expect("mobile.runtimeSettings.update response"),
        stored,
    )
}

#[tokio::test]
async fn mobile_runtime_settings_update_persists_agent_session_deletion() {
    let (_dir, response, stored) =
        mobile_settings_update(json!({"deleteAgentSessionsOnWorkspaceRemoval": true})).await;
    assert_eq!(response["ok"], true);
    assert_eq!(
        response["payload"]["deleteAgentSessionsOnWorkspaceRemoval"],
        true
    );
    assert!(stored);
}

#[tokio::test]
async fn mobile_runtime_settings_update_rejects_a_non_boolean_agent_session_deletion() {
    let (_dir, response, stored) =
        mobile_settings_update(json!({"deleteAgentSessionsOnWorkspaceRemoval": "yes"})).await;
    assert_eq!(response["ok"], false);
    assert!(!stored);
}
