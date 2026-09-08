use std::collections::HashMap;

use serde_json::json;

use super::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn templates_upsert_fills_missing_updated_at() {
    let runtime_dir = tempfile::tempdir().unwrap();
    let (handle, _events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &runtime_dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;

    let saved = actor
        .handle_automation_request(
            1,
            "automation.templates",
            &json!({
                "template": {
                    "id": "t",
                    "name": "T",
                    "promptTemplate": "ping",
                    "createdAt": "2026-09-08T00:00:00Z",
                    "createdBy": {"kind": "localCli"}
                }
            }),
        )
        .await
        .unwrap();

    assert_eq!(saved["id"], "t");
    assert_eq!(saved["name"], "T");
    assert_eq!(saved["promptTemplate"], "ping");
    assert!(
        saved["updatedAt"]
            .as_str()
            .is_some_and(|value| !value.is_empty()),
        "host must fill updatedAt on save, got {saved}"
    );

    let listed = actor
        .handle_automation_request(1, "automation.templates", &json!({}))
        .await
        .unwrap();
    assert_eq!(listed["items"][0]["id"], "t");
    assert!(listed["items"][0]["updatedAt"].as_str().is_some());
}
