use std::collections::HashMap;

use serde_json::json;

use crate::terminal_host::client::ClientHandle;

use super::super::actor_test_harness::{local_client, test_actor};

#[tokio::test]
async fn routes_authenticated_gpui_workspace_file_requests() {
    let runtime = tempfile::tempdir().unwrap();
    let workspace = tempfile::tempdir().unwrap();
    std::fs::write(workspace.path().join("note.txt"), "hello").unwrap();
    let (handle, _terminal_rx) = ClientHandle::test_terminal_channels();
    let mut actor = test_actor(
        &runtime,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;

    let result = actor
        .handle_gpui_workspace_request(
            1,
            "workspaceFiles.list",
            &json!({
                "workspacePath": workspace.path(),
                "relativePath": "",
                "hideIgnored": false,
            }),
        )
        .await
        .unwrap()
        .unwrap();

    assert_eq!(result.as_array().unwrap().len(), 1);
    assert_eq!(result[0]["relativePath"], "note.txt");
    assert!(actor
        .handle_gpui_workspace_request(1, "unrelated.request", &json!({}))
        .await
        .unwrap()
        .is_none());
}
