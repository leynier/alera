use super::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::client::ClientHandle;
use serde_json::json;
use std::collections::HashMap;

#[tokio::test]
async fn retired_policy_requests_cannot_read_or_mutate_permission_tables() {
    let runtime = tempfile::tempdir().unwrap();
    let (handle, _events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &runtime,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    for payload in [
        json!({}),
        json!({"kind":"agent","profileId":"missing","policy":{"mayExecute":true}}),
        json!({"kind":"project","projectId":"missing","policy":{"localApproved":true}}),
    ] {
        let error = actor
            .handle_automation_request(1, "automation.policy", &payload)
            .await
            .unwrap_err();
        assert!(error.to_string().contains("policies were removed"));
    }
    assert!(actor
        .runtime_store
        .list_automation_agent_policies()
        .await
        .unwrap()
        .is_empty());
    assert!(actor
        .runtime_store
        .list_automation_project_policies()
        .await
        .unwrap()
        .is_empty());
}
