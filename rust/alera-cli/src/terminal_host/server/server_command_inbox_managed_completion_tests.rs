use std::collections::HashMap;
use std::time::Duration;

use crate::project_management::register_project;
use crate::shared_workspace::SharedWorkspaceCreateRequest;
use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};

use super::deferred_tests::{fill_control_and_request_shutdown, next_deferred};
use super::*;

#[tokio::test]
async fn managed_workspace_completion_survives_admission_shutdown_and_releases_job() {
    let root = tempfile::tempdir().unwrap();
    let project_path = root.path().join("project");
    std::fs::create_dir(&project_path).unwrap();
    let (handle, mut responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &root,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut commands) = ServerInbox::channel();
    actor.inbox = inbox.clone();
    let project = register_project(
        &actor.runtime_store,
        project_path.to_str().unwrap(),
        Some("Deferred completion test"),
    )
    .await
    .unwrap()
    .project;
    let workspace_id = "deferred-workspace";
    let request_id = 901;

    actor.start_shared_workspace_create(
        1,
        request_id,
        SharedWorkspaceCreateRequest {
            project_id: project.id,
            id: Some(workspace_id.to_string()),
            name: Some("Deferred workspace".to_string()),
            host_id: None,
            parent_workspace_id: None,
        },
        None,
    );
    assert_eq!(actor.managed_workspace_jobs, 1);
    fill_control_and_request_shutdown(&inbox);
    assert_eq!(inbox.queued_counts().2, SERVER_COMMAND_CONTROL_CAPACITY);

    let completion = tokio::time::timeout(Duration::from_secs(10), next_deferred(&mut commands))
        .await
        .expect("managed workspace completion should survive admission shutdown");
    match &completion {
        ServerCommand::ManagedWorkspaceCreated {
            client_id,
            request_id: actual_request_id,
            ..
        } => {
            assert_eq!(*client_id, 1);
            assert_eq!(*actual_request_id, request_id);
        }
        _ => panic!("unexpected deferred command"),
    }
    actor.handle(completion).await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(inbox.completion_counts(), (0, 0));

    let response = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let frame: ClientFrame = responses.recv().await.expect("client response channel");
            let Some(value) = frame.as_json() else {
                continue;
            };
            if value["id"] == request_id {
                break value;
            }
        }
    })
    .await
    .expect("requesting client should receive the managed workspace response");
    assert_eq!(response["id"], request_id);
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["workspace"]["id"], workspace_id);
}
