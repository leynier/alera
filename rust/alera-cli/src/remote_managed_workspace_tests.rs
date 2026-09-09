use std::collections::VecDeque;
use std::path::Path;
use std::process::Command as StdCommand;
use std::sync::Mutex;

use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget, WorkspaceKind,
    LOCAL_HOST_ID,
};
use anyhow::{anyhow, Result};
use chrono::Utc;

use super::{last_nonempty_line, parse_probe_roots, posix_create_script};
use crate::managed_workspace::{create_managed_workspace_with, ManagedWorkspaceCreateRequest};
use crate::ssh_remote::RemoteHostExecutor;

struct ScriptedRemoteHost {
    probe: Option<bool>,
    runs: Mutex<VecDeque<Result<String, String>>>,
    recorded: Mutex<Vec<String>>,
    uploads: Mutex<Vec<String>>,
}

impl ScriptedRemoteHost {
    fn posix(responses: Vec<Result<String, String>>) -> Self {
        Self {
            probe: Some(false),
            runs: Mutex::new(VecDeque::from(responses)),
            recorded: Mutex::new(Vec::new()),
            uploads: Mutex::new(Vec::new()),
        }
    }

    fn unreachable() -> Self {
        Self {
            probe: None,
            runs: Mutex::new(VecDeque::new()),
            recorded: Mutex::new(Vec::new()),
            uploads: Mutex::new(Vec::new()),
        }
    }
}

impl RemoteHostExecutor for ScriptedRemoteHost {
    async fn probe_windows(&self, _target: &SshTarget) -> Option<bool> {
        self.probe
    }

    async fn run(&self, _target: &SshTarget, _windows: bool, script: &str) -> Result<String> {
        self.recorded.lock().unwrap().push(script.to_string());
        match self.runs.lock().unwrap().pop_front() {
            Some(Ok(stdout)) => Ok(stdout),
            Some(Err(error)) => Err(anyhow!(error)),
            None => Ok("/remote/ws\n".to_string()),
        }
    }

    async fn upload(
        &self,
        _target: &SshTarget,
        _local: &std::path::Path,
        remote: &str,
    ) -> Result<()> {
        self.uploads.lock().unwrap().push(remote.to_string());
        Ok(())
    }
}

fn ssh_target(id: &str, status: SshBootstrapStatus) -> SshTarget {
    let now = Utc::now();
    SshTarget {
        id: id.to_string(),
        alias: id.to_string(),
        host: format!("{id}.example.test"),
        port: 22,
        username: "alera".to_string(),
        platform: Some("linux".to_string()),
        arch: None,
        auth_kind: SshAuthKind::Agent,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        runtime_version: None,
        runtime_platform: Some("linux".to_string()),
        runtime_arch: None,
        bootstrap_status: status,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
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
    std::fs::create_dir_all(repo).unwrap();
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

fn create_request(host_id: &str) -> ManagedWorkspaceCreateRequest {
    ManagedWorkspaceCreateRequest {
        id: Some("remote-ws".to_string()),
        project_id: "project-1".to_string(),
        name: Some("feature/remote".to_string()),
        branch: "feature/remote".to_string(),
        source_branch: Some("main".to_string()),
        reuse_existing_branch: false,
        workspace_root: None,
        path: None,
        parent_workspace_id: None,
        host_id: Some(host_id.to_string()),
        defer_setup: false,
        skip_setup: false,
        setup_script_directory: None,
    }
}

#[tokio::test]
async fn create_remote_workspace_records_host_id_and_remote_path() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    init_git_repo(&repo);
    let store = seed_project(dir.path(), &repo).await;
    store
        .upsert_ssh_target(ssh_target("build-mac", SshBootstrapStatus::Installed))
        .await
        .unwrap();
    let host = ScriptedRemoteHost::posix(vec![
        Ok("/home/alera/.alera/workspaces\n/tmp\n".to_string()),
        Ok("/home/alera/.alera/workspaces/repo-project-1/feature-remote\n".to_string()),
    ]);

    let result = create_managed_workspace_with(&store, create_request("build-mac"), &host)
        .await
        .unwrap();

    assert_eq!(result.workspace.host_id, "build-mac");
    assert_eq!(
        result.workspace.path,
        "/home/alera/.alera/workspaces/repo-project-1/feature-remote"
    );
    assert_eq!(result.workspace.kind, WorkspaceKind::Linked);
    assert_eq!(result.workspace.branch.as_deref(), Some("feature/remote"));
    assert!(result.setup_report.steps.is_empty());
    assert!(result.deferred_setup_command.is_none());
    let scripts = host.recorded.lock().unwrap().clone();
    assert!(
        scripts.iter().any(|script| script.contains("worktree add")),
        "{scripts:?}"
    );
    assert!(!host.uploads.lock().unwrap().is_empty());
}

#[tokio::test]
async fn create_remote_workspace_rejects_a_missing_ssh_target() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    init_git_repo(&repo);
    let store = seed_project(dir.path(), &repo).await;
    let host = ScriptedRemoteHost::posix(Vec::new());

    let error = create_managed_workspace_with(&store, create_request("missing-host"), &host)
        .await
        .unwrap_err()
        .to_string();

    assert!(
        error.contains("ssh target not found: missing-host"),
        "{error}"
    );
    assert!(error.contains("alera ssh-target add"), "{error}");
    assert!(host.recorded.lock().unwrap().is_empty());
}

