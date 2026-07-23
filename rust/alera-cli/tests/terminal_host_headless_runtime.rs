//! Runtime-owned terminal lifecycle tests that do not connect a desktop client.

use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::{Child, Command};
use std::time::{Duration, Instant};

use alera_core::runtime::{
    RuntimeAgentStatusHookSettings, RuntimeStore, Workspace, WorkspaceTabRecord,
};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;

struct HostGuard(Child);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
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
    let read = reader.read_line(&mut line).unwrap();
    assert!(read > 0, "host closed the connection unexpectedly");
    serde_json::from_str(line.trim_end()).unwrap()
}

fn read_response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let message = read_message(reader);
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
    }
}

fn connect(port: u16, token: &str) -> (TcpStream, BufReader<TcpStream>) {
    let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    let mut writer = stream.try_clone().unwrap();
    let mut reader = BufReader::new(stream);
    send(
        &mut writer,
        json!({"id": 0, "type": "hello", "payload": {"protocolVersion": PROTOCOL_VERSION, "token": token}}),
    );
    let hello = read_message(&mut reader);
    assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");
    (writer, reader)
}

fn spawn_host(runtime_dir: &std::path::Path, token: &str) -> (HostGuard, u16) {
    let control_path = runtime_dir.join("runtime-host.json");
    let test_home = runtime_dir.join("test-home");
    std::fs::create_dir_all(&test_home).unwrap();
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
        .env("HOME", test_home)
        .env_remove("CLAUDE_CONFIG_DIR")
        .env_remove("CODEX_HOME")
        .env_remove("COPILOT_HOME")
        .env_remove("GROK_HOME")
        .env_remove("OPENCODE_CONFIG_DIR")
        .env_remove("PI_CODING_AGENT_DIR")
        .env_remove("AMP_CONFIG_DIR")
        .spawn()
        .unwrap();
    let guard = HostGuard(child);
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Ok(contents) = std::fs::read_to_string(&control_path) {
            let value: Value = serde_json::from_str(&contents).unwrap();
            return (guard, value["port"].as_u64().unwrap() as u16);
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    }
}

