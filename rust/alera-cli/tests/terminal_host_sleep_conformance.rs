#[allow(dead_code)]
mod terminal_host_test_platform;

use alera_core::child_process::windowless_command;
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
    let child = windowless_command(env!("CARGO_BIN_EXE_alera"))
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
fn workspace_sleep_removes_all_tabs_layout_and_sessions() {
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
    assert_eq!(read_response(&mut reader, 7)["payload"], json!([]));
    send(
        &mut writer,
        json!({"id": 8, "type": "layout.find", "payload": {"workspaceId": "w1"}}),
    );
    assert_eq!(read_response(&mut reader, 8)["payload"], Value::Null);
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
