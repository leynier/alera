use super::*;

#[tokio::test]
async fn shared_folders_and_remote_paths_never_run_local_worktree_setup() {
    let directory = tempfile::tempdir().unwrap();
    let folder = directory.path().join("project");
    std::fs::create_dir(&folder).unwrap();
    let command = if cfg!(windows) {
        "echo unsafe > forbidden"
    } else {
        "printf unsafe > forbidden"
    };
    std::fs::write(
        folder.join("alera.toml"),
        format!(
            "[worktree]\nsetup = [{}]\n",
            serde_json::to_string(command).unwrap()
        ),
    )
    .unwrap();
    let store = RuntimeStore::open(&directory.path().join("state"))
        .await
        .unwrap();
    let project =
        crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let workspace = store.list_workspaces(&project.id).await.unwrap().remove(0);
    let config = effective_project_config(&store, &project).await.unwrap();
    assert!(!config.worktree.setup.is_empty());
    let error = run_workspace_setup(&store, &workspace.id, false)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("shared project folders"));
    let mut remote = workspace.clone();
    remote.host_id = "ssh".into();
    remote.kind = alera_core::runtime::WorkspaceKind::Linked;
    for task in [&workspace, &remote] {
        let report = run_worktree_setup(&store, &project, task).await;
        assert!(!report.steps[0].succeeded);
        let report = run_setup_config(&store, &project, task, &config, true, None).await;
        assert!(!report.steps[0].succeeded);
        let (report, command) = prepare_deferred_worktree_setup(
            &store,
            &project,
            task,
            Some(&directory.path().join("scripts")),
        )
        .await;
        assert!(!report.steps[0].succeeded);
        assert!(command.is_none());
        assert!(!folder.join("forbidden").exists());
        assert!(!directory.path().join("scripts").exists());
    }
}
