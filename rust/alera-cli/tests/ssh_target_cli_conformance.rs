//! CLI coverage for `alera ssh-target` missing-id, duplicate-alias, and
//! password-auth errors.

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

fn add_target_args<'a>(id: &'a str, alias: &'a str) -> [&'a str; 11] {
    [
        "add",
        "--id",
        id,
        "--alias",
        alias,
        "--host",
        "mac.example.test",
        "--username",
        "alera",
        "--auth",
        "agent",
    ]
}

fn add_target(runtime_dir: &Path, id: &str) -> Value {
    success_json(runtime_dir, &add_target_args(id, "Build Mac"))
}

const PASSWORD_BOOTSTRAP_UNSUPPORTED: &str =
    "password SSH targets are not supported for bootstrap; configure SSH agent or key authentication.";

fn password_add_args<'a>(id: &'a str, alias: &'a str) -> [&'a str; 11] {
    [
        "add",
        "--id",
        id,
        "--alias",
        alias,
        "--host",
        "192.168.1.66",
        "--username",
        "leynier",
        "--auth",
        "password",
    ]
}

fn seed_password_target(runtime_dir: &Path, id: &str) {
    let now = chrono::Utc::now();
    let target = alera_core::runtime::SshTarget {
        id: id.to_string(),
        alias: id.to_string(),
        host: "192.168.1.66".to_string(),
        port: 22,
        username: "leynier".to_string(),
        platform: None,
        arch: None,
        auth_kind: alera_core::runtime::SshAuthKind::Password,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: Default::default(),
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    };
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let store = alera_core::runtime::RuntimeStore::open(runtime_dir)
                .await
                .unwrap();
            store.upsert_ssh_target(target).await.unwrap();
        });
}

fn assert_json_error(output: &Output, expected: &str) {
    assert!(
        !output.status.success(),
        "command should fail: stdout={} stderr={}",
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
        stderr.contains(expected),
        "stderr should match the product error: {stderr}"
    );
    let combined = format!("{}{}", String::from_utf8_lossy(&output.stdout), stderr);
    assert!(
        !combined.contains("UNIQUE")
            && !combined.contains("2067")
            && !combined.to_lowercase().contains("sqlite"),
        "user-facing output leaked a SQLite unique-constraint: {combined}"
    );
}

fn assert_missing_id_error(output: &Output, id: &str) {
    assert_json_error(output, &format!("ssh target not found: {id}"));
}

fn assert_duplicate_alias_error(output: &Output, alias: &str) {
    assert_json_error(output, &format!("ssh target alias already exists: {alias}"));
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

fn reject_duplicate_aliases(runtime_dir: &Path) {
    let added = success_json(runtime_dir, &add_target_args("remote-1", "audit-637-mac"));
    assert_eq!(added["id"], json!("remote-1"));
    assert_eq!(added["alias"], json!("audit-637-mac"));

    let exact = run_ssh_target(runtime_dir, &add_target_args("remote-2", "audit-637-mac"));
    assert_duplicate_alias_error(&exact, "audit-637-mac");

    let nocase = run_ssh_target(runtime_dir, &add_target_args("remote-3", "Audit-637-mac"));
    assert_duplicate_alias_error(&nocase, "Audit-637-mac");

    let listed = success_json(runtime_dir, &["list"]);
    assert_eq!(listed["items"].as_array().map(Vec::len), Some(1));

    let free = success_json(runtime_dir, &add_target_args("remote-4", "build-linux"));
    assert_eq!(free["alias"], json!("build-linux"));
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

#[test]
fn ssh_target_add_rejects_duplicate_alias_through_the_store() {
    let dir = tempfile::tempdir().unwrap();
    reject_duplicate_aliases(dir.path());
}

#[test]
fn ssh_target_add_rejects_duplicate_alias_through_the_runtime_host() {
    let dir = tempfile::tempdir().unwrap();
    let _host = spawn_host(dir.path());
    reject_duplicate_aliases(dir.path());
}

fn reject_password_add(runtime_dir: &Path) {
    let output = run_ssh_target(
        runtime_dir,
        &password_add_args("audit-674-pass", "audit-674-pass"),
    );
    assert_json_error(&output, PASSWORD_BOOTSTRAP_UNSUPPORTED);

    let listed = success_json(runtime_dir, &["list"]);
    assert_eq!(listed["items"], json!([]));
}

fn reject_password_bootstrap_plan(runtime_dir: &Path) {
    seed_password_target(runtime_dir, "audit-674-pass");
    let output = run_ssh_target(runtime_dir, &["bootstrap-plan", "--id", "audit-674-pass"]);
    assert_json_error(&output, PASSWORD_BOOTSTRAP_UNSUPPORTED);
}

#[test]
fn ssh_target_add_rejects_password_auth_through_the_store() {
    let dir = tempfile::tempdir().unwrap();
    reject_password_add(dir.path());
}

#[test]
fn ssh_target_add_rejects_password_auth_through_the_runtime_host() {
    let dir = tempfile::tempdir().unwrap();
    let _host = spawn_host(dir.path());
    reject_password_add(dir.path());
}

#[test]
fn ssh_target_bootstrap_plan_rejects_password_auth_through_the_store() {
    let dir = tempfile::tempdir().unwrap();
    reject_password_bootstrap_plan(dir.path());
}

#[test]
fn ssh_target_bootstrap_plan_rejects_password_auth_through_the_runtime_host() {
    let dir = tempfile::tempdir().unwrap();
    seed_password_target(dir.path(), "audit-674-pass");
    let _host = spawn_host(dir.path());
    let output = run_ssh_target(dir.path(), &["bootstrap-plan", "--id", "audit-674-pass"]);
    assert_json_error(&output, PASSWORD_BOOTSTRAP_UNSUPPORTED);
}
