mod agent_integration_home_isolation;

#[allow(dead_code)]
mod terminal_host_test_platform;

use agent_integration_home_isolation::alera_command_with_isolated_home;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::Child;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

#[cfg(windows)]
use base64::engine::general_purpose::STANDARD;
#[cfg(windows)]
use base64::Engine as _;

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

#[cfg(windows)]
fn answer_conpty_cursor_query(writer: &mut TcpStream, session_id: &str) {
    send(
        writer,
        json!({
            "id": 9_001,
            "type": "write",
            "payload": {
                "sessionId": session_id,
                "dataBase64": STANDARD.encode(b"\x1b[1;1R")
            }
        }),
    );
}

#[cfg(not(windows))]
fn answer_conpty_cursor_query(_writer: &mut TcpStream, _session_id: &str) {}

fn read_response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let mut line = String::new();
        assert!(reader.read_line(&mut line).unwrap() > 0);
        let message: Value = serde_json::from_str(line.trim_end()).unwrap();
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
    }
}

fn spawn_host(runtime_dir: &std::path::Path, control_path: &std::path::Path) -> HostGuard {
    let child = alera_command_with_isolated_home(runtime_dir)
        .args([
            "terminal-host",
            "--runtime-dir",
            runtime_dir.to_str().unwrap(),
            "--control-file",
            control_path.to_str().unwrap(),
            "--token",
            "sleep-token",
            "--empty-shutdown-delay-seconds",
            "60",
            "--detached-session-shutdown-delay-seconds",
            "60",
        ])
        .spawn()
        .unwrap();
    HostGuard(child)
}

fn connect(control_path: &std::path::Path) -> (TcpStream, BufReader<TcpStream>) {
    let deadline = Instant::now() + Duration::from_secs(10);
    let port = loop {
        if let Ok(contents) = std::fs::read_to_string(control_path) {
            let value: Value = serde_json::from_str(&contents).unwrap();
            break value["port"].as_u64().unwrap() as u16;
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    };
    let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    (stream.try_clone().unwrap(), BufReader::new(stream))
}

fn upsert_tab(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    tab_id: &str,
    workspace_id: &str,
    kind: &str,
) {
    send(
        writer,
        json!({
            "id": id,
            "type": "tab.upsert",
            "payload": {
                "id": tab_id,
                "workspaceId": workspace_id,
                "kind": kind,
                "title": tab_id,
                "createdAt": "2026-07-19T00:00:00Z",
                "updatedAt": "2026-07-19T00:00:00Z",
                "payload": {}
            }
        }),
    );
    assert_eq!(read_response(reader, id)["ok"], json!(true));
}

#[test]
fn workspace_sleep_terminates_sessions_but_preserves_tabs_and_layout() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let _guard = spawn_host(dir.path(), &control_path);
    let (mut writer, mut reader) = connect(&control_path);
    send(
        &mut writer,
        json!({
            "id": 0,
            "type": "hello",
            "payload": {"protocolVersion": PROTOCOL_VERSION, "token": "sleep-token"}
        }),
    );
    assert_eq!(read_response(&mut reader, 0)["ok"], json!(true));

    upsert_tab(&mut writer, &mut reader, 1, "terminal-1", "w1", "terminal");
    upsert_tab(&mut writer, &mut reader, 2, "editor-1", "w1", "editor");
    upsert_tab(&mut writer, &mut reader, 3, "terminal-2", "w2", "terminal");
    send(
        &mut writer,
        json!({
            "id": 4,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "sleep-session",
                "workspaceId": "w1",
                "tabId": "terminal-1",
                "workingDirectory": terminal_host_test_platform::working_directory(),
                "launch": terminal_host_test_platform::long_running_launch(),
                "cols": 80,
                "rows": 24
            }
        }),
    );
    answer_conpty_cursor_query(&mut writer, "sleep-session");
    assert_eq!(read_response(&mut reader, 4)["ok"], json!(true));
    send(
        &mut writer,
        json!({
            "id": 5,
            "type": "layout.upsert",
            "payload": {"workspaceId": "w1", "data": {"activeTabId": "terminal-1"}}
        }),
    );
    assert_eq!(read_response(&mut reader, 5)["ok"], json!(true));

    send(
        &mut writer,
        json!({"id": 6, "type": "workspace.sleep", "payload": {"workspaceId": "w1"}}),
    );
    assert_eq!(read_response(&mut reader, 6)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 7, "type": "tab.list", "payload": {"workspaceId": "w1"}}),
    );
    assert_eq!(
        read_response(&mut reader, 7)["payload"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    send(
        &mut writer,
        json!({"id": 8, "type": "layout.find", "payload": {"workspaceId": "w1"}}),
    );
    assert!(read_response(&mut reader, 8)["payload"].is_object());
    send(
        &mut writer,
        json!({"id": 9, "type": "tab.list", "payload": {"workspaceId": "w2"}}),
    );
    assert_eq!(
        read_response(&mut reader, 9)["payload"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    send(
        &mut writer,
        json!({
            "id": 10,
            "type": "write",
            "payload": {"sessionId": "sleep-session", "dataBase64": "aWdub3JlZA=="}
        }),
    );
    assert_eq!(read_response(&mut reader, 10)["ok"], json!(false));
}

#[test]
fn slept_terminals_stay_listed_until_one_of_them_starts_again() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let _guard = spawn_host(dir.path(), &control_path);
    let (mut writer, mut reader) = connect(&control_path);
    send(
        &mut writer,
        json!({
            "id": 0,
            "type": "hello",
            "payload": {"protocolVersion": PROTOCOL_VERSION, "token": "sleep-token"}
        }),
    );
    assert_eq!(read_response(&mut reader, 0)["ok"], json!(true));
    upsert_tab(&mut writer, &mut reader, 1, "terminal-1", "w1", "terminal");
    upsert_tab(&mut writer, &mut reader, 2, "editor-1", "w1", "editor");

    send(
        &mut writer,
        json!({"id": 3, "type": "workspace.sleep", "payload": {"workspaceId": "w1"}}),
    );
    assert_eq!(read_response(&mut reader, 3)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 4, "type": "workspace.sleptTabs", "payload": {}}),
    );
    assert_eq!(
        read_response(&mut reader, 4)["payload"],
        json!({"w1": ["terminal-1"]})
    );

    send(
        &mut writer,
        json!({
            "id": 5,
            "type": "createOrAttach",
            "payload": {
                "sessionId": "woken-session",
                "workspaceId": "w1",
                "tabId": "terminal-1",
                "workingDirectory": terminal_host_test_platform::working_directory(),
                "launch": terminal_host_test_platform::long_running_launch(),
                "cols": 80,
                "rows": 24
            }
        }),
    );
    answer_conpty_cursor_query(&mut writer, "woken-session");
    assert_eq!(read_response(&mut reader, 5)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 6, "type": "workspace.sleptTabs", "payload": {}}),
    );
    assert_eq!(read_response(&mut reader, 6)["payload"], json!({}));
}

