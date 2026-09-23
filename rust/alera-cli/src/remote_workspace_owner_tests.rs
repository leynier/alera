use super::*;

#[tokio::test]
async fn terminal_rejects_old_live_host_before_registering_owner_state() {
    use base64::Engine;
    use serde_json::json;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    let (_home, owner, store, project, task) = fixture().await;
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let control = json!({
        "protocolVersion": crate::terminal_host::protocol::PROTOCOL_VERSION,
        "port": listener.local_addr().unwrap().port(),
        "token": "isolated-test-token",
        "runtimeCapabilities": [],
    })
    .to_string();
    let control_path = owner.path().join("runtime-host.json");
    std::fs::write(&control_path, &control).unwrap();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (reader, mut writer) = socket.into_split();
        let mut lines = BufReader::new(reader).lines();
        let request: serde_json::Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(request["type"], "hello");
        writer
            .write_all(
                format!("{}\n", json!({"id":request["id"],"ok":true,"payload":{}})).as_bytes(),
            )
            .await
            .unwrap();
        assert!(lines.next_line().await.unwrap().is_none());
    });
    let metadata = base64::engine::general_purpose::STANDARD
        .encode(json!({"project":project,"workspace":task}).to_string());
    let error =
        crate::remote_owner_terminal::run(crate::remote_owner_terminal::RemoteOwnerTerminalArgs {
            automation_run_id: None,
            launch_token: None,
            owner: RemoteWorkspaceOwnerArgs {
                state_dir: owner.path().into(),
                metadata_base64: metadata,
            },
            session_id: "session".into(),
            tab_id: "tab".into(),
            cols: 80,
            rows: 24,
        })
        .await
        .unwrap_err();
    assert!(error.to_string().contains("sharedCheckoutWorkspacesV1"));
    assert!(store.find_project(&project.id).await.unwrap().is_none());
    assert!(store.find_workspace(&task.id).await.unwrap().is_none());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_none());
    assert_eq!(std::fs::read_to_string(control_path).unwrap(), control);
    server.await.unwrap();
}

async fn fixture() -> (
    tempfile::TempDir,
    tempfile::TempDir,
    RuntimeStore,
    Project,
    Workspace,
) {
    let home = tempfile::tempdir().unwrap();
    let owner = tempfile::tempdir().unwrap();
    let folder = home.path().join("project");
    std::fs::create_dir(&folder).unwrap();
    let home_store = RuntimeStore::open(&home.path().join("state"))
        .await
        .unwrap();
    let project =
        crate::project_management::register_project(&home_store, folder.to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let task = home_store
        .list_workspaces(&project.id)
        .await
        .unwrap()
        .remove(0);
    let store = RuntimeStore::open(owner.path()).await.unwrap();
    (home, owner, store, project, task)
}

#[tokio::test]
async fn registers_stable_task_identity_without_an_extra_default_workspace() {
    let (_home, owner, store, project, mut task) = fixture().await;
    task.host_id = "home-ssh-target".into();
    let original_id = task.id.clone();
    let original_instance = task.instance_id.clone();
    let created = register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: project.clone(),
            workspace: task.clone(),
        },
    )
    .await
    .unwrap();
    assert_eq!(created.id, original_id);
    assert_eq!(created.instance_id, original_instance);
    assert_eq!(created.host_id, LOCAL_HOST_ID);
    assert_eq!(store.list_workspaces(&project.id).await.unwrap().len(), 1);
    let mut second = task.clone();
    second.id = "second-task".into();
    second.instance_id = "second-instance".into();
    second.name = "Second Task".into();
    register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: project.clone(),
            workspace: second,
        },
    )
    .await
    .unwrap();
    let reopened = RuntimeStore::open(owner.path()).await.unwrap();
    let mut renamed = project.clone();
    renamed.name = "Incoming Name".into();
    let retried = register(
        &reopened,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: renamed,
            workspace: task,
        },
    )
    .await
    .unwrap();
    assert_eq!(retried, created);
    assert_eq!(
        reopened.list_workspaces(&project.id).await.unwrap().len(),
        2
    );
    assert_eq!(
        reopened
            .find_project(&project.id)
            .await
            .unwrap()
            .unwrap()
            .name,
        project.name
    );
}

