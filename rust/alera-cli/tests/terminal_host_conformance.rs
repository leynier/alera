//! End-to-end protocol conformance test. Spawns the real `alera terminal-host`
//! binary, connects over the loopback socket it advertises, and drives the full
//! request/event sequence the Dart app relies on.

use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::Child;
use std::time::{Duration, Instant};

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;

/// Kills the host process when the test ends, regardless of assertions.
struct HostGuard(Child);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn read_control(path: &std::path::Path) -> Option<(u16, String)> {
    let contents = std::fs::read_to_string(path).ok()?;
    let value: Value = serde_json::from_str(&contents).ok()?;
    let port = value.get("port")?.as_u64()? as u16;
    let token = value.get("token")?.as_str()?.to_string();
    Some((port, token))
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
        .expect("timed out or failed reading from host");
    assert!(read > 0, "host closed the connection unexpectedly");
    serde_json::from_str(line.trim_end()).expect("host sent invalid JSON")
}

fn read_message_with_timeout(
    reader: &mut BufReader<TcpStream>,
    timeout: Duration,
) -> Option<Value> {
    reader.get_mut().set_read_timeout(Some(timeout)).unwrap();
    let mut line = String::new();
    let result = reader.read_line(&mut line);
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    match result {
        Ok(0) => panic!("host closed the connection unexpectedly"),
        Ok(_) => Some(serde_json::from_str(line.trim_end()).expect("host sent invalid JSON")),
        Err(error)
            if error.kind() == std::io::ErrorKind::WouldBlock
                || error.kind() == std::io::ErrorKind::TimedOut =>
        {
            None
        }
        Err(error) => panic!("timed out or failed reading from host: {error}"),
    }
}

fn connect(port: u16) -> (TcpStream, BufReader<TcpStream>) {
    let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    let writer = stream.try_clone().unwrap();
    (writer, BufReader::new(stream))
}

fn read_response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let message = read_message(reader);
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
    }
}

/// Appends an `output` event's bytes to `sink`. Returns whether it was one.
fn collect_output(message: &Value, sink: &mut Vec<u8>) -> bool {
    if message.get("event").and_then(Value::as_str) != Some("output") {
        return false;
    }
    let encoded = message["payload"]["dataBase64"].as_str().unwrap();
    sink.extend_from_slice(&STANDARD.decode(encoded).unwrap());
    true
}

fn read_output_until(reader: &mut BufReader<TcpStream>, sink: &mut Vec<u8>, needle: &str) {
    while !String::from_utf8_lossy(sink).contains(needle) {
        let message = read_message(reader);
        collect_output(&message, sink);
    }
}

fn handshake(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, token: &str) {
    send(
        writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": PROTOCOL_VERSION, "token": token}}),
    );
    let hello = read_message(reader);
    assert_eq!(hello["id"], json!(0));
    assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");
}

fn create_long_running_session(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    session_id: &str,
    workspace_id: &str,
    tab_id: &str,
) {
    send(
        writer,
        json!({
            "id": id,
            "type": "createOrAttach",
            "payload": {
                "sessionId": session_id,
                "workspaceId": workspace_id,
                "tabId": tab_id,
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": ["-c", "sleep 30"],
                    "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
                },
                "cols": 80,
                "rows": 24
            }
        }),
    );
    let created = read_response(reader, id);
    assert_eq!(
        created["ok"],
        json!(true),
        "createOrAttach failed: {created}"
    );
    assert_eq!(created["payload"]["running"], json!(true));
}

fn assert_session_is_not_attached(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    session_id: &str,
) {
    send(
        writer,
        json!({
            "id": id,
            "type": "write",
            "payload": {
                "sessionId": session_id,
                "dataBase64": STANDARD.encode(b"ignored")
            }
        }),
    );
    let write = read_response(reader, id);
    assert_eq!(write["ok"], json!(false), "write succeeded: {write}");
    assert!(
        write["error"]
            .as_str()
            .is_some_and(|error| error.contains("Terminal session is not attached")),
        "unexpected write error: {write}"
    );
}

/// Spawn a host against the given runtime dir / control file and wait until it
/// publishes its loopback port.
fn spawn_host(
    runtime_dir: &std::path::Path,
    control_path: &std::path::Path,
    token: &str,
) -> (HostGuard, u16) {
    spawn_host_with_env(runtime_dir, control_path, token, &[])
}

