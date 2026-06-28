//! End-to-end protocol conformance test. Spawns the real `alera terminal-host`
//! binary, connects over the loopback socket it advertises, and drives the full
//! request/event sequence the Dart app relies on.

use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

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

fn handshake(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, token: &str) {
    send(
        writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": 2, "token": token}}),
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
    assert_eq!(
        write["ok"],
        json!(false),
        "write unexpectedly succeeded: {write}"
    );
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
    let child = Command::new(env!("CARGO_BIN_EXE_alera"))
        .args([
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
        ])
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

#[test]
fn full_protocol_sequence() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "test-token";

    let child = Command::new(env!("CARGO_BIN_EXE_alera"))
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
                let bytes = STANDARD
                    .decode(message["payload"]["dataBase64"].as_str().unwrap())
                    .unwrap();
                output.extend_from_slice(&bytes);
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

    // Second client: reattach to the now-exited session and replay its snapshot.
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
        json!(false),
        "reattach must not create a new session"
    );
    assert_eq!(reattach["payload"]["running"], json!(false));
    assert_eq!(reattach["payload"]["exitCode"], json!(7));
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
    let terminated = read_message(&mut reader2);
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
fn pauses_output_per_client_and_resumes_from_snapshot() {
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
    while !String::from_utf8_lossy(&active_output).contains("READY") {
        let message = read_message(&mut active_reader);
        if message.get("event").and_then(Value::as_str) == Some("output") {
            let bytes = STANDARD
                .decode(message["payload"]["dataBase64"].as_str().unwrap())
                .unwrap();
            active_output.extend_from_slice(&bytes);
        }
    }

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
    while !String::from_utf8_lossy(&active_output).contains("GOT:abc") {
        let message = read_message(&mut active_reader);
        if message.get("event").and_then(Value::as_str) == Some("output") {
            let bytes = STANDARD
                .decode(message["payload"]["dataBase64"].as_str().unwrap())
                .unwrap();
            active_output.extend_from_slice(&bytes);
        }
    }

    while let Some(message) =
        read_message_with_timeout(&mut paused_reader, Duration::from_millis(200))
    {
        assert_ne!(
            message.get("event").and_then(Value::as_str),
            Some("output"),
            "paused client received output: {message}"
        );
    }

    send(
        &mut paused_writer,
        json!({"id": 3, "type": "setOutputPaused", "payload": {"sessionId": "paused", "paused": false}}),
    );
    let resumed = read_response(&mut paused_reader, 3);
    assert_eq!(resumed["ok"], json!(true), "resume failed: {resumed}");
    let snapshot = STANDARD
        .decode(resumed["payload"]["snapshotBase64"].as_str().unwrap())
        .unwrap();
    assert!(
        String::from_utf8_lossy(&snapshot).contains("GOT:abc"),
        "resume snapshot should include hidden output"
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

    let output = Command::new(env!("CARGO_BIN_EXE_alera"))
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

    let output = Command::new(env!("CARGO_BIN_EXE_alera"))
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

    let output = Command::new(env!("CARGO_BIN_EXE_alera"))
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
fn rejects_bad_token() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "good-token";

    let child = Command::new(env!("CARGO_BIN_EXE_alera"))
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
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": 2, "token": "wrong"}}),
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
fn restores_session_from_disk_after_restart() {
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
                        "arguments": ["-c", "printf PERSISTED; exit 3"],
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

    // Host B: a new process over the same runtime dir restores the session.
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
    assert_eq!(restored["payload"]["created"], json!(false));
    assert_eq!(restored["payload"]["running"], json!(false));
    assert_eq!(restored["payload"]["exitCode"], json!(3));
    let snapshot = STANDARD
        .decode(restored["payload"]["snapshotBase64"].as_str().unwrap())
        .unwrap();
    assert!(
        String::from_utf8_lossy(&snapshot).contains("PERSISTED"),
        "restored snapshot should contain prior output"
    );
}
