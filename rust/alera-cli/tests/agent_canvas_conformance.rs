//! End-to-end Agent Canvas conformance against the real runtime host.

use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::Child;
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;
use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;

struct HostGuard(Child);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn read_control(path: &std::path::Path) -> Option<(u16, String)> {
    let value: Value = serde_json::from_str(&std::fs::read_to_string(path).ok()?).ok()?;
    Some((
        value.get("port")?.as_u64()? as u16,
        value.get("token")?.as_str()?.to_string(),
    ))
}

fn start_host(
    runtime_dir: &std::path::Path,
    control_path: &std::path::Path,
    token: &str,
) -> (HostGuard, u16) {
    let child = windowless_command(env!("CARGO_BIN_EXE_alera"))
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

fn connect(port: u16) -> (TcpStream, BufReader<TcpStream>) {
    let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(15)))
        .unwrap();
    let writer = stream.try_clone().unwrap();
    (writer, BufReader::new(stream))
}

fn send(writer: &mut TcpStream, message: Value) {
    let mut bytes = serde_json::to_vec(&message).unwrap();
    bytes.push(b'\n');
    writer.write_all(&bytes).unwrap();
    writer.flush().unwrap();
}

fn response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let mut line = String::new();
        assert!(
            reader.read_line(&mut line).unwrap() > 0,
            "host closed the connection"
        );
        let message: Value = serde_json::from_str(line.trim_end()).unwrap();
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
    }
}

fn request(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    request_type: &str,
    payload: Value,
) -> Value {
    send(
        writer,
        json!({"id": id, "type": request_type, "payload": payload}),
    );
    response(reader, id)
}

fn payload(response: Value) -> Value {
    assert_eq!(response["ok"], json!(true), "request failed: {response}");
    response["payload"].clone()
}

#[test]
fn publish_decision_resume_and_complete_round_trip() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("host.json");
    let token = "agent-canvas-test-token";
    let (_guard, port) = start_host(dir.path(), &control_path, token);
    let (mut writer, mut reader) = connect(port);

    let hello = request(
        &mut writer,
        &mut reader,
        0,
        "hello",
        json!({"protocolVersion": PROTOCOL_VERSION, "token": token}),
    );
    assert_eq!(hello["ok"], json!(true), "handshake failed: {hello}");

    let created = request(
        &mut writer,
        &mut reader,
        1,
        "createOrAttach",
        json!({
            "sessionId": "session-1",
            "workspaceId": "workspace-1",
            "tabId": "tab-1",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-c", "sleep 30"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 80,
            "rows": 24
        }),
    );
    assert_eq!(
        created["ok"],
        json!(true),
        "session creation failed: {created}"
    );

    let capabilities = payload(request(
        &mut writer,
        &mut reader,
        2,
        "agentCanvas.capabilities",
        json!({}),
    ));
    assert_eq!(capabilities["supported"], json!(true));
    assert_eq!(capabilities["capabilities"]["protocolVersion"], json!(1));

    let published = payload(request(
        &mut writer,
        &mut reader,
        3,
        "agentCanvas.publish",
        json!({
            "workspaceId": "workspace-1",
            "terminalSessionId": "session-1",
            "tabId": "tab-1",
            "agentType": "codex",
            "title": "Review",
            "expectedRevision": 0,
            "document": {
                "version": 1,
                "components": [{
                    "type": "DecisionRequest",
                    "props": {"id": "decision-1", "question": "Ship it?", "options": ["Yes", "No"]}
                }]
            }
        }),
    ));
    let canvas_id = published["canvas"]["id"].as_str().unwrap().to_string();
    assert_eq!(published["canvas"]["revision"], json!(1));
    assert_eq!(
        published["canvas"]["decisions"][0]["state"],
        json!("pending")
    );

    let resolved = payload(request(
        &mut writer,
        &mut reader,
        4,
        "agentCanvas.decision.resolve",
        json!({"decisionId": "decision-1", "resolution": "Yes"}),
    ));
    assert_eq!(resolved["decision"]["state"], json!("resolved"));

    let events = payload(request(
        &mut writer,
        &mut reader,
        5,
        "agentCanvas.events",
        json!({"workspaceId": "workspace-1", "since": 0, "limit": 20}),
    ));
    let event_types: Vec<&str> = events["events"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|event| event["eventType"].as_str())
        .collect();
    assert!(event_types.contains(&"created"));
    assert!(event_types.contains(&"decisionRequest"));
    assert!(event_types.contains(&"decisionResolved"));

    let completed = payload(request(
        &mut writer,
        &mut reader,
        6,
        "agentCanvas.complete",
        json!({"canvasId": canvas_id}),
    ));
    assert_eq!(completed["canvas"]["state"], json!("completed"));
    assert_eq!(completed["canvas"]["finalRevision"], json!(1));

    let rejected = request(
        &mut writer,
        &mut reader,
        7,
        "agentCanvas.publish",
        json!({
            "workspaceId": "workspace-1",
            "terminalSessionId": "session-1",
            "tabId": "tab-1",
            "canvasId": canvas_id,
            "expectedRevision": 1,
            "document": {"version": 1, "components": []}
        }),
    );
    assert_eq!(rejected["ok"], json!(false));
}
