use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

use alera_core::git;
use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use super::{
    hand_off_managed_workspace, hand_on_managed_workspace, ManagedWorkspaceHandOffRequest,
    ManagedWorkspaceHandOnRequest,
};

#[tokio::test]
async fn hand_off_moves_dirty_main_work_into_a_child_worktree() {
    let fixture = Fixture::new().await;
    std::fs::write(fixture.repo.join("scratch.txt"), "from-main\n").unwrap();
    std::fs::write(fixture.repo.join("tracked.txt"), "edited\n").unwrap();

    let worktree_path = fixture.child_path("hand-off-dirty");
    let result = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".to_string(),
            branch: "feat/hand-off".to_string(),
            name: Some("Hand Off Dirty".to_string()),
            reuse_existing_branch: false,
            workspace_root: None,
            path: Some(worktree_path.to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap();

    assert_eq!(result.workspace.kind, WorkspaceKind::Linked);
    assert_eq!(result.workspace.branch.as_deref(), Some("feat/hand-off"));
    assert_eq!(
        result.workspace.parent_workspace_id.as_deref(),
        Some("main")
    );
    assert_eq!(
        git::current_branch(fixture.repo.to_str().unwrap()).unwrap(),
        "main"
    );
    assert!(git::is_worktree_clean(fixture.repo.to_str().unwrap()).unwrap());
    assert!(!fixture.repo.join("scratch.txt").exists());
    assert_eq!(
        std::fs::read_to_string(fixture.repo.join("tracked.txt")).unwrap(),
        "initial\n"
    );
    assert_eq!(
        git::current_branch(worktree_path.to_str().unwrap()).unwrap(),
        "feat/hand-off"
    );
    assert_eq!(
        std::fs::read_to_string(worktree_path.join("scratch.txt")).unwrap(),
        "from-main\n"
    );
    assert_eq!(
        std::fs::read_to_string(worktree_path.join("tracked.txt")).unwrap(),
        "edited\n"
    );
}

#[tokio::test]
async fn hand_off_moves_a_feature_branch_off_the_main_worktree() {
    let fixture = Fixture::new().await;
    fixture.run_git(&["checkout", "-b", "feat/current"]);
    std::fs::write(fixture.repo.join("scratch.txt"), "on-feature\n").unwrap();

    let worktree_path = fixture.child_path("hand-off-branch");
    let result = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".to_string(),
            branch: "feat/current".to_string(),
            name: Some("Current Feature".to_string()),
            reuse_existing_branch: true,
            workspace_root: None,
            path: Some(worktree_path.to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap();

    assert_eq!(result.workspace.branch.as_deref(), Some("feat/current"));
    assert_eq!(
        git::current_branch(fixture.repo.to_str().unwrap()).unwrap(),
        "main"
    );
    assert!(git::is_worktree_clean(fixture.repo.to_str().unwrap()).unwrap());
    assert_eq!(
        git::current_branch(worktree_path.to_str().unwrap()).unwrap(),
        "feat/current"
    );
    assert_eq!(
        std::fs::read_to_string(worktree_path.join("scratch.txt")).unwrap(),
        "on-feature\n"
    );
    let main = fixture.store.find_workspace("main").await.unwrap().unwrap();
    assert_eq!(main.branch.as_deref(), Some("main"));
}

#[tokio::test]
async fn hand_on_brings_child_work_back_onto_main() {
    let fixture = Fixture::new().await;
    std::fs::write(fixture.repo.join("scratch.txt"), "round-trip\n").unwrap();
    let worktree_path = fixture.child_path("hand-on-child");
    let created = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".to_string(),
            branch: "feat/round-trip".to_string(),
            name: Some("Round Trip".to_string()),
            reuse_existing_branch: false,
            workspace_root: None,
            path: Some(worktree_path.to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap();
    std::fs::write(worktree_path.join("later.txt"), "after-hand-off\n").unwrap();

    let result = hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: created.workspace.id.clone(),
            close_sessions: true,
            active_workspace_id: None,
        },
    )
    .await
    .unwrap();

    assert_eq!(result.removed_workspace_id, created.workspace.id);
    assert_eq!(result.workspace.kind, WorkspaceKind::Main);
    assert_eq!(result.workspace.branch.as_deref(), Some("feat/round-trip"));
    assert_eq!(
        git::current_branch(fixture.repo.to_str().unwrap()).unwrap(),
        "feat/round-trip"
    );
    assert_eq!(
        std::fs::read_to_string(fixture.repo.join("scratch.txt")).unwrap(),
        "round-trip\n"
    );
    assert_eq!(
        std::fs::read_to_string(fixture.repo.join("later.txt")).unwrap(),
        "after-hand-off\n"
    );
    assert!(!worktree_path.exists());
    assert!(fixture
        .store
        .find_workspace(&created.workspace.id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn hand_off_rejects_a_child_workspace() {
    let fixture = Fixture::new().await;
    let worktree_path = fixture.child_path("not-main");
    let created = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".to_string(),
            branch: "feat/child".to_string(),
            name: Some("Child".to_string()),
            reuse_existing_branch: false,
            workspace_root: None,
            path: Some(worktree_path.to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap();

    let error = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: created.workspace.id,
            branch: "feat/other".to_string(),
            name: None,
            reuse_existing_branch: false,
            workspace_root: None,
            path: None,
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.to_lowercase().contains("main worktree"), "{error}");
}

#[tokio::test]
async fn hand_on_rejects_the_main_workspace() {
    let fixture = Fixture::new().await;
    let error = hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: "main".to_string(),
            close_sessions: true,
            active_workspace_id: None,
        },
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.to_lowercase().contains("child worktree"), "{error}");
}

#[tokio::test]
async fn hand_on_rejects_a_dirty_main_worktree() {
    let fixture = Fixture::new().await;
    let worktree_path = fixture.child_path("blocked-child");
    let created = hand_off_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOffRequest {
            id: "main".to_string(),
            branch: "feat/blocked".to_string(),
            name: Some("Blocked".to_string()),
            reuse_existing_branch: false,
            workspace_root: None,
            path: Some(worktree_path.to_string_lossy().into_owned()),
            defer_setup: false,
            setup_script_directory: None,
        },
    )
    .await
    .unwrap();
    std::fs::write(fixture.repo.join("main-dirty.txt"), "nope\n").unwrap();

    let error = hand_on_managed_workspace(
        &fixture.store,
        ManagedWorkspaceHandOnRequest {
            id: created.workspace.id,
            close_sessions: true,
            active_workspace_id: None,
        },
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.to_lowercase().contains("local changes"), "{error}");
    assert!(worktree_path.exists());
}

struct Fixture {
    store: RuntimeStore,
    repo: PathBuf,
    root: PathBuf,
    _dir: tempfile::TempDir,
}

impl Fixture {
    async fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        std::fs::write(repo.join("tracked.txt"), "initial\n").unwrap();
        run_git(&repo, &["add", "tracked.txt"]);
        run_git(&repo, &["commit", "-m", "add tracked"]);

        let store = RuntimeStore::open(&dir.path().join("runtime"))
            .await
            .unwrap();
        let workspaces = dir.path().join("workspaces");
        std::fs::create_dir_all(&workspaces).unwrap();
        store
            .set_workspace_directory(Some(workspaces.to_str().unwrap()))
            .await
            .unwrap();
        let now = Utc::now();
        store
            .upsert_project(Project {
                id: "project-1".to_string(),
                name: "Project".to_string(),
                repo_path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
            .upsert_workspace(Workspace {
                id: "main".to_string(),
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
                reuses_existing_branch: false,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                section_id: None,
                child_count: 0,
            })
            .await
            .unwrap();
        Self {
            store,
            repo,
            root: dir.path().to_path_buf(),
            _dir: dir,
        }
    }

    fn child_path(&self, name: &str) -> PathBuf {
        self.root.join("workspaces").join(name)
    }

    fn run_git(&self, args: &[&str]) {
        run_git(&self.repo, args);
    }
}

fn init_git_repo(repo: &Path) {
    run_git(repo, &["init"]);
    run_git(repo, &["config", "user.email", "test@example.com"]);
    run_git(repo, &["config", "user.name", "Test"]);
    std::fs::write(repo.join("README.md"), "hello\n").unwrap();
    run_git(repo, &["add", "README.md"]);
    run_git(repo, &["commit", "-m", "initial"]);
    run_git(repo, &["branch", "-M", "main"]);
}

#[allow(clippy::disallowed_methods)]
fn run_git(repo: &Path, args: &[&str]) {
    let output = StdCommand::new("git")
        .args(args)
        .current_dir(repo)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {} failed\nstdout:\n{}\nstderr:\n{}",
        args.join(" "),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
