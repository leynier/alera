use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Barrier};
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;
use serde_json::Value;

struct HostGuard(Option<Child>);

impl HostGuard {
    fn new(child: Child) -> Self {
        Self(Some(child))
    }

    fn child_mut(&mut self) -> &mut Child {
        self.0.as_mut().unwrap()
    }

    fn stop(&mut self) {
        let Some(mut child) = self.0.take() else {
            return;
        };
        let _ = child.kill();
        let _ = child.wait();
    }
}

impl Drop for HostGuard {
    fn drop(&mut self) {
        self.stop();
    }
}

fn host_command(runtime_dir: &Path, control_path: &Path, token: &str) -> Command {
    let mut command = windowless_command(env!("CARGO_BIN_EXE_alera"));
    command.args([
        "runtime-host",
        "--runtime-dir",
        runtime_dir.to_str().unwrap(),
        "--control-file",
        control_path.to_str().unwrap(),
        "--token",
        token,
        "--empty-shutdown-delay-seconds",
        "60",
        "--detached-session-shutdown-delay-seconds",
        "60",
    ]);
    command
}

fn spawn_host(runtime_dir: &Path, control_path: &Path, token: &str) -> Child {
    host_command(runtime_dir, control_path, token)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap()
}

fn read_control_for_pid(path: &Path, pid: u32) -> Value {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Ok(contents) = std::fs::read_to_string(path) {
            if let Ok(value) = serde_json::from_str::<Value>(&contents) {
                if value["pid"].as_u64() == Some(u64::from(pid)) {
                    return value;
                }
            }
        }
        assert!(
            Instant::now() < deadline,
            "control file was not published for process {pid}"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn wait_for_exit(child: &mut Child) -> std::process::ExitStatus {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        assert!(Instant::now() < deadline, "child did not exit");
        std::thread::sleep(Duration::from_millis(25));
    }
}

#[test]
fn concurrent_runtime_hosts_leave_exactly_one_owner() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let barrier = Arc::new(Barrier::new(3));

    let spawn = |token: &'static str,
                 barrier: Arc<Barrier>,
                 runtime_dir: PathBuf,
                 control_path: PathBuf| {
        std::thread::spawn(move || {
            barrier.wait();
            spawn_host(&runtime_dir, &control_path, token)
        })
    };
    let first = spawn(
        "first-token",
        barrier.clone(),
        runtime_dir.clone(),
        control_path.clone(),
    );
    let second = spawn(
        "second-token",
        barrier.clone(),
        runtime_dir.clone(),
        control_path.clone(),
    );
    barrier.wait();
    let mut hosts = [
        HostGuard::new(first.join().unwrap()),
        HostGuard::new(second.join().unwrap()),
    ];

    let deadline = Instant::now() + Duration::from_secs(15);
    let loser = loop {
        let exited: Vec<usize> = hosts
            .iter_mut()
            .enumerate()
            .filter_map(|(index, host)| {
                host.child_mut()
                    .try_wait()
                    .unwrap()
                    .map(|status| (index, status))
            })
            .map(|(index, status)| {
                assert!(!status.success(), "duplicate host unexpectedly succeeded");
                index
            })
            .collect();
        if exited.len() == 1 {
            break exited[0];
        }
        assert!(exited.is_empty(), "both concurrent hosts exited");
        assert!(Instant::now() < deadline, "neither concurrent host exited");
        std::thread::sleep(Duration::from_millis(25));
    };
    let winner = 1 - loser;
    assert!(hosts[winner].child_mut().try_wait().unwrap().is_none());
    let winner_pid = hosts[winner].child_mut().id();
    assert_eq!(
        read_control_for_pid(&control_path, winner_pid)["pid"],
        winner_pid
    );
    let owner: Value = serde_json::from_str(
        &std::fs::read_to_string(runtime_dir.join("runtime-owner.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(owner["pid"], winner_pid);
}

#[test]
fn duplicate_start_preserves_live_control_and_owner_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let mut owner = HostGuard::new(spawn_host(&runtime_dir, &control_path, "owner-token"));
    read_control_for_pid(&control_path, owner.child_mut().id());
    let control_before = std::fs::read(&control_path).unwrap();
    let owner_path = runtime_dir.join("runtime-owner.json");
    let owner_before = std::fs::read(&owner_path).unwrap();

    let mut challenger = spawn_host(&runtime_dir, &control_path, "challenger-token");
    let status = wait_for_exit(&mut challenger);

    assert!(!status.success());
    assert!(owner.child_mut().try_wait().unwrap().is_none());
    assert_eq!(std::fs::read(control_path).unwrap(), control_before);
    assert_eq!(std::fs::read(owner_path).unwrap(), owner_before);
}

fn assert_invalid_handoff_is_rejected(
    runtime_dir: &Path,
    control_path: &Path,
    owner: &mut HostGuard,
    handoff_pid: u32,
    handoff_start_marker: u64,
) {
    let control_before = std::fs::read(control_path).unwrap();
    let owner_path = runtime_dir.join("runtime-owner.json");
    let owner_before = std::fs::read(&owner_path).unwrap();
    let mut command = host_command(runtime_dir, control_path, "invalid-handoff-token");
    let handoff_pid = handoff_pid.to_string();
    let handoff_start_marker = handoff_start_marker.to_string();
    command.args([
        "--handoff-owner-pid",
        &handoff_pid,
        "--handoff-owner-start-marker",
        &handoff_start_marker,
    ]);
    let output = command.output().unwrap();

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("refusing replacement"));
    assert!(owner.child_mut().try_wait().unwrap().is_none());
    assert_eq!(std::fs::read(control_path).unwrap(), control_before);
    assert_eq!(std::fs::read(owner_path).unwrap(), owner_before);
}

#[test]
fn handoff_rejects_the_wrong_owner_pid_without_modifying_live_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let mut owner = HostGuard::new(spawn_host(&runtime_dir, &control_path, "owner-token"));
    read_control_for_pid(&control_path, owner.child_mut().id());
    let owner_record: Value = serde_json::from_str(
        &std::fs::read_to_string(runtime_dir.join("runtime-owner.json")).unwrap(),
    )
    .unwrap();
    let owner_pid = owner.child_mut().id();

    assert_invalid_handoff_is_rejected(
        &runtime_dir,
        &control_path,
        &mut owner,
        owner_pid.checked_add(1).unwrap(),
        owner_record["processStartMarker"].as_u64().unwrap(),
    );
}

