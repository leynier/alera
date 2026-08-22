use std::path::Path;
use std::process::Command as StdCommand;

use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use crate::managed_workspace::{
    create_managed_workspace, remove_managed_workspace, validate_managed_workspace_removal,
    ManagedWorkspaceCreateRequest, ManagedWorkspaceRemoveRequest,
};

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
            child_count: 0,
        })
        .await
        .unwrap();

    let error = validate_managed_workspace_removal(
        &store,
        &ManagedWorkspaceRemoveRequest {
            id: "main-workspace".to_string(),
            delete_branch: None,
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
async fn deletes_branch_after_worktree_was_removed() {
    let fixture = RemovalFixture::new("retry").await;
    fixture.remove_worktree();

    fixture.remove_managed_workspace().await.unwrap();

    assert!(!fixture.branch_exists());
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

    assert!(error.to_string().contains("git worktree remove failed"));
    assert!(sentinel.exists());
    assert!(fixture.workspace_record().await.is_some());
    assert!(fixture.branch_exists());
}

struct RemovalFixture {
    _root: tempfile::TempDir,
    repo: std::path::PathBuf,
    store: RuntimeStore,
    worktree_path: std::path::PathBuf,
    workspace_id: String,
    branch: String,
}

impl RemovalFixture {
    async fn new(suffix: &str) -> Self {
        let root = tempfile::tempdir().unwrap();
        let repo = root.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        let store = seed_project(root.path(), &repo).await;
        let worktree_path = root.path().join("workspaces").join(suffix);
        let workspace_id = format!("workspace-{suffix}");
        let branch = format!("feature/{suffix}");
        create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some(workspace_id.clone()),
                project_id: "project-1".to_string(),
                name: Some(branch.clone()),
                branch: branch.clone(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: None,
                defer_setup: false,
                skip_setup: false,
                setup_script_directory: None,
            },
        )
        .await
        .unwrap();
        Self {
            _root: root,
            repo,
            store,
            worktree_path,
            workspace_id,
            branch,
        }
    }

    fn remove_worktree(&self) {
        alera_core::git::remove_worktree(
            &self.repo.to_string_lossy(),
            &self.worktree_path.to_string_lossy(),
            true,
        )
        .unwrap();
    }

    fn delete_branch(&self) {
        alera_core::git::delete_branch(&self.repo.to_string_lossy(), &self.branch, true).unwrap();
    }

    fn branch_exists(&self) -> bool {
        alera_core::git::branch_exists(&self.repo.to_string_lossy(), &self.branch).unwrap()
    }

    async fn workspace_record(&self) -> Option<alera_core::runtime::Workspace> {
        self.store.find_workspace(&self.workspace_id).await.unwrap()
    }

    async fn remove_managed_workspace(&self) -> anyhow::Result<alera_core::runtime::Workspace> {
        self.remove_managed_workspace_with(None).await
    }

    async fn remove_managed_workspace_with(
        &self,
        delete_branch: Option<bool>,
    ) -> anyhow::Result<alera_core::runtime::Workspace> {
        remove_managed_workspace(
            &self.store,
            ManagedWorkspaceRemoveRequest {
                id: self.workspace_id.clone(),
                delete_branch,
            },
        )
        .await
    }
}

async fn seed_project(root: &Path, repo: &Path) -> RuntimeStore {
    let store = RuntimeStore::open(&root.join("runtime")).await.unwrap();
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
