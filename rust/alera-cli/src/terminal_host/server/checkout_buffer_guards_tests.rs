use std::collections::HashMap;

use alera_core::runtime::{Project, ProjectKind, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::json;

use crate::shared_workspace::{create_shared_workspace, SharedWorkspaceCreateRequest};
use crate::terminal_host::client::ClientHandle;

use super::actor_test_harness::test_actor;
use super::{ClientState, ServerActor};

pub(super) async fn fixture() -> (tempfile::TempDir, ServerActor) {
    let root = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    for (id, app) in [(1, true), (2, true), (3, false)] {
        let (handle, _) = ClientHandle::test_channels();
        clients.insert(id, ClientState::local(handle, app));
    }
    let actor = test_actor(&root, clients, HashMap::new()).await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: root.path().to_string_lossy().to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::Folder,
        })
        .await
        .unwrap();
    for id in ["task", "sibling"] {
        create_shared_workspace(
            &actor.runtime_store,
            SharedWorkspaceCreateRequest {
                id: Some(id.into()),
                project_id: "project".into(),
                name: None,
                host_id: None,
                parent_workspace_id: None,
            },
        )
        .await
        .unwrap();
        actor
            .runtime_store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: format!("{id}-editor"),
                workspace_id: id.into(),
                kind: "editor".into(),
                title: id.into(),
                created_at: now,
                updated_at: now,
                payload: json!({"filePath": "notes.md"}),
            })
            .await
            .unwrap();
    }
    (root, actor)
}

#[tokio::test]
async fn remote_retirement_preparation_does_not_close_the_home_terminal() {
    let (_root, mut actor) = fixture().await;
    let mut workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    workspace.host_id = "ssh".into();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    let mut session =
        crate::terminal_host::session::Session::driver_test_stub("ssh-session", 80, 24);
    session.workspace_id = "task".into();
    actor.sessions.insert("ssh-session".into(), session);
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id":"task","operation":"removeShared"}),
        )
        .await
        .unwrap();
    let guard_id = acquired["guardId"].as_str().unwrap();
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId":guard_id,"blockers":[]}))
            .unwrap();
    }
    let proof = actor
        .claim_checkout_buffer_guard(
            3,
            9,
            "task",
            "removeShared",
            &json!({"bufferGuardId":guard_id}),
        )
        .unwrap();
    let shutdown = actor
        .prepare_runtime_mutation(
            &super::runtime_mutations::RuntimeMutationRequest::RemoveSharedWorkspace {
                remote_automation_cleanup: None,
                automation_cleanup: None,
                request: crate::managed_workspace::ManagedWorkspaceRemoveRequest {
                    id: "task".into(),
                    delete_branch: Some(false),
                    active_workspace_id: None,
                    close_sessions: true,
                },
                buffer_guard: proof,
                remote_retirement: None,
            },
        )
        .await
        .unwrap();
    assert!(shutdown.closed_tab_ids.is_empty());
    assert!(actor.sessions["ssh-session"].running());
    assert!(actor
        .runtime_store
        .find_workspace_tab("task-editor")
        .await
        .unwrap()
        .is_some());
    assert!(actor.checkout_buffer_guards[guard_id].started);
}

#[tokio::test]
async fn expected_instance_must_match_before_preparing_an_operation() {
    let (_root, mut actor) = fixture().await;
    let error = actor.checkout_buffer_guard_request(3, "workspace.bufferGuard.acquire",
        &json!({"id":"task", "operation":"removeShared", "expectedInstanceId":"another-instance"}))
        .await.unwrap_err();
    assert!(error.to_string().contains("identity changed"));
    assert!(actor.checkout_buffer_guards.is_empty());
}

#[tokio::test]
async fn changed_instance_invalidates_a_prepared_operation() {
    let (_root, mut actor) = fixture().await;
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id":"task", "operation":"removeShared"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId":id, "blockers":[]}))
            .unwrap();
    }
    let proof = actor
        .claim_checkout_buffer_guard(3, 7, "task", "removeShared", &json!({"bufferGuardId":id}))
        .unwrap();
    let mut task = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    task.instance_id = "replacement-instance".into();
    actor.runtime_store.upsert_workspace(task).await.unwrap();
    assert!(actor
        .start_checkout_buffer_guard(&proof)
        .await
        .unwrap_err()
        .to_string()
        .contains("identity or location changed"));
    assert!(!actor.checkout_buffer_guards[id].started);
}

#[tokio::test]
async fn every_editor_client_must_freeze_clean_buffers_before_readiness() {
    let (_root, mut actor) = fixture().await;
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "removeShared"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    assert_eq!(acquired["ready"], false);
    assert_eq!(acquired["pendingClients"], 2);
    let guard = actor.checkout_buffer_guards.get(id).unwrap();
    assert_eq!(guard.scope.tab_ids, ["task-editor"]);
    assert!(guard.scope.workspace_paths.is_empty());
    assert!(actor
        .acknowledge_buffer_guard(3, &json!({"guardId": id, "blockers": []}))
        .is_err());
    let first = actor
        .acknowledge_buffer_guard(1, &json!({"guardId": id, "blockers": []}))
        .unwrap();
    assert_eq!(first["ready"], false);
    let second = actor.acknowledge_buffer_guard(2, &json!({"guardId": id, "blockers": [{"tabId": "task-editor", "path": "notes.md", "reason": "Unsaved"}]})).unwrap();
    assert_eq!(second["ready"], false);
    assert_eq!(second["blockers"][0]["path"], "notes.md");
    assert!(actor
        .acknowledge_buffer_guard(2, &json!({"guardId": id, "blockers": []}))
        .is_err());
    assert!(actor
        .checkout_buffer_guard_request(2, "workspace.bufferGuard.release", &json!({"guardId": id}))
        .await
        .is_err());
    actor
        .checkout_buffer_guard_request(3, "workspace.bufferGuard.release", &json!({"guardId": id}))
        .await
        .unwrap();
    assert!(actor.checkout_buffer_guards.is_empty());
}