fn spawn_host_with_env(
    runtime_dir: &std::path::Path,
    control_path: &std::path::Path,
    token: &str,
    env: &[(&str, &str)],
) -> (HostGuard, u16) {
    let mut command = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"));
    command.args([
        "terminal-host",
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
    for (key, value) in env {
        command.env(key, value);
    }
    let child = command
        .spawn()
        .expect("failed to spawn alera terminal-host");
    let guard = HostGuard(child);
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some((port, _)) = read_control(control_path) {
            return (guard, port);
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn ssh_target_payload(id: &str, bootstrap_status: &str) -> Value {
    json!({
        "id": id,
        "alias": "Test Remote",
        "host": "example.invalid",
        "port": 22,
        "username": "tester",
        "platform": "linux",
        "arch": "x64",
        "authKind": "agent",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z",
        "lastStatus": null,
        "installDir": null,
        "runtimeVersion": null,
        "runtimePlatform": null,
        "runtimeArch": null,
        "bootstrapStatus": bootstrap_status,
        "lastBootstrapAt": null,
        "lastCheckedAt": null,
        "lastError": null,
    })
}

fn fake_blocking_ssh_path(root: &std::path::Path) -> String {
    let bin_dir = root.join("fake-bin");
    std::fs::create_dir_all(&bin_dir).unwrap();
    let ssh_path = bin_dir.join("ssh");
    std::fs::write(&ssh_path, "#!/bin/sh\nsleep 30\n").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        let mut permissions = std::fs::metadata(&ssh_path).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&ssh_path, permissions).unwrap();
    }
    let current_path = std::env::var("PATH").unwrap_or_default();
    format!("{}:{current_path}", bin_dir.display())
}

fn fake_ready_ssh_path(root: &std::path::Path) -> String {
    let bin_dir = root.join("fake-ready-bin");
    std::fs::create_dir_all(&bin_dir).unwrap();
    let ssh_path = bin_dir.join("ssh");
    std::fs::write(&ssh_path, "#!/bin/sh\nprintf '/tmp/alera-runtime\\n'\n").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        let mut permissions = std::fs::metadata(&ssh_path).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&ssh_path, permissions).unwrap();
    }
    let current_path = std::env::var("PATH").unwrap_or_default();
    format!("{}:{current_path}", bin_dir.display())
}

#[test]
fn full_protocol_sequence() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "test-token";

    let child = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "terminal-host",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            token,
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .spawn()
        .expect("failed to spawn alera terminal-host");
    let _guard = HostGuard(child);

    // Wait for the host to bind and publish its control file.
    let deadline = Instant::now() + Duration::from_secs(10);
    let (port, file_token) = loop {
        if let Some(control) = read_control(&control_path) {
            break control;
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    };
    assert_eq!(file_token, token);

    // First client: create a session that prints a marker and exits with code 7.
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);
    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "s1",
                "workspaceId": "w1",
                "tabId": "t1",
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": ["-c", "printf MARKER; exit 7"],
                    "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
                },
                "cols": 80,
                "rows": 24
            }
        }),
    );

    let mut output: Vec<u8> = Vec::new();
    let mut created = None;
    let mut exit_code = None;
    let event_deadline = Instant::now() + Duration::from_secs(10);
    while Instant::now() < event_deadline {
        let message = read_message(&mut reader);
        if message.get("id") == Some(&json!(1)) {
            assert_eq!(
                message["ok"],
                json!(true),
                "createOrAttach failed: {message}"
            );
            created = message["payload"]["created"].as_bool();
            assert_eq!(message["payload"]["running"], json!(true));
            continue;
        }
        match message.get("event").and_then(Value::as_str) {
            Some("output") => {
                collect_output(&message, &mut output);
            }
            Some("exit") => {
                exit_code = message["payload"]["exitCode"].as_i64();
                break;
            }
            Some("error") => panic!("unexpected error event: {message}"),
            _ => {}
        }
    }

    assert_eq!(
        created,
        Some(true),
        "first attach should create the session"
    );
    assert_eq!(exit_code, Some(7), "child exit code should propagate");
    let text = String::from_utf8_lossy(&output);
    assert!(text.contains("MARKER"), "PTY output was: {text:?}");

    // Second client: remint the exited session under the same handle while
    // preserving its prior snapshot.
    let (mut writer2, mut reader2) = connect(port);
    handshake(&mut writer2, &mut reader2, token);
    send(
        &mut writer2,
        json!({
            "id": 1,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "s1",
                "workspaceId": "w1",
                "tabId": "t1",
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": [],
                    "environment": {"PATH": "/usr/bin:/bin"}
                },
                "cols": 80,
                "rows": 24
            }
        }),
    );
    let reattach = read_message(&mut reader2);
    assert_eq!(reattach["id"], json!(1));
    assert_eq!(reattach["ok"], json!(true));
    assert_eq!(
        reattach["payload"]["created"],
        json!(true),
        "reopen must remint the exited session"
    );
    assert_eq!(reattach["payload"]["running"], json!(true));
    assert_eq!(reattach["payload"]["exitCode"], Value::Null);
    let snapshot = STANDARD
        .decode(reattach["payload"]["snapshotBase64"].as_str().unwrap())
        .unwrap();
    assert!(
        String::from_utf8_lossy(&snapshot).contains("MARKER"),
        "snapshot should replay prior output"
    );

    // Terminating the session must succeed and remove its history.
    send(
        &mut writer2,
        json!({"id": 2, "type": "terminate", "payload": {"sessionId": "s1"}}),
    );
    let terminated = read_response(&mut reader2, 2);
    assert_eq!(terminated["id"], json!(2));
    assert_eq!(
        terminated["ok"],
        json!(true),
        "terminate failed: {terminated}"
    );
}

