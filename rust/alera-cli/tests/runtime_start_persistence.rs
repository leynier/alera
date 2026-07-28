#![cfg(unix)]

use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use serde_json::Value;

struct RuntimeGuard {
    runtime_dir: PathBuf,
}

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
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

#[test]
fn runtime_start_survives_its_launching_pty_closing() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let _guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let pty = native_pty_system();
    let pair = pty
        .openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })
        .unwrap();
    let mut command = CommandBuilder::new(env!("CARGO_BIN_EXE_alera"));
    for argument in [
        "runtime",
        "--runtime-dir",
        runtime_dir.to_str().unwrap(),
        "start",
    ] {
        command.arg(argument);
    }
    let mut child = pair.slave.spawn_command(command).unwrap();
    drop(pair.slave);
    assert!(child.wait().unwrap().success());

    let control_path = runtime_dir.join("runtime-host.json");
    let before = read_control(&control_path);
    let pid = before["pid"].as_u64().unwrap() as u32;
    assert_eq!(before["persistent"], true);
    drop(pair.master);
    std::thread::sleep(Duration::from_millis(500));
    assert!(process_exists(pid), "runtime host died when its PTY closed");

    let output = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "runtime",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "--json",
            "status",
        ])
        .output()
        .unwrap();
    assert!(output.status.success());
    let status: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(status["running"], true);
    assert_eq!(status["host"]["persistent"], true);
    let after = read_control(&control_path);
    assert_eq!(after["pid"], before["pid"], "runtime host was restarted");
    assert_eq!(after["persistent"], true);
}

#[test]
fn runtime_start_promotes_an_existing_host_without_restarting_it() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let _runtime_guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let control_path = runtime_dir.join("runtime-host.json");
    let child = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "runtime-host",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            "promotion-test-token",
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let _child_guard = ChildGuard(child);
    let before = read_control(&control_path);
    assert_eq!(before["persistent"], false);

    let output = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "runtime",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "--json",
            "start",
        ])
        .output()
        .unwrap();
    assert!(output.status.success());
    let status: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(status["persistent"], true);
    let after = read_control(&control_path);
    assert_eq!(after["persistent"], true);
    assert_eq!(after["pid"], before["pid"], "runtime host was restarted");
    assert!(process_exists(after["pid"].as_u64().unwrap() as u32));
}

fn read_control(path: &Path) -> Value {
    let deadline = Instant::now() + Duration::from_secs(10);
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

fn process_exists(pid: u32) -> bool {
    let result = unsafe { libc::kill(pid as i32, 0) };
    result == 0 || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
}
