use alera_core::child_process::windowless_command;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::path::Path;
use std::process::Child;
use std::time::{Duration, Instant};

#[cfg(unix)]
use base64::engine::general_purpose::STANDARD;
#[cfg(unix)]
use base64::Engine as _;
use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;

#[path = "orchestration_review_regressions/deferred_delivery_cases.rs"]
#[cfg(unix)]
mod deferred_delivery_cases;
#[path = "orchestration_review_regressions/orchestration_pain_point_cases.rs"]
#[cfg(unix)]
mod orchestration_pain_point_cases;
#[path = "orchestration_review_regressions/readiness_spawn_exit_cases.rs"]
#[cfg(unix)]
mod readiness_spawn_exit_cases;
#[path = "orchestration_review_regressions/terminal_prune_cases.rs"]
#[cfg(unix)]
mod terminal_prune_cases;
#[path = "orchestration_review_regressions/terminal_wait_input_cases.rs"]
#[cfg(unix)]
mod terminal_wait_input_cases;

struct HostGuard(Child);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

struct Host {
    _dir: tempfile::TempDir,
    _guard: HostGuard,
    port: u16,
    token: String,
}

fn read_control(path: &std::path::Path) -> Option<(u16, String)> {
    let contents = std::fs::read_to_string(path).ok()?;
    let value: Value = serde_json::from_str(&contents).ok()?;
    let port = value.get("port")?.as_u64()? as u16;
    let token = value.get("token")?.as_str()?.to_string();
    Some((port, token))
}

fn start_host() -> Host {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let token = "orchestration-review-test-token".to_string();
    let mut command = windowless_command(env!("CARGO_BIN_EXE_alera"));
    command.args([
        "runtime-host",
        "--runtime-dir",
        dir.path().to_str().unwrap(),
        "--control-file",
        control_path.to_str().unwrap(),
        "--token",
        &token,
        "--empty-shutdown-delay-seconds",
        "60",
        "--detached-session-shutdown-delay-seconds",
        "60",
    ]);
    #[cfg(unix)]
    command.env("SHELL", "/bin/bash");
    let child = command.spawn().expect("failed to spawn alera runtime-host");
    let guard = HostGuard(child);
    let deadline = Instant::now() + Duration::from_secs(10);
    let port = loop {
        if let Some((port, _)) = read_control(&control_path) {
            break port;
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    };
    Host {
        _dir: dir,
        _guard: guard,
        port,
        token,
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
    let mut line = serde_json::to_vec(&message).unwrap();
    line.push(b'\n');
    writer.write_all(&line).unwrap();
    writer.flush().unwrap();
}

#[cfg(unix)]
fn send_batch(writer: &mut TcpStream, messages: &[Value]) {
    let mut batch = Vec::new();
    for message in messages {
        serde_json::to_writer(&mut batch, message).unwrap();
        batch.push(b'\n');
    }
    writer.write_all(&batch).unwrap();
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

fn handshake(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, token: &str) {
    send(
        writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": PROTOCOL_VERSION, "token": token}}),
    );
    let hello = read_response(reader, 0);
    assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");
}

fn handshake_app(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, token: &str) {
    send(
        writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": PROTOCOL_VERSION, "token": token, "clientKind": "app"}}),
    );
    let hello = read_response(reader, 0);
    assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");
}

fn seed_workspace(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, workspace_id: &str) {
    seed_workspace_with_path(writer, reader, workspace_id, Path::new("/tmp"));
}

fn seed_workspace_with_path(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    workspace_id: &str,
    workspace_path: &Path,
) {
    expect_ok(request(
        writer,
        reader,
        9_000,
        "workspace.upsert",
        json!({
            "id": workspace_id,
            "instanceId": format!("{workspace_id}-instance"),
            "hostId": "local",
            "projectId": "project-1",
            "name": "Workspace",
            "branch": null,
            "path": workspace_path.to_string_lossy().to_string(),
            "createdAt": "2026-07-06T00:00:00.000Z",
            "updatedAt": "2026-07-06T00:00:00.000Z",
            "kind": "main",
            "status": "active",
            "sourceBranch": null,
            "reusesExistingBranch": false,
            "tagIds": [],
            "tagNames": [],
            "parentWorkspaceId": null,
            "childCount": 0
        }),
    ));
}

#[cfg(unix)]
fn worktree_behind_upstream(behind: usize) -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    let mut options = git2::RepositoryInitOptions::new();
    options.initial_head("main");
    let repo = git2::Repository::init_opts(dir.path(), &options).unwrap();
    repo.remote("origin", dir.path().to_str().unwrap()).unwrap();

    let base = commit_fixture_file(&repo, Some("HEAD"), None, "base\n", "base");
    let mut parent = base;
    for index in 0..behind {
        parent = commit_fixture_file(
            &repo,
            None,
            Some(parent),
            &format!("upstream {index}\n"),
            &format!("upstream {index}"),
        );
    }

    repo.reference("refs/remotes/origin/main", parent, true, "seed upstream")
        .unwrap();
    let mut config = repo.config().unwrap();
    config.set_str("branch.main.remote", "origin").unwrap();
    config
        .set_str("branch.main.merge", "refs/heads/main")
        .unwrap();
    drop(config);
    drop(repo);
    dir
}

#[cfg(unix)]
fn commit_fixture_file(
    repo: &git2::Repository,
    update_ref: Option<&str>,
    parent: Option<git2::Oid>,
    contents: &str,
    message: &str,
) -> git2::Oid {
    std::fs::write(repo.workdir().unwrap().join("drift.txt"), contents).unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("drift.txt")).unwrap();
    index.write().unwrap();
    let tree_id = index.write_tree().unwrap();
    let tree = repo.find_tree(tree_id).unwrap();
    let signature = git2::Signature::now("Alera Test", "alera@example.com").unwrap();
    let parent_commit = parent.map(|oid| repo.find_commit(oid).unwrap());
    let parents = parent_commit.iter().collect::<Vec<_>>();
    repo.commit(update_ref, &signature, &signature, message, &tree, &parents)
        .unwrap()
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

#[cfg(unix)]
fn collect_output(
    reader: &mut BufReader<TcpStream>,
    session_id: &str,
    duration: Duration,
) -> String {
    let deadline = Instant::now() + duration;
    let mut output = String::new();
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_millis(300)))
        .unwrap();
    while Instant::now() < deadline {
        let mut line = String::new();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let message: Value = serde_json::from_str(line.trim_end()).unwrap();
                if message.get("event") == Some(&json!("output"))
                    && message["payload"]["sessionId"] == json!(session_id)
                {
                    let bytes = STANDARD
                        .decode(message["payload"]["dataBase64"].as_str().unwrap())
                        .unwrap();
                    output.push_str(&String::from_utf8_lossy(&bytes));
                }
            }
            Err(_) => {}
        }
    }
    reader
        .get_mut()
        .set_read_timeout(Some(Duration::from_secs(15)))
        .unwrap();
    output
}

