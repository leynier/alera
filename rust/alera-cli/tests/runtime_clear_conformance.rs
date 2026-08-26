#![cfg(unix)]

use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;
use serde_json::Value;

struct ChildGuard(Option<Child>);

impl ChildGuard {
    fn child_mut(&mut self) -> &mut Child {
        self.0.as_mut().unwrap()
    }
}

impl Drop for ChildGuard {
    fn drop(&mut self) {
        if let Some(mut child) = self.0.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[test]
fn clear_refuses_a_live_host_until_force_is_explicit() {
    let root = tempfile::tempdir().unwrap();
    let runtime_dir = root.path().join("runtime");
    let control_path = runtime_dir.join("runtime-host.json");
    let mut host = spawn_host(&runtime_dir, &control_path, "clear-live-token");
    let control = read_control(&control_path);
    let pid = control["pid"].as_u64().unwrap() as u32;

    let refused = clear_command(&runtime_dir, false);

    assert!(!refused.status.success());
    assert!(String::from_utf8_lossy(&refused.stderr).contains("runtime host is running"));
    assert!(process_exists(pid));
    assert!(control_path.exists());

    let cleared = clear_command(&runtime_dir, true);

    assert!(
        cleared.status.success(),
        "{}",
        String::from_utf8_lossy(&cleared.stderr)
    );
    let payload: Value = serde_json::from_slice(&cleared.stdout).unwrap();
    assert_eq!(payload["cleared"], true);
    assert_eq!(payload["forced"], true);
    assert_eq!(payload["hostStopped"], true);
    assert!(wait_for_exit(host.child_mut()).success());
    assert_clean_profile(&runtime_dir);
}

#[test]
fn force_clear_recovers_when_the_live_hosts_control_file_is_missing() {
    let root = tempfile::tempdir().unwrap();
    let runtime_dir = root.path().join("runtime");
    let control_path = runtime_dir.join("host.json");
    let mut host = spawn_host(&runtime_dir, &control_path, "clear-missing-control-token");
    read_control(&control_path);
    std::fs::remove_file(&control_path).unwrap();

    let cleared = clear_command(&runtime_dir, true);

    assert!(
        cleared.status.success(),
        "{}",
        String::from_utf8_lossy(&cleared.stderr)
    );
    let payload: Value = serde_json::from_slice(&cleared.stdout).unwrap();
    assert_eq!(payload["cleared"], true);
    assert_eq!(payload["hostStopped"], true);
    assert!(wait_for_exit(host.child_mut()).success());
    assert_clean_profile(&runtime_dir);
}

fn spawn_host(runtime_dir: &Path, control_path: &Path, token: &str) -> ChildGuard {
    std::fs::create_dir_all(runtime_dir).unwrap();
    let child = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "runtime-host",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            token,
            "--persistent",
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    ChildGuard(Some(child))
}

fn clear_command(runtime_dir: &Path, force: bool) -> std::process::Output {
    let mut command = windowless_command(env!("CARGO_BIN_EXE_alera"));
    command.args([
        "runtime",
        "--runtime-dir",
        runtime_dir.to_str().unwrap(),
        "--json",
        "clear",
    ]);
    if force {
        command.arg("--force");
    }
    command.output().unwrap()
}

fn read_control(path: &Path) -> Value {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Ok(contents) = std::fs::read_to_string(path) {
            if let Ok(value) = serde_json::from_str(&contents) {
                return value;
            }
        }
        assert!(Instant::now() < deadline, "control file was not published");
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn wait_for_exit(child: &mut Child) -> std::process::ExitStatus {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        assert!(Instant::now() < deadline, "runtime host did not exit");
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn assert_clean_profile(runtime_dir: &Path) {
    let entries: Vec<PathBuf> = std::fs::read_dir(runtime_dir)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    assert_eq!(entries, [runtime_dir.join("runtime-owner.lock")]);
}

fn process_exists(pid: u32) -> bool {
    let result = unsafe { libc::kill(pid as i32, 0) };
    result == 0 || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
}
