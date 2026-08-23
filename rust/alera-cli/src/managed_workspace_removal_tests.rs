use std::path::Path;
use std::process::Command as StdCommand;

use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationMisfirePolicy,
    AutomationOccurrence, AutomationOverlapPolicy, AutomationRunTrigger, AutomationSchedule,
    AutomationSetupPolicy, AutomationState, AutomationTarget, Project, ProjectKind, RuntimeStore,
    Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use crate::managed_workspace::{
    create_managed_workspace, measure_workspace_storage, remove_managed_workspace,
    validate_managed_workspace_removal, validate_workspace_storage_path,
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
            active_workspace_id: None,
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
async fn rejects_stale_branch_identity_before_cleanup() {
    let fixture = RemovalFixture::new("stale-branch").await;
    let mut workspace = fixture.workspace_record().await.unwrap();
    workspace.branch = Some("main".to_string());
    fixture.store.upsert_workspace(workspace).await.unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error.to_string().contains("branch does not match"));
    assert!(fixture.worktree_path.exists());
    assert!(fixture.branch_exists());
}

#[tokio::test]
async fn rejects_workspace_owned_by_another_host() {
    let fixture = RemovalFixture::new("remote-host").await;
    let mut workspace = fixture.workspace_record().await.unwrap();
    workspace.host_id = "remote".to_string();
    fixture.store.upsert_workspace(workspace).await.unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error.to_string().contains("not owned by the local host"));
    assert!(fixture.worktree_path.exists());
}

#[tokio::test]
async fn rejects_workspace_owned_by_an_active_automation_run() {
    let fixture = RemovalFixture::new("automation-run").await;
    let definition = automation_definition(&fixture.workspace_id);
    let actor = definition.created_by.clone();
    fixture
        .store
        .upsert_automation(definition.clone(), actor)
        .await
        .unwrap();
    fixture
        .store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "manual|cleanup-owner".to_string(),
                scheduled_at: Utc::now(),
                local_time: "UTC".to_string(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();

    let error = fixture.remove_managed_workspace().await.unwrap_err();

    assert!(error.to_string().contains("active automation"));
    assert!(fixture.worktree_path.exists());
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
    assert!(!fixture.branch_exists());
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
                active_workspace_id: None,
            },
        )
        .await
    }
}

async fn seed_project(root: &Path, repo: &Path) -> RuntimeStore {
    let store = RuntimeStore::open(&root.join("runtime")).await.unwrap();
    let workspace_root = root.join("workspaces");
    std::fs::create_dir_all(&workspace_root).unwrap();
    store
        .set_workspace_directory(Some(&workspace_root.to_string_lossy()))
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
}

fn automation_definition(workspace_id: &str) -> AutomationDefinition {
    let now = Utc::now();
    let actor = AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    };
    AutomationDefinition {
        id: "cleanup-owner".to_string(),
        slug: "cleanup-owner".to_string(),
        name: "Cleanup Owner".to_string(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Run".to_string(),
        schedule: AutomationSchedule::OneTime {
            at: now + chrono::Duration::hours(1),
            timezone: "UTC".to_string(),
        },
        target: AutomationTarget::FreshTab {
            workspace_id: workspace_id.to_string(),
            agent_profile_id: "profile".to_string(),
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: AutomationOverlapPolicy::Skip,
        queue_cap: 10,
        inactivity_timeout_seconds: 7200,
        heartbeat_interval_seconds: 60,
        misfire_grace_seconds: 900,
        misfire_policy: AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 60,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 900,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        state: AutomationState::Draft,
        revision: 1,
        approved_revision: None,
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
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