/// Agent integrations are reconciled after the host starts accepting, so the
/// control file can appear before the hook files are on disk.
#[cfg(unix)]
fn wait_for_path(path: &std::path::Path) {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !path.exists() {
        assert!(
            Instant::now() < deadline,
            "integration was not reconciled: {}",
            path.display()
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[cfg(unix)]
fn hook_endpoint(runtime_dir: &std::path::Path) -> (u16, String) {
    let contents = std::fs::read_to_string(runtime_dir.join("agent-hooks/endpoint.env")).unwrap();
    let values = contents
        .lines()
        .filter_map(|line| line.split_once('='))
        .collect::<std::collections::HashMap<_, _>>();
    (
        values["ALERA_AGENT_HOOK_PORT"].parse().unwrap(),
        values["ALERA_AGENT_HOOK_TOKEN"].to_string(),
    )
}

#[cfg(unix)]
fn post_hook(runtime_dir: &std::path::Path, agent: &str, event_name: &str) {
    let (port, token) = hook_endpoint(runtime_dir);
    let body = serde_json::to_string(&json!({
        "terminalSessionId": "hook-session",
        "workspaceId": "hook-workspace",
        "tabId": "hook-tab",
        "hookEventName": event_name,
        "payload": {"prompt": format!("{agent} is working")}
    }))
    .unwrap();
    let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    write!(
        stream,
        "POST /hook/{agent} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nX-Alera-Agent-Hook-Token: {token}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
    .unwrap();
    stream.flush().unwrap();
    let mut response = String::new();
    std::io::Read::read_to_string(&mut stream, &mut response).unwrap();
    assert!(
        response.starts_with("HTTP/1.1 204"),
        "hook failed: {response}"
    );
}

fn assert_session_is_not_attached(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    session_id: &str,
) {
    send(
        writer,
        json!({"id": id, "type": "write", "payload": {"sessionId": session_id, "dataBase64": STANDARD.encode(b"ignored")}}),
    );
    let response = read_response(reader, id);
    assert_eq!(response["ok"], json!(false), "write succeeded: {response}");
}

fn workspace_payload(id: &str, path: &std::path::Path) -> Value {
    json!({
        "id": id,
        "instanceId": format!("{id}-instance"),
        "hostId": "local",
        "projectId": "project-1",
        "name": "Headless Workspace",
        "branch": null,
        "path": path.to_string_lossy(),
        "createdAt": "2026-07-19T00:00:00Z",
        "updatedAt": "2026-07-19T00:00:00Z",
        "kind": "main",
        "status": "active",
        "sourceBranch": null,
        "reusesExistingBranch": false,
        "isPinned": false,
        "tagIds": [],
        "tagNames": [],
        "parentWorkspaceId": null,
        "childCount": 0
    })
}

#[test]
#[cfg(unix)]
fn exited_terminal_removes_its_persisted_tab_without_an_app_client() {
    let dir = tempfile::tempdir().unwrap();
    let token = "terminal-exit-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 1, "type": "tab.upsert", "payload": {
            "id": "exit-tab", "workspaceId": "workspace-1", "kind": "terminal",
            "title": "Exit Terminal", "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {"terminalSessionId": "exit-session"}
        }}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 2, "type": "createOrAttach", "payload": {
            "sessionId": "exit-session", "workspaceId": "workspace-1", "tabId": "exit-tab",
            "workingDirectory": "/tmp", "launch": {"shell": "/bin/sh", "arguments": ["-c", "exit 0"],
            "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}}, "cols": 80, "rows": 24
        }}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], json!(true));

    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        assert!(Instant::now() < deadline, "terminal never exited");
        if read_message(&mut reader)
            .get("event")
            .and_then(Value::as_str)
            == Some("exit")
        {
            break;
        }
    }
    send(
        &mut writer,
        json!({"id": 3, "type": "tab.find", "payload": {"id": "exit-tab"}}),
    );
    assert_eq!(read_response(&mut reader, 3)["payload"], Value::Null);
    assert_session_is_not_attached(&mut writer, &mut reader, 4, "exit-session");
}

