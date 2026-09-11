use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use crate::managed_workspace::{
    measure_workspace_storage, validate_managed_workspace_removal, validate_workspace_storage_path,
    ManagedWorkspaceRemoveRequest,
};

mod automation_tests;
mod fixture;
use fixture::*;

#[tokio::test]
async fn unknown_branch_choice_refuses_without_removing_work() {
    let fixture = RemovalFixture::new("unknown-choice").await;
    let error = fixture
        .remove_managed_workspace_with(None)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("requires a choice"));
    assert!(fixture.worktree_path.exists());
    assert!(fixture.branch_exists());
    assert!(fixture.workspace_record().await.is_some());
}

#[tokio::test]
async fn unmerged_branch_is_kept_when_workspace_is_removed() {
    let fixture = RemovalFixture::new("unmerged").await;
    std::fs::write(fixture.worktree_path.join("feature.txt"), "unique commit").unwrap();
    run_git(&fixture.worktree_path, &["add", "feature.txt"]);
    run_git(&fixture.worktree_path, &["commit", "-m", "feature"]);
    fixture
        .remove_managed_workspace_with(Some(true))
        .await
        .unwrap();
    assert!(!fixture.worktree_path.exists());
    assert!(fixture.branch_exists());
    assert!(fixture.workspace_record().await.is_none());
}

#[tokio::test]
async fn squash_merged_branch_is_deleted_with_workspace() {
    let fixture = RemovalFixture::new("squash").await;
    std::fs::write(fixture.worktree_path.join("feature.txt"), "unique commit").unwrap();
    run_git(&fixture.worktree_path, &["add", "feature.txt"]);
    run_git(&fixture.worktree_path, &["commit", "-m", "feature"]);
    run_git(&fixture.repo, &["merge", "--squash", &fixture.branch]);
    run_git(&fixture.repo, &["commit", "-m", "squash"]);
    fixture
        .remove_managed_workspace_with(Some(true))
        .await
        .unwrap();
    assert!(!fixture.worktree_path.exists());
    assert!(!fixture.branch_exists());
    assert!(fixture.workspace_record().await.is_none());
}

#[tokio::test]
async fn origin_squash_deletes_branch_when_local_default_is_stale() {
    let fixture = RemovalFixture::new("origin-squash").await;
    std::fs::write(fixture.worktree_path.join("feature.txt"), "unique commit").unwrap();
    run_git(&fixture.worktree_path, &["add", "feature.txt"]);
    run_git(&fixture.worktree_path, &["commit", "-m", "feature"]);
    let tree = git_stdout(
        &fixture.repo,
        &["rev-parse", &format!("{}^{{tree}}", fixture.branch)],
    );
    let parent = git_stdout(&fixture.repo, &["rev-parse", "main"]);
    let oid = git_stdout(
        &fixture.repo,
        &[
            "commit-tree",
            tree.trim(),
            "-p",
            parent.trim(),
            "-m",
            "squash",
        ],
    );
    run_git(
        &fixture.repo,
        &["update-ref", "refs/remotes/origin/main", oid.trim()],
    );
    fixture
        .remove_managed_workspace_with(Some(true))
        .await
        .unwrap();
    assert!(!fixture.worktree_path.exists());
    assert!(!fixture.branch_exists());
}

#[tokio::test]
async fn rejects_main_workspace_during_removal_validation() {
    let root = tempfile::tempdir().unwrap();
    let repo = root.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let store = seed_project(root.path(), &repo).await;
    let now = Utc::now();
    store
        .upsert_workspace(Workspace {
            id: "main-workspace".to_string(),
            instance_id: "main-instance".to_string(),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: "project-1".to_string(),
            name: "Main".to_string(),
            branch: Some("main".to_string()),
            path: repo.to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: true,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();

    let error = validate_managed_workspace_removal(
        &store,
        &ManagedWorkspaceRemoveRequest {
            id: "main-workspace".to_string(),
            delete_branch: None,
            active_workspace_id: None,
            close_sessions: false,
        },
    )
    .await
    .unwrap_err();

    assert!(error
        .to_string()
        .contains("main workspace cannot be removed"));
}

#[tokio::test]
async fn recovers_when_worktree_and_branch_are_missing() {
    let fixture = RemovalFixture::new("stale").await;
    fixture.remove_worktree();
    fixture.delete_branch();

    let removed = fixture.remove_managed_workspace().await.unwrap();

    assert_eq!(removed.id, fixture.workspace_id);
    assert!(fixture.workspace_record().await.is_none());
}

#[tokio::test]
async fn keeps_branch_when_live_identity_cannot_be_verified() {
    let fixture = RemovalFixture::new("retry").await;
    fixture.remove_worktree();

    fixture.remove_managed_workspace().await.unwrap();

    assert!(fixture.branch_exists());
    assert!(fixture.workspace_record().await.is_none());
}

#[tokio::test]
async fn keeps_branch_when_worktree_was_removed() {
    let fixture = RemovalFixture::new("keep-branch").await;
    fixture.remove_worktree();

    fixture
        .remove_managed_workspace_with(Some(false))
        .await
        .unwrap();

    assert!(fixture.branch_exists());
    assert!(fixture.workspace_record().await.is_none());
}

#[tokio::test]
async fn preserves_unregistered_filesystem_entry() {
    let fixture = RemovalFixture::new("occupied").await;
    fixture.remove_worktree();
    std::fs::create_dir_all(&fixture.worktree_path).unwrap();
    let sentinel = fixture.worktree_path.join("keep.txt");
    std::fs::write(&sentinel, "keep").unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error.to_string().contains("not a registered Git worktree"));
    assert!(sentinel.exists());
    assert!(fixture.workspace_record().await.is_some());
    assert!(fixture.branch_exists());
}

#[tokio::test]
async fn rejects_workspace_path_outside_host_owned_root() {
    let fixture = RemovalFixture::new("contained").await;
    let outside = fixture._root.path().join("outside");
    std::fs::create_dir_all(&outside).unwrap();
    let mut workspace = fixture.workspace_record().await.unwrap();
    workspace.path = outside.to_string_lossy().into_owned();
    fixture.store.upsert_workspace(workspace).await.unwrap();

    let error = validate_workspace_storage_path(&fixture.store, &fixture.workspace_id)
        .await
        .unwrap_err();

    assert!(error.to_string().contains("outside Alera-managed storage"));
    assert!(outside.exists());
}

#[tokio::test]
async fn removal_rechecks_path_containment_at_destructive_boundary() {
    let fixture = RemovalFixture::new("moved-outside").await;
    let outside = fixture._root.path().join("outside-removal");
    std::fs::create_dir_all(&outside).unwrap();
    let sentinel = outside.join("keep.txt");
    std::fs::write(&sentinel, "keep").unwrap();
    let mut workspace = fixture.workspace_record().await.unwrap();
    workspace.path = outside.to_string_lossy().into_owned();
    fixture.store.upsert_workspace(workspace).await.unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error.to_string().contains("outside Alera-managed storage"));
    assert!(sentinel.exists());
    assert!(fixture.workspace_record().await.is_some());
}