#[tokio::test]
async fn conflicting_task_and_project_identities_never_replace_owner_state() {
    let (home, _owner, store, project, task) = fixture().await;
    let created = register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: project.clone(),
            workspace: task.clone(),
        },
    )
    .await
    .unwrap();
    let original_project = store.find_project(&project.id).await.unwrap();
    let mut collision = task.clone();
    collision.instance_id = "different-instance".into();
    assert!(register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: project.clone(),
            workspace: collision
        }
    )
    .await
    .is_err());
    let other = home.path().join("other");
    std::fs::create_dir(&other).unwrap();
    let mut collision_project = project.clone();
    collision_project.repo_path = other.to_str().unwrap().into();
    let mut collision_task = task;
    collision_task.id = "different-task".into();
    collision_task.instance_id = "different-instance".into();
    collision_task.path = collision_project.repo_path.clone();
    assert!(register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: collision_project,
            workspace: collision_task
        }
    )
    .await
    .is_err());
    assert_eq!(
        store.find_workspace(&created.id).await.unwrap(),
        Some(created)
    );
    assert_eq!(
        store.find_project(&project.id).await.unwrap(),
        original_project
    );
    assert!(store
        .find_workspace("different-task")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn linked_owner_requires_an_actual_worktree_of_the_registered_repository() {
    let (home, _owner, store, mut project, mut task) = fixture().await;
    let repo = git2::Repository::init(&project.repo_path).unwrap();
    repo.set_head("refs/heads/main").unwrap();
    let tree = repo.index().unwrap().write_tree().unwrap();
    let signature = git2::Signature::now("Test", "test@example.test").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "Initial",
        &repo.find_tree(tree).unwrap(),
        &[],
    )
    .unwrap();
    project.kind = ProjectKind::GitRepository;
    task.kind = WorkspaceKind::Linked;
    let child = std::path::Path::new(&project.repo_path).join("child");
    std::fs::create_dir(&child).unwrap();
    task.path = child.to_str().unwrap().into();
    assert!(register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: project.clone(),
            workspace: task.clone()
        }
    )
    .await
    .is_err());
    assert!(store.find_workspace(&task.id).await.unwrap().is_none());
    let linked = home.path().join("linked");
    alera_core::git::create_worktree(
        &project.repo_path,
        "owner-task",
        linked.to_str().unwrap(),
        "main",
        false,
    )
    .unwrap();
    task.path = linked.to_str().unwrap().into();
    let created = register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            repository_path: None,
            project: project.clone(),
            workspace: task,
        },
    )
    .await
    .unwrap();
    assert_eq!(created.branch.as_deref(), Some("owner-task"));
    assert_eq!(
        store
            .find_workspace_checkout(&created.id)
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .as_deref(),
        Some(project.repo_path.as_str())
    );
}

#[tokio::test]
async fn legacy_bare_origin_survives_registration_beside_a_new_project_checkout() {
    let (home, owner, store, mut project, mut task) = fixture().await;
    git2::Repository::init(&project.repo_path).unwrap();
    project.kind = ProjectKind::GitRepository;
    let bare = home.path().join("legacy.git");
    let repo = git2::Repository::init_bare(&bare).unwrap();
    repo.set_head("refs/heads/main").unwrap();
    let tree = repo.treebuilder(None).unwrap().write().unwrap();
    let signature = git2::Signature::now("Test", "test@example.test").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "Legacy",
        &repo.find_tree(tree).unwrap(),
        &[],
    )
    .unwrap();
    let linked = home.path().join("legacy-worktree");
    alera_core::git::create_worktree(
        bare.to_str().unwrap(),
        "legacy-task",
        linked.to_str().unwrap(),
        "main",
        false,
    )
    .unwrap();
    task.path = linked.to_str().unwrap().into();
    task.kind = WorkspaceKind::Linked;
    let origin = bare.canonicalize().unwrap().to_str().unwrap().to_string();
    let created = register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            project: project.clone(),
            workspace: task.clone(),
            repository_path: Some(origin.clone()),
        },
    )
    .await
    .unwrap();
    assert_eq!(
        store
            .find_project_checkout(&project.id, LOCAL_HOST_ID)
            .await
            .unwrap()
            .unwrap()
            .path,
        project.repo_path
    );
    let reopened = RuntimeStore::open(owner.path()).await.unwrap();
    assert_eq!(
        reopened
            .find_project(&project.id)
            .await
            .unwrap()
            .unwrap()
            .repo_path,
        project.repo_path
    );
    assert_eq!(
        reopened
            .find_workspace_checkout(&task.id)
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .as_deref(),
        Some(origin.as_str())
    );
    assert!(register(
        &reopened,
        RemoteWorkspaceOwnerRegistration {
            project: project.clone(),
            workspace: task.clone(),
            repository_path: Some(project.repo_path.clone())
        }
    )
    .await
    .is_err());
    let retry = register(
        &reopened,
        RemoteWorkspaceOwnerRegistration {
            project,
            workspace: task,
            repository_path: Some(origin),
        },
    )
    .await
    .unwrap();
    assert_eq!(retry, created);
    assert_eq!(
        alera_core::git::current_branch(bare.to_str().unwrap()).unwrap(),
        "main"
    );
    assert_eq!(
        alera_core::git::current_branch(linked.to_str().unwrap()).unwrap(),
        "legacy-task"
    );
}

#[cfg(unix)]
#[tokio::test]
async fn shared_owner_accepts_canonical_alias_of_the_same_origin() {
    let (home, _owner, store, project, task) = fixture().await;
    let alias = home.path().join("alias");
    std::os::unix::fs::symlink(&project.repo_path, &alias).unwrap();
    let result = register(
        &store,
        RemoteWorkspaceOwnerRegistration {
            project: project.clone(),
            workspace: task,
            repository_path: Some(alias.to_str().unwrap().into()),
        },
    )
    .await
    .unwrap();
    assert_eq!(result.path, project.repo_path);
    assert_eq!(
        store
            .find_workspace_checkout(&result.id)
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .as_deref(),
        Some(project.repo_path.as_str())
    );
}