fn upsert_workspace(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    workspace_id: &str,
    path: &std::path::Path,
) {
    send(
        writer,
        json!({
            "id": id,
            "type": "workspace.upsert",
            "payload": {
                "id": workspace_id,
                "instanceId": format!("inst-{workspace_id}"),
                "hostId": "local",
                "projectId": "p",
                "name": workspace_id,
                "branch": format!("feat/{workspace_id}"),
                "path": path.to_str().unwrap(),
                "createdAt": "2026-07-19T00:00:00Z",
                "updatedAt": "2026-07-19T00:00:00Z",
                "kind": "linked",
                "status": "active",
                "reusesExistingBranch": false
            }
        }),
    );
    let response = read_response(reader, id);
    assert_eq!(response["ok"], json!(true), "{response}");
}

fn start_session(
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
                "workingDirectory": terminal_host_test_platform::working_directory(),
                "launch": terminal_host_test_platform::long_running_launch(),
                "cols": 80,
                "rows": 24
            }
        }),
    );
    answer_conpty_cursor_query(writer, session_id);
    assert_eq!(read_response(reader, id)["ok"], json!(true));
}

fn session_accepts_input(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    session_id: &str,
) -> bool {
    send(
        writer,
        json!({
            "id": id,
            "type": "write",
            "payload": {"sessionId": session_id, "dataBase64": "aWdub3JlZA=="}
        }),
    );
    read_response(reader, id)["ok"] == json!(true)
}

fn run_workspace_cli(runtime_dir: &std::path::Path, args: &[&str]) -> std::process::Output {
    let mut command = alera_command_with_isolated_home(runtime_dir);
    command
        .env_remove("ALERA_WORKSPACE_ID")
        .env_remove("ALERA_RUNTIME_DIR")
        .args(["workspace", "--runtime-dir", runtime_dir.to_str().unwrap()])
        .args(args);
    command.output().unwrap()
}

