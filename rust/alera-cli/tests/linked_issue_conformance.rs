//! Drives `linkedIssue.*` against the real `alera terminal-host` binary. Only
//! URLs no provider recognizes are linked, so no forge CLI or network is used.

mod agent_integration_home_isolation;

use agent_integration_home_isolation::alera_command_with_isolated_home;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::process::Child;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

const PROTOCOL_VERSION: i64 = 4;
const JIRA_URL: &str = "https://example.atlassian.net/browse/ABC-1";

struct HostGuard(Child);

impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn spawn_host(runtime_dir: &std::path::Path, token: &str) -> (HostGuard, u16) {
    let control_path = runtime_dir.join("runtime-host.json");
    let mut command = alera_command_with_isolated_home(runtime_dir);
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
    ]);
    let guard = HostGuard(
        command
            .spawn()
            .expect("failed to spawn alera terminal-host"),
    );
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let port = std::fs::read_to_string(&control_path)
            .ok()
            .and_then(|contents| serde_json::from_str::<Value>(&contents).ok())
            .and_then(|value| value["port"].as_u64());
        if let Some(port) = port {
            return (guard, port as u16);
        }
        assert!(Instant::now() < deadline, "control file was never written");
        std::thread::sleep(Duration::from_millis(50));
    }
}

struct Connection {
    writer: TcpStream,
    reader: BufReader<TcpStream>,
    events: Vec<Value>,
}

impl Connection {
    fn open(port: u16, token: &str) -> Self {
        let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(10)))
            .unwrap();
        let mut connection = Connection {
            writer: stream.try_clone().unwrap(),
            reader: BufReader::new(stream),
            events: Vec::new(),
        };
        let hello = connection.request(
            0,
            "hello",
            json!({"protocolVersion": PROTOCOL_VERSION, "token": token}),
        );
        assert_eq!(hello["ok"], json!(true), "handshake rejected: {hello}");
        connection
    }

    fn request(&mut self, id: i64, kind: &str, payload: Value) -> Value {
        let mut line =
            serde_json::to_vec(&json!({"id": id, "type": kind, "payload": payload})).unwrap();
        line.push(b'\n');
        self.writer.write_all(&line).unwrap();
        loop {
            let mut text = String::new();
            let read = self
                .reader
                .read_line(&mut text)
                .expect("host did not answer");
            assert!(read > 0, "host closed the connection");
            let message: Value = serde_json::from_str(text.trim_end()).unwrap();
            if message.get("id") == Some(&json!(id)) {
                return message;
            }
            if message.get("event").is_some() {
                self.events.push(message);
            }
        }
    }
}

#[test]
fn linked_issues_persist_broadcast_and_cascade() {
    let dir = tempfile::tempdir().unwrap();
    let token = "linked-issue-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let mut host = Connection::open(port, token);

    let status = host.request(1, "status.get", json!({}));
    assert!(
        status["payload"]["runtimeCapabilities"]
            .as_array()
            .unwrap()
            .contains(&json!("linkedIssuesV1")),
        "linkedIssuesV1 is not advertised: {status}"
    );

    let workspace = host.request(
        2,
        "workspace.upsert",
        json!({
            "id": "w1", "instanceId": "w1-instance", "hostId": "local", "projectId": "p1",
            "name": "Workspace", "branch": null, "path": dir.path().to_string_lossy(),
            "createdAt": "2026-09-12T00:00:00Z", "updatedAt": "2026-09-12T00:00:00Z",
            "kind": "main", "status": "active", "sourceBranch": null,
            "reusesExistingBranch": false, "isPinned": false, "tagIds": [], "tagNames": [],
            "parentWorkspaceId": null, "childCount": 0
        }),
    );
    assert_eq!(
        workspace["ok"],
        json!(true),
        "workspace.upsert failed: {workspace}"
    );

    let invalid = host.request(
        3,
        "linkedIssue.link",
        json!({"workspaceId": "w1", "url": "not a url"}),
    );
    assert_eq!(
        invalid["ok"],
        json!(false),
        "invalid url accepted: {invalid}"
    );

    let linked = host.request(
        4,
        "linkedIssue.link",
        json!({"workspaceId": "w1", "url": JIRA_URL}),
    );
    assert_eq!(linked["ok"], json!(true), "link failed: {linked}");
    assert_eq!(linked["payload"]["linkedIssue"]["url"], json!(JIRA_URL));
    assert_eq!(linked["payload"]["linkedIssue"]["provider"], Value::Null);
    assert_eq!(
        linked["payload"]["fetchError"]["code"],
        json!("unsupported")
    );

    let listed = host.request(5, "linkedIssue.list", json!({}));
    assert_eq!(listed["payload"]["items"][0]["workspaceId"], json!("w1"));
    assert!(
        host.events
            .iter()
            .any(|event| event["event"] == json!("linkedIssuesChanged")
                && event["payload"]["workspaceId"] == json!("w1")),
        "no scoped linkedIssuesChanged event: {:?}",
        host.events
    );

    let rejected_create = host.request(
        6,
        "workspace.createManaged",
        json!({"projectId": "p1", "branch": "feature", "issueUrl": "ftp://nope"}),
    );
    assert_eq!(rejected_create["ok"], json!(false), "{rejected_create}");

    let removed = host.request(
        7,
        "workspace.remove",
        json!({"id": "w1", "cascadeTabs": true}),
    );
    assert_eq!(
        removed["ok"],
        json!(true),
        "workspace.remove failed: {removed}"
    );
    let after = host.request(8, "linkedIssue.find", json!({"workspaceId": "w1"}));
    assert_eq!(
        after["payload"],
        Value::Null,
        "link survived removal: {after}"
    );
}