#[test]
fn runtime_tab_remove_terminates_active_session() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "test-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    create_long_running_session(&mut writer, &mut reader, 1, "s-runtime-tab", "w1", "t1");

    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "tab.remove",
            "payload": {"id": "t1"}
        }),
    );
    let removed = read_response(&mut reader, 2);
    assert_eq!(removed["ok"], json!(true), "tab.remove failed: {removed}");

    assert_session_is_not_attached(&mut writer, &mut reader, 3, "s-runtime-tab");
}

#[test]
fn runtime_workspace_remove_terminates_active_sessions() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "test-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    create_long_running_session(
        &mut writer,
        &mut reader,
        1,
        "s-runtime-workspace",
        "w1",
        "t1",
    );

    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "workspace.remove",
            "payload": {"id": "w1", "cascadeTabs": true}
        }),
    );
    let removed = read_response(&mut reader, 2);
    assert_eq!(
        removed["ok"],
        json!(true),
        "workspace.remove failed: {removed}"
    );

    assert_session_is_not_attached(&mut writer, &mut reader, 3, "s-runtime-workspace");
}

#[test]
fn runtime_linked_review_persists_and_cascades_on_workspace_remove() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "linked-review-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    // No review linked yet.
    send(
        &mut writer,
        json!({"id": 1, "type": "linkedReview.find", "payload": {"workspaceId": "w1"}}),
    );
    let missing = read_response(&mut reader, 1);
    assert_eq!(missing["ok"], json!(true), "find failed: {missing}");
    assert_eq!(missing["payload"], Value::Null);

    // Link a review to the workspace.
    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "linkedReview.upsert",
            "payload": {
                "workspaceId": "w1",
                "provider": "github",
                "number": 123,
                "url": "https://github.com/o/r/pull/123",
                "linkedAt": "2026-07-09T00:00:00Z"
            }
        }),
    );
    let saved = read_response(&mut reader, 2);
    assert_eq!(saved["ok"], json!(true), "upsert failed: {saved}");
    assert_eq!(saved["payload"]["number"], json!(123));

    send(
        &mut writer,
        json!({"id": 3, "type": "linkedReview.find", "payload": {"workspaceId": "w1"}}),
    );
    let found = read_response(&mut reader, 3);
    assert_eq!(found["payload"]["provider"], json!("github"));
    assert_eq!(
        found["payload"]["url"],
        json!("https://github.com/o/r/pull/123")
    );

    // Removing the workspace cascades the linked review.
    send(
        &mut writer,
        json!({
            "id": 4,
            "type": "workspace.remove",
            "payload": {"id": "w1", "cascadeTabs": true}
        }),
    );
    let removed = read_response(&mut reader, 4);
    assert_eq!(removed["ok"], json!(true), "remove failed: {removed}");

    send(
        &mut writer,
        json!({"id": 5, "type": "linkedReview.find", "payload": {"workspaceId": "w1"}}),
    );
    let after = read_response(&mut reader, 5);
    assert_eq!(
        after["payload"],
        Value::Null,
        "linked review should be cascaded on workspace remove: {after}"
    );
}

