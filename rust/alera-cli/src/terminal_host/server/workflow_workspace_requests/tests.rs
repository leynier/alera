use std::collections::HashMap;

use serde_json::json;

use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, mobile_client, test_actor};

#[tokio::test]
async fn workflow_worktrees_rpc_rejects_mobile_unauthenticated_and_unbounded_payloads() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _rx) = ClientHandle::test_channels();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    for verb in ["workflows.prepareWorkspace", "workflows.workspaces"] {
        assert!(actor
            .start_workflow_workspace_request(1, 1, verb, &json!({}))
            .is_err());
        actor
            .clients
            .insert(1, mobile_client(handle.clone(), "device"));
        assert!(actor
            .start_workflow_workspace_request(1, 1, verb, &json!({}))
            .is_err());
        actor.clients.insert(1, local_client(handle.clone()));
        actor.clients.get_mut(&1).unwrap().authenticated = false;
        assert!(actor
            .start_workflow_workspace_request(1, 1, verb, &json!({}))
            .is_err());
        actor.clients.get_mut(&1).unwrap().authenticated = true;
        for payload in [
            json!({"runId":"x".repeat(161)}),
            json!({"runId":vec![0;10000]}),
            json!({"runId":"run","actor":"app","path":"/foreign"}),
        ] {
            assert!(actor
                .start_workflow_workspace_request(1, 1, verb, &payload)
                .is_err());
        }
        actor.clients.clear();
    }
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(actor.sessions.is_empty());
}

#[tokio::test]
async fn workflow_worktrees_read_completion_does_not_broadcast_workspace_changes() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    actor.managed_workspace_jobs = 1;
    actor
        .handle_workflow_workspace_finished(1, 1, Ok(json!({"items":[]})), false)
        .await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(rx.try_recv().unwrap().as_json().unwrap()["ok"]
        .as_bool()
        .unwrap());
    assert!(rx.try_recv().is_err());
}

#[test]
fn workflow_worktrees_capability_is_additive_and_cli_cannot_select_paths() {
    use crate::terminal_host::{control_file, protocol};
    use clap::Parser;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("control.json");
    control_file::write_control_file(&path, 1234, "shared-control-token", false).unwrap();
    let value: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    assert_eq!(protocol::PROTOCOL_VERSION, 4);
    assert!(value["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!(
            protocol::RUNTIME_HOST_WORKFLOW_WORKSPACES_CAPABILITY
        )));
    let args = [
        "alera",
        "orchestration",
        "workspaces",
        "prepare",
        "--run",
        "run",
        "--revision",
        "1",
        "--request-id",
        "key",
    ];
    crate::cli::Cli::try_parse_from(args).unwrap();
    for forbidden in ["--path", "--workspace-id", "--branch", "--approve"] {
        assert!(
            crate::cli::Cli::try_parse_from(args.into_iter().chain([forbidden, "foreign"]))
                .is_err()
        );
    }
}
