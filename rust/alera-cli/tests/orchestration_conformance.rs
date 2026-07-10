//! End-to-end orchestration conformance. Spawns the real `alera runtime-host`
//! binary, connects raw TCP clients, and exercises messaging, long-poll
//! waits, tasks, dispatch, gates, agent presence, and push-on-idle delivery
//! against a live PTY.

use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 3;

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

fn spawn_host(
    runtime_dir: &std::path::Path,
    control_path: &std::path::Path,
    token: &str,
) -> (HostGuard, u16) {
    let mut command = Command::new(env!("CARGO_BIN_EXE_alera"));
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
    let child = command.spawn().expect("failed to spawn alera runtime-host");
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

fn read_response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let message = read_message(reader);
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
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

fn handshake(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, token: &str) {
    send(
        writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": PROTOCOL_VERSION, "token": token}}),
    );
    let hello = read_response(reader, 0);
    assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");
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
    read_response(reader, id)
}

fn expect_ok(response: Value) -> Value {
    assert_eq!(response["ok"], json!(true), "request failed: {response}");
    response["payload"].clone()
}

struct Host {
    _dir: tempfile::TempDir,
    _guard: HostGuard,
    port: u16,
    token: String,
}

fn start_host() -> Host {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "orchestration-test-token".to_string();
    let (guard, port) = spawn_host(dir.path(), &control_path, &token);
    Host {
        _dir: dir,
        _guard: guard,
        port,
        token,
    }
}

#[test]
fn send_check_reply_roundtrip() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let sent = expect_ok(request(
        &mut writer,
        &mut reader,
        1,
        "orchestration.send",
        json!({"from": "a", "to": "b", "subject": "hi", "body": "hello there"}),
    ));
    assert_eq!(sent["recipients"], json!(["b"]));
    let message_id = sent["messages"][0]["id"].as_str().unwrap().to_string();

    // First check consumes the unread message.
    let checked = expect_ok(request(
        &mut writer,
        &mut reader,
        2,
        "orchestration.check",
        json!({"terminal": "b", "inject": true}),
    ));
    assert_eq!(checked["messages"][0]["id"], json!(message_id));
    let formatted = checked["formatted"].as_str().unwrap();
    assert!(formatted.contains("--- Orchestration Messages (1) ---"));
    assert!(formatted.contains("alera orchestration reply --id"));

    // Second check is empty (read/delivered independence handled in unit tests).
    let empty = expect_ok(request(
        &mut writer,
        &mut reader,
        3,
        "orchestration.check",
        json!({"terminal": "b"}),
    ));
    assert_eq!(empty["messages"], json!([]));

    // Reply flows back to the original sender with the thread inherited.
    let reply = expect_ok(request(
        &mut writer,
        &mut reader,
        4,
        "orchestration.reply",
        json!({"id": message_id, "body": "ack"}),
    ));
    assert_eq!(reply["to_handle"], json!("a"));
    assert_eq!(reply["thread_id"], json!(message_id));
    let back = expect_ok(request(
        &mut writer,
        &mut reader,
        5,
        "orchestration.check",
        json!({"terminal": "a"}),
    ));
    assert_eq!(back["messages"][0]["subject"], json!("Re: hi"));
}

#[test]
fn check_wait_wakes_on_matching_type_only() {
    let host = start_host();
    let (mut coordinator_writer, mut coordinator_reader) = connect(host.port);
    handshake(
        &mut coordinator_writer,
        &mut coordinator_reader,
        &host.token,
    );
    let (mut sender_writer, mut sender_reader) = connect(host.port);
    handshake(&mut sender_writer, &mut sender_reader, &host.token);

    // Park a waiter filtered to worker_done.
    send(
        &mut coordinator_writer,
        json!({"id": 10, "type": "orchestration.check", "payload": {
            "terminal": "coord", "wait": true, "types": ["worker_done"], "timeoutMs": 10_000
        }}),
    );
    std::thread::sleep(Duration::from_millis(300));

    // A status message must NOT wake the worker_done waiter.
    expect_ok(request(
        &mut sender_writer,
        &mut sender_reader,
        11,
        "orchestration.send",
        json!({"from": "w", "to": "coord", "subject": "noise", "type": "status"}),
    ));
    std::thread::sleep(Duration::from_millis(300));

    // The worker_done wakes it. Task/dispatch ids are bogus, so lifecycle
    // reconciliation ignores it, but delivery to the waiter still happens.
    expect_ok(request(
        &mut sender_writer,
        &mut sender_reader,
        12,
        "orchestration.send",
        json!({"from": "w", "to": "coord", "subject": "done", "type": "worker_done",
               "payload": "{\"taskId\":\"t\",\"dispatchId\":\"d\"}"}),
    ));
    let woken = read_response(&mut coordinator_reader, 10);
    assert_eq!(woken["ok"], json!(true));
    let messages = woken["payload"]["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["type"], json!("worker_done"));
}

#[test]
fn check_wait_times_out_cleanly() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let timed_out = expect_ok(request(
        &mut writer,
        &mut reader,
        20,
        "orchestration.check",
        json!({"terminal": "nobody", "wait": true, "timeoutMs": 700}),
    ));
    assert_eq!(timed_out["timedOut"], json!(true));
    assert_eq!(timed_out["messages"], json!([]));
}

