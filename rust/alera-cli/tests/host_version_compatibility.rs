//! Cross-version conformance for the smallest contract shared with v0.49.0.
//!
//! The current-host direction runs with the normal workspace tests. The
//! previous-host direction is ignored unless `tool/ci/host_compatibility.sh`
//! supplies the binary built from the pinned release tag.

#![cfg(unix)]

use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::Child;
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;
const PROFILE_CAPABILITY: &str = "orchestrationAgentProfilesV1";
const PROFILE_ORDERING_CAPABILITY: &str = "agentProfileOrderingV1";
const V049_COMMIT: &str = "e60c96ec7522052e9af81ab15ae5d6da2443dac4";

struct HostGuard {
    child: Child,
    _runtime: tempfile::TempDir,
}

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn send(writer: &mut TcpStream, message: Value) {
    let mut line = serde_json::to_vec(&message).unwrap();
    line.push(b'\n');
    writer.write_all(&line).unwrap();
    writer.flush().unwrap();
}

fn read_message(reader: &mut BufReader<TcpStream>) -> Value {
    let mut line = String::new();
    let read = reader
        .read_line(&mut line)
        .expect("timed out or failed reading from compatibility host");
    assert!(read > 0, "compatibility host closed the connection");
    serde_json::from_str(line.trim_end()).expect("compatibility host sent invalid JSON")
}

fn read_response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let message = read_message(reader);
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
    }
}

