use super::*;

struct Declaration(Option<bool>);

impl crate::ssh_remote::RemoteHostExecutor for Declaration {
    async fn probe_windows(&self, _: &alera_core::runtime::SshTarget) -> Option<bool> {
        Some(false)
    }
    async fn run(&self, _: &alera_core::runtime::SshTarget, _: bool, _: &str) -> Result<String> {
        Ok(
            serde_json::json!({"version":1,"path":"/fixture/remote","kind":"folder",
            "branch":null,"automationDeclared":self.0})
            .to_string(),
        )
    }
}

#[tokio::test]
async fn automation_preparation_requires_remote_declaration_before_allocating() {
    let state = tempfile::tempdir().unwrap();
    let folder = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(state.path()).await.unwrap();
    let project =
        crate::project_management::register_project(&store, folder.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    store.upsert_ssh_target(serde_json::from_value(serde_json::json!({
        "id":"ssh", "alias":"Fixture", "host":"fixture.invalid", "port":22,
        "username":"fixture", "authKind":"agent", "createdAt":Utc::now(), "updatedAt":Utc::now(),
        "installDir":"/fixture/sidecar", "bootstrapStatus":"installed"
    })).unwrap()).await.unwrap();
    store
        .register_project_checkout(&project.id, "ssh", "/fixture/remote")
        .await
        .unwrap();
    for declaration in [None, Some(false), Some(true)] {
        let mut candidate = request(&project.id, "candidate");
        candidate.host_id = Some("ssh".into());
        let prepared =
            prepare_shared_workspace_with(&store, candidate, &Declaration(declaration), true).await;
        assert_eq!(prepared.is_ok(), declaration == Some(true));
        assert!(store.find_workspace("candidate").await.unwrap().is_none());
    }
    let mut manual = request(&project.id, "manual");
    manual.host_id = Some("ssh".into());
    create_shared_workspace_with(&store, manual, &Declaration(Some(false)))
        .await
        .unwrap();
    assert!(store.find_workspace("manual").await.unwrap().is_some());
}

fn request(project_id: &str, id: &str) -> SharedWorkspaceCreateRequest {
    SharedWorkspaceCreateRequest {
        project_id: project_id.into(),
        id: Some(id.into()),
        name: None,
        host_id: None,
        parent_workspace_id: None,
    }
}

#[tokio::test]
async fn creates_fresh_tasks_on_a_folder_without_touching_files_or_running_setup() {
    let runtime = tempfile::tempdir().unwrap();
    let folder = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(runtime.path()).await.unwrap();
    std::fs::write(folder.path().join("keep.txt"), "original").unwrap();
    std::fs::write(
        folder.path().join("alera.toml"),
        "[worktree]\nsetup = ['invalid-command']",
    )
    .unwrap();
    let project =
        crate::project_management::register_project(&store, folder.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let a = create_shared_workspace(&store, request(&project.id, "a"))
        .await
        .unwrap();
    let b = create_shared_workspace(&store, request(&project.id, "b"))
        .await
        .unwrap();
    assert_ne!(a.workspace.id, b.workspace.id);
    assert_ne!(a.workspace.name, b.workspace.name);
    assert_eq!(a.workspace.path, b.workspace.path);
    assert!(a.workspace.parent_workspace_id.is_none());
    assert!(a.workspace.branch.is_none());
    assert!(a.deferred_setup_command.is_none());
    assert!(store.list_workspace_tabs("a").await.unwrap().is_empty());
    assert_eq!(
        std::fs::read_to_string(folder.path().join("keep.txt")).unwrap(),
        "original"
    );
    let retry = create_shared_workspace(&store, request(&project.id, "a"))
        .await
        .unwrap();
    assert_eq!(retry.workspace, a.workspace);
    assert_eq!(store.list_workspaces(&project.id).await.unwrap().len(), 3);
}

#[tokio::test]
async fn missing_checkout_does_not_remove_existing_tasks() {
    let runtime = tempfile::tempdir().unwrap();
    let folder = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(runtime.path()).await.unwrap();
    let project =
        crate::project_management::register_project(&store, folder.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    folder.close().unwrap();
    let error = create_shared_workspace(&store, request(&project.id, "new"))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("unavailable"));
    assert_eq!(store.list_workspaces(&project.id).await.unwrap().len(), 1);
}

#[tokio::test]
async fn invalid_parent_does_not_leave_a_workspace() {
    let runtime = tempfile::tempdir().unwrap();
    let folder = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(runtime.path()).await.unwrap();
    let project =
        crate::project_management::register_project(&store, folder.path().to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let mut create = request(&project.id, "new");
    create.parent_workspace_id = Some("missing".into());
    assert!(create_shared_workspace(&store, create).await.is_err());
    assert!(store.find_workspace("new").await.unwrap().is_none());
}