#[test]
#[cfg(unix)]
fn spawn_on_create_starts_headless_without_an_app_client() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("spawned.txt");
    let token = "headless-spawn-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("headless-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    let tab = json!({
        "id": "headless-tab", "workspaceId": "headless-workspace", "kind": "terminal",
        "title": "Headless Terminal", "createdAt": "2026-07-19T00:00:00Z",
        "updatedAt": "2026-07-19T00:00:00Z", "payload": {
            "terminalSessionId": "headless-session",
            "initialCommand": format!("printf X >> {}; sleep 30", marker.display()),
            "spawnOnCreate": true
        }
    });
    send(
        &mut writer,
        json!({"id": 2, "type": "tab.upsert", "payload": tab.clone()}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], json!(true));

    let deadline = Instant::now() + Duration::from_secs(10);
    while !marker.exists() {
        assert!(
            Instant::now() < deadline,
            "initial command was never executed"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
    send(
        &mut writer,
        json!({"id": 3, "type": "tab.upsert", "payload": tab}),
    );
    assert_eq!(read_response(&mut reader, 3)["ok"], json!(true));
    std::thread::sleep(Duration::from_millis(300));
    assert_eq!(std::fs::read_to_string(&marker).unwrap(), "X");
}

#[test]
#[cfg(unix)]
fn runtime_start_reconciles_persisted_spawn_on_create_tabs() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("reconciled.txt");
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        let workspace: Workspace =
            serde_json::from_value(workspace_payload("reconcile-workspace", dir.path())).unwrap();
        store.upsert_workspace(workspace).await.unwrap();
        let tab: WorkspaceTabRecord = serde_json::from_value(json!({
            "id": "reconcile-tab", "workspaceId": "reconcile-workspace", "kind": "terminal",
            "title": "Reconcile Terminal", "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {
                "terminalSessionId": "reconcile-session",
                "initialCommand": format!("printf RESTORED > {}; exit", marker.display()),
                "spawnOnCreate": true
            }
        }))
        .unwrap();
        store.upsert_workspace_tab(tab).await.unwrap();
    });

    let token = "reconcile-spawn-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let deadline = Instant::now() + Duration::from_secs(10);
    while !marker.exists() {
        assert!(
            Instant::now() < deadline,
            "persisted command was never executed"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
    assert_eq!(std::fs::read_to_string(&marker).unwrap(), "RESTORED");

    let (mut writer, mut reader) = connect(port, token);
    send(
        &mut writer,
        json!({"id": 1, "type": "tab.find", "payload": {"id": "reconcile-tab"}}),
    );
    assert_eq!(read_response(&mut reader, 1)["payload"], Value::Null);
}

#[test]
#[cfg(unix)]
fn runtime_hook_receiver_detects_every_enabled_agent() {
    let dir = tempfile::tempdir().unwrap();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        store
            .set_agent_status_hook_settings(&RuntimeAgentStatusHookSettings {
                codex: true,
                claude: true,
                copilot: true,
                cursor: true,
                agy: true,
                opencode: true,
                pi: true,
                amp: true,
                grok: true,
            })
            .await
            .unwrap();
    });

    let token = "agent-hook-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let test_home = dir.path().join("test-home");
    for integration in [
        dir.path().join("agent-runtime-homes/codex/home/hooks.json"),
        dir.path()
            .join("agent-runtime-homes/claude/home/settings.json"),
        test_home.join(".copilot/hooks/alera.json"),
        test_home.join(".cursor/hooks.json"),
        test_home.join(".gemini/config/hooks.json"),
        test_home.join(".grok/hooks/alera-status.json"),
        test_home.join(".config/opencode/plugins/alera-agent-status.js"),
        test_home.join(".pi/agent/extensions/alera-agent-status.ts"),
        test_home.join(".config/amp/plugins/alera-agent-status.ts"),
    ] {
        wait_for_path(&integration);
    }
    let (mut writer, mut reader) = connect(port, token);
    send(
        &mut writer,
        json!({"id": 1, "type": "createOrAttach", "payload": {
            "sessionId": "hook-session", "workspaceId": "hook-workspace", "tabId": "hook-tab",
            "workingDirectory": "/tmp", "launch": {"shell": "/bin/sh", "arguments": ["-c", "sleep 30"],
            "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}}, "cols": 80, "rows": 24
        }}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));

    for (index, (agent, event_name)) in [
        ("codex", "UserPromptSubmit"),
        ("claude", "UserPromptSubmit"),
        ("copilot", "userPromptSubmitted"),
        ("cursor", "beforeSubmitPrompt"),
        ("agy", "PreInvocation"),
        ("opencode", "SessionBusy"),
        ("pi", "agent_start"),
        ("amp", "session.start"),
        ("grok", "UserPromptSubmit"),
    ]
    .into_iter()
    .enumerate()
    {
        post_hook(dir.path(), agent, event_name);
        let request_id = index as i64 + 2;
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            send(
                &mut writer,
                json!({"id": request_id, "type": "agentPresence.list", "payload": {}}),
            );
            let response = read_response(&mut reader, request_id);
            let detected = response["payload"].as_array().is_some_and(|items| {
                items
                    .iter()
                    .any(|item| item["agentType"] == agent && item["agentState"] == "working")
            });
            if detected {
                break;
            }
            assert!(Instant::now() < deadline, "{agent} was not detected");
            std::thread::sleep(Duration::from_millis(25));
        }
    }
}
