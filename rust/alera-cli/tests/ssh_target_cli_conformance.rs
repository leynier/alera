//! CLI coverage for `alera ssh-target remove` when the target is missing.

mod agent_integration_home_isolation;

use std::path::Path;
use std::process::{Child, Output};
use std::time::{Duration, Instant};

use agent_integration_home_isolation::alera_command_with_isolated_home;
use serde_json::{json, Value};

struct HostGuard(Child);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn run_ssh_target(runtime_dir: &Path, args: &[&str]) -> Output {
    alera_command_with_isolated_home(runtime_dir)
        .arg("ssh-target")
        .arg("--runtime-dir")
        .arg(runtime_dir)
        .arg("--json")
        .args(args)
        .output()
        .expect("failed to run alera ssh-target")
}

fn success_json(runtime_dir: &Path, args: &[&str]) -> Value {
    let output = run_ssh_target(runtime_dir, args);
    assert!(
        output.status.success(),
        "command failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("command did not return JSON")
}

fn add_target(runtime_dir: &Path, id: &str) -> Value {
    success_json(
        runtime_dir,
        &[
            "add",
            "--id",
            id,
            "--alias",
            "Build Mac",
            "--host",
            "mac.example.test",
            "--username",
            "alera",
            "--auth",
            "agent",
        ],
    )
}

fn assert_missing_id_error(output: &Output, id: &str) {
    let expected = format!("ssh target not found: {id}");
    assert!(
        !output.status.success(),
        "missing-id command should fail: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "json error path should leave stdout empty: {}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains(&expected),
        "stderr should match status/bootstrap-plan: {stderr}"
    );
}

fn spawn_host(runtime_dir: &Path) -> HostGuard {
    std::fs::create_dir_all(runtime_dir).unwrap();
    let control_path = runtime_dir.join("host.json");
    let child = alera_command_with_isolated_home(runtime_dir)
        .args([
            "runtime-host",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            "ssh-remove-missing-token",
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .spawn()
        .expect("failed to spawn alera runtime-host");
    let guard = HostGuard(child);
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Ok(contents) = std::fs::read_to_string(&control_path) {
            if serde_json::from_str::<Value>(&contents)
                .ok()
                .and_then(|value| value.get("port").and_then(Value::as_u64))
                .is_some()
            {
                return guard;
            }
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn remove_existing_then_missing(runtime_dir: &Path) {
    let added = add_target(runtime_dir, "remote-1");
    assert_eq!(added["id"], json!("remote-1"));

    let removed = success_json(runtime_dir, &["remove", "--id", "remote-1"]);
    assert_eq!(removed, json!({ "id": "remote-1" }));

    let listed = success_json(runtime_dir, &["list"]);
    assert_eq!(listed["items"], json!([]));

    let already_gone = run_ssh_target(runtime_dir, &["remove", "--id", "remote-1"]);
    assert_missing_id_error(&already_gone, "remote-1");

    let missing = run_ssh_target(runtime_dir, &["remove", "--id", "definitely-missing-637"]);
    assert_missing_id_error(&missing, "definitely-missing-637");

    let status = run_ssh_target(runtime_dir, &["status", "--id", "definitely-missing-637"]);
    assert_missing_id_error(&status, "definitely-missing-637");
}

#[test]
fn ssh_target_remove_rejects_missing_id_through_the_store() {
    let dir = tempfile::tempdir().unwrap();
    remove_existing_then_missing(dir.path());
}

#[test]
fn ssh_target_remove_rejects_missing_id_through_the_runtime_host() {
    let dir = tempfile::tempdir().unwrap();
    let _host = spawn_host(dir.path());
    remove_existing_then_missing(dir.path());
}
