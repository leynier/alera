use super::*;
use alera_core::runtime::SshTarget;
use serde_json::{json, Value};
use std::sync::Mutex;

struct Remote {
    response: Value,
    scripts: Mutex<Vec<String>>,
    online: bool,
}

impl RemoteHostExecutor for Remote {
    async fn probe_windows(&self, _: &SshTarget) -> Option<bool> {
        self.online.then_some(false)
    }
    async fn run(&self, _: &SshTarget, _: bool, script: &str) -> Result<String> {
        self.scripts.lock().unwrap().push(script.into());
        Ok(self.response.to_string())
    }
}

impl Remote {
    fn folder(path: &str) -> Self {
        Self {
            response: json!({"version": 1, "path": path, "kind": "folder", "branch": null}),
            scripts: Mutex::new(vec![]),
            online: true,
        }
    }
}

async fn fixture() -> (tempfile::TempDir, tempfile::TempDir, RuntimeStore, String) {
    let state = tempfile::tempdir().unwrap();
    let local = tempfile::tempdir().unwrap();
    std::fs::write(local.path().join("keep"), "local files").unwrap();
    let store = RuntimeStore::open(state.path()).await.unwrap();
    let project =
        crate::project_management::register_project(&store, local.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let target: SshTarget = serde_json::from_value(json!({
        "id": "ssh", "alias": "Test Host", "host": "test.invalid", "port": 22,
        "username": "test", "authKind": "agent", "createdAt": chrono::Utc::now(),
        "updatedAt": chrono::Utc::now(), "installDir": "/remote/sidecar", "bootstrapStatus": "installed",
    })).unwrap();
    store.upsert_ssh_target(target).await.unwrap();
    (state, local, store, project.id)
}

fn request(project_id: &str, path: &str) -> RegisterProjectCheckoutRequest {
    RegisterProjectCheckoutRequest {
        clone_url: None,
        clone_name: None,
        project_id: project_id.into(),
        host_id: "ssh".into(),
        path: path.into(),
    }
}

#[tokio::test]
async fn registers_canonical_remote_folder_and_creates_independent_tasks_without_uploading() {
    let (_state, local, store, project) = fixture().await;
    for workspace in store.list_workspaces(&project).await.unwrap() {
        store.remove_workspace(&workspace.id, true).await.unwrap();
    }
    let remote = Remote::folder("/canonical/remote/project");
    let checkout = register(&store, request(&project, "/alias"), &remote)
        .await
        .unwrap();
    assert_eq!(checkout.path, "/canonical/remote/project");
    assert_eq!(
        register(&store, request(&project, "/alias"), &remote)
            .await
            .unwrap()
            .id,
        checkout.id
    );
    let before = store.list_workspaces(&project).await.unwrap().len();
    assert_eq!(before, 0);
    let mut tasks = vec![];
    for id in ["task-a", "task-b"] {
        let result = crate::shared_workspace::create_shared_workspace_with(
            &store,
            crate::shared_workspace::SharedWorkspaceCreateRequest {
                project_id: project.clone(),
                id: Some(id.into()),
                host_id: Some("ssh".into()),
                name: None,
                parent_workspace_id: None,
            },
            &remote,
        )
        .await
        .unwrap();
        assert_eq!(result.workspace.host_id, "ssh");
        assert_eq!(result.workspace.path, checkout.path);
        assert!(result.deferred_setup_command.is_none());
        assert!(store.list_workspace_tabs(id).await.unwrap().is_empty());
        tasks.push(result.workspace);
    }
    assert_ne!(tasks[0].instance_id, tasks[1].instance_id);
    assert_ne!(tasks[0].name, tasks[1].name);
    assert_eq!(
        store.list_workspaces(&project).await.unwrap().len(),
        before + 2
    );
    assert_eq!(
        std::fs::read_to_string(local.path().join("keep")).unwrap(),
        "local files"
    );
    assert!(remote
        .scripts
        .lock()
        .unwrap()
        .iter()
        .all(|script| script.contains("inspect-checkout")));
    let mut offline = Remote::folder("/canonical/remote/project");
    offline.online = false;
    assert!(register(&store, request(&project, "/alias"), &offline)
        .await
        .is_err());
    assert_eq!(
        store
            .find_project_checkout(&project, "ssh")
            .await
            .unwrap()
            .unwrap()
            .id,
        checkout.id
    );
    assert_eq!(
        store.list_workspaces(&project).await.unwrap().len(),
        before + 2
    );
}

#[tokio::test]
async fn invalid_or_incompatible_inspections_never_register_checkout() {
    let (_state, _local, store, project) = fixture().await;
    for response in [
        json!({"version": 2, "path": "/remote", "kind": "folder", "branch": null}),
        json!({"version": 1, "path": "relative", "kind": "folder", "branch": null}),
        json!({"version": 1, "path": "/remote", "kind": "gitRepository", "branch": "main"}),
    ] {
        let remote = Remote {
            response,
            scripts: Mutex::new(vec![]),
            online: true,
        };
        assert!(register(&store, request(&project, "/remote"), &remote)
            .await
            .is_err());
        assert!(store
            .find_project_checkout(&project, "ssh")
            .await
            .unwrap()
            .is_none());
    }
}

#[test]
fn inspection_commands_quote_paths_for_each_host_platform() {
    let posix = inspection_script(
        false,
        "~/.alera/sidecar",
        "/work/a'b $(touch forbidden)",
        ProjectKind::Folder,
    );
    assert!(posix.contains("--path '/work/a'\"'\"'b $(touch forbidden)' --kind folder"));
    let windows = inspection_script(
        true,
        r"C:\Alera Runtime",
        r"C:\work\a'b",
        ProjectKind::GitRepository,
    );
    assert!(windows.contains("-LiteralPath (Join-Path $install 'current.txt')"));
    assert!(windows.contains(r"--path 'C:\work\a''b' --kind git-repository"));
    assert!(windows.contains("$LASTEXITCODE -ne 0"));
}

#[tokio::test]
async fn clone_requires_git_project_and_never_replaces_registered_checkout() {
    let (_state, _local, store, project_id) = fixture().await;
    let remote = Remote::folder("/remote");
    let mut clone_request = request(&project_id, "/remote");
    clone_request.clone_url = Some("https://example.invalid/repo.git".into());
    assert!(register(&store, clone_request, &remote)
        .await
        .unwrap_err()
        .to_string()
        .contains("Only Git projects"));
    assert!(remote.scripts.lock().unwrap().is_empty());
    let mut project = store.find_project(&project_id).await.unwrap().unwrap();
    project.kind = ProjectKind::GitRepository;
    store.upsert_project(project).await.unwrap();
    let remote = Remote {
        response: json!({"version": 1, "path": "/new/repo", "kind": "gitRepository", "branch": "main"}),
        scripts: Mutex::new(vec![]),
        online: true,
    };
    let mut clone_request = request(&project_id, "/new/repo");
    clone_request.clone_url = Some("https://example.invalid/repo.git".into());
    register(&store, clone_request, &remote).await.unwrap();
    let mut duplicate = request(&project_id, "/another/repo");
    duplicate.clone_url = Some("https://example.invalid/repo.git".into());
    assert!(register(&store, duplicate, &remote)
        .await
        .unwrap_err()
        .to_string()
        .contains("already has a checkout"));
    let scripts = remote.scripts.lock().unwrap();
    assert_eq!(scripts.len(), 1);
    assert!(scripts[0].contains("clone-checkout-folder"));
    assert!(scripts[0].contains("--url 'https://example.invalid/repo.git'"));
}

#[tokio::test]
async fn remote_git_tasks_use_the_owning_hosts_current_branch() {
    let (_state, _local, store, project_id) = fixture().await;
    let mut project = store.find_project(&project_id).await.unwrap().unwrap();
    project.kind = ProjectKind::GitRepository;
    store.upsert_project(project).await.unwrap();
    let remote = Remote {
        response: json!({"version": 1, "path": "/remote/git", "kind": "gitRepository", "branch": "remote-current"}),
        scripts: Mutex::new(vec![]),
        online: true,
    };
    register(&store, request(&project_id, "/remote/git"), &remote)
        .await
        .unwrap();
    let task = crate::shared_workspace::create_shared_workspace_with(
        &store,
        crate::shared_workspace::SharedWorkspaceCreateRequest {
            project_id,
            id: Some("git-task".into()),
            host_id: Some("ssh".into()),
            name: None,
            parent_workspace_id: None,
        },
        &remote,
    )
    .await
    .unwrap();
    assert_eq!(task.workspace.branch.as_deref(), Some("remote-current"));
    assert_eq!(task.workspace.path, "/remote/git");
}

#[tokio::test]
async fn changed_remote_path_does_not_replace_a_checkout_or_create_a_task() {
    let (_state, _local, store, project_id) = fixture().await;
    let original = register(
        &store,
        request(&project_id, "/alias"),
        &Remote::folder("/original"),
    )
    .await
    .unwrap();
    let changed = Remote::folder("/changed");
    assert!(register(&store, request(&project_id, "/alias"), &changed)
        .await
        .is_err());
    let error = crate::shared_workspace::create_shared_workspace_with(
        &store,
        crate::shared_workspace::SharedWorkspaceCreateRequest {
            project_id: project_id.clone(),
            id: Some("must-not-exist".into()),
            host_id: Some("ssh".into()),
            name: None,
            parent_workspace_id: None,
        },
        &changed,
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("different directory"));
    assert!(store
        .find_workspace("must-not-exist")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .find_project_checkout(&project_id, "ssh")
            .await
            .unwrap()
            .unwrap()
            .path,
        original.path
    );
}

#[tokio::test]
async fn missing_linked_origin_uses_native_evidence_and_preserves_known_ownership() {
    use alera_core::runtime::WorkspaceKind;
    for windows in [false, true] {
        let (_state, _local, store, project_id) = fixture().await;
        let target = store.find_ssh_target("ssh").await.unwrap().unwrap();
        let mut project = store.find_project(&project_id).await.unwrap().unwrap();
        project.kind = ProjectKind::GitRepository;
        store.upsert_project(project).await.unwrap();
        let mut task = store.list_workspaces(&project_id).await.unwrap().remove(0);
        task.id = "legacy".into();
        task.instance_id = "legacy-instance".into();
        task.host_id = "ssh".into();
        task.kind = WorkspaceKind::Linked;
        task.path = if windows {
            "C:\\fixture\\linked"
        } else {
            "/fixture/linked"
        }
        .into();
        let task = store.insert_workspace(task).await.unwrap();
        let origin = if windows {
            "C:\\fixture\\legacy.git"
        } else {
            "/fixture/legacy.git"
        };
        for response in [
            json!({"version": 2, "path": task.path, "repositoryPath": origin, "branch": "task"}),
            json!({"version": 1, "path": "/different", "repositoryPath": origin, "branch": "task"}),
            json!({"version": 1, "path": task.path, "repositoryPath": "relative.git", "branch": "task"}),
        ] {
            let remote = Remote {
                response,
                scripts: Mutex::new(vec![]),
                online: true,
            };
            assert!(
                ensure_linked_origin(&store, &task, &target, windows, "/sidecar", &remote)
                    .await
                    .is_err()
            );
            assert!(store
                .find_workspace_checkout(&task.id)
                .await
                .unwrap()
                .unwrap()
                .repository_path
                .is_none());
        }
        let remote = Remote {
            response: json!({"version": 1, "path": task.path, "repositoryPath": origin, "branch": "task"}),
            scripts: Mutex::new(vec![]),
            online: true,
        };
        ensure_linked_origin(&store, &task, &target, windows, "/sidecar", &remote)
            .await
            .unwrap();
        ensure_linked_origin(&store, &task, &target, windows, "/sidecar", &remote)
            .await
            .unwrap();
        assert_eq!(remote.scripts.lock().unwrap().len(), 1);
        assert!(remote.scripts.lock().unwrap()[0].contains("inspect-linked-checkout"));
        assert_eq!(
            store
                .find_workspace_checkout(&task.id)
                .await
                .unwrap()
                .unwrap()
                .repository_path
                .as_deref(),
            Some(origin)
        );
        assert_eq!(store.find_workspace(&task.id).await.unwrap(), Some(task));
        assert!(store
            .find_project_checkout(&project_id, "ssh")
            .await
            .unwrap()
            .is_none());
    }
}

#[tokio::test]
async fn branch_catalog_uses_registered_owner_and_rejects_mismatched_or_old_responses() {
    let (_state, _local, store, project_id) = fixture().await;
    let mut project = store.find_project(&project_id).await.unwrap().unwrap();
    project.kind = ProjectKind::GitRepository;
    store.upsert_project(project).await.unwrap();
    let mut remote = Remote {
        response: json!({"version": 1, "path": "/remote/git", "branches": ["remote-only", "origin/topic"], "localBranches": ["remote-only"]}),
        scripts: Mutex::new(vec![]),
        online: true,
    };
    assert!(
        crate::project_branch_catalog::list(&store, &project_id, "ssh", &remote)
            .await
            .is_err()
    );
    assert!(remote.scripts.lock().unwrap().is_empty());
    store
        .register_project_checkout(&project_id, "ssh", "/remote/git")
        .await
        .unwrap();
    let value = crate::project_branch_catalog::list(&store, &project_id, "ssh", &remote)
        .await
        .unwrap();
    assert_eq!(value["hostId"], "ssh");
    assert_eq!(value["branches"], json!(["remote-only", "origin/topic"]));
    assert_eq!(value["localBranches"], json!(["remote-only"]));
    assert!(remote.scripts.lock().unwrap()[0]
        .contains("inspect-checkout-branches --path '/remote/git'"));
    for invalid in [
        json!({"version": 1, "path": "/wrong", "branches": [], "localBranches": []}),
        json!({"version": 2, "path": "/remote/git", "branches": [], "localBranches": []}),
        json!({"path": "/remote/git", "branches": []}),
    ] {
        remote.response = invalid;
        assert!(
            crate::project_branch_catalog::list(&store, &project_id, "ssh", &remote)
                .await
                .is_err()
        );
    }
}

#[path = "project_file_catalog_tests.rs"]
mod file_catalog_tests;