#[test]
fn pauses_output_per_client_and_resumes_from_a_delta() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "pause-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);

    let (mut active_writer, mut active_reader) = connect(port);
    handshake(&mut active_writer, &mut active_reader, token);
    send(
        &mut active_writer,
        json!({
            "id": 1,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "paused",
                "workspaceId": "w1",
                "tabId": "t1",
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": ["-c", "printf READY; IFS= read -r line; printf 'GOT:%s' \"$line\"; exit 0"],
                    "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
                },
                "cols": 80,
                "rows": 24
            }
        }),
    );
    let create = read_response(&mut active_reader, 1);
    assert_eq!(create["ok"], json!(true), "create failed: {create}");

    let mut active_output = Vec::new();
    read_output_until(&mut active_reader, &mut active_output, "READY");

    let (mut paused_writer, mut paused_reader) = connect(port);
    handshake(&mut paused_writer, &mut paused_reader, token);
    send(
        &mut paused_writer,
        json!({
            "id": 1,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "paused",
                "workspaceId": "w1",
                "tabId": "t1",
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": [],
                    "environment": {"PATH": "/usr/bin:/bin"}
                },
                "cols": 80,
                "rows": 24
            }
        }),
    );
    let attached = read_response(&mut paused_reader, 1);
    assert_eq!(attached["ok"], json!(true), "attach failed: {attached}");
    assert_eq!(attached["payload"]["created"], json!(false));
    send(
        &mut paused_writer,
        json!({"id": 2, "type": "setOutputPaused", "payload": {"sessionId": "paused", "paused": true}}),
    );
    let paused = read_response(&mut paused_reader, 2);
    assert_eq!(paused["ok"], json!(true), "pause failed: {paused}");

    send(
        &mut active_writer,
        json!({"id": 2, "type": "write", "payload": {"sessionId": "paused", "dataBase64": STANDARD.encode(b"abc\r")}}),
    );
    let _ = read_response(&mut active_reader, 2);
    read_output_until(&mut active_reader, &mut active_output, "GOT:abc");

    let mut leaked = Vec::new();
    while let Some(message) =
        read_message_with_timeout(&mut paused_reader, Duration::from_millis(200))
    {
        assert!(!collect_output(&message, &mut leaked), "{message}");
    }

    send(
        &mut paused_writer,
        json!({"id": 3, "type": "setOutputPaused", "payload": {"sessionId": "paused", "paused": false}}),
    );
    // The missed bytes are queued on the terminal lane before the reply is on
    // the control lane, and the writer drains terminal frames first, so they
    // arrive ahead of the response instead of inside it.
    let mut resumed_output = Vec::new();
    let resumed = loop {
        let message = read_message(&mut paused_reader);
        if message.get("id") == Some(&json!(3)) {
            break message;
        }
        collect_output(&message, &mut resumed_output);
    };
    assert_eq!(resumed["ok"], json!(true), "resume failed: {resumed}");
    assert_eq!(resumed["payload"]["delta"], json!(true), "{resumed}");
    assert_eq!(resumed["payload"].get("snapshotBase64"), None, "{resumed}");
    assert!(
        String::from_utf8_lossy(&resumed_output).contains("GOT:abc"),
        "the resume delta should carry the output hidden while paused"
    );
}

#[test]
fn cli_mutations_use_running_runtime_host() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "cli-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);

    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    let output = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "project",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
            "--json",
            "add",
            "--id",
            "cli-project",
            "--name",
            "CLI Project",
            "--repo-path",
            dir.path().to_str().unwrap(),
        ])
        .output()
        .expect("failed to run alera project add");
    assert!(
        output.status.success(),
        "project add failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let project: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(project["id"], json!("cli-project"));

    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        assert!(Instant::now() < deadline, "never observed projectsChanged");
        let message = read_message(&mut reader);
        if message.get("event").and_then(Value::as_str) == Some("projectsChanged") {
            break;
        }
    }
}

#[test]
fn cli_mutations_use_alternate_runtime_host_control_after_legacy_host_json() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_control_path = dir.path().join("runtime-host.json");
    let token = "alternate-cli-token";
    let (_guard, port) = spawn_host(dir.path(), &runtime_control_path, token);
    std::fs::write(
        dir.path().join("host.json"),
        json!({
            "protocolVersion": 2,
            "port": 1,
            "token": "legacy-token"
        })
        .to_string(),
    )
    .unwrap();

    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    let output = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "project",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
            "--json",
            "add",
            "--id",
            "alternate-cli-project",
            "--name",
            "Alternate CLI Project",
            "--repo-path",
            dir.path().to_str().unwrap(),
        ])
        .output()
        .expect("failed to run alera project add");
    assert!(
        output.status.success(),
        "project add failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let project: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(project["id"], json!("alternate-cli-project"));

    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        assert!(Instant::now() < deadline, "never observed projectsChanged");
        let message = read_message(&mut reader);
        if message.get("event").and_then(Value::as_str) == Some("projectsChanged") {
            break;
        }
    }
}

#[test]
fn cli_rejects_unknown_tab_kind() {
    let dir = tempfile::tempdir().unwrap();

    let output = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "tab",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
            "--json",
            "create",
            "--workspace-id",
            "workspace-1",
            "--title",
            "Broken",
            "--kind",
            "typo",
        ])
        .output()
        .expect("failed to run alera tab create");

    assert_eq!(
        output.status.code(),
        Some(64),
        "tab create should fail as a usage error: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "invalid tab creation should not print JSON"
    );
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("Unsupported tab kind"),
        "stderr should explain the invalid tab kind: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        !dir.path().join("runtime.sqlite").exists(),
        "invalid tab creation should not open or mutate the runtime store"
    );
}

