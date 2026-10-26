//! The production injected MCP command against an isolated runtime host, without inference.

#![cfg(unix)]

use alera_core::child_process::windowless_async_command;
use serde_json::{json, Value};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::process::{Child, ChildStdin, ChildStdout};

#[allow(
    dead_code,
    reason = "The shared socket fixture also supports broader lifecycle tests."
)]
#[path = "support/agent_chat_socket_host.rs"]
mod agent_chat_socket_host;

use agent_chat_socket_host::{Host, WORKSPACE};

const DEADLINE: Duration = Duration::from_secs(15);

struct McpChild {
    child: Child,
    stdin: ChildStdin,
    stdout: Lines<BufReader<ChildStdout>>,
    next_id: u64,
}

impl McpChild {
    fn start(host: &Host, specification: &Value) -> Self {
        let mut command = windowless_async_command(specification["command"].as_str().unwrap());
        command.args(
            specification["args"]
                .as_array()
                .unwrap()
                .iter()
                .map(|arg| arg.as_str().unwrap()),
        );
        command
            .env_clear()
            .env("HOME", host.root().join("home"))
            .env("XDG_CONFIG_HOME", host.root().join("home/.config"))
            .env("SHELL", "/bin/sh")
            .env("PATH", "/usr/bin:/bin")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::from(
                std::fs::File::create(host.root().join("mcp.stderr")).unwrap(),
            ))
            .kill_on_drop(true);
        for (key, value) in specification["env"].as_object().unwrap() {
            command.env(key, value.as_str().unwrap());
        }
        let mut child = command
            .spawn()
            .expect("spawn the production injected MCP command");
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap()).lines();
        Self {
            child,
            stdin,
            stdout,
            next_id: 1,
        }
    }

    async fn request(&mut self, method: &str, params: Value) -> Value {
        let id = self.next_id;
        self.next_id += 1;
        let mut line = serde_json::to_vec(
            &json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}),
        )
        .unwrap();
        line.push(b'\n');
        self.stdin.write_all(&line).await.unwrap();
        self.stdin.flush().await.unwrap();
        tokio::time::timeout(DEADLINE, async {
            loop {
                let line = self
                    .stdout
                    .next_line()
                    .await
                    .unwrap()
                    .expect("the injected MCP process exited before replying");
                let response: Value = serde_json::from_str(&line).unwrap();
                if response["id"] == id {
                    return response;
                }
            }
        })
        .await
        .expect("the injected MCP process must reply before the deadline")
    }

    async fn finish(mut self) {
        self.stdin.shutdown().await.unwrap();
        drop(self.stdin);
        let status = tokio::time::timeout(DEADLINE, self.child.wait())
            .await
            .unwrap()
            .unwrap();
        assert!(
            status.success(),
            "the injected MCP process did not exit successfully"
        );
    }
}

#[tokio::test]
async fn injected_mcp_child_handshakes_and_reads_only_during_its_bound_live_turn() {
    let host = Host::start();
    let mut desktop = host.connect();
    host.seed(&mut desktop);
    let created = desktop.create();
    let chat = created["chatId"].as_str().unwrap();
    let draft = desktop.ok("agentChat.snapshot", json!({"chatId": chat}));
    assert_eq!(draft["session"]["status"], "stopped");
    host.assert_no_provider_start();
    desktop.ok(
        "agentChat.send",
        json!({
            "requestId": "mint-mcp-credential", "chatId": chat, "workspaceId": WORKSPACE,
            "clientMessageId": "mcp-credential-message", "text": "first"
        }),
    );
    desktop.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "ready"
            && snapshot["turns"]
                .as_array()
                .is_some_and(|turns| turns.len() == 1 && turns[0]["status"] == "completed")
    });
    let starts = host.inputs("thread/start");
    assert_eq!(starts.len(), 1);
    let specification = &starts[0]["message"]["params"]["config"]["mcp_servers"]["alera"];
    assert_eq!(specification["command"], env!("CARGO_BIN_EXE_alera"));
    let mut mcp = McpChild::start(&host, specification);
    let initialized = mcp
        .request(
            "initialize",
            json!({
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "injected-chat-regression", "version": "1"}
            }),
        )
        .await;
    assert_eq!(initialized["result"]["serverInfo"]["name"], "alera");
    assert_eq!(
        initialized["result"]["capabilities"]["resources"]["subscribe"],
        false
    );
    mcp.stdin
        .write_all(b"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n")
        .await
        .unwrap();
    mcp.stdin.flush().await.unwrap();
    let listed = mcp.request("tools/list", json!({})).await;
    let names = listed["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|tool| tool["name"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(names.len(), 16);
    assert!(names.contains(&"chat_background_wait"));
    assert!(names
        .iter()
        .all(|name| name.starts_with("chat_")
            || matches!(*name, "list_projects" | "list_workspaces")));
    assert!(names.contains(&"chat_read"));
    let arguments = json!({"name": "chat_read", "arguments": {"chatId": chat}});
    let inactive = mcp.request("tools/call", arguments.clone()).await;
    assert_eq!(inactive["result"]["isError"], true);
    assert!(inactive["result"]["content"][0]["text"]
        .as_str()
        .unwrap()
        .contains("The caller chat does not have a live turn."));
    desktop.ok(
        "agentChat.send",
        json!({
            "requestId": "start-mcp-bound-turn", "chatId": chat, "workspaceId": WORKSPACE,
            "clientMessageId": "mcp-live-message", "text": "approval"
        }),
    );
    desktop.wait_snapshot(chat, |snapshot| {
        snapshot["session"]["status"] == "waiting"
            && snapshot["session"]["activeTurnId"].is_string()
    });
    let read = mcp.request("tools/call", arguments.clone()).await;
    assert_eq!(read["result"]["isError"], false);
    assert_eq!(read["result"]["structuredContent"]["chat"]["chatId"], chat);
    assert_eq!(host.inputs("turn/start").len(), 2);
    let resources = mcp.request("resources/list", json!({})).await;
    assert_eq!(resources["result"]["resources"], json!([]));
    desktop.ok(
        "agentChat.close",
        json!({"requestId": "close-mcp-bound-chat", "chatId": chat}),
    );
    let revoked = mcp.request("tools/call", arguments).await;
    assert_eq!(revoked["result"]["isError"], true);
    mcp.finish().await;
}
