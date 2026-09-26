//! `alera runtime-attach --stdio` is the satellite end of a hub host link. It
//! must start (or join) the runtime host of its runtime dir, announce the
//! attachment first, and then forward protocol frames verbatim.

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, Stdio};

use alera_core::child_process::windowless_command;
use serde_json::{json, Value};

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

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn runtime_attach_announces_then_forwards_frames() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    let _guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let mut child = ChildGuard(
        windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args([
                "runtime-attach",
                "--stdio",
                "--runtime-dir",
                runtime_dir.to_str().unwrap(),
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    );
    let mut stdin = child.0.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.0.stdout.take().unwrap());

    let mut first = String::new();
    stdout.read_line(&mut first).unwrap();
    let attached: Value = serde_json::from_str(first.trim()).unwrap();
    assert_eq!(attached["event"], "hostLink.attached");
    assert_eq!(attached["payload"]["platform"], std::env::consts::OS);
    let capabilities = attached["payload"]["runtimeCapabilities"]
        .as_array()
        .unwrap();
    assert!(capabilities.iter().any(|c| c == "remoteSatelliteV1"));
    assert!(capabilities.iter().any(|c| c == "remoteHostLinkV1"));

    let request = json!({"id": 7, "type": "status.get", "payload": {}});
    writeln!(stdin, "{request}").unwrap();
    stdin.flush().unwrap();
    let response = loop {
        let mut line = String::new();
        assert!(stdout.read_line(&mut line).unwrap() > 0, "attach closed");
        let frame: Value = serde_json::from_str(line.trim()).unwrap();
        if frame.get("id") == Some(&json!(7)) {
            break frame;
        }
    };
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["runtime"], "alera");

    drop(stdin);
    let status = child.0.wait().unwrap();
    assert_eq!(status.code(), Some(0), "clean hub disconnect exits 0");
}

#[test]
fn runtime_attach_requires_stdio() {
    let dir = tempfile::tempdir().unwrap();
    let output = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "runtime-attach",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("--stdio"));
}
