use super::*;

fn prepare(state: &Path, request: &Value) -> Value {
    let encoded =
        base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(request).unwrap());
    success(cli(
        state,
        "project",
        &[
            "relocate-owner-workspace",
            "--state-dir",
            state.to_str().unwrap(),
            "--request-base64",
            &encoded,
            "--prepare-only",
        ],
    ))
}

#[tokio::test]
async fn owner_preparation_resolves_its_default_path_without_mutating_git_or_task_location() {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    repository(&folder);
    let state = root.path().join("owner");
    let managed = root.path().join("owner-managed");
    std::fs::create_dir(&managed).unwrap();
    let store = alera_core::runtime::RuntimeStore::open(&state)
        .await
        .unwrap();
    store
        .set_workspace_directory(Some(managed.to_str().unwrap()))
        .await
        .unwrap();
    let _guard = HostGuard(state.clone());
    success(cli(&state, "runtime", &["start"]));
    let registered = success(cli(
        &state,
        "project",
        &[
            "add",
            "--name",
            "Task",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    ));
    let workspace = registered["initialWorkspace"].clone();
    std::fs::write(folder.join("retained.txt"), "pending source changes\n").unwrap();
    std::fs::write(folder.join(".worktreeinclude"), "owner.env\n").unwrap();
    std::fs::write(folder.join(".git/info/exclude"), "owner.env\n").unwrap();
    std::fs::write(folder.join("owner.env"), "owner-local fixture\n").unwrap();
    let request = json!({"workspace":workspace,"relocationId":uuid::Uuid::new_v4(),
        "setupConfig":{"newWorkspace":{"promptAppend":"Home snapshot"}},
        "intent":{"workspaceId":workspace["id"],"toProjectCheckout":false,"destinationPath":null,"branch":"prepared-topic","replacementBranch":null,"moveChanges":false,"sharedImpactConfirmed":true}});
    let prepared = prepare(&state, &request);
    let recipe = store
        .find_relocation_setup(request["relocationId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recipe.config.new_workspace.prompt_append, "Home snapshot");
    assert!(recipe
        .config
        .worktree
        .copy
        .iter()
        .any(|rule| rule.from == "owner.env"));
    assert!(recipe.report.is_none());
    assert_eq!(prepared["prepared"], true);
    assert_eq!(prepared["relocation"]["phase"], "prepared");
    let destination = PathBuf::from(
        prepared["relocation"]["destination"]["path"]
            .as_str()
            .unwrap(),
    );
    assert!(destination.starts_with(std::fs::canonicalize(&managed).unwrap()));
    assert!(!destination.exists());
    assert_eq!(
        git2::Repository::open(&folder)
            .unwrap()
            .worktrees()
            .unwrap()
            .len(),
        0
    );
    assert_eq!(
        alera_core::git::current_branch(folder.to_str().unwrap()).unwrap(),
        "main"
    );
    assert_eq!(
        std::fs::read_to_string(folder.join("retained.txt")).unwrap(),
        "pending source changes\n"
    );
    assert_eq!(
        store
            .find_workspace(workspace["id"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .path,
        workspace["path"].as_str().unwrap()
    );
    let changed_default = root.path().join("changed-default");
    std::fs::create_dir(&changed_default).unwrap();
    store
        .set_workspace_directory(Some(changed_default.to_str().unwrap()))
        .await
        .unwrap();
    assert_eq!(
        prepare(&state, &request)["relocation"],
        prepared["relocation"]
    );
    let mut changed = request.clone();
    changed["setupConfig"]["newWorkspace"]["promptAppend"] = json!("Later configuration");
    prepare(&state, &changed);
    assert_eq!(
        store
            .find_relocation_setup(request["relocationId"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .config,
        recipe.config
    );
    let mut execution = request.clone();
    execution.as_object_mut().unwrap().remove("setupConfig");
    execution["intent"]["destinationPath"] = json!(destination);
    let moved = success(relocate(&state, &execution));
    assert_eq!(moved["relocation"]["id"], prepared["relocation"]["id"]);
    assert_eq!(
        moved["workspace"]["path"],
        prepared["relocation"]["destination"]["path"]
    );
    assert_eq!(moved["workspace"]["instanceId"], workspace["instanceId"]);
    assert_eq!(
        std::fs::read_to_string(folder.join("retained.txt")).unwrap(),
        "pending source changes\n"
    );
    std::fs::write(folder.join("retained.txt"), "original\n").unwrap();
    std::fs::remove_file(folder.join(".worktreeinclude")).unwrap();
    assert_eq!(
        std::fs::read_to_string(destination.join("owner.env")).unwrap(),
        "owner-local fixture\n"
    );
    std::fs::remove_file(destination.join("owner.env")).unwrap();
    let on_request = json!({"workspace":moved["workspace"],"relocationId":uuid::Uuid::new_v4(),
        "intent":{"workspaceId":workspace["id"],"toProjectCheckout":true,"destinationPath":null,"branch":null,"replacementBranch":null,"moveChanges":true,"sharedImpactConfirmed":true}});
    #[cfg(unix)]
    {
        let backup = root.path().join("original-worktree");
        let foreign = root.path().join("foreign-folder");
        std::fs::create_dir(&foreign).unwrap();
        std::fs::write(foreign.join("keep.txt"), "unrelated content").unwrap();
        std::fs::rename(&destination, &backup).unwrap();
        std::os::unix::fs::symlink(&foreign, &destination).unwrap();
        let rejected = relocate(&state, &on_request);
        assert!(!rejected.status.success());
        assert_eq!(
            std::fs::read_to_string(foreign.join("keep.txt")).unwrap(),
            "unrelated content"
        );
        assert_eq!(
            store
                .find_workspace(workspace["id"].as_str().unwrap())
                .await
                .unwrap()
                .unwrap()
                .path,
            destination.to_str().unwrap()
        );
        std::fs::remove_file(&destination).unwrap();
        std::fs::rename(&backup, &destination).unwrap();
        let git_pointer = destination.join(".git");
        let original_pointer = std::fs::read(&git_pointer).unwrap();
        std::fs::write(
            &git_pointer,
            format!("gitdir: {}\n", folder.join(".git").display()),
        )
        .unwrap();
        assert!(!alera_core::git::is_workspace_relocation_worktree(
            folder.to_str().unwrap(),
            destination.to_str().unwrap(),
            prepared["relocation"]["id"].as_str().unwrap(),
        )
        .unwrap_or(false));
        let rejected = relocate(&state, &on_request);
        assert!(!rejected.status.success());
        std::fs::write(&git_pointer, original_pointer).unwrap();
        assert!(alera_core::git::is_workspace_relocation_worktree(
            folder.to_str().unwrap(),
            destination.to_str().unwrap(),
            prepared["relocation"]["id"].as_str().unwrap(),
        )
        .unwrap());
    }
    let returned = success(relocate(&state, &on_request));
    assert_eq!(returned["workspace"]["path"], workspace["path"]);
    assert!(!destination.exists());
}

#[cfg(unix)]
#[tokio::test]
async fn owner_preparation_canonicalizes_a_symbolic_storage_root_without_creating_the_worktree() {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    repository(&folder);
    let managed = root.path().join("managed");
    std::fs::create_dir(&managed).unwrap();
    let alias = root.path().join("alias");
    std::os::unix::fs::symlink(&managed, &alias).unwrap();
    let state = root.path().join("owner");
    let _guard = HostGuard(state.clone());
    success(cli(&state, "runtime", &["start"]));
    let registered = success(cli(
        &state,
        "project",
        &[
            "add",
            "--name",
            "Task",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    ));
    let workspace = registered["initialWorkspace"].clone();
    let request = json!({"workspace":workspace,"relocationId":uuid::Uuid::new_v4(),"workspaceRoot":alias,
        "intent":{"workspaceId":workspace["id"],"toProjectCheckout":false,"destinationPath":null,"branch":"topic","replacementBranch":null,"moveChanges":false,"sharedImpactConfirmed":true}});
    let prepared = prepare(&state, &request);
    let destination = PathBuf::from(
        prepared["relocation"]["destination"]["path"]
            .as_str()
            .unwrap(),
    );
    assert!(destination.starts_with(std::fs::canonicalize(&managed).unwrap()));
    assert!(!destination.exists());
    assert_eq!(
        git2::Repository::open(&folder)
            .unwrap()
            .worktrees()
            .unwrap()
            .len(),
        0
    );
}