#[test]
fn cli_bootstrap_cancel_requires_runtime_host_job() {
    let dir = tempfile::tempdir().unwrap();

    let output = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "ssh-target",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
            "bootstrap-cancel",
            "--id",
            "target-1",
        ])
        .output()
        .expect("failed to run alera ssh-target bootstrap-cancel");

    assert!(
        !output.status.success(),
        "cancel should fail without a runtime host: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("no active runtime host bootstrap job"),
        "stderr should explain the missing active job: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn runtime_bootstrap_start_rejects_missing_target_before_job() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "ssh-missing-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "sshTarget.bootstrap.start",
            "payload": {
                "targetId": "missing-target",
                "platform": "linux",
                "arch": "x64",
                "artifactPath": dir.path().join("unused.tar.gz")
            }
        }),
    );
    let response = read_response(&mut reader, 1);
    assert_eq!(
        response["ok"],
        json!(false),
        "bootstrap should fail: {response}"
    );
    assert!(
        response["error"]
            .as_str()
            .is_some_and(|error| error.contains("ssh target not found")),
        "error should explain the missing target: {response}"
    );

    send(
        &mut writer,
        json!({"id": 2, "type": "sshTarget.bootstrap.jobs", "payload": {}}),
    );
    let jobs = read_response(&mut reader, 2);
    assert_eq!(jobs["ok"], json!(true), "jobs failed: {jobs}");
    assert_eq!(jobs["payload"], json!([]));
}

#[test]
fn runtime_bootstrap_start_rejects_password_target_before_job() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "ssh-password-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    let mut target = ssh_target_payload("remote-password", "notInstalled");
    target["authKind"] = json!("password");
    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "sshTarget.upsert",
            "payload": target
        }),
    );
    let saved = read_response(&mut reader, 1);
    assert_eq!(saved["ok"], json!(true), "upsert failed: {saved}");

    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "sshTarget.bootstrap.start",
            "payload": {
                "targetId": "remote-password",
                "platform": "linux",
                "arch": "x64",
                "artifactPath": dir.path().join("unused.tar.gz")
            }
        }),
    );
    let response = read_response(&mut reader, 2);
    assert_eq!(
        response["ok"],
        json!(false),
        "bootstrap should fail: {response}"
    );
    assert!(
        response["error"]
            .as_str()
            .is_some_and(|error| error.contains("password SSH targets are not supported")),
        "error should explain the unsupported auth: {response}"
    );

    send(
        &mut writer,
        json!({"id": 3, "type": "sshTarget.bootstrap.jobs", "payload": {}}),
    );
    let jobs = read_response(&mut reader, 3);
    assert_eq!(jobs["ok"], json!(true), "jobs failed: {jobs}");
    assert_eq!(jobs["payload"], json!([]));
}

#[test]
fn runtime_ssh_target_upsert_distinguishes_omitted_and_null_install_dir() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "ssh-install-dir-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    let mut target = ssh_target_payload("remote-dir", "notInstalled");
    target["installDir"] = json!("/custom/alera/runtime");
    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "sshTarget.upsert",
            "payload": target
        }),
    );
    let saved = read_response(&mut reader, 1);
    assert_eq!(saved["ok"], json!(true), "upsert failed: {saved}");
    assert_eq!(
        saved["payload"]["installDir"],
        json!("/custom/alera/runtime")
    );

    let mut omitted = ssh_target_payload("remote-dir", "notInstalled");
    omitted["host"] = json!("renamed.example.invalid");
    omitted.as_object_mut().unwrap().remove("installDir");
    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "sshTarget.upsert",
            "payload": omitted
        }),
    );
    let preserved = read_response(&mut reader, 2);
    assert_eq!(
        preserved["payload"]["installDir"],
        json!("/custom/alera/runtime")
    );
    assert_eq!(
        preserved["payload"]["host"],
        json!("renamed.example.invalid")
    );

    let cleared = ssh_target_payload("remote-dir", "notInstalled");
    send(
        &mut writer,
        json!({
            "id": 3,
            "type": "sshTarget.upsert",
            "payload": cleared
        }),
    );
    let cleared = read_response(&mut reader, 3);
    assert_eq!(cleared["payload"]["installDir"], Value::Null);
}