#[cfg(unix)]
fn attach_shell_session(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    session_id: &str,
    workspace_id: &str,
    tab_id: &str,
    arguments: &[&str],
) {
    expect_ok(request(
        writer,
        reader,
        id,
        "createOrAttach",
        json!({
            "sessionId": session_id,
            "workspaceId": workspace_id,
            "tabId": tab_id,
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": arguments,
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
}

#[cfg(unix)]
fn occurrences(haystack: &str, needle: &str) -> usize {
    haystack.match_indices(needle).count()
}

#[test]
fn waited_check_with_inject_returns_formatted_banner() {
    let host = start_host();
    let (mut waiter_writer, mut waiter_reader) = connect(host.port);
    handshake(&mut waiter_writer, &mut waiter_reader, &host.token);
    let (mut sender_writer, mut sender_reader) = connect(host.port);
    handshake(&mut sender_writer, &mut sender_reader, &host.token);

    send(
        &mut waiter_writer,
        json!({"id": 10, "type": "orchestration.check", "payload": {
            "terminal": "worker", "wait": true, "inject": true, "timeoutMs": 5000
        }}),
    );
    std::thread::sleep(Duration::from_millis(200));
    expect_ok(request(
        &mut sender_writer,
        &mut sender_reader,
        11,
        "orchestration.send",
        json!({"from": "coord", "to": "worker", "subject": "hello", "body": "body"}),
    ));

    let response = read_response(&mut waiter_reader, 10);
    assert_eq!(response["ok"], json!(true));
    let formatted = response["payload"]["formatted"].as_str().unwrap();
    assert!(formatted.contains("Orchestration Messages (1)"));
    assert!(formatted.contains("Subject: hello"));
}

#[test]
fn ask_timeout_survives_unrelated_message_wake() {
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
        json!({"id": 20, "type": "orchestration.ask", "payload": {
            "from": "worker", "to": "coord", "question": "Which path?", "timeoutMs": 700
        }}),
    );
    std::thread::sleep(Duration::from_millis(200));
    expect_ok(request(
        &mut coordinator_writer,
        &mut coordinator_reader,
        21,
        "orchestration.send",
        json!({"from": "coord", "to": "worker", "subject": "unrelated", "body": "noise"}),
    ));

    let response = read_response(&mut worker_reader, 20);
    assert_eq!(response["ok"], json!(true));
    assert_eq!(response["payload"]["answered"], json!(false));
    assert_eq!(response["payload"]["timedOut"], json!(true));
}

#[test]
fn check_all_applies_type_filter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    expect_ok(request(
        &mut writer,
        &mut reader,
        40,
        "orchestration.send",
        json!({"from": "worker", "to": "coord", "subject": "status", "body": "noise"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        41,
        "orchestration.send",
        json!({"from": "worker", "to": "coord", "type": "escalation", "subject": "blocked", "body": "details"}),
    ));

    let payload = expect_ok(request(
        &mut writer,
        &mut reader,
        42,
        "orchestration.check",
        json!({"terminal": "coord", "all": true, "types": ["escalation"]}),
    ));
    let messages = payload["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1, "{payload}");
    assert_eq!(messages[0]["type"], json!("escalation"));
    assert_eq!(messages[0]["subject"], json!("blocked"));
}

#[test]
#[cfg(unix)]
fn broadcast_group_sends_get_distinct_default_threads() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    for (id, handle) in [(431, "worker-a"), (432, "worker-b")] {
        attach_shell_session(
            &mut writer,
            &mut reader,
            id,
            handle,
            "ws-1",
            handle,
            &["-lc", "stty -echo; cat"],
        );
    }

    expect_ok(request(
        &mut writer,
        &mut reader,
        43,
        "orchestration.send",
        json!({"from": "coord", "to": "@all", "subject": "first", "body": "one"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        44,
        "orchestration.send",
        json!({"from": "coord", "to": "@all", "subject": "second", "body": "two"}),
    ));

    let payload = expect_ok(request(
        &mut writer,
        &mut reader,
        45,
        "orchestration.check",
        json!({"terminal": "worker-a", "all": true}),
    ));
    let messages = payload["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 2, "{payload}");
    let first_thread = messages[0]["thread_id"].as_str().unwrap();
    let second_thread = messages[1]["thread_id"].as_str().unwrap();
    assert_ne!(first_thread, second_thread, "{payload}");
}

#[test]
fn coordinator_run_requires_from_handle() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let response = request(
        &mut writer,
        &mut reader,
        40,
        "orchestration.run",
        json!({"spec": "coordinate"}),
    );
    assert_eq!(response["ok"], json!(false));
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("from is required"));
}

#[test]
fn stale_escalations_do_not_fail_current_dispatch() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        50,
        "orchestration.taskCreate",
        json!({"spec": "do work"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    let first = expect_ok(request(
        &mut writer,
        &mut reader,
        51,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": "worker", "from": "coord"}),
    ));
    let first_dispatch = first["dispatch"]["id"].as_str().unwrap().to_string();
    let first_context_token = first["contextToken"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        52,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": first_context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        520,
        "orchestration.complete",
        json!({"terminal": "worker", "contextToken": first_context_token, "result": {
            "summary": "first attempt", "completionKind": "failure",
            "artifacts": ["failure.log"], "filesModified": ["src/main.rs"],
            "validation": ["cargo test failed"]
        }}),
    ));
    let failed_attempt = expect_ok(request(
        &mut writer,
        &mut reader,
        521,
        "orchestration.taskShow",
        json!({"id": &task_id}),
    ));
    let failure_result: Value =
        serde_json::from_str(failed_attempt["task"]["result"].as_str().unwrap()).unwrap();
    assert_eq!(failure_result["artifacts"], json!(["failure.log"]));
    assert_eq!(failure_result["filesModified"], json!(["src/main.rs"]));
    let second = expect_ok(request(
        &mut writer,
        &mut reader,
        53,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": "worker", "from": "coord"}),
    ));
    let second_dispatch = second["dispatch"]["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        54,
        "orchestration.run",
        json!({"from": "coord", "spec": "coordinate", "pollIntervalMs": 100}),
    ));

    expect_ok(request(
        &mut writer,
        &mut reader,
        55,
        "orchestration.send",
        json!({
            "from": "intruder",
            "to": "coord",
            "type": "escalation",
            "subject": "Blocked: wrong terminal",
            "payload": json!({"taskId": &task_id}).to_string()
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        56,
        "orchestration.send",
        json!({
            "from": "worker",
            "to": "coord",
            "type": "escalation",
            "subject": "Blocked: missing dispatch",
            "payload": json!({"taskId": &task_id}).to_string()
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        57,
        "orchestration.send",
        json!({
            "from": "worker",
            "to": "coord",
            "type": "escalation",
            "subject": "Blocked: stale retry",
            "payload": json!({"taskId": &task_id, "dispatchId": &first_dispatch}).to_string()
        }),
    ));

    std::thread::sleep(Duration::from_millis(700));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        58,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert_eq!(show["active"]["id"], json!(second_dispatch));
    assert_eq!(show["active"]["status"], json!("awaiting_acceptance"));

    expect_ok(request(
        &mut writer,
        &mut reader,
        59,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn stale_decision_gates_do_not_block_current_dispatch() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        60,
        "orchestration.taskCreate",
        json!({"spec": "choose a path"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    let first = expect_ok(request(
        &mut writer,
        &mut reader,
        61,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": "worker", "from": "coord"}),
    ));
    let first_dispatch = first["dispatch"]["id"].as_str().unwrap().to_string();
    let first_context_token = first["contextToken"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        62,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": first_context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        620,
        "orchestration.complete",
        json!({"terminal": "worker", "contextToken": first_context_token, "result": {
            "summary": "first attempt", "completionKind": "failure",
            "artifacts": [], "filesModified": [], "validation": []
        }}),
    ));
    let second = expect_ok(request(
        &mut writer,
        &mut reader,
        63,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": "worker", "from": "coord"}),
    ));
    let second_dispatch = second["dispatch"]["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        64,
        "orchestration.run",
        json!({"from": "coord", "spec": "coordinate", "pollIntervalMs": 100}),
    ));

    expect_ok(request(
        &mut writer,
        &mut reader,
        65,
        "orchestration.send",
        json!({
            "from": "worker",
            "to": "coord",
            "type": "decision_gate",
            "subject": "Question: missing dispatch",
            "payload": json!({"taskId": &task_id, "question": "missing?"}).to_string()
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        66,
        "orchestration.send",
        json!({
            "from": "worker",
            "to": "coord",
            "type": "decision_gate",
            "subject": "Question: stale retry",
            "payload": json!({"taskId": &task_id, "dispatchId": &first_dispatch, "question": "stale?"}).to_string()
        }),
    ));

    std::thread::sleep(Duration::from_millis(700));
    let gates = expect_ok(request(
        &mut writer,
        &mut reader,
        67,
        "orchestration.gateList",
        json!({"task": &task_id}),
    ));
    assert_eq!(gates["gates"].as_array().unwrap().len(), 0, "{gates}");
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        68,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert_eq!(show["active"]["id"], json!(second_dispatch));
    assert_eq!(show["active"]["status"], json!("awaiting_acceptance"));

    expect_ok(request(
        &mut writer,
        &mut reader,
        69,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
#[cfg(unix)]
fn injected_dispatch_requires_idle_agent_presence() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "busy-worker";

    expect_ok(request(
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
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        61,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "working"}]}),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        62,
        "orchestration.taskCreate",
        json!({"spec": "busy injection", "workspace": "ws-1"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();

    let response = request(
        &mut writer,
        &mut reader,
        63,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": session_id, "from": "coord", "inject": true}),
    );
    assert_eq!(response["ok"], json!(false));
    assert!(response["error"].as_str().unwrap().contains("not idle"));

    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        64,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert!(show["active"].is_null());
    assert!(show["history"].as_array().unwrap().is_empty());
}

#[test]
#[cfg(unix)]
fn explicit_terminal_termination_fails_active_dispatch() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "terminated-worker";

    expect_ok(request(
        &mut writer,
        &mut reader,
        65,
        "createOrAttach",
        json!({
            "sessionId": session_id,
            "workspaceId": "ws-1",
            "tabId": "tab-1",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        66,
        "orchestration.taskCreate",
        json!({"spec": "active dispatch should fail on close"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        67,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": session_id, "from": "coord"}),
    ));

    expect_ok(request(
        &mut writer,
        &mut reader,
        68,
        "terminate",
        json!({"sessionId": session_id}),
    ));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        69,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert!(show["active"].is_null(), "{show}");
    assert_eq!(show["history"][0]["status"], json!("failed"), "{show}");
    assert!(
        show["history"][0]["last_failure"]
            .as_str()
            .unwrap()
            .contains("explicitly terminated"),
        "{show}"
    );
}

#[test]
#[cfg(unix)]
fn removed_agent_status_fails_active_dispatch() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "removed-status-worker";

    expect_ok(request(
        &mut writer,
        &mut reader,
        111,
        "createOrAttach",
        json!({
            "sessionId": session_id,
            "workspaceId": "ws-1",
            "tabId": "tab-1",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        112,
        "orchestration.taskCreate",
        json!({"spec": "active dispatch should fail on removed status"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        113,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": session_id, "from": "coord"}),
    ));

    expect_ok(request(
        &mut writer,
        &mut reader,
        114,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "removed": true}]}),
    ));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        115,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert!(show["active"].is_null(), "{show}");
    assert_eq!(show["history"][0]["status"], json!("failed"), "{show}");
    assert!(
        show["history"][0]["last_failure"]
            .as_str()
            .unwrap()
            .contains("agent status was removed"),
        "{show}"
    );
}

#[test]
#[cfg(unix)]
fn dispatch_injection_respects_cursor_skip_auto_enter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "cursor-worker";

    expect_ok(request(
        &mut writer,
        &mut reader,
        66,
        "createOrAttach",
        json!({
            "sessionId": session_id,
            "workspaceId": "ws-1",
            "tabId": "tab-1",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    std::thread::sleep(Duration::from_millis(700));
    let _ = collect_output(&mut reader, session_id, Duration::from_millis(400));
    expect_ok(request(
        &mut writer,
        &mut reader,
        67,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "cursor", "state": "done"}]}),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        68,
        "orchestration.taskCreate",
        json!({"spec": "cursor should keep this editable", "workspace": "ws-1"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();

    expect_ok(request(
        &mut writer,
        &mut reader,
        69,
        "orchestration.dispatch",
        json!({"task": &task_id, "to": session_id, "from": "coord", "inject": true}),
    ));

    let output = collect_output(&mut reader, session_id, Duration::from_secs(2));
    assert!(
        !output.contains("cursor should keep this editable"),
        "cursor dispatch task line was submitted instead of left editable: {output}"
    );
}

#[test]
#[cfg(unix)]
fn coordinator_force_submits_cursor_workers_and_waits_for_acceptance() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "cursor-coordinator-worker";

    attach_shell_session(
        &mut writer,
        &mut reader,
        1160,
        session_id,
        "ws-1",
        "tab-1",
        &["-lc", "stty -echo; cat"],
    );
    std::thread::sleep(Duration::from_millis(700));
    let _ = collect_output(&mut reader, session_id, Duration::from_millis(400));
    expect_ok(request(
        &mut writer,
        &mut reader,
        1161,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "cursor", "state": "done"}]}),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        1162,
        "orchestration.taskCreate",
        json!({"spec": "cursor must not be auto-dispatched"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();

    expect_ok(request(
        &mut writer,
        &mut reader,
        1163,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "ws-1"
        }),
    ));
    std::thread::sleep(Duration::from_millis(350));

    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        1164,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert_eq!(
        show["active"]["status"],
        json!("awaiting_acceptance"),
        "{show}"
    );
    assert_eq!(show["history"].as_array().unwrap().len(), 1, "{show}");
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        1165,
        "orchestration.taskList",
        json!({"status": "dispatched"}),
    ));
    assert_eq!(dispatched["tasks"][0]["id"], json!(task_id), "{dispatched}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        1166,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn coordinator_run_exposes_taskless_question_through_documented_filter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    expect_ok(request(
        &mut writer,
        &mut reader,
        70,
        "orchestration.taskCreate",
        json!({"spec": "keep run active"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        71,
        "orchestration.run",
        json!({"from": "coord", "spec": "coordinate", "pollIntervalMs": 100}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        72,
        "orchestration.send",
        json!({
            "from": "worker",
            "to": "coord",
            "type": "decision_gate",
            "subject": "Question: Which path?",
            "body": "Which path?"
        }),
    ));

    std::thread::sleep(Duration::from_millis(500));
    let inbox = expect_ok(request(
        &mut writer,
        &mut reader,
        73,
        "orchestration.check",
        json!({"terminal": "coord", "types": ["worker_done", "escalation", "decision_gate"]}),
    ));
    assert_eq!(inbox["messages"].as_array().unwrap().len(), 1);
    assert_eq!(
        inbox["messages"][0]["subject"],
        json!("Question: Which path?")
    );

    expect_ok(request(
        &mut writer,
        &mut reader,
        74,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn coordinator_run_does_not_consume_unhandled_status_message() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    expect_ok(request(
        &mut writer,
        &mut reader,
        76,
        "orchestration.taskCreate",
        json!({"spec": "keep run active"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        77,
        "orchestration.run",
        json!({"from": "coord", "spec": "coordinate", "pollIntervalMs": 100}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        78,
        "orchestration.send",
        json!({
            "from": "worker",
            "to": "coord",
            "type": "status",
            "subject": "Progress",
            "body": "Still working"
        }),
    ));

    std::thread::sleep(Duration::from_millis(500));
    let inbox = expect_ok(request(
        &mut writer,
        &mut reader,
        79,
        "orchestration.check",
        json!({"terminal": "coord", "types": ["status"]}),
    ));
    assert_eq!(inbox["messages"].as_array().unwrap().len(), 1);
    assert_eq!(inbox["messages"][0]["subject"], json!("Progress"));

    expect_ok(request(
        &mut writer,
        &mut reader,
        80,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
#[cfg(unix)]
fn coordinator_codex_spawn_respects_stale_base_skip() {
    let repo_dir = worktree_behind_upstream(21);
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace_with_path(&mut writer, &mut reader, "ws-stale", repo_dir.path());

    let skipped = expect_ok(request(
        &mut writer,
        &mut reader,
        85,
        "orchestration.taskCreate",
        json!({"spec": "blocked by stale base"}),
    ));
    let skipped_task_id = skipped["id"].as_str().unwrap().to_string();
    std::thread::sleep(Duration::from_millis(1_100));
    let allowed = expect_ok(request(
        &mut writer,
        &mut reader,
        86,
        "orchestration.taskCreate",
        json!({"spec": "allow-stale-base: true\ncan still dispatch"}),
    ));
    let allowed_task_id = allowed["id"].as_str().unwrap().to_string();

    expect_ok(request(
        &mut writer,
        &mut reader,
        89,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "maxConcurrent": 1,
            "workspace": "ws-stale",
            "agent": "codex"
        }),
    ));

    std::thread::sleep(Duration::from_millis(700));
    let skipped_show = expect_ok(request(
        &mut writer,
        &mut reader,
        90,
        "orchestration.dispatchShow",
        json!({"task": &skipped_task_id}),
    ));
    assert!(skipped_show["active"].is_null(), "{skipped_show}");
    let allowed_show = expect_ok(request(
        &mut writer,
        &mut reader,
        91,
        "orchestration.dispatchShow",
        json!({"task": &allowed_task_id}),
    ));
    assert_eq!(
        allowed_show["active"]["status"],
        json!("awaiting_acceptance"),
        "{allowed_show}"
    );
    let worker_handle = allowed_show["active"]["assignee_handle"]
        .as_str()
        .unwrap()
        .to_string();
    let context_file = std::fs::read_to_string(
        host._dir
            .path()
            .join("orchestration-contexts")
            .join(format!("{worker_handle}.json")),
    )
    .unwrap();
    let context_credentials: Value = serde_json::from_str(&context_file).unwrap();
    let context_token = context_credentials["token"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        92,
        "orchestration.dispatchAccept",
        json!({"terminal": &worker_handle, "contextToken": context_token}),
    ));
    let context = expect_ok(request(
        &mut writer,
        &mut reader,
        93,
        "orchestration.context",
        json!({"terminal": &worker_handle, "contextToken": context_token}),
    ));
    assert_eq!(context["task"]["spec"], json!("can still dispatch"));
    assert_eq!(context["baseDrift"]["base"], json!("origin/main"));
    assert_eq!(context["baseDrift"]["behind"], json!(21));
    assert!(
        !context["baseDrift"]["recentSubjects"]
            .as_array()
            .unwrap()
            .is_empty(),
        "{context}"
    );

    expect_ok(request(
        &mut writer,
        &mut reader,
        94,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn coordinator_waits_for_spawned_worker_presence_before_creating_another() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");

    expect_ok(request(
        &mut writer,
        &mut reader,
        80,
        "orchestration.taskCreate",
        json!({"spec": "needs a worker"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        81,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "ws-1"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        82,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 1, "{tabs}");
    assert_eq!(tabs[0]["payload"]["spawnOnCreate"], json!(true));
    assert_eq!(tabs[0]["payload"]["initialCommand"], json!("claude"));

    std::thread::sleep(Duration::from_millis(350));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        83,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 1, "{tabs}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        84,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

/// A coordinator-spawned Claude worker is dispatched at spawn, like every other
/// agent. Waiting for it to announce itself first would wait forever: a worker
/// that has been asked nothing never reports that it is idle.
#[test]
#[cfg(unix)]
fn coordinator_dispatches_a_spawned_claude_worker_without_waiting_for_presence() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake_app(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");

    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        116,
        "orchestration.taskCreate",
        json!({"spec": "dispatch after spawned Claude starts"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        117,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "ws-1"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        118,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 1, "{tabs}");
    let tab_id = tabs[0]["id"].as_str().unwrap().to_string();
    let worker_handle = tabs[0]["payload"]["terminalSessionId"]
        .as_str()
        .unwrap()
        .to_string();

    expect_ok(request(
        &mut writer,
        &mut reader,
        119,
        "createOrAttach",
        json!({
            "sessionId": worker_handle,
            "workspaceId": "ws-1",
            "tabId": tab_id,
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        120,
        "write",
        json!({"sessionId": worker_handle, "dataBase64": STANDARD.encode("claude\n")}),
    ));

    std::thread::sleep(Duration::from_millis(650));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        121,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert_eq!(
        show["active"]["status"],
        json!("awaiting_acceptance"),
        "{show}"
    );
    assert_eq!(
        show["active"]["assignee_handle"],
        json!(worker_handle),
        "{show}"
    );

    // A presence report on an already dispatched worker changes nothing.
    expect_ok(request(
        &mut writer,
        &mut reader,
        122,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": worker_handle, "agentType": "claude", "state": "done"}]}),
    ));

    std::thread::sleep(Duration::from_millis(650));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        123,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert_eq!(
        show["active"]["status"],
        json!("awaiting_acceptance"),
        "{show}"
    );
    assert_eq!(show["history"].as_array().unwrap().len(), 1, "{show}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        124,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn coordinator_counts_booting_worker_presence_as_pending() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake_app(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");

    expect_ok(request(
        &mut writer,
        &mut reader,
        95,
        "orchestration.taskCreate",
        json!({"spec": "needs one booting worker"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        96,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "ws-1"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        97,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 1, "{tabs}");
    let worker_handle = tabs[0]["payload"]["terminalSessionId"]
        .as_str()
        .unwrap()
        .to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        98,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": worker_handle, "agentType": "claude", "state": "working"}]}),
    ));

    std::thread::sleep(Duration::from_millis(450));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        99,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 1, "{tabs}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        100,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
#[cfg(unix)]
fn coordinator_does_not_count_busy_spawned_worker_as_pending() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake_app(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let worker_handle = "busy-spawned-worker";
    let now = chrono::Utc::now().to_rfc3339();

    let first = expect_ok(request(
        &mut writer,
        &mut reader,
        101,
        "orchestration.taskCreate",
        json!({"spec": "first concurrent task"}),
    ));
    let first_task_id = first["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        102,
        "orchestration.taskCreate",
        json!({"spec": "second concurrent task"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        103,
        "tab.upsert",
        json!({
            "id": "busy-spawned-worker-tab",
            "workspaceId": "ws-1",
            "kind": "terminal",
            "title": "Worker: busy",
            "createdAt": now,
            "updatedAt": now,
            "payload": {
                "terminalSessionId": worker_handle,
                "initialCommand": "claude",
                "spawnOnCreate": true
            }
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        104,
        "createOrAttach",
        json!({
            "sessionId": worker_handle,
            "workspaceId": "ws-1",
            "tabId": "busy-spawned-worker-tab",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        105,
        "orchestration.dispatch",
        json!({"task": &first_task_id, "to": worker_handle, "from": "coord"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        106,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": worker_handle, "agentType": "claude", "state": "working"}]}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        107,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "maxConcurrent": 2,
            "workspace": "ws-1"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        109,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 2, "{tabs}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        110,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
#[cfg(unix)]
fn coordinator_reuses_done_spawned_worker_instead_of_spawning_replacement() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake_app(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let worker_handle = "done-spawned-worker";
    let now = chrono::Utc::now().to_rfc3339();

    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        123,
        "orchestration.taskCreate",
        json!({"spec": "needs a replacement worker"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        124,
        "tab.upsert",
        json!({
            "id": "done-spawned-worker-tab",
            "workspaceId": "ws-1",
            "kind": "terminal",
            "title": "Worker: done",
            "createdAt": now,
            "updatedAt": now,
            "payload": {
                "terminalSessionId": worker_handle,
                "initialCommand": "claude",
                "spawnOnCreate": true
            }
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        125,
        "createOrAttach",
        json!({
            "sessionId": worker_handle,
            "workspaceId": "ws-1",
            "tabId": "done-spawned-worker-tab",
            "workingDirectory": "/tmp",
            "launch": {
                "shell": "/bin/sh",
                "arguments": ["-lc", "stty -echo; cat"],
                "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
            },
            "cols": 120,
            "rows": 40
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        126,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": worker_handle, "agentType": "claude", "state": "done"}]}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        127,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "ws-1"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        128,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 1, "{tabs}");
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        129,
        "orchestration.dispatchShow",
        json!({"task": &task_id}),
    ));
    assert_eq!(
        show["active"]["status"],
        json!("awaiting_acceptance"),
        "{show}"
    );
    assert_eq!(
        show["active"]["assignee_handle"],
        json!(worker_handle),
        "{show}"
    );

    expect_ok(request(
        &mut writer,
        &mut reader,
        130,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn coordinator_ignores_stale_spawned_worker_tabs_when_creating_replacement() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake_app(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");

    expect_ok(request(
        &mut writer,
        &mut reader,
        85,
        "tab.upsert",
        json!({
            "id": "stale-worker-tab",
            "workspaceId": "ws-1",
            "kind": "terminal",
            "title": "Worker: stale",
            "createdAt": "2000-01-01T00:00:00Z",
            "updatedAt": "2000-01-01T00:00:00Z",
            "payload": {
                "terminalSessionId": "stale-worker-tab",
                "initialCommand": "claude",
                "spawnOnCreate": true
            }
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        86,
        "orchestration.taskCreate",
        json!({"spec": "needs a replacement worker"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        87,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "ws-1"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        88,
        "tab.list",
        json!({"workspaceId": "ws-1"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 2, "{tabs}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        89,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn coordinator_does_not_create_worker_tab_for_missing_workspace() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake_app(&mut writer, &mut reader, &host.token);

    expect_ok(request(
        &mut writer,
        &mut reader,
        131,
        "orchestration.taskCreate",
        json!({"spec": "needs a worker"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        132,
        "orchestration.run",
        json!({
            "from": "coord",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "workspace": "missing-workspace"
        }),
    ));

    std::thread::sleep(Duration::from_millis(550));
    let tabs = expect_ok(request(
        &mut writer,
        &mut reader,
        133,
        "tab.list",
        json!({"workspaceId": "missing-workspace"}),
    ));
    assert_eq!(tabs.as_array().unwrap().len(), 0, "{tabs}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        134,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn reset_tasks_stops_active_coordinator() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    expect_ok(request(
        &mut writer,
        &mut reader,
        70,
        "orchestration.taskCreate",
        json!({"spec": "first"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        71,
        "orchestration.run",
        json!({"from": "coord", "spec": "coordinate", "pollIntervalMs": 10_000}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        72,
        "orchestration.reset",
        json!({"tasks": true}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        73,
        "orchestration.taskCreate",
        json!({"spec": "second"}),
    ));
    let rerun = request(
        &mut writer,
        &mut reader,
        74,
        "orchestration.run",
        json!({"from": "coord", "spec": "coordinate again", "pollIntervalMs": 10_000}),
    );
    assert_eq!(rerun["ok"], json!(true), "rerun failed: {rerun}");
    expect_ok(request(
        &mut writer,
        &mut reader,
        75,
        "orchestration.runStop",
        json!({"force": true}),
    ));
}

#[test]
fn task_cancel_enforces_coordinator_ownership_unless_forced() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        80,
        "orchestration.taskCreate",
        json!({"spec": "owned work", "coordinator": "owner"}),
    ));
    let task_id = task["id"].as_str().unwrap();

    let rejected = request(
        &mut writer,
        &mut reader,
        81,
        "orchestration.taskCancel",
        json!({"id": task_id, "reason": "intruder", "actor": "other"}),
    );
    assert_eq!(rejected["ok"], json!(false), "{rejected}");
    assert!(rejected["error"]
        .as_str()
        .unwrap()
        .contains("only coordinator owner"));

    let cancelled = expect_ok(request(
        &mut writer,
        &mut reader,
        82,
        "orchestration.taskCancel",
        json!({"id": task_id, "reason": "admin recovery", "actor": "other", "force": true}),
    ));
    assert_eq!(cancelled["task"]["status"], json!("cancelled"));
}

#[test]
#[cfg(unix)]
fn lifecycle_mutations_enforce_coordinator_ownership() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_090,
        "owner",
        "ws-1",
        "owner-tab",
        &["-c", "stty -echo; cat"],
    );
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_091,
        "unrelated",
        "ws-2",
        "unrelated-tab",
        &["-c", "stty -echo; cat"],
    );
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_100,
        "orchestration.taskCreate",
        json!({"spec": "owned work", "coordinator": "owner", "workspace": "ws-1"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_101,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "worker", "from": "owner"}),
    ));
    let dispatch_id = dispatched["dispatch"]["id"].as_str().unwrap();
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_102,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": context_token}),
    ));

    let interrupt = request(
        &mut writer,
        &mut reader,
        8_103,
        "orchestration.dispatchInterrupt",
        json!({"id": dispatch_id, "reason": "intruder", "actor": "other"}),
    );
    assert_eq!(interrupt["ok"], json!(false), "{interrupt}");
    assert!(interrupt["error"]
        .as_str()
        .unwrap()
        .contains("only coordinator owner"));

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        sqlx::query("UPDATE orchestrationTasks SET status = 'stalled' WHERE id = ?")
            .bind(task_id)
            .execute(store.pool())
            .await
            .unwrap();
        sqlx::query("UPDATE orchestrationDispatchContexts SET status = 'stalled' WHERE id = ?")
            .bind(dispatch_id)
            .execute(store.pool())
            .await
            .unwrap();
    });
    let recover = request(
        &mut writer,
        &mut reader,
        8_104,
        "orchestration.taskRecover",
        json!({"id": task_id, "status": "ready", "reason": "intruder", "actor": "other"}),
    );
    assert_eq!(recover["ok"], json!(false), "{recover}");
    assert!(recover["error"]
        .as_str()
        .unwrap()
        .contains("only coordinator owner"));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_105,
        "orchestration.taskRecover",
        json!({"id": task_id, "status": "ready", "reason": "retry", "actor": "owner"}),
    ));

    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        8_106,
        "orchestration.run",
        json!({"from": "owner", "spec": "coordinate", "workspace": "ws-1", "pollIntervalMs": 60000}),
    ));
    let run_id = run["runId"].as_str().unwrap();
    let status = expect_ok(request(
        &mut writer,
        &mut reader,
        81_061,
        "orchestration.status",
        json!({"id": run_id}),
    ));
    let terminal_handles = status["terminals"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|terminal| terminal["handle"].as_str())
        .collect::<Vec<_>>();
    assert_eq!(terminal_handles, vec!["owner"], "{status}");
    let stop = request(
        &mut writer,
        &mut reader,
        8_107,
        "orchestration.runStop",
        json!({"id": run_id, "actor": "other"}),
    );
    assert_eq!(stop["ok"], json!(false), "{stop}");
    assert!(stop["error"]
        .as_str()
        .unwrap()
        .contains("only coordinator owner"));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_108,
        "orchestration.runStop",
        json!({"id": run_id, "actor": "owner"}),
    ));
}

#[test]
fn forced_run_stop_preserves_administrative_actor_in_task_audit() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_300,
        "orchestration.taskCreate",
        json!({"spec": "active", "workspace": "ws-1", "coordinator": "owner"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        8_301,
        "orchestration.run",
        json!({"from": "owner", "spec": "coordinate", "workspace": "ws-1", "pollIntervalMs": 60000}),
    ));
    let run_id = run["runId"].as_str().unwrap();
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_302,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "worker", "from": "owner"}),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_303,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_304,
        "orchestration.runStop",
        json!({
            "id": run_id,
            "actor": "admin",
            "force": true,
            "cancelActive": true,
            "reason": "emergency stop"
        }),
    ));

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        let rows = sqlx::query(
            "SELECT actor_handle, action FROM orchestrationAuditEvents ORDER BY created_at, id",
        )
        .fetch_all(store.pool())
        .await
        .unwrap();
        let entries = rows
            .iter()
            .map(|row| {
                (
                    sqlx::Row::get::<Option<String>, _>(row, "actor_handle"),
                    sqlx::Row::get::<String, _>(row, "action"),
                )
            })
            .collect::<Vec<_>>();
        assert!(entries.contains(&(Some("admin".to_string()), "task.cancel.force".to_string())));
        assert!(entries.contains(&(Some("admin".to_string()), "run.stop.force".to_string())));
        let stopped = store
            .orchestration_coordinator_run_by_id(run_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(stopped.stop_reason.as_deref(), Some("emergency stop"));
    });
}

#[test]
fn worker_done_recovery_enforces_task_result_schema() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        83,
        "orchestration.taskCreate",
        json!({
            "spec": "schema work",
            "resultSchema": json!({
                "type": "object",
                "properties": {"ticket": {"type": "integer"}},
                "required": ["ticket"]
            }).to_string()
        }),
    ));
    let task_id = task["id"].as_str().unwrap();
    let dispatch = expect_ok(request(
        &mut writer,
        &mut reader,
        84,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "worker", "from": "coord"}),
    ));
    let dispatch_id = dispatch["dispatch"]["id"].as_str().unwrap();

    let rejected = request(
        &mut writer,
        &mut reader,
        85,
        "orchestration.workerDone",
        json!({
            "terminal": "worker",
            "task": task_id,
            "dispatch": dispatch_id,
            "result": {
                "summary": "done",
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": []
            }
        }),
    );
    assert_eq!(rejected["ok"], json!(false), "{rejected}");
    assert!(rejected["error"].as_str().unwrap().contains("ticket"));

    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        86,
        "orchestration.taskShow",
        json!({"id": task_id}),
    ));
    assert_eq!(show["task"]["status"], json!("dispatched"));
}

#[test]
fn context_aware_escalation_preserves_dispatch_authority() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        87,
        "orchestration.taskCreate",
        json!({"spec": "escalate", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        88,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "worker", "from": "coord"}),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        89,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        90,
        "orchestration.run",
        json!({
            "from": "coord",
            "workspace": "ws-1",
            "agent": "codex",
            "spec": "coordinate",
            "pollIntervalMs": 50
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        91,
        "orchestration.escalate",
        json!({
            "terminal": "worker",
            "contextToken": context_token,
            "subject": "Blocked",
            "body": "Need coordinator help"
        }),
    ));

    std::thread::sleep(Duration::from_millis(250));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        92,
        "orchestration.dispatchShow",
        json!({"task": task_id}),
    ));
    assert!(show["active"].is_null(), "{show}");
    assert_eq!(show["history"][0]["status"], json!("failed"), "{show}");
}

#[test]
#[cfg(unix)]
fn stalled_task_keeps_coordinator_run_available_for_recovery() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        93,
        "orchestration.taskCreate",
        json!({"spec": "lease", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let queued = expect_ok(request(
        &mut writer,
        &mut reader,
        94,
        "orchestration.taskCreate",
        json!({"spec": "second", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let queued_task_id = queued["id"].as_str().unwrap();
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        95,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "worker", "from": "coord"}),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        96,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": context_token}),
    ));
    attach_shell_session(
        &mut writer,
        &mut reader,
        9_601,
        "idle-after-stall",
        "ws-1",
        "idle-after-stall-tab",
        &["-c", "stty -echo; cat"],
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        9_602,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": "idle-after-stall", "agentType": "codex", "state": "done"}]}),
    ));
    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        9_603,
        "orchestration.run",
        json!({
            "from": "coord",
            "workspace": "ws-1",
            "agent": "codex",
            "spec": "coordinate",
            "pollIntervalMs": 100,
            "maxConcurrent": 1
        }),
    ));
    let run_id = run["runId"].as_str().unwrap();

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        let future_threshold = chrono::Utc::now()
            .checked_add_signed(chrono::Duration::hours(1))
            .unwrap()
            .format("%Y-%m-%d %H:%M:%S")
            .to_string();
        let stalled = store
            .stall_expired_orchestration_dispatches(&future_threshold)
            .await
            .unwrap();
        assert_eq!(stalled.len(), 1);
    });

    std::thread::sleep(Duration::from_millis(450));
    let queued_show = expect_ok(request(
        &mut writer,
        &mut reader,
        9_604,
        "orchestration.dispatchShow",
        json!({"task": queued_task_id}),
    ));
    assert!(queued_show["active"].is_null(), "{queued_show}");
    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        97,
        "orchestration.runShow",
        json!({"id": run_id}),
    ));
    assert_eq!(run["run"]["status"], json!("running"), "{run}");
    let recovered = expect_ok(request(
        &mut writer,
        &mut reader,
        98,
        "orchestration.taskRecover",
        json!({"id": task_id, "status": "ready", "reason": "worker stopped", "actor": "coord"}),
    ));
    assert_eq!(recovered["task"]["status"], json!("ready"));
}

#[test]
#[cfg(unix)]
fn cancelling_active_worker_interrupts_before_idle_banner_delivery() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "cancel-worker";
    attach_shell_session(
        &mut writer,
        &mut reader,
        99,
        session_id,
        "ws-1",
        "tab-1",
        &[
            "-c",
            "stty -echo; trap 'printf INTERRUPTED' INT; while :; do IFS= read -r line || continue; printf 'LINE:%s' \"$line\"; done",
        ],
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        100,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "codex", "state": "working"}]}),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        101,
        "orchestration.taskCreate",
        json!({"spec": "cancel me", "coordinator": "coord"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        102,
        "orchestration.dispatch",
        json!({"task": task_id, "to": session_id, "from": "coord"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        103,
        "orchestration.taskCancel",
        json!({"id": task_id, "reason": "stop now", "actor": "coord"}),
    ));

    let active_output = collect_output(&mut reader, session_id, Duration::from_secs(1));
    assert!(active_output.contains("INTERRUPTED"), "{active_output:?}");
    assert!(
        !active_output.contains("Task Cancelled"),
        "{active_output:?}"
    );
    let queued = expect_ok(request(
        &mut writer,
        &mut reader,
        104,
        "orchestration.inbox",
        json!({"terminal": session_id, "direction": "inbound"}),
    ));
    assert_eq!(queued["items"][0]["subject"], json!("Task Cancelled"));
    assert!(queued["items"][0]["delivered_at"].is_null(), "{queued}");

    expect_ok(request(
        &mut writer,
        &mut reader,
        105,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "codex", "state": "done"}]}),
    ));
    std::thread::sleep(Duration::from_secs(1));
    let delivered = expect_ok(request(
        &mut writer,
        &mut reader,
        106,
        "orchestration.inbox",
        json!({"terminal": session_id, "direction": "inbound"}),
    ));
    assert!(
        delivered["items"][0]["delivered_at"].is_string(),
        "{delivered}"
    );
}

#[test]
#[cfg(unix)]
fn pty_output_refreshes_active_dispatch_activity() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "active-output-worker";
    attach_shell_session(
        &mut writer,
        &mut reader,
        107,
        session_id,
        "ws-1",
        "tab-1",
        &[
            "-c",
            "stty -echo; while IFS= read -r line; do printf 'OUTPUT:%s' \"$line\"; done",
        ],
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        108,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "codex", "state": "working"}]}),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        109,
        "orchestration.taskCreate",
        json!({"spec": "long build", "coordinator": "coord"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        110,
        "orchestration.dispatch",
        json!({"task": task_id, "to": session_id, "from": "coord"}),
    ));
    let dispatch_id = dispatched["dispatch"]["id"].as_str().unwrap();
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        111,
        "orchestration.dispatchAccept",
        json!({"terminal": session_id, "contextToken": context_token}),
    ));

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET last_activity_at = '2020-01-01 00:00:00' WHERE id = ?",
        )
        .bind(dispatch_id)
        .execute(store.pool())
        .await
        .unwrap();
    });
    expect_ok(request(
        &mut writer,
        &mut reader,
        112,
        "write",
        json!({"sessionId": session_id, "dataBase64": STANDARD.encode(b"go\n")}),
    ));
    std::thread::sleep(Duration::from_millis(150));
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        let threshold = (chrono::Utc::now() - chrono::Duration::minutes(1))
            .format("%Y-%m-%d %H:%M:%S")
            .to_string();
        assert!(store
            .stall_expired_orchestration_dispatches(&threshold)
            .await
            .unwrap()
            .is_empty());
    });
}

#[test]
fn task_create_rejects_invalid_run_scope() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_200,
        "orchestration.taskCreate",
        json!({"spec": "seed", "workspace": "ws-1", "coordinator": "owner"}),
    ));
    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        8_201,
        "orchestration.run",
        json!({"from": "owner", "spec": "coordinate", "workspace": "ws-1", "pollIntervalMs": 60000}),
    ));
    let run_id = run["runId"].as_str().unwrap();

    for (request_id, payload, expected) in [
        (
            8_202,
            json!({"spec": "missing", "workspace": "ws-1", "run": "run_missing"}),
            "coordinator run not found",
        ),
        (
            8_203,
            json!({"spec": "wrong workspace", "workspace": "ws-2", "run": run_id}),
            "does not match run workspace",
        ),
        (
            8_204,
            json!({"spec": "wrong owner", "workspace": "ws-1", "run": run_id, "coordinator": "other"}),
            "does not match run coordinator",
        ),
    ] {
        let rejected = request(
            &mut writer,
            &mut reader,
            request_id,
            "orchestration.taskCreate",
            payload,
        );
        assert_eq!(rejected["ok"], json!(false), "{rejected}");
        assert!(rejected["error"].as_str().unwrap().contains(expected));
    }
    let valid = expect_ok(request(
        &mut writer,
        &mut reader,
        8_205,
        "orchestration.taskCreate",
        json!({"spec": "valid", "workspace": "ws-1", "run": run_id}),
    ));
    assert_eq!(valid["run_id"], json!(run_id));
    assert_eq!(valid["coordinator_handle"], json!("owner"));
    let transfer = request(
        &mut writer,
        &mut reader,
        82_051,
        "orchestration.transferCoordinator",
        json!({
            "task": valid["id"],
            "to": "replacement",
            "reason": "partial handoff",
            "actor": "owner",
            "force": true
        }),
    );
    assert_eq!(transfer["ok"], json!(false), "{transfer}");
    assert!(transfer["error"]
        .as_str()
        .unwrap()
        .contains("transfer the run instead"));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_206,
        "orchestration.runStop",
        json!({"id": run_id, "actor": "owner"}),
    ));
}