#[tokio::test]
async fn new_or_disconnected_clients_invalidate_a_ready_preparation() {
    let (_root, mut actor) = fixture().await;
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "handOff"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    let scope = &actor.checkout_buffer_guards.get(id).unwrap().scope;
    assert_eq!(scope.tab_ids, ["sibling-editor", "task-editor"]);
    assert_eq!(scope.workspace_paths.len(), 1);
    actor
        .acknowledge_buffer_guard(1, &json!({"guardId": id, "blockers": []}))
        .unwrap();
    let ready = actor
        .acknowledge_buffer_guard(2, &json!({"guardId": id, "blockers": []}))
        .unwrap();
    assert_eq!(ready["ready"], true);
    let (handle, _) = ClientHandle::test_channels();
    actor.clients.insert(4, ClientState::local(handle, true));
    let hello = actor.buffer_guard_hello(4);
    assert_eq!(hello[0]["guardId"], id);
    assert_eq!(
        actor.checkout_buffer_guards.get(id).unwrap().status(id)["ready"],
        false
    );
    actor
        .acknowledge_buffer_guard(4, &json!({"guardId": id, "blockers": []}))
        .unwrap();
    actor.disconnect_buffer_guard_client(1);
    let disconnected = actor.checkout_buffer_guards.get(id).unwrap().status(id);
    assert_eq!(disconnected["ready"], false);
    assert_eq!(disconnected["disconnectedClients"], 1);
    actor.disconnect_buffer_guard_client(3);
    assert!(actor.checkout_buffer_guards.is_empty());
}

#[tokio::test]
async fn older_editors_require_update_without_disconnect_or_task_changes() {
    let (_root, mut actor) = fixture().await;
    actor.clients.get_mut(&2).unwrap().checkout_buffer_guards = false;
    let before = actor.runtime_store.list_all_workspaces().await.unwrap();
    let error = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "removeShared"}),
        )
        .await
        .unwrap_err();
    assert!(error.wire_message().contains("update"));
    assert_eq!(actor.clients.len(), 3);
    assert!(actor.checkout_buffer_guards.is_empty());
    assert_eq!(
        actor.runtime_store.list_all_workspaces().await.unwrap(),
        before
    );
}

#[tokio::test]
async fn a_new_tab_after_acknowledgement_requires_fresh_buffer_verification() {
    let (_root, mut actor) = fixture().await;
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "removeShared"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId": id, "blockers": []}))
            .unwrap();
    }
    let proof = actor
        .claim_checkout_buffer_guard(3, 9, "task", "removeShared", &json!({"bufferGuardId": id}))
        .unwrap();
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "new-editor".into(),
            workspace_id: "task".into(),
            kind: "editor".into(),
            title: "New".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"filePath": "new.md"}),
        })
        .await
        .unwrap();
    let error = actor.start_checkout_buffer_guard(&proof).await.unwrap_err();
    assert!(error.wire_message().contains("tabs changed"));
    assert!(actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .is_some());
    actor.finish_checkout_buffer_guard(3, 9, false);
    assert!(actor.checkout_buffer_guards.is_empty());
}

#[tokio::test]
async fn started_mutations_hold_guards_until_completion_and_recheck_disconnects() {
    let (_root, mut actor) = fixture().await;
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "removeShared"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    let payload = json!({"bufferGuardId": id});
    assert!(actor
        .claim_checkout_buffer_guard(3, 8, "task", "removeShared", &payload)
        .is_err());
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId": id, "blockers": []}))
            .unwrap();
    }
    assert!(actor
        .claim_checkout_buffer_guard(2, 8, "task", "removeShared", &payload)
        .is_err());
    assert!(actor
        .claim_checkout_buffer_guard(3, 8, "sibling", "removeShared", &payload)
        .is_err());
    let proof = actor
        .claim_checkout_buffer_guard(3, 8, "task", "removeShared", &payload)
        .unwrap();
    actor.start_checkout_buffer_guard(&proof).await.unwrap();
    actor.expire_checkout_buffer_guard(id);
    assert!(actor.checkout_buffer_guards.contains_key(id));
    assert!(proof.verify().is_ok());
    assert!(actor
        .checkout_buffer_guard_request(3, "workspace.bufferGuard.release", &json!({"guardId": id}))
        .await
        .is_err());
    actor.disconnect_buffer_guard_client(3);
    assert!(proof.verify().is_err());
    assert!(actor.checkout_buffer_guards.contains_key(id));
    actor.finish_checkout_buffer_guard(3, 8, false);
    assert!(actor.checkout_buffer_guards.is_empty());
}