#[test]
fn runtime_failed_bootstrap_preserves_previous_runtime_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "ssh-failed-metadata-token";
    let path = fake_ready_ssh_path(dir.path());
    let (_guard, port) = spawn_host_with_env(dir.path(), &control_path, token, &[("PATH", &path)]);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    let mut target = ssh_target_payload("remote-installed", "installed");
    target["runtimeVersion"] = json!("1.2.2");
    target["runtimePlatform"] = json!("linux");
    target["runtimeArch"] = json!("x64");
    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "sshTarget.upsert",
            "payload": target
        }),
    );
    let saved = read_response(&mut reader, 1);
    assert_eq!(saved["ok"], json!(true), "upsert failed: {saved}");

    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "sshTarget.bootstrap.start",
            "payload": {
                "targetId": "remote-installed",
                "platform": "linux",
                "arch": "x64",
                "version": "1.2.3",
                "artifactPath": dir.path().join("missing-runtime.tar.gz")
            }
        }),
    );
    let started = read_response(&mut reader, 2);
    assert_eq!(
        started["ok"],
        json!(true),
        "bootstrap start failed: {started}"
    );

    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        assert!(
            Instant::now() < deadline,
            "bootstrap failure event was never emitted"
        );
        let message = read_message(&mut reader);
        if message["event"] == json!("sshTargetBootstrapProgress")
            && message["payload"]["targetId"] == json!("remote-installed")
            && message["payload"]["status"] == json!("failed")
        {
            break;
        }
    }

    send(
        &mut writer,
        json!({"id": 3, "type": "sshTarget.list", "payload": {}}),
    );
    let listed = read_response(&mut reader, 3);
    assert_eq!(listed["ok"], json!(true), "list failed: {listed}");
    let target = listed["payload"]
        .as_array()
        .and_then(|items| {
            items
                .iter()
                .find(|item| item["id"] == json!("remote-installed"))
        })
        .expect("saved target should be listed");
    assert_eq!(target["bootstrapStatus"], json!("failed"));
    assert_eq!(target["runtimeVersion"], json!("1.2.2"));
    assert_eq!(target["runtimePlatform"], json!("linux"));
    assert_eq!(target["runtimeArch"], json!("x64"));
}

#[test]
fn runtime_remove_aborts_active_ssh_bootstrap_job() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "ssh-remove-token";
    let path = fake_blocking_ssh_path(dir.path());
    let (_guard, port) = spawn_host_with_env(dir.path(), &control_path, token, &[("PATH", &path)]);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "sshTarget.upsert",
            "payload": ssh_target_payload("remote-active", "notInstalled")
        }),
    );
    let saved = read_response(&mut reader, 1);
    assert_eq!(saved["ok"], json!(true), "upsert failed: {saved}");

    send(
        &mut writer,
        json!({
            "id": 2,
            "type": "sshTarget.bootstrap.start",
            "payload": {
                "targetId": "remote-active",
                "platform": "linux",
                "arch": "x64",
                "artifactPath": dir.path().join("unused.tar.gz")
            }
        }),
    );
    let started = read_response(&mut reader, 2);
    assert_eq!(
        started["ok"],
        json!(true),
        "bootstrap start failed: {started}"
    );
    assert_eq!(started["payload"]["status"], json!("installing"));

    send(
        &mut writer,
        json!({"id": 3, "type": "sshTarget.list", "payload": {}}),
    );
    let installing_targets = read_response(&mut reader, 3);
    assert_eq!(
        installing_targets["ok"],
        json!(true),
        "list failed: {installing_targets}"
    );
    assert_eq!(
        installing_targets["payload"][0]["bootstrapStatus"],
        json!("installing")
    );

    send(
        &mut writer,
        json!({
            "id": 4,
            "type": "sshTarget.remove",
            "payload": {"id": "remote-active"}
        }),
    );
    let removed = read_response(&mut reader, 4);
    assert_eq!(removed["ok"], json!(true), "remove failed: {removed}");

    send(
        &mut writer,
        json!({"id": 5, "type": "sshTarget.bootstrap.jobs", "payload": {}}),
    );
    let jobs = read_response(&mut reader, 5);
    assert_eq!(jobs["ok"], json!(true), "jobs failed: {jobs}");
    assert_eq!(jobs["payload"], json!([]));

    send(
        &mut writer,
        json!({"id": 6, "type": "sshTarget.list", "payload": {}}),
    );
    let targets = read_response(&mut reader, 6);
    assert_eq!(targets["ok"], json!(true), "list failed: {targets}");
    assert_eq!(targets["payload"], json!([]));
}

#[test]
fn runtime_cancel_clears_stale_installing_ssh_bootstrap_state() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "ssh-stale-token";

    {
        let (_guard, port) = spawn_host(dir.path(), &control_path, token);
        let (mut writer, mut reader) = connect(port);
        handshake(&mut writer, &mut reader, token);
        send(
            &mut writer,
            json!({
                "id": 1,
                "type": "sshTarget.upsert",
                "payload": ssh_target_payload("remote-stale", "installing")
            }),
        );
        let saved = read_response(&mut reader, 1);
        assert_eq!(saved["ok"], json!(true), "upsert failed: {saved}");
    }

    std::fs::remove_file(&control_path).ok();
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "sshTarget.bootstrap.cancel",
            "payload": {"id": "remote-stale"}
        }),
    );
    let cancelled = read_response(&mut reader, 1);
    assert_eq!(
        cancelled["ok"],
        json!(true),
        "stale cancel failed: {cancelled}"
    );
    assert_eq!(cancelled["payload"]["bootstrapStatus"], json!("cancelled"));
    assert_eq!(cancelled["payload"]["lastError"], Value::Null);

    send(
        &mut writer,
        json!({"id": 2, "type": "sshTarget.list", "payload": {}}),
    );
    let targets = read_response(&mut reader, 2);
    assert_eq!(targets["ok"], json!(true), "list failed: {targets}");
    assert_eq!(targets["payload"][0]["bootstrapStatus"], json!("cancelled"));
    assert_eq!(targets["payload"][0]["lastError"], Value::Null);
}