#[tokio::test]
async fn rejects_path_registered_as_another_project_source() {
    let fixture = RemovalFixture::new("second-source").await;
    let now = Utc::now();
    fixture
        .store
        .upsert_project(Project {
            id: "project-2".to_string(),
            name: "Second".to_string(),
            repo_path: fixture.worktree_path.to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error
        .to_string()
        .contains("registered as a project source repository"));
    assert!(fixture.worktree_path.exists());
    assert!(fixture.workspace_record().await.is_some());
}

#[tokio::test]
async fn stale_branch_identity_keeps_the_branch_and_still_removes_the_worktree() {
    let fixture = RemovalFixture::new("stale-branch").await;
    let mut workspace = fixture.workspace_record().await.unwrap();
    workspace.branch = Some("other-branch".to_string());
    fixture.store.upsert_workspace(workspace).await.unwrap();

    fixture
        .remove_managed_workspace_with(Some(true))
        .await
        .unwrap();

    assert!(!fixture.worktree_path.exists());
    assert!(fixture.branch_exists());
    assert!(fixture.workspace_record().await.is_none());
}

#[tokio::test]
async fn rejects_workspace_owned_by_another_host() {
    let fixture = RemovalFixture::new("remote-host").await;
    let mut workspace = fixture.workspace_record().await.unwrap();
    workspace.host_id = "remote".to_string();
    fixture.store.upsert_workspace(workspace).await.unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(
        error
            .to_string()
            .contains("Workspace is not owned by the local host"),
        "{}",
        error
    );
    assert!(fixture.worktree_path.exists());
    assert!(fixture.workspace_record().await.is_some());
}

#[cfg(unix)]
#[tokio::test]
async fn measurement_does_not_follow_workspace_symlinks() {
    use std::os::unix::fs::symlink;

    let fixture = RemovalFixture::new("linked-entry").await;
    let outside = fixture._root.path().join("outside-large");
    std::fs::create_dir_all(&outside).unwrap();
    std::fs::write(outside.join("large.bin"), vec![0_u8; 256 * 1024]).unwrap();
    symlink(&outside, fixture.worktree_path.join("external")).unwrap();

    let impact = measure_workspace_storage(&fixture.store, &fixture.workspace_id, Vec::new())
        .await
        .unwrap();

    assert!(impact.safe_to_clean);
    assert!(impact.size_bytes < 256 * 1024);
}

#[tokio::test]
async fn active_workspace_blocker_disables_cleanup() {
    let fixture = RemovalFixture::new("active").await;

    let impact = measure_workspace_storage(
        &fixture.store,
        &fixture.workspace_id,
        vec!["Workspace is active in the workbench".to_string()],
    )
    .await
    .unwrap();

    assert!(!impact.safe_to_clean);
    assert_eq!(impact.blockers, ["Workspace is active in the workbench"]);
}

#[tokio::test]
async fn missing_orphaned_worktree_is_measured_as_zero_and_remains_cleanable() {
    let fixture = RemovalFixture::new("orphaned").await;
    fixture.remove_worktree();

    let impact = measure_workspace_storage(&fixture.store, &fixture.workspace_id, Vec::new())
        .await
        .unwrap();

    assert!(impact.safe_to_clean);
    assert_eq!(impact.size_bytes, 0);
    assert_eq!(impact.entry_count, 0);
}

#[tokio::test]
async fn successful_cleanup_after_safe_impact_removes_worktree_and_record() {
    let fixture = RemovalFixture::new("cleanup").await;
    let impact = measure_workspace_storage(&fixture.store, &fixture.workspace_id, Vec::new())
        .await
        .unwrap();
    assert!(impact.safe_to_clean);

    fixture.remove_managed_workspace().await.unwrap();

    assert!(!fixture.worktree_path.exists());
    assert!(fixture.workspace_record().await.is_none());
    assert!(fixture.branch_exists());
}
