#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use alera_core::child_process::windowless_command;
use serde_json::Value;

struct RuntimeGuard {
    runtime_dir: PathBuf,
}

impl Drop for RuntimeGuard {
    fn drop(&mut self) {
        let _ = windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args([
                "runtime",
                "--runtime-dir",
                self.runtime_dir.to_str().unwrap(),
                "stop",
                "--force",
            ])
            .output();
    }
}

fn alera(runtime_dir: &Path, args: &[&str]) -> Output {
    let (group, rest) = args.split_first().expect("command group required");
    windowless_command(env!("CARGO_BIN_EXE_alera"))
        .arg(group)
        .arg("--runtime-dir")
        .arg(runtime_dir)
        .arg("--json")
        .args(rest)
        .output()
        .expect("failed to run alera")
}

fn success_json(runtime_dir: &Path, args: &[&str]) -> Value {
    let output = alera(runtime_dir, args);
    assert!(
        output.status.success(),
        "command failed: args={args:?} stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("command did not return JSON")
}

fn init_git_repo(repo: &Path) {
    for args in [
        ["init"].as_slice(),
        ["config", "user.email", "test@example.com"].as_slice(),
        ["config", "user.name", "Test"].as_slice(),
    ] {
        run_git(repo, args);
    }
    std::fs::write(repo.join("README.md"), "hello\n").unwrap();
    run_git(repo, &["add", "README.md"]);
    run_git(repo, &["commit", "-m", "initial"]);
    run_git(repo, &["branch", "-M", "main"]);
}

fn run_git(repo: &Path, args: &[&str]) {
    #[allow(clippy::disallowed_methods)]
    let output = Command::new("git")
        .args(args)
        .current_dir(repo)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {} failed\n{}",
        args.join(" "),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn write_recorder(dir: &Path, marker: &Path) -> PathBuf {
    let path = dir.join("record-launch.sh");
    std::fs::write(
        &path,
        format!("#!/bin/sh\nprintf X >> {}\nsleep 30\n", marker.display()),
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&path).unwrap().permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(&path, permissions).unwrap();
    path
}

#[test]
fn workspace_start_and_profile_launch_create_a_tab_snapshot() {
    let temp = tempfile::tempdir().unwrap();
    let runtime_dir = temp.path().join("runtime");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let _guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let repo = temp.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let marker = temp.path().join("launched.txt");
    let recorder = write_recorder(temp.path(), &marker);

    let project = success_json(
        &runtime_dir,
        &[
            "project",
            "add",
            "--name",
            "Launch Project",
            "--repo-path",
            repo.to_str().unwrap(),
            "--kind",
            "git-repository",
        ],
    );
    let project_id = project["id"].as_str().unwrap();

    success_json(
        &runtime_dir,
        &[
            "agent-profile",
            "create",
            "--name",
            "Recorder",
            "--agent-type",
            "codex",
            "--launch-mode",
            "command",
            "--command",
            recorder.to_str().unwrap(),
        ],
    );

    let started = success_json(
        &runtime_dir,
        &[
            "workspace",
            "start",
            "--profile",
            "Recorder",
            "--prompt",
            "Add dark mode",
            "--project-id",
            project_id,
            "--source-branch",
            "main",
            "--branch",
            "feat/dark-mode",
            "--name",
            "Dark Mode",
            "--no-parent",
            "--workspace-root",
            temp.path().join("workspaces").to_str().unwrap(),
        ],
    );
    assert_eq!(started["branch"], "feat/dark-mode");
    assert_eq!(started["profileName"], "Recorder");
    assert_eq!(
        started["tab"]["payload"]["agentProfileLaunchV1"]["profile"]["name"],
        "Recorder"
    );
    let workspace_id = started["workspaceId"].as_str().unwrap();
    assert!(!started["tabId"].as_str().unwrap().is_empty());

    let launched = success_json(
        &runtime_dir,
        &[
            "agent-profile",
            "launch",
            "--workspace",
            workspace_id,
            "--profile",
            "Recorder",
            "--prompt",
            "Fix the flaky test",
        ],
    );
    assert_eq!(launched["workspaceId"], workspace_id);
    assert_eq!(launched["profileName"], "Recorder");
    assert_ne!(launched["tabId"], started["tabId"]);
}

#[test]
fn workspace_start_rejects_unknown_profile_before_creating_a_worktree() {
    let temp = tempfile::tempdir().unwrap();
    let runtime_dir = temp.path().join("runtime");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let _guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let repo = temp.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let project = success_json(
        &runtime_dir,
        &[
            "project",
            "add",
            "--name",
            "Missing Profile Project",
            "--repo-path",
            repo.to_str().unwrap(),
            "--kind",
            "git-repository",
        ],
    );
    let project_id = project["id"].as_str().unwrap();
    let failed = alera(
        &runtime_dir,
        &[
            "workspace",
            "start",
            "--profile",
            "Missing",
            "--prompt",
            "Should not create a workspace",
            "--project-id",
            project_id,
            "--source-branch",
            "main",
            "--branch",
            "feat/missing-profile",
            "--name",
            "Missing Profile",
            "--no-parent",
            "--workspace-root",
            temp.path().join("workspaces").to_str().unwrap(),
        ],
    );
    assert!(
        !failed.status.success(),
        "unknown profile should fail: {}",
        String::from_utf8_lossy(&failed.stderr)
    );
    let listed = success_json(&runtime_dir, &["workspace", "list", "--all"]);
    let items = listed["items"].as_array().cloned().unwrap_or_default();
    assert!(
        items
            .iter()
            .all(|workspace| { workspace["branch"].as_str() != Some("feat/missing-profile") }),
        "unknown profile created a workspace: {listed}"
    );
}

#[test]
fn orchestration_delegate_creates_a_task_for_the_declared_profile() {
    let temp = tempfile::tempdir().unwrap();
    let runtime_dir = temp.path().join("runtime");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let _guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let repo = temp.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    let marker = temp.path().join("delegated.txt");
    let recorder = write_recorder(temp.path(), &marker);

    let project = success_json(
        &runtime_dir,
        &[
            "project",
            "add",
            "--name",
            "Delegate Project",
            "--repo-path",
            repo.to_str().unwrap(),
            "--kind",
            "git-repository",
        ],
    );
    let project_id = project["id"].as_str().unwrap();
    success_json(
        &runtime_dir,
        &[
            "agent-profile",
            "create",
            "--name",
            "Worker",
            "--agent-type",
            "codex",
            "--launch-mode",
            "command",
            "--command",
            recorder.to_str().unwrap(),
        ],
    );
    let workspace = success_json(
        &runtime_dir,
        &[
            "workspace",
            "add",
            "--project-id",
            project_id,
            "--branch",
            "feat/delegate",
            "--source-branch",
            "main",
            "--name",
            "Delegate",
            "--workspace-root",
            temp.path().join("workspaces").to_str().unwrap(),
        ],
    );
    let workspace_id = workspace["workspace"]["id"].as_str().unwrap();

    let delegated = alera(
        &runtime_dir,
        &[
            "orchestration",
            "delegate",
            "--workspace",
            workspace_id,
            "--profile",
            "Worker",
            "--spec",
            "Review test coverage",
            "--from",
            "coordinator-1",
            "--timeout-ms",
            "1000",
            "--keep-on-failure",
        ],
    );
    let payload: Value = serde_json::from_slice(&delegated.stdout).unwrap_or(Value::Null);
    assert!(
        payload.get("taskId").and_then(Value::as_str).is_some(),
        "delegate stdout={} stderr={}",
        String::from_utf8_lossy(&delegated.stdout),
        String::from_utf8_lossy(&delegated.stderr)
    );
    assert_eq!(payload["profileName"], "Worker");
    assert_eq!(payload["workspaceId"], workspace_id);
    assert_eq!(payload["profileName"], "Worker");
    assert_eq!(payload["spawn"]["taskId"], payload["taskId"]);
    if let Some(recorded) = payload
        .pointer("/spawn/dispatch/agentProfile")
        .and_then(Value::as_str)
    {
        assert_eq!(recorded, "Worker");
    }
    let task = success_json(
        &runtime_dir,
        &[
            "orchestration",
            "task-show",
            "--id",
            payload["taskId"].as_str().unwrap(),
        ],
    );
    assert_eq!(task["task"]["id"], payload["taskId"]);
}