#[test]
fn active_worker_questions_follow_run_coordinator_transfer() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_230,
        "orchestration.taskCreate",
        json!({"spec": "ask", "workspace": "ws-1", "coordinator": "old-coord"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        8_231,
        "orchestration.run",
        json!({"from": "old-coord", "spec": "coordinate", "workspace": "ws-1", "pollIntervalMs": 60000}),
    ));
    let run_id = run["runId"].as_str().unwrap();
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_232,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "worker", "from": "old-coord"}),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_233,
        "orchestration.dispatchAccept",
        json!({"terminal": "worker", "contextToken": context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_234,
        "orchestration.transferCoordinator",
        json!({
            "run": run_id,
            "to": "new-coord",
            "reason": "handoff",
            "actor": "old-coord"
        }),
    ));

    send(
        &mut writer,
        json!({
            "id": 8_235,
            "type": "orchestration.ask",
            "payload": {
                "from": "worker",
                "to": "old-coord",
                "question": "Where next?",
                "timeoutMs": 5000
            }
        }),
    );
    let new_inbox = expect_ok(request(
        &mut writer,
        &mut reader,
        8_236,
        "orchestration.inbox",
        json!({"terminal": "new-coord"}),
    ));
    assert_eq!(
        new_inbox["items"].as_array().unwrap().len(),
        1,
        "{new_inbox}"
    );
    assert_eq!(new_inbox["items"][0]["to_handle"], json!("new-coord"));
    assert_eq!(
        new_inbox["items"][0]["dispatch_id"],
        dispatched["dispatch"]["id"]
    );
    let old_inbox = expect_ok(request(
        &mut writer,
        &mut reader,
        8_237,
        "orchestration.inbox",
        json!({"terminal": "old-coord"}),
    ));
    assert!(old_inbox["items"].as_array().unwrap().is_empty());
}