fn spawn_host(
    binary: &str,
    expected_version: Option<&str>,
) -> (HostGuard, TcpStream, BufReader<TcpStream>) {
    let runtime = tempfile::tempdir().unwrap();
    let control_path = runtime.path().join("runtime-host.json");
    let home_path = runtime.path().join("home");
    std::fs::create_dir_all(&home_path).unwrap();
    let token = "cross-version-conformance-token";
    let child = windowless_command(binary)
        .args([
            "terminal-host",
            "--runtime-dir",
            runtime.path().to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            token,
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .env("HOME", &home_path)
        .env("SHELL", "/bin/sh")
        .spawn()
        .expect("failed to spawn compatibility host");
    let guard = HostGuard {
        child,
        _runtime: runtime,
    };
    let deadline = Instant::now() + Duration::from_secs(15);
    let port = loop {
        if let Ok(contents) = std::fs::read_to_string(&control_path) {
            let control: Value = serde_json::from_str(&contents).unwrap();
            assert_eq!(control["protocolVersion"], json!(PROTOCOL_VERSION));
            break control["port"].as_u64().unwrap() as u16;
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    };
    let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    let mut writer = stream.try_clone().unwrap();
    let mut reader = BufReader::new(stream);
    send(
        &mut writer,
        json!({"id": 0, "type": "hello", "payload": {
            "protocolVersion": PROTOCOL_VERSION, "token": token
        }}),
    );
    let hello = read_response(&mut reader, 0);
    assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");

    if let Some(version) = expected_version {
        send(
            &mut writer,
            json!({"id": 1, "type": "status.get", "payload": {}}),
        );
        let status = read_response(&mut reader, 1);
        assert_eq!(status["ok"], json!(true), "status failed: {status}");
        assert_eq!(status["payload"]["runtimeHostVersion"], json!(version));
        assert_eq!(status["payload"]["runtimeHostCommit"], json!(V049_COMMIT));
    }
    (guard, writer, reader)
}

fn assert_v049_baseline(binary: &str, expected_version: Option<&str>) -> Vec<Value> {
    let (_guard, mut writer, mut reader) = spawn_host(binary, expected_version);
    send(
        &mut writer,
        json!({"id": 2, "type": "status.get", "payload": {}}),
    );
    let status = read_response(&mut reader, 2);
    assert_eq!(status["ok"], json!(true), "status failed: {status}");
    assert_eq!(
        status["payload"]["protocolVersion"],
        json!(PROTOCOL_VERSION)
    );
    let capabilities = status["payload"]["runtimeCapabilities"]
        .as_array()
        .expect("status capabilities");
    assert!(capabilities.contains(&json!(PROFILE_CAPABILITY)));

    send(
        &mut writer,
        json!({"id": 3, "type": "agentProfile.upsert", "payload": {
            "name": "Cross Version Profile",
            "agentType": "codex",
            "command": "codex"
        }}),
    );
    let upsert = read_response(&mut reader, 3);
    assert_eq!(upsert["ok"], json!(true), "profile upsert failed: {upsert}");
    send(
        &mut writer,
        json!({"id": 4, "type": "agentProfile.list", "payload": {}}),
    );
    let catalog = read_response(&mut reader, 4);
    assert_eq!(catalog["ok"], json!(true), "profile list failed: {catalog}");
    assert!(catalog["payload"]["items"]
        .as_array()
        .unwrap()
        .iter()
        .any(|profile| profile["name"] == json!("Cross Version Profile")));

    send(
        &mut writer,
        json!({"id": 5, "type": "createOrAttach", "payload": {
            "sessionId": "compat-session",
            "workspaceId": "compat-workspace",
            "tabId": "compat-tab",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-c", "sleep 0.2; printf compat-terminal-ok; sleep 1"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 80,
            "rows": 24
        }}),
    );
    let created = read_response(&mut reader, 5);
    assert_eq!(
        created["ok"],
        json!(true),
        "terminal launch failed: {created}"
    );
    let mut output = Vec::new();
    while !String::from_utf8_lossy(&output).contains("compat-terminal-ok") {
        let message = read_message(&mut reader);
        if message.get("event").and_then(Value::as_str) == Some("output") {
            let encoded = message["payload"]["dataBase64"].as_str().unwrap();
            output.extend_from_slice(&STANDARD.decode(encoded).unwrap());
        }
    }
    capabilities.clone()
}

#[test]
fn current_host_accepts_v049_baseline_contract() {
    assert_v049_baseline(env!("CARGO_BIN_EXE_alera"), None);
}

#[test]
#[ignore = "run through tool/ci/host_compatibility.sh with the pinned v0.49.0 host"]
fn v049_host_accepts_current_baseline_client() {
    let binary = std::env::var("ALERA_PREVIOUS_HOST_BINARY")
        .expect("ALERA_PREVIOUS_HOST_BINARY must name the pinned host");
    let version = std::env::var("ALERA_PREVIOUS_HOST_VERSION")
        .expect("ALERA_PREVIOUS_HOST_VERSION must identify the pinned host");
    let capabilities = assert_v049_baseline(&binary, Some(&version));
    assert!(!capabilities.contains(&json!(PROFILE_ORDERING_CAPABILITY)));
    assert!(!capabilities.contains(&json!("workflowRecipeCatalogV1")));
    assert!(!capabilities.contains(&json!("workflowReviewedPlansV1")));

    let (_guard, mut writer, mut reader) = spawn_host(&binary, Some(&version));
    send(
        &mut writer,
        json!({"id": 6, "type": "agentProfile.reorder", "payload": {"ids": []}}),
    );
    let response = read_response(&mut reader, 6);
    assert_eq!(response["ok"], json!(false));
    assert!(
        response["error"].as_str().is_some_and(
            |error| error.contains("Unknown terminal host request: agentProfile.reorder")
        ),
        "new feature returned an opaque error: {response}"
    );
    send(
        &mut writer,
        json!({"id": 7, "type": "orchestration.taskCreateContracted", "payload": {
            "spec": "Must not become an uncontracted task", "workspace": "compat-workspace",
            "roleContract": {"version": 1}, "contractInputs": {}
        }}),
    );
    let response = read_response(&mut reader, 7);
    assert_eq!(response["ok"], json!(false));
    assert!(
        response["error"].as_str().is_some_and(|error| error
            .contains("Unknown orchestration request: orchestration.taskCreateContracted")),
        "old host silently accepted a contracted task: {response}"
    );
    send(
        &mut writer,
        json!({"id": 8, "type": "orchestration.taskList", "payload": {}}),
    );
    let response = read_response(&mut reader, 8);
    assert_eq!(response["ok"], json!(true));
    assert!(response["payload"]["items"].as_array().unwrap().is_empty());
    send(
        &mut writer,
        json!({"id": 9, "type": "workflows.catalog", "payload": {}}),
    );
    let response = read_response(&mut reader, 9);
    assert_eq!(response["ok"], json!(false));
    assert!(response["error"]
        .as_str()
        .is_some_and(|error| error.contains("Unknown terminal host request: workflows.catalog")));
    for (id, verb) in [(10, "workflows.preparePlan"), (11, "workflows.decide")] {
        send(
            &mut writer,
            json!({"id": id, "type": verb, "payload": {"actor":"app", "document":"{}"}}),
        );
        let response = read_response(&mut reader, id);
        assert_eq!(response["ok"], json!(false), "old host accepted {verb}");
    }
}
