use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::Child;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;

struct HostGuard(Child);

struct RuntimeGuard(PathBuf);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

impl Drop for RuntimeGuard {
    fn drop(&mut self) {
        let _ = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args([
                "runtime",
                "--runtime-dir",
                self.0.to_str().unwrap(),
                "stop",
                "--force",
            ])
            .output();
    }
}

#[test]
fn host_restart_replaces_the_process_and_accepts_a_new_connection() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_dir = dir.path().join("runtime");
    std::fs::create_dir_all(&runtime_dir).unwrap();
    let _runtime_guard = RuntimeGuard(runtime_dir.clone());
    let control_path = runtime_dir.join("runtime-host.json");
    let token = "restart-conformance-token";
    let (_host_guard, port) = spawn_host(&runtime_dir, &control_path, token);
    let before = read_control(&control_path).unwrap();
    let before_pid = before["pid"].as_u64().unwrap();

    let (mut writer, mut reader) = connect(port);
    handshake(&mut writer, &mut reader, token);
    send(
        &mut writer,
        json!({"id": 1, "type": "host.restart", "payload": {"force": true}}),
    );
    let response = read_response(&mut reader, 1);
    assert_eq!(response["ok"], json!(true), "restart failed: {response}");
    assert_eq!(response["payload"]["restarting"], json!(true));
    drop(writer);
    drop(reader);

    let replacement = wait_for_replacement(&control_path, before_pid);
    let replacement_port = replacement["port"].as_u64().unwrap() as u16;
    let replacement_token = replacement["token"].as_str().unwrap();
    assert_ne!(replacement_token, token);

    let (mut replacement_writer, mut replacement_reader) = connect(replacement_port);
    handshake(
        &mut replacement_writer,
        &mut replacement_reader,
        replacement_token,
    );
    send(
        &mut replacement_writer,
        json!({"id": 2, "type": "status.get", "payload": {}}),
    );
    let status = read_response(&mut replacement_reader, 2);
    assert_eq!(
        status["ok"],
        json!(true),
        "replacement host did not answer: {status}"
    );
}

fn spawn_host(runtime_dir: &Path, control_path: &Path, token: &str) -> (HostGuard, u16) {
    let child = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
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
    let control = wait_for_control(control_path);
    (guard, control["port"].as_u64().unwrap() as u16)
}

fn wait_for_control(path: &Path) -> Value {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some(value) = read_control(path) {
            return value;
        }
        assert!(Instant::now() < deadline, "control file was not published");
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn wait_for_replacement(path: &Path, previous_pid: u64) -> Value {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some(value) = read_control(path) {
            if value["pid"].as_u64().is_some_and(|pid| pid != previous_pid) {
                return value;
            }
        }
        assert!(
            Instant::now() < deadline,
            "replacement runtime host was not published"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn read_control(path: &Path) -> Option<Value> {
    let contents = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&contents).ok()
}

fn connect(port: u16) -> (TcpStream, BufReader<TcpStream>) {
    let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    let writer = stream.try_clone().unwrap();
    (writer, BufReader::new(stream))
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

fn send(writer: &mut TcpStream, message: Value) {
    let mut line = serde_json::to_vec(&message).unwrap();
    line.push(b'\n');
    writer.write_all(&line).unwrap();
    writer.flush().unwrap();
}

fn read_response(reader: &mut BufReader<TcpStream>, id: i64) -> Value {
    loop {
        let message = read_message(reader);
        if message.get("id") == Some(&json!(id)) {
            return message;
        }
    }
}

fn read_message(reader: &mut BufReader<TcpStream>) -> Value {
    let mut line = String::new();
    let read = reader
        .read_line(&mut line)
        .expect("timed out or failed reading from host");
    assert!(read > 0, "host closed the connection unexpectedly");
    serde_json::from_str(line.trim_end()).expect("host sent invalid JSON")
}