#[test]
#[cfg(unix)]
fn injected_dispatch_rejects_terminal_from_another_workspace() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_210,
        "worker-ws-2",
        "ws-2",
        "worker-tab",
        &["-c", "stty -echo; cat"],
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_211,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": "worker-ws-2", "agentType": "codex", "state": "done"}]}),
    ));
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_212,
        "orchestration.taskCreate",
        json!({"spec": "scoped", "workspace": "ws-1", "coordinator": "owner"}),
    ));
    let rejected = request(
        &mut writer,
        &mut reader,
        8_213,
        "orchestration.dispatch",
        json!({
            "task": task["id"],
            "to": "worker-ws-2",
            "from": "owner",
            "inject": true
        }),
    );
    assert_eq!(rejected["ok"], json!(false), "{rejected}");
    assert!(rejected["error"]
        .as_str()
        .unwrap()
        .contains("not task workspace ws-1"));
}

#[test]
#[cfg(unix)]
fn close_on_success_removes_the_persisted_worker_tab() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let now = chrono::Utc::now().to_rfc3339();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_220,
        "tab.upsert",
        json!({
            "id": "close-tab",
            "workspaceId": "ws-1",
            "kind": "terminal",
            "title": "Close Worker",
            "createdAt": now,
            "updatedAt": now,
            "payload": {"terminalSessionId": "close-worker"}
        }),
    ));
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_221,
        "close-worker",
        "ws-1",
        "close-tab",
        &["-c", "stty -echo; cat"],
    );
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_222,
        "orchestration.taskCreate",
        json!({"spec": "close", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_223,
        "orchestration.dispatch",
        json!({
            "task": task["id"],
            "to": "close-worker",
            "from": "coord",
            "terminalPolicy": "close-on-success"
        }),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_224,
        "orchestration.dispatchAccept",
        json!({"terminal": "close-worker", "contextToken": context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_225,
        "orchestration.complete",
        json!({
            "terminal": "close-worker",
            "contextToken": context_token,
            "result": {
                "summary": "done",
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": []
            }
        }),
    ));

    let tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_226,
        "tab.find",
        json!({"id": "close-tab"}),
    ));
    assert!(tab.is_null(), "{tab}");
    let terminal = request(
        &mut writer,
        &mut reader,
        8_227,
        "orchestration.terminalShow",
        json!({"handle": "close-worker"}),
    );
    assert_eq!(terminal["ok"], json!(false), "{terminal}");
}