#[tokio::test]
async fn create_remote_workspace_rejects_a_host_that_is_not_bootstrapped() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    init_git_repo(&repo);
    let store = seed_project(dir.path(), &repo).await;
    store
        .upsert_ssh_target(ssh_target("build-mac", SshBootstrapStatus::NotInstalled))
        .await
        .unwrap();
    let host = ScriptedRemoteHost::posix(Vec::new());

    let error = create_managed_workspace_with(&store, create_request("build-mac"), &host)
        .await
        .unwrap_err()
        .to_string();

    assert!(error.contains("not bootstrapped"), "{error}");
    assert!(
        error.contains("alera ssh-target bootstrap --id build-mac"),
        "{error}"
    );
    assert!(host.recorded.lock().unwrap().is_empty());
}

#[tokio::test]
async fn create_remote_workspace_rejects_an_unreachable_host() {
    let dir = tempfile::tempdir().unwrap();
    let repo = dir.path().join("repo");
    init_git_repo(&repo);
    let store = seed_project(dir.path(), &repo).await;
    store
        .upsert_ssh_target(ssh_target("build-mac", SshBootstrapStatus::Installed))
        .await
        .unwrap();
    let host = ScriptedRemoteHost::unreachable();

    let error = create_managed_workspace_with(&store, create_request("build-mac"), &host)
        .await
        .unwrap_err()
        .to_string();

    assert!(error.contains("unreachable"), "{error}");
    assert!(
        error.contains("alera ssh-target status --id build-mac"),
        "{error}"
    );
}

#[test]
fn posix_create_script_invokes_git_worktree_add() {
    let script = posix_create_script(
        "/home/alera/.alera/workspaces/repo.git",
        "/home/alera/.alera/workspaces/repo/feature",
        "/tmp/bundle",
        "feature/x",
        "main",
        false,
    );
    assert!(script.contains("git clone --bare"));
    assert!(script.contains("worktree add"));
    assert!(script.contains("git is not installed"));
}

#[test]
fn probe_roots_parser_reads_two_lines() {
    let parsed = parse_probe_roots("/home/alera/.alera/workspaces\n/tmp\n").unwrap();
    assert_eq!(parsed.0, "/home/alera/.alera/workspaces");
    assert_eq!(parsed.1, "/tmp");
    assert_eq!(
        last_nonempty_line("noise\n/remote/ws\n").as_deref(),
        Some("/remote/ws")
    );
}

#[test]
fn local_host_id_is_not_treated_as_remote_in_this_module() {
    assert_eq!(LOCAL_HOST_ID, "local");
}