#[test]
fn cli_workspace_sleep_stops_only_that_workspace_and_keeps_it_visible() {
    let dir = tempfile::tempdir().unwrap();
    let control_path = dir.path().join("runtime-host.json");
    let _guard = spawn_host(dir.path(), &control_path);
    let (mut writer, mut reader) = connect(&control_path);
    send(
        &mut writer,
        json!({
            "id": 0,
            "type": "hello",
            "payload": {
                "protocolVersion": PROTOCOL_VERSION,
                "token": "sleep-token",
                "sharedCheckoutWorkspacesV1": true
            }
        }),
    );
    assert_eq!(read_response(&mut reader, 0)["ok"], json!(true));
    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "project.upsert",
            "payload": {
                "id": "p",
                "name": "p",
                "repoPath": terminal_host_test_platform::working_directory(),
                "createdAt": "2026-07-19T00:00:00Z",
                "updatedAt": "2026-07-19T00:00:00Z",
                "kind": "gitRepository"
            }
        }),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    upsert_workspace(&mut writer, &mut reader, 2, "w1", &dir.path().join("w1"));
    upsert_workspace(&mut writer, &mut reader, 3, "w2", &dir.path().join("w2"));
    upsert_tab(&mut writer, &mut reader, 4, "w1-term-1", "w1", "terminal");
    upsert_tab(&mut writer, &mut reader, 5, "w1-term-2", "w1", "terminal");
    upsert_tab(&mut writer, &mut reader, 6, "w1-editor", "w1", "editor");
    upsert_tab(&mut writer, &mut reader, 7, "w2-term", "w2", "terminal");
    start_session(&mut writer, &mut reader, 8, "w1-s1", "w1", "w1-term-1");
    start_session(&mut writer, &mut reader, 9, "w1-s2", "w1", "w1-term-2");
    start_session(&mut writer, &mut reader, 10, "w2-s", "w2", "w2-term");

    let output = run_workspace_cli(dir.path(), &["--json", "sleep", "--id", "w1"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let outcome: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(outcome["runtimeHost"], json!(true));
    assert_eq!(outcome["sleptTabIds"], json!(["w1-term-1", "w1-term-2"]));
    // Attached clients learn the cause, so they keep the tabs for the wake.
    let mut removed = Vec::new();
    let mut sleep_ids = std::collections::BTreeSet::new();
    while removed.len() < 2 {
        let mut line = String::new();
        assert!(reader.read_line(&mut line).unwrap() > 0);
        let message: Value = serde_json::from_str(line.trim_end()).unwrap();
        if message["event"] == json!("terminalSessionRemoved") {
            assert_eq!(message["payload"]["reason"], json!("workspaceSleep"));
            sleep_ids.insert(message["payload"]["sleepId"].as_str().unwrap().to_string());
            removed.push(
                message["payload"]["sessionId"]
                    .as_str()
                    .unwrap()
                    .to_string(),
            );
        }
    }
    removed.sort();
    assert_eq!(removed, vec!["w1-s1", "w1-s2"]);
    assert_eq!(sleep_ids.len(), 1, "one sleep, one id: {sleep_ids:?}");

    // Both sessions of w1 stopped; the other workspace's session still runs.
    assert!(!session_accepts_input(
        &mut writer,
        &mut reader,
        11,
        "w1-s1"
    ));
    assert!(!session_accepts_input(
        &mut writer,
        &mut reader,
        12,
        "w1-s2"
    ));
    assert!(session_accepts_input(&mut writer, &mut reader, 13, "w2-s"));

    // Unlike archive and remove, the workspace record, branch, and every tab
    // stay, and the workspace remains visible.
    send(
        &mut writer,
        json!({"id": 14, "type": "workspace.find", "payload": {"id": "w1"}}),
    );
    let workspace = read_response(&mut reader, 14)["payload"].clone();
    assert_eq!(workspace["isArchived"], json!(false));
    assert_eq!(workspace["status"], json!("active"));
    assert_eq!(workspace["branch"], json!("feat/w1"));
    send(
        &mut writer,
        json!({"id": 15, "type": "tab.list", "payload": {"workspaceId": "w1"}}),
    );
    assert_eq!(
        read_response(&mut reader, 15)["payload"]
            .as_array()
            .unwrap()
            .len(),
        3
    );
    send(
        &mut writer,
        json!({"id": 16, "type": "workspace.sleptTabs", "payload": {}}),
    );
    assert_eq!(
        read_response(&mut reader, 16)["payload"],
        json!({"w1": ["w1-term-1", "w1-term-2"]})
    );

    let missing = run_workspace_cli(dir.path(), &["sleep", "--id", "missing"]);
    assert!(!missing.status.success());
    assert!(String::from_utf8_lossy(&missing.stderr).contains("Workspace not found: missing"));
    assert!(session_accepts_input(&mut writer, &mut reader, 17, "w2-s"));
}
