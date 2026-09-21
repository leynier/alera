use super::*;

fn workspace(path: &str) -> Workspace {
    let now = chrono::Utc::now();
    Workspace {
        id: "ws-1".into(),
        instance_id: "instance".into(),
        host_id: alera_core::runtime::LOCAL_HOST_ID.into(),
        project_id: "project-1".into(),
        name: "feature".into(),
        branch: Some("feature".into()),
        path: path.to_string(),
        created_at: now,
        updated_at: now,
        kind: alera_core::runtime::WorkspaceKind::Linked,
        status: alera_core::runtime::WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

#[test]
fn git_path_defaults_to_the_workspace_root() {
    let path = git_path(&workspace("/srv/repo/.worktrees/feature"), &json!({})).unwrap();
    assert_eq!(path, "/srv/repo/.worktrees/feature");
}

#[test]
fn git_path_accepts_a_source_control_root_inside_the_workspace() {
    let path = git_path(
        &workspace("/srv/repo/.worktrees/feature"),
        &json!({ "path": "/srv/repo/.worktrees/feature/packages/app" }),
    )
    .unwrap();
    assert_eq!(path, "/srv/repo/.worktrees/feature/packages/app");
}

#[test]
fn git_path_refuses_a_sibling_that_shares_the_prefix_text() {
    let error = git_path(
        &workspace("/srv/repo/.worktrees/feature"),
        &json!({ "path": "/srv/repo/.worktrees/feature-two" }),
    )
    .unwrap_err();
    assert!(error.to_string().contains("outside workspace"));
}

#[test]
fn git_path_compares_windows_paths_without_case_or_separator_sensitivity() {
    let path = git_path(
        &workspace("C:\\Users\\dev\\repo"),
        &json!({ "path": "c:/users/dev/repo/src" }),
    )
    .unwrap();
    assert_eq!(path, "c:/users/dev/repo/src");
}

#[test]
fn git_errors_are_typed_conflicts_with_their_kind() {
    let error = git_conflict(GitError::new(
        alera_core::git::GitErrorKind::NotARepository,
        "/tmp/nowhere",
    ));
    let response = error.wire_response(7);
    assert_eq!(response["errorCode"], GIT_ERROR_CODE);
    assert_eq!(response["errorDetails"]["kind"], "notARepository");
    assert_eq!(response["error"], "/tmp/nowhere");
}

#[test]
fn status_of_a_fresh_repository_serializes_the_core_shape() {
    let dir = tempfile::tempdir().unwrap();
    let repo = git2::Repository::init(dir.path()).unwrap();
    {
        let mut config = repo.config().unwrap();
        config.set_str("user.name", "Alera Test").unwrap();
        config.set_str("user.email", "alera@example.com").unwrap();
    }
    std::fs::write(dir.path().join("readme.md"), "hello\n").unwrap();
    let path = dir.path().to_string_lossy().into_owned();

    let status = run_git_verb("git.status", path.clone(), &json!({})).unwrap();
    assert_eq!(status["entries"][0]["path"], "readme.md");
    assert_eq!(status["entries"][0]["area"], "untracked");
    assert_eq!(status["entries"][0]["status"], "untracked");

    run_git_verb(
        "git.stage",
        path.clone(),
        &json!({ "filePath": "readme.md" }),
    )
    .unwrap();
    let commit = run_git_verb("git.commit", path.clone(), &json!({ "message": "init" })).unwrap();
    assert_eq!(commit["oid"].as_str().unwrap().len(), 40);

    let state = run_git_verb("git.repositoryState", path.clone(), &json!({})).unwrap();
    assert_eq!(state["headMessage"], "init");
    assert_eq!(state["hasConflicts"], false);

    let history = run_git_verb("git.history", path.clone(), &json!({ "limit": 10 })).unwrap();
    assert_eq!(history["items"][0]["subject"], "init");
    assert_eq!(history["limit"], 10);

    let branches = run_git_verb("git.listBranches", path.clone(), &json!({})).unwrap();
    assert!(!branches.as_array().unwrap().is_empty());

    let explorer = run_git_verb("git.explorerStatus", path, &json!({})).unwrap();
    assert_eq!(explorer["entries"].as_array().unwrap().len(), 0);
}

#[test]
fn a_missing_repository_is_reported_with_the_not_a_repository_kind() {
    let dir = tempfile::tempdir().unwrap();
    let error = run_git_verb(
        "git.status",
        dir.path().to_string_lossy().into_owned(),
        &json!({}),
    )
    .unwrap_err();
    assert_eq!(
        error.wire_response(1)["errorDetails"]["kind"],
        "notARepository"
    );
}
