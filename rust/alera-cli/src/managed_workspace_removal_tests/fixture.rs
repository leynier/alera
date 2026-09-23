use std::path::{Path, PathBuf};
use std::process::Command as StdCommand;

use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationMisfirePolicy,
    AutomationOverlapPolicy, AutomationSchedule, AutomationSetupPolicy, AutomationState,
    AutomationTarget, Project, ProjectKind, RuntimeStore, Workspace,
};
use chrono::Utc;

use crate::managed_workspace::{
    create_managed_workspace, remove_managed_workspace, ManagedWorkspaceCreateRequest,
    ManagedWorkspaceRemoveRequest,
};

pub(super) struct RemovalFixture {
    pub(super) _root: tempfile::TempDir,
    pub(super) repo: PathBuf,
    pub(super) store: RuntimeStore,
    pub(super) worktree_path: PathBuf,
    pub(super) workspace_id: String,
    pub(super) branch: String,
}

impl RemovalFixture {
    pub(super) async fn new(suffix: &str) -> Self {
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
                host_id: None,
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

    pub(super) fn remove_worktree(&self) {
        alera_core::git::remove_worktree(
            &self.repo.to_string_lossy(),
            &self.worktree_path.to_string_lossy(),
            true,
        )
        .unwrap();
    }

    pub(super) fn delete_branch(&self) {
        alera_core::git::delete_branch(&self.repo.to_string_lossy(), &self.branch, true).unwrap();
    }

    pub(super) fn branch_exists(&self) -> bool {
        alera_core::git::branch_exists(&self.repo.to_string_lossy(), &self.branch).unwrap()
    }

    pub(super) async fn workspace_record(&self) -> Option<Workspace> {
        self.store.find_workspace(&self.workspace_id).await.unwrap()
    }

    pub(super) async fn remove_managed_workspace(&self) -> anyhow::Result<Workspace> {
        self.remove_managed_workspace_with(Some(false)).await
    }

    pub(super) async fn remove_managed_workspace_with(
        &self,
        delete_branch: Option<bool>,
    ) -> anyhow::Result<Workspace> {
        remove_managed_workspace(
            &self.store,
            ManagedWorkspaceRemoveRequest {
                id: self.workspace_id.clone(),
                delete_branch,
                active_workspace_id: None,
                close_sessions: false,
            },
        )
        .await
    }
}

pub(super) async fn seed_project(root: &Path, repo: &Path) -> RuntimeStore {
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

pub(super) fn automation_definition(workspace_id: &str) -> AutomationDefinition {
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
        circuit_opened_at: None,
        state: AutomationState::Draft,
        revision: 1,
        approved_revision: None,
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
    }
}

pub(super) fn init_git_repo(repo: &Path) {
    run_git(repo, &["init"]);
    run_git(repo, &["config", "user.email", "test@example.com"]);
    run_git(repo, &["config", "user.name", "Test"]);
    std::fs::write(repo.join("README.md"), "hello\n").unwrap();
    run_git(repo, &["add", "README.md"]);
    run_git(repo, &["commit", "-m", "initial"]);
    run_git(repo, &["branch", "-M", "main"]);
}

#[allow(clippy::disallowed_methods)]
pub(super) fn git_stdout(repo: &Path, args: &[&str]) -> String {
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
    String::from_utf8(output.stdout).unwrap()
}

#[allow(clippy::disallowed_methods)]
pub(super) fn run_git(repo: &Path, args: &[&str]) {
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