#[test]
fn ask_blocks_until_reply() {
    let host = start_host();
    let (mut worker_writer, mut worker_reader) = connect(host.port);
    handshake(&mut worker_writer, &mut worker_reader, &host.token);
    let (mut coordinator_writer, mut coordinator_reader) = connect(host.port);
    handshake(
        &mut coordinator_writer,
        &mut coordinator_reader,
        &host.token,
    );

    send(
        &mut worker_writer,
        json!({"id": 30, "type": "orchestration.ask", "payload": {
            "from": "worker", "to": "coord", "question": "Which db?",
            "options": "sqlite,postgres", "timeoutMs": 10_000
        }}),
    );
    std::thread::sleep(Duration::from_millis(300));

    let inbox = expect_ok(request(
        &mut coordinator_writer,
        &mut coordinator_reader,
        31,
        "orchestration.check",
        json!({"terminal": "coord", "types": ["decision_gate"]}),
    ));
    let question_id = inbox["messages"][0]["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut coordinator_writer,
        &mut coordinator_reader,
        32,
        "orchestration.reply",
        json!({"id": question_id, "body": "sqlite"}),
    ));

    let answered = read_response(&mut worker_reader, 30);
    assert_eq!(answered["ok"], json!(true));
    assert_eq!(answered["payload"]["answered"], json!(true));
    assert_eq!(answered["payload"]["reply"]["body"], json!("sqlite"));
}

#[test]
fn task_dag_dispatch_and_worker_done() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let task_a = expect_ok(request(
        &mut writer,
        &mut reader,
        40,
        "orchestration.taskCreate",
        json!({"spec": "implement A"}),
    ));
    let a_id = task_a["id"].as_str().unwrap().to_string();
    assert_eq!(task_a["status"], json!("ready"));
    let task_b = expect_ok(request(
        &mut writer,
        &mut reader,
        41,
        "orchestration.taskCreate",
        json!({"spec": "test A", "deps": [a_id]}),
    ));
    assert_eq!(task_b["status"], json!("pending"));
    let b_id = task_b["id"].as_str().unwrap().to_string();

    // Dry-run builds a preamble without mutating anything.
    let dry = expect_ok(request(
        &mut writer,
        &mut reader,
        42,
        "orchestration.dispatch",
        json!({"task": a_id, "to": "w1", "from": "coord", "dryRun": true}),
    ));
    let dry_preamble = dry["preamble"].as_str().unwrap();
    assert!(dry_preamble.contains("NEVER use AskUserQuestion"));
    assert!(dry_preamble.contains("Exit the shell after completion"));
    assert!(!dry_preamble.contains("return to an idle prompt"));

    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        43,
        "orchestration.dispatch",
        json!({"task": a_id, "to": "w1", "from": "coord"}),
    ));
    let dispatch_id = dispatched["dispatch"]["id"].as_str().unwrap().to_string();
    assert!(dispatched["preamble"]
        .as_str()
        .unwrap()
        .contains(&dispatch_id));

    // worker_done from the assignee with matching ids completes A and
    // promotes B in one send.
    expect_ok(request(
        &mut writer,
        &mut reader,
        44,
        "orchestration.send",
        json!({"from": "w1", "to": "coord", "subject": "done", "type": "worker_done",
               "payload": format!("{{\"taskId\":\"{a_id}\",\"dispatchId\":\"{dispatch_id}\"}}")}),
    ));
    let tasks = expect_ok(request(
        &mut writer,
        &mut reader,
        45,
        "orchestration.taskList",
        json!({}),
    ));
    let by_id: std::collections::HashMap<&str, &str> = tasks["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .map(|task| {
            (
                task["id"].as_str().unwrap(),
                task["status"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(by_id[a_id.as_str()], "completed");
    assert_eq!(by_id[b_id.as_str()], "ready");
}

#[test]
fn gate_blocks_and_resolution_feeds_next_preamble() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        50,
        "orchestration.taskCreate",
        json!({"spec": "risky change"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    let gate = expect_ok(request(
        &mut writer,
        &mut reader,
        51,
        "orchestration.gateCreate",
        json!({"task": task_id, "question": "Proceed?", "options": ["yes", "no"]}),
    ));
    let gate_id = gate["id"].as_str().unwrap().to_string();

    let blocked = expect_ok(request(
        &mut writer,
        &mut reader,
        52,
        "orchestration.taskList",
        json!({"status": "blocked"}),
    ));
    assert_eq!(blocked["tasks"][0]["id"], json!(task_id));

    expect_ok(request(
        &mut writer,
        &mut reader,
        53,
        "orchestration.gateResolve",
        json!({"id": gate_id, "resolution": "yes, carefully"}),
    ));
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        54,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "w1", "from": "coord", "returnPreamble": true}),
    ));
    let preamble = dispatched["preamble"].as_str().unwrap();
    assert!(preamble.contains("DECISION GATE RESOLVED"));
    assert!(preamble.contains("yes, carefully"));
}

