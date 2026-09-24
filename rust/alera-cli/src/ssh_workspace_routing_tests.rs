use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::json;

#[tokio::test]
async fn registering_project_folder_preserves_unmigrated_linked_terminal_transport() {
    let state = tempfile::tempdir().unwrap();
    let folder = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(state.path()).await.unwrap();
    let project =
        crate::project_management::register_project(&store, folder.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let mut legacy = store.list_workspaces(&project.id).await.unwrap().remove(0);
    legacy.id = "legacy".into();
    legacy.instance_id = "legacy-instance".into();
    legacy.host_id = "ssh".into();
    legacy.path = "/legacy/worktree".into();
    legacy.kind = alera_core::runtime::WorkspaceKind::Linked;
    legacy.branch = Some("legacy-branch".into());
    let legacy = store.insert_workspace(legacy).await.unwrap();
    store
        .upsert_ssh_target(
            serde_json::from_value(json!({
                "id":"ssh", "alias":"Fixture", "host":"offline.invalid", "port":22,
                "username":"fixture", "authKind":"agent", "createdAt":chrono::Utc::now(),
                "updatedAt":chrono::Utc::now(), "runtimePlatform":"linux",
                "bootstrapStatus":"installed", "installDir":"/fixture/sidecar"
            }))
            .unwrap(),
        )
        .await
        .unwrap();
    let mut before = None;
    for registered in [false, true] {
        if registered {
            store
                .register_project_checkout(&project.id, "ssh", "/new/project")
                .await
                .unwrap();
        }
        assert!(!super::uses_owner_terminal(&store, &legacy).await.unwrap());
        assert!(store
            .find_workspace_checkout(&legacy.id)
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .is_none());
        let (launch, path) = super::remote_workspace_terminal_override(
            &store,
            &legacy.id,
            crate::remote_owner_terminal_launch::TerminalIdentity {
                session_id: "session",
                tab_id: "tab",
                cols: 80,
                rows: 24,
            },
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(path, legacy.path);
        assert!(launch
            .arguments
            .last()
            .unwrap()
            .contains("cd '/legacy/worktree'"));
        if let Some(expected) = &before {
            assert_eq!(&launch.arguments, expected);
        } else {
            before = Some(launch.arguments);
        }
    }
    assert_eq!(
        store.find_workspace(&legacy.id).await.unwrap().unwrap(),
        legacy
    );
    store.pool().close().await;
    let reopened = RuntimeStore::open(state.path()).await.unwrap();
    assert!(!super::uses_owner_terminal(&reopened, &legacy)
        .await
        .unwrap());
    let (launch, path) = super::remote_workspace_terminal_override(
        &reopened,
        &legacy.id,
        crate::remote_owner_terminal_launch::TerminalIdentity {
            session_id: "session",
            tab_id: "tab",
            cols: 80,
            rows: 24,
        },
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(Some(launch.arguments), before);
    assert_eq!(path, legacy.path);
    assert_eq!(
        reopened.find_workspace(&legacy.id).await.unwrap().unwrap(),
        legacy
    );
}

async fn fixture() -> (
    tempfile::TempDir,
    tempfile::TempDir,
    RuntimeStore,
    Workspace,
) {
    let state = tempfile::tempdir().unwrap();
    let folder = tempfile::tempdir().unwrap();
    std::fs::write(folder.path().join("private.txt"), "local-only").unwrap();
    let store = RuntimeStore::open(state.path()).await.unwrap();
    let project =
        crate::project_management::register_project(&store, folder.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let mut workspace = store.list_workspaces(&project.id).await.unwrap().remove(0);
    workspace.id = "remote-task".into();
    workspace.instance_id = "remote-instance".into();
    workspace.host_id = "unavailable-host".into();
    let workspace = store.insert_workspace(workspace).await.unwrap();
    (state, folder, store, workspace)
}

#[tokio::test]
async fn remote_terminal_never_falls_back_to_an_identical_local_path() {
    let (_state, folder, store, workspace) = fixture().await;
    let error = super::remote_workspace_terminal_override(
        &store,
        &workspace.id,
        crate::remote_owner_terminal_launch::TerminalIdentity {
            session_id: "session",
            tab_id: "tab",
            cols: 80,
            rows: 24,
        },
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("ssh target not found"));
    assert_eq!(
        std::fs::read_to_string(folder.path().join("private.txt")).unwrap(),
        "local-only"
    );
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
}

#[tokio::test]
async fn terminal_launch_for_an_offline_registered_host_does_not_wait_for_ssh() {
    let (_state, _folder, store, workspace) = fixture().await;
    let target = serde_json::from_value(json!({
        "id": workspace.host_id, "alias": "Offline Fixture", "host": "offline.invalid",
        "port": 22, "username": "fixture", "authKind": "agent",
        "createdAt": chrono::Utc::now(), "updatedAt": chrono::Utc::now(),
        "installDir": "/fixture/sidecar", "bootstrapStatus": "installed",
        "runtimePlatform": "linux"
    }))
    .unwrap();
    store.upsert_ssh_target(target).await.unwrap();
    store
        .register_project_checkout(&workspace.project_id, &workspace.host_id, &workspace.path)
        .await
        .unwrap();
    let (launch, path) = tokio::time::timeout(
        std::time::Duration::from_secs(1),
        super::remote_workspace_terminal_override(
            &store,
            &workspace.id,
            crate::remote_owner_terminal_launch::TerminalIdentity {
                session_id: "session",
                tab_id: "tab",
                cols: 80,
                rows: 24,
            },
        ),
    )
    .await
    .expect("constructing a terminal launch must not wait for a remote connection")
    .unwrap()
    .unwrap();
    assert_eq!(launch.shell, "ssh");
    assert_eq!(path, workspace.path);
    assert!(launch
        .arguments
        .iter()
        .any(|value| value.contains("offline.invalid")));
}

#[tokio::test]
async fn remote_file_requests_never_read_an_identical_local_path() {
    let (_state, _folder, store, workspace) = fixture().await;
    let listing =
        crate::remote_workspace_files::list_workspace_files(&store, &workspace, "", false)
            .await
            .unwrap_err();
    assert!(listing.to_string().contains("ssh target not found"));
    let read = crate::remote_workspace_files::try_read_remote_from_payload(
        &store,
        &workspace,
        &json!({"relativePath": "private.txt"}),
    )
    .await
    .unwrap_err();
    assert!(read.to_string().contains("ssh target not found"));
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
}