#[test]
fn handoff_rejects_the_wrong_start_marker_without_modifying_live_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let mut owner = HostGuard::new(spawn_host(&runtime_dir, &control_path, "owner-token"));
    read_control_for_pid(&control_path, owner.child_mut().id());
    let owner_record: Value = serde_json::from_str(
        &std::fs::read_to_string(runtime_dir.join("runtime-owner.json")).unwrap(),
    )
    .unwrap();
    let owner_pid = owner.child_mut().id();

    assert_invalid_handoff_is_rejected(
        &runtime_dir,
        &control_path,
        &mut owner,
        owner_pid,
        owner_record["processStartMarker"]
            .as_u64()
            .unwrap()
            .checked_add(1)
            .unwrap(),
    );
}

#[test]
fn client_start_fails_safely_when_live_control_metadata_is_incompatible() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let mut owner = HostGuard::new(spawn_host(&runtime_dir, &control_path, "owner-token"));
    let mut incompatible = read_control_for_pid(&control_path, owner.child_mut().id());
    incompatible["protocolVersion"] = Value::from(-1);
    let incompatible = serde_json::to_vec(&incompatible).unwrap();
    std::fs::write(&control_path, &incompatible).unwrap();
    let owner_before = std::fs::read(runtime_dir.join("runtime-owner.json")).unwrap();

    let output = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "runtime",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "start",
        ])
        .output()
        .unwrap();

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("Refusing to start a duplicate host"));
    assert!(owner.child_mut().try_wait().unwrap().is_none());
    assert_eq!(std::fs::read(control_path).unwrap(), incompatible);
    assert_eq!(
        std::fs::read(runtime_dir.join("runtime-owner.json")).unwrap(),
        owner_before
    );
}

#[test]
fn stale_owner_is_recovered_after_the_process_exits() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let mut first = HostGuard::new(spawn_host(&runtime_dir, &control_path, "first-token"));
    let first_pid = first.child_mut().id();
    read_control_for_pid(&control_path, first_pid);
    first.stop();

    let mut replacement =
        HostGuard::new(spawn_host(&runtime_dir, &control_path, "replacement-token"));
    let replacement_pid = replacement.child_mut().id();
    let control = read_control_for_pid(&control_path, replacement_pid);
    let owner: Value = serde_json::from_str(
        &std::fs::read_to_string(runtime_dir.join("runtime-owner.json")).unwrap(),
    )
    .unwrap();

    assert_ne!(first_pid, replacement_pid);
    assert_eq!(control["pid"], replacement_pid);
    assert_eq!(control["token"], "replacement-token");
    assert_eq!(owner["pid"], replacement_pid);
    assert!(replacement.child_mut().try_wait().unwrap().is_none());
}