#[test]
#[cfg(unix)]
fn completed_dispatch_does_not_hide_an_exited_terminal() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_228,
        "exited-worker",
        "ws-1",
        "exited-tab",
        &["-c", "stty -echo; cat"],
    );
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_229,
        "orchestration.taskCreate",
        json!({"spec": "exit after completion", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_230,
        "orchestration.dispatch",
        json!({"task": task["id"], "to": "exited-worker", "from": "coord"}),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_231,
        "orchestration.dispatchAccept",
        json!({"terminal": "exited-worker", "contextToken": context_token}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_232,
        "orchestration.complete",
        json!({
            "terminal": "exited-worker",
            "contextToken": context_token,
            "result": {
                "summary": "done",
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": []
            }
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_233,
        "write",
        json!({"sessionId": "exited-worker", "dataBase64": STANDARD.encode([3_u8])}),
    ));

    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let terminal = expect_ok(request(
            &mut writer,
            &mut reader,
            8_234,
            "orchestration.terminalShow",
            json!({"handle": "exited-worker"}),
        ));
        if terminal["running"] == json!(false) {
            assert_eq!(terminal["startupState"], json!("failed"), "{terminal}");
            break;
        }
        assert!(
            Instant::now() < deadline,
            "terminal did not exit: {terminal}"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}
