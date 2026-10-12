use std::collections::HashMap;

use alera_core::runtime::{Project, Workspace};

use super::super::actor_test_harness::test_actor;
use super::*;

async fn seed(actor: &ServerActor, root: &std::path::Path) {
    let store = &actor.runtime_store;
    for (id, repo_path) in [
        ("local-project", root.join("local").display().to_string()),
        ("remote-project", "/srv/remote".to_string()),
    ] {
        let project: Project = serde_json::from_value(json!({
            "id": id, "name": id, "repoPath": repo_path, "kind": "folder",
            "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
        }))
        .unwrap();
        store.upsert_project(project).await.unwrap();
    }
    store
        .register_project_checkout("local-project", "lab", "/srv/local")
        .await
        .unwrap();
    store
        .register_project_checkout("remote-project", "lab", "/srv/remote")
        .await
        .unwrap();
    let workspace: Workspace = serde_json::from_value(json!({
        "id": "task", "instanceId": "task-instance", "hostId": "lab",
        "projectId": "local-project", "name": "Task", "path": "/srv/local-task",
        "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
        "kind": "linked", "status": "active", "reusesExistingBranch": false,
        "isPinned": false,
    }))
    .unwrap();
    store.insert_workspace(workspace).await.unwrap();
    let target: SshTarget = serde_json::from_value(json!({
        "id": "lab", "alias": "Lab", "host": "lab.invalid", "port": 22,
        "username": "dev", "authKind": "agent", "bootstrapStatus": "installed",
        "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
    }))
    .unwrap();
    store.upsert_ssh_target(target).await.unwrap();
}

#[tokio::test]
async fn a_host_in_use_is_refused_with_what_still_lives_there() {
    let root = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&root, HashMap::new(), HashMap::new()).await;
    seed(&actor, root.path()).await;

    let refused = actor
        .ssh_target_remove(&json!({"id": "lab"}))
        .await
        .unwrap_err();
    let HostError::Conflict {
        code,
        message,
        details,
    } = refused
    else {
        panic!("expected a conflict, got {refused:?}");
    };
    assert_eq!(code, "sshTargetInUse");
    assert_eq!(
        message,
        "Lab still has 2 projects and 1 workspace. Remove them first."
    );
    assert_eq!(details["hostId"], "lab");
    assert_eq!(details["alias"], "Lab");
    assert_eq!(details["workspaceCount"], 1);
    assert_eq!(details["checkoutCount"], 2);
    assert_eq!(
        details["projectIds"],
        json!(["local-project", "remote-project"])
    );
    assert_eq!(
        details["remoteOnlyProjectIds"],
        json!(["remote-project"]),
        "a project whose repoPath is the host's checkout lives only there"
    );
    assert!(actor
        .runtime_store
        .find_ssh_target("lab")
        .await
        .unwrap()
        .is_some());

    actor
        .runtime_store
        .remove_workspace("task", true)
        .await
        .unwrap();
    for project in ["local-project", "remote-project"] {
        actor
            .runtime_store
            .remove_project_checkout(project, "lab")
            .await
            .unwrap();
    }
    assert_eq!(
        actor
            .ssh_target_remove(&json!({"id": "lab"}))
            .await
            .unwrap(),
        json!({})
    );
    assert!(actor
        .runtime_store
        .find_ssh_target("lab")
        .await
        .unwrap()
        .is_none());

    let missing = actor
        .ssh_target_remove(&json!({"id": "lab"}))
        .await
        .unwrap_err();
    assert_eq!(missing.to_string(), "ssh target not found: lab");
}

#[test]
fn counts_read_naturally() {
    assert_eq!(counted(0, "project"), "0 projects");
    assert_eq!(counted(1, "workspace"), "1 workspace");
    assert_eq!(counted(3, "workspace"), "3 workspaces");
}