#[test]
fn rejects_bad_token() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "good-token";

    let child = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args([
            "terminal-host",
            "--runtime-dir",
            dir.path().to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            token,
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .spawn()
        .expect("failed to spawn alera terminal-host");
    let _guard = HostGuard(child);

    let deadline = Instant::now() + Duration::from_secs(10);
    let port = loop {
        if let Some((port, _)) = read_control(&control_path) {
            break port;
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    };

    let (mut writer, mut reader) = connect(port);
    send(
        &mut writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": PROTOCOL_VERSION, "token": "wrong"}}),
    );
    let response = read_message(&mut reader);
    assert_eq!(response["id"], json!(0));
    assert_eq!(response["ok"], json!(false));
    assert_eq!(
        response["error"],
        json!("Terminal host authentication failed.")
    );
}

/// A session that exited under one host process must be restorable from the
/// SQLite checkpoint store by a freshly started host sharing the runtime dir.
/// This is the persistence guarantee that makes incremental migration safe.
#[test]
fn remints_session_from_disk_after_restart_with_prior_scrollback() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "restart-token";

    // Host A: run a session that prints a marker and exits.
    {
        let (_guard, port) = spawn_host(dir.path(), &control_path, token);
        let (mut writer, mut reader) = connect(port);
        handshake(&mut writer, &mut reader, token);
        send(
            &mut writer,
            json!({
                "id": 1,
                "type": "createOrAttach",
                "payload": {
                    "sessionId": "s1",
                    "workspaceId": "w1",
                    "tabId": "t1",
                    "workingDirectory": "/tmp",
                    "launch": {
                        "shell": "/bin/sh",
                        "arguments": ["-c", "printf FIRST; sleep 0.2; printf SECOND; exit 3"],
                        "environment": {"PATH": "/usr/bin:/bin"}
                    },
                    "cols": 80,
                    "rows": 24
                }
            }),
        );
        // Drain until the exit event, which triggers an immediate checkpoint.
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            assert!(Instant::now() < deadline, "never observed session exit");
            let message = read_message(&mut reader);
            if message.get("event").and_then(Value::as_str) == Some("exit") {
                assert_eq!(message["payload"]["exitCode"], json!(3));
                break;
            }
        }
        // Round-trip a detach: the actor processes commands in order, so its OK
        // response guarantees the exit checkpoint has been flushed to SQLite
        // before we kill host A by dropping the guard.
        send(
            &mut writer,
            json!({"id": 2, "type": "detach", "payload": {"sessionId": "s1"}}),
        );
        let detached = read_message(&mut reader);
        assert_eq!(detached["id"], json!(2));
        assert_eq!(detached["ok"], json!(true));
        // Dropping _guard kills host A, leaving the checkpoint on disk.
    }

    // A killed host does not delete its control file. The app treats a stale
    // file as unusable and removes it before relaunching; do the same so we
    // wait for host B's freshly published port rather than host A's dead one.
    std::fs::remove_file(&control_path).ok();

    // Host B: remint the session, seed it with the previous output, then add a
    // new output chunk whose sequence must follow Host A's chunks.
    {
        let (_guard, port) = spawn_host(dir.path(), &control_path, token);
        let (mut writer, mut reader) = connect(port);
        handshake(&mut writer, &mut reader, token);
        send(
            &mut writer,
            json!({
                "id": 1,
                "type": "createOrAttach",
                "payload": {
                    "sessionId": "s1",
                    "workspaceId": "w1",
                    "tabId": "t1",
                    "workingDirectory": "/tmp",
                    "launch": {
                        "shell": "/bin/sh",
                        "arguments": ["-c", "printf AFTER; exit 0"],
                        "environment": {"PATH": "/usr/bin:/bin"}
                    },
                    "cols": 80,
                    "rows": 24
                }
            }),
        );
        let restored = read_message(&mut reader);
        assert_eq!(restored["id"], json!(1));
        assert_eq!(restored["ok"], json!(true), "restore failed: {restored}");
        assert_eq!(restored["payload"]["created"], json!(true));
        assert_eq!(restored["payload"]["running"], json!(true));
        assert_eq!(restored["payload"]["exitCode"], Value::Null);
        let snapshot = STANDARD
            .decode(restored["payload"]["snapshotBase64"].as_str().unwrap())
            .unwrap();
        let snapshot = String::from_utf8_lossy(&snapshot);
        assert!(snapshot.contains("FIRST"));
        assert!(snapshot.contains("SECOND"));

        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            assert!(Instant::now() < deadline, "never observed reminted exit");
            let message = read_message(&mut reader);
            if message.get("event").and_then(Value::as_str) == Some("exit") {
                assert_eq!(message["payload"]["exitCode"], json!(0));
                break;
            }
        }
        send(
            &mut writer,
            json!({"id": 2, "type": "detach", "payload": {"sessionId": "s1"}}),
        );
        let detached = read_message(&mut reader);
        assert_eq!(detached["id"], json!(2));
        assert_eq!(detached["ok"], json!(true));
    }

    std::fs::remove_file(&control_path).ok();

    // Host C observes the persisted chunks in chronological order.
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);
    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "s1",
                "workspaceId": "w1",
                "tabId": "t1",
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": [],
                    "environment": {"PATH": "/usr/bin:/bin"}
                },
                "cols": 80,
                "rows": 24
            }
        }),
    );
    let restored = read_message(&mut reader);
    assert_eq!(restored["id"], json!(1));
    assert_eq!(restored["ok"], json!(true), "restore failed: {restored}");
    let snapshot = STANDARD
        .decode(restored["payload"]["snapshotBase64"].as_str().unwrap())
        .unwrap();
    let snapshot = String::from_utf8_lossy(&snapshot);
    let first = snapshot.find("FIRST").expect("FIRST output");
    let second = snapshot.find("SECOND").expect("SECOND output");
    let after = snapshot.find("AFTER").expect("AFTER output");
    assert!(
        first < second && second < after,
        "scrollback order: {snapshot}"
    );
}