#[test]
#[cfg(unix)]
fn push_on_idle_delivers_into_live_pty() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    // A real PTY running `cat`: everything written to it is echoed to output.
    let session_id = "orchestration-pty-1";
    let created = expect_ok(request(
        &mut writer,
        &mut reader,
        60,
        "createOrAttach",
        json!({
            "sessionId": session_id,
            "workspaceId": "ws-1",
            "tabId": "tab-1",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/cat",
                "arguments": [],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    assert_eq!(created["running"], json!(true));

    // Queue a message while the agent is busy: no delivery yet.
    expect_ok(request(
        &mut writer,
        &mut reader,
        61,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "working"}]}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        62,
        "orchestration.send",
        json!({"from": "coord", "to": session_id, "subject": "next step", "body": "run the tests"}),
    ));

    // The transition to done flushes the queue into the PTY.
    expect_ok(request(
        &mut writer,
        &mut reader,
        63,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}),
    ));

    // Collect PTY output events until the banner (echoed by cat) appears.
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut output = String::new();
    while Instant::now() < deadline {
        let message = read_message(&mut reader);
        if message.get("event") == Some(&json!("output"))
            && message["payload"]["sessionId"] == json!(session_id)
        {
            let bytes = STANDARD
                .decode(message["payload"]["dataBase64"].as_str().unwrap())
                .unwrap();
            output.push_str(&String::from_utf8_lossy(&bytes));
            if output.contains("Orchestration Messages (1)") && output.contains("next step") {
                break;
            }
        }
    }
    assert!(
        output.contains("Orchestration Messages (1)"),
        "banner never reached the PTY; captured: {output}"
    );
    assert!(output.contains("Subject: next step"));

    // After the deferred Enter, the message is stamped delivered: a second
    // done transition must not redeliver it.
    std::thread::sleep(Duration::from_millis(900));
    expect_ok(request(
        &mut writer,
        &mut reader,
        64,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "working"}]}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        65,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}),
    ));
    // Drain events briefly; a redelivered banner would echo again.
    let quiet_deadline = Instant::now() + Duration::from_secs(2);
    let mut redelivered = String::new();
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_millis(300)))
        .unwrap();
    while Instant::now() < quiet_deadline {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let message: Value = serde_json::from_str(line.trim_end()).unwrap();
                if message.get("event") == Some(&json!("output")) {
                    let bytes = STANDARD
                        .decode(message["payload"]["dataBase64"].as_str().unwrap())
                        .unwrap();
                    redelivered.push_str(&String::from_utf8_lossy(&bytes));
                }
            }
            Err(_) => break,
        }
    }
    assert!(
        !redelivered.contains("Orchestration Messages"),
        "message was redelivered after being marked delivered: {redelivered}"
    );
}

#[test]
fn lifecycle_to_group_and_unknown_recipients_are_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let group_lifecycle = request(
        &mut writer,
        &mut reader,
        70,
        "orchestration.send",
        json!({"from": "a", "to": "@all", "subject": "x", "type": "worker_done"}),
    );
    assert_eq!(group_lifecycle["ok"], json!(false));

    let no_recipients = request(
        &mut writer,
        &mut reader,
        71,
        "orchestration.send",
        json!({"from": "a", "to": "@all", "subject": "x"}),
    );
    assert_eq!(no_recipients["ok"], json!(false));
}