#[test]
fn resource_snapshot_attributes_a_live_session_to_its_workspace_and_tab() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "test-token";
    let (_guard, port) = spawn_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);

    send(
        &mut writer,
        json!({"id": 1, "type": "status.get", "payload": {}}),
    );
    let status = read_response(&mut reader, 1);
    let capabilities = status["payload"]["runtimeCapabilities"].as_array().unwrap();
    assert!(
        capabilities.contains(&json!("resourceMonitorV1")),
        "resource monitor capability missing: {capabilities:?}"
    );
    // The verb is additive, so the protocol version must not have moved.
    assert_eq!(
        status["payload"]["protocolVersion"],
        json!(PROTOCOL_VERSION)
    );

    create_long_running_session(&mut writer, &mut reader, 2, "s-resources", "w1", "t1");

    // The first call starts the sampler, so it answers with the warming
    // placeholder rather than blocking on a process sweep.
    send(
        &mut writer,
        json!({"id": 3, "type": "resources.snapshot", "payload": {"appPid": std::process::id()}}),
    );
    let warming = read_response(&mut reader, 3);
    assert_eq!(warming["ok"], json!(true), "snapshot failed: {warming}");
    assert_eq!(warming["payload"]["warming"], json!(true));

    // Poll until a real sweep lands. The sampler ticks every 2s and needs two
    // refreshes before its CPU deltas mean anything.
    let mut sampled = Value::Null;
    for id in 4..14 {
        std::thread::sleep(std::time::Duration::from_millis(1_500));
        send(
            &mut writer,
            json!({"id": id, "type": "resources.snapshot", "payload": {"appPid": std::process::id()}}),
        );
        let response = read_response(&mut reader, id);
        assert_eq!(response["ok"], json!(true), "snapshot failed: {response}");
        if response["payload"]["warming"] == json!(false) {
            sampled = response["payload"].clone();
            break;
        }
    }
    assert!(!sampled.is_null(), "no settled resource sample arrived");

    let sessions = sampled["sessions"].as_array().expect("sessions array");
    let session = sessions
        .iter()
        .find(|entry| entry["sessionId"] == json!("s-resources"))
        .expect("the live session is reported");
    assert_eq!(session["workspaceId"], json!("w1"));
    assert_eq!(session["tabId"], json!("t1"));
    assert_eq!(session["running"], json!(true));
    assert!(session["shellPid"].as_u64().unwrap() > 0);
    assert_eq!(session["measured"], json!(true));
    assert!(
        session["memoryBytes"].as_u64().unwrap() > 0,
        "the shell should report resident memory: {session}"
    );

    // The app pid was supplied, so the app row is measured too, and the host
    // row never swallows the PTY children it parents.
    assert!(sampled["processes"]["app"]["memoryBytes"].as_u64().unwrap() > 0);
    assert!(
        sampled["processes"]["host"]["memoryBytes"]
            .as_u64()
            .unwrap()
            > 0
    );
    assert!(sampled["host"]["totalMemoryBytes"].as_u64().unwrap() > 0);
    assert!(sampled["host"]["cpuCoreCount"].as_u64().unwrap() > 0);
}
