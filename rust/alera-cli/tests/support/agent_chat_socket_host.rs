use alera_core::child_process::windowless_command;
use serde_json::{json, Value};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::time::{Duration, Instant};

const TIMEOUT: Duration = Duration::from_secs(15);
const TOKEN: &str = "agent-chat-socket-test";
pub const WORKSPACE: &str = "fixture-workspace";

pub struct Host {
    child: Child,
    directory: tempfile::TempDir,
    stderr: PathBuf,
    pub port: u16,
}

impl Host {
    pub fn start() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let home = root.join("home");
        let workspace = root.join("workspace");
        fs::create_dir_all(&home).unwrap();
        fs::create_dir_all(&workspace).unwrap();
        let fixture = root.join("codex-fixture");
        fs::write(&fixture, include_str!("agent_chat_codex_fixture.py")).unwrap();
        fs::set_permissions(&fixture, fs::Permissions::from_mode(0o700)).unwrap();
        fs::write(
            root.join("agent-chat-providers.json"),
            serde_json::to_vec(&json!({"instances": [{
                "providerInstanceId": "fixture-codex", "provider": "codex",
                "executable": fixture, "label": "Socket Fixture", "models": ["fixture-model"],
                "defaultModel": "fixture-model",
                "env": {"ALERA_CHAT_FIXTURE_LOG": root.join("provider.jsonl")}
            }]}))
            .unwrap(),
        )
        .unwrap();
        let control = root.join("runtime-host.json");
        let stderr = root.join("host.stderr");
        let mut command = windowless_command(env!("CARGO_BIN_EXE_alera"));
        command
            .args(["terminal-host", "--runtime-dir"])
            .arg(root)
            .arg("--control-file")
            .arg(&control)
            .args([
                "--token",
                TOKEN,
                "--empty-shutdown-delay-seconds",
                "60",
                "--detached-session-shutdown-delay-seconds",
                "60",
            ])
            .env("HOME", &home)
            .env("XDG_CONFIG_HOME", home.join(".config"))
            .env("SHELL", "/bin/sh")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::from(fs::File::create(&stderr).unwrap()));
        for name in [
            "CLAUDE_CONFIG_DIR",
            "CODEX_HOME",
            "COPILOT_HOME",
            "GROK_HOME",
            "OPENCODE_CONFIG_DIR",
            "PI_CODING_AGENT_DIR",
            "AMP_CONFIG_DIR",
            "ALERA_RUNTIME_DIR",
            "ALERA_CHAT_CREDENTIAL_FILE",
        ] {
            command.env_remove(name);
        }
        // A fallback kill must include the provider if startup or the socket fails.
        unsafe {
            command.pre_exec(|| {
                if libc::setsid() == -1 {
                    Err(std::io::Error::last_os_error())
                } else {
                    Ok(())
                }
            });
        }
        let child = command
            .spawn()
            .expect("spawn the current runtime-host binary");
        let mut host = Self {
            child,
            directory,
            stderr,
            port: 0,
        };
        let deadline = Instant::now() + TIMEOUT;
        loop {
            if let Ok(contents) = fs::read_to_string(&control) {
                if let Ok(value) = serde_json::from_str::<Value>(&contents) {
                    host.port = value["port"].as_u64().expect("ephemeral host port") as u16;
                    assert!(
                        value["runtimeCapabilities"]
                            .as_array()
                            .is_some_and(|values| {
                                values.iter().any(|value| value == "agentChatV1")
                            }),
                        "host does not advertise chats: {value}"
                    );
                    return host;
                }
            }
            assert!(
                host.child.try_wait().unwrap().is_none(),
                "host exited: {}",
                host.diagnostics()
            );
            assert!(
                Instant::now() < deadline,
                "host startup timed out: {}",
                host.diagnostics()
            );
            std::thread::sleep(Duration::from_millis(25));
        }
    }

    pub fn root(&self) -> &Path {
        self.directory.path()
    }

    pub fn connect(&self) -> Socket {
        let mut socket = self.raw_socket();
        assert_eq!(socket.hello(true, true, None)["ok"], true);
        socket
    }

    pub fn raw_socket(&self) -> Socket {
        Socket::new(self.port, &self.stderr)
    }

    pub fn seed(&self, socket: &mut Socket) {
        let workspace = self.root().join("workspace");
        socket.ok(
            "project.upsert",
            json!({
                "id": "fixture-project", "name": "Chat Socket Fixture", "kind": "folder",
                "repoPath": workspace,
                "createdAt": "2026-10-12T00:00:00Z", "updatedAt": "2026-10-12T00:00:00Z",
            }),
        );
        socket.ok(
            "workspace.upsert",
            json!({
                "id": WORKSPACE, "instanceId": "fixture-instance", "hostId": "local",
                "projectId": "fixture-project", "name": "Chat Socket Fixture",
                "path": workspace, "branch": null, "kind": "main", "status": "active",
                "createdAt": "2026-10-12T00:00:00Z", "updatedAt": "2026-10-12T00:00:00Z",
            "tagIds": [], "tagNames": [], "isPinned": false, "reusesExistingBranch": false,
            }),
        );
    }

    pub fn log(&self) -> Vec<Value> {
        fs::read_to_string(self.root().join("provider.jsonl"))
            .unwrap_or_default()
            .lines()
            .map(|line| serde_json::from_str(line).expect("fixture log frame"))
            .collect()
    }

    pub fn inputs(&self, method: &str) -> Vec<Value> {
        self.log()
            .into_iter()
            .filter(|row| row["message"]["method"] == method)
            .collect()
    }

    pub fn assert_no_chat_credentials(&self) {
        assert_eq!(
            fs::read_dir(self.root().join("agent-chat-mcp"))
                .unwrap()
                .count(),
            0,
            "an idle draft or reopened chat minted a launch credential"
        );
    }

    pub fn assert_no_provider_start(&self) {
        for row in self.log() {
            assert_eq!(
                row["event"], "metadata_probe",
                "unexpected SDK activity: {row}"
            );
            let args = &row["args"];
            assert!(args == &json!(["--version"]) || args == &json!(["debug", "models"]));
            assert!(row["credentialPath"].is_null());
        }
        for method in [
            "initialize",
            "initialized",
            "thread/start",
            "thread/resume",
            "turn/start",
        ] {
            assert!(
                self.inputs(method).is_empty(),
                "native {method} ran before the first send"
            );
        }
        self.assert_no_chat_credentials();
    }

    pub fn wait_for_exit(&self, pid: i64) {
        let deadline = Instant::now() + TIMEOUT;
        while unsafe { libc::kill(pid as libc::pid_t, 0) } == 0 {
            assert!(
                Instant::now() < deadline,
                "provider {pid} was not reaped: {}",
                self.diagnostics()
            );
            std::thread::sleep(Duration::from_millis(25));
        }
        assert!(
            self.log()
                .iter()
                .any(|row| row["event"] == "exited" && row["pid"] == pid),
            "provider did not observe stdin EOF"
        );
    }

    fn diagnostics(&self) -> String {
        fs::read_to_string(&self.stderr).unwrap_or_default()
    }
}

impl Drop for Host {
    fn drop(&mut self) {
        if self.port != 0 {
            if let Ok(mut stream) = TcpStream::connect(("127.0.0.1", self.port)) {
                let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
                let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
                let reader_stream = stream.try_clone().ok();
                let mut reader = reader_stream.map(BufReader::new);
                for value in [
                    json!({"id": 0, "type": "hello", "payload": {"protocolVersion": 5, "token": TOKEN}}),
                    json!({"id": 1, "type": "host.shutdown", "payload": {"force": true}}),
                ] {
                    let _ = writeln!(stream, "{value}");
                    let _ = stream.flush();
                    if let Some(reader) = reader.as_mut() {
                        let _ = reader.read_line(&mut String::new());
                    }
                }
            }
        }
        let deadline = Instant::now() + Duration::from_secs(5);
        while self.child.try_wait().ok().flatten().is_none() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(25));
        }
        if self.child.try_wait().ok().flatten().is_none() {
            unsafe {
                libc::kill(-(self.child.id() as libc::pid_t), libc::SIGKILL);
            }
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}

pub struct Socket {
    writer: TcpStream,
    reader: BufReader<TcpStream>,
    stderr: PathBuf,
    next_id: i64,
    pub events: Vec<Value>,
}

impl Socket {
    fn new(port: u16, stderr: &Path) -> Self {
        let stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        stream.set_write_timeout(Some(TIMEOUT)).unwrap();
        Self {
            writer: stream.try_clone().unwrap(),
            reader: BufReader::new(stream),
            stderr: stderr.to_owned(),
            next_id: 1,
            events: Vec::new(),
        }
    }

    pub fn hello(&mut self, kinds: bool, capability: bool, credential: Option<&str>) -> Value {
        let mut payload = json!({"protocolVersion": 5, "token": TOKEN,
                                 "clientKind": "app", "sharedCheckoutWorkspacesV1": true});
        if kinds {
            payload["supportedTabKinds"] = json!(["agentChat"]);
        }
        if capability {
            payload["capabilities"] = json!(["agentChatV1"]);
        }
        if let Some(credential) = credential {
            payload["chatCredential"] = json!(credential);
        }
        self.request("hello", payload)
    }

    pub fn request(&mut self, verb: &str, payload: Value) -> Value {
        let id = self.next_id;
        self.next_id += 1;
        writeln!(
            self.writer,
            "{}",
            json!({"id": id, "type": verb, "payload": payload})
        )
        .unwrap();
        self.writer.flush().unwrap();
        let deadline = Instant::now() + TIMEOUT;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            assert!(
                !remaining.is_zero(),
                "{verb} timed out: {}",
                self.diagnostics()
            );
            self.reader
                .get_ref()
                .set_read_timeout(Some(remaining))
                .unwrap();
            let mut line = String::new();
            let read = self
                .reader
                .read_line(&mut line)
                .unwrap_or_else(|error| panic!("{verb}: {error}; {}", self.diagnostics()));
            assert!(read != 0, "{verb}: socket closed; {}", self.diagnostics());
            let value: Value = serde_json::from_str(&line).expect("host JSONL frame");
            if value["id"] == id {
                return value;
            }
            self.events.push(value);
        }
    }

    pub fn ok(&mut self, verb: &str, payload: Value) -> Value {
        let response = self.request(verb, payload);
        assert_eq!(
            response["ok"],
            true,
            "{verb}: {response}; {}",
            self.diagnostics()
        );
        response["payload"].clone()
    }

    pub fn create(&mut self) -> Value {
        self.ok(
            "agentChat.create",
            json!({
                "requestId": "create-chat", "workspaceId": WORKSPACE, "provider": "codex",
                "providerInstanceId": "fixture-codex", "runtimeMode": "approval-required",
                "title": "Fixture Chat",
            }),
        )
    }

    pub fn wait_event(&mut self, predicate: impl Fn(&Value) -> bool) -> Value {
        if let Some(event) = self.events.iter().find(|event| predicate(event)) {
            return event.clone();
        }
        let deadline = Instant::now() + TIMEOUT;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            assert!(
                !remaining.is_zero(),
                "chat event timed out: {}",
                self.diagnostics()
            );
            self.reader
                .get_ref()
                .set_read_timeout(Some(remaining))
                .unwrap();
            let mut line = String::new();
            let read = self
                .reader
                .read_line(&mut line)
                .unwrap_or_else(|error| panic!("chat event: {error}; {}", self.diagnostics()));
            assert!(
                read != 0,
                "chat event: socket closed; {}",
                self.diagnostics()
            );
            let event: Value = serde_json::from_str(&line).expect("host event frame");
            let matches = predicate(&event);
            self.events.push(event.clone());
            if matches {
                return event;
            }
        }
    }

    pub fn wait_snapshot(&mut self, chat: &str, ready: impl Fn(&Value) -> bool) -> Value {
        let deadline = Instant::now() + TIMEOUT;
        loop {
            let snapshot = self.ok("agentChat.snapshot", json!({"chatId": chat}));
            if ready(&snapshot) {
                return snapshot;
            }
            assert!(
                Instant::now() < deadline,
                "snapshot did not reach expected state: {snapshot}; {}",
                self.diagnostics()
            );
            std::thread::sleep(Duration::from_millis(25));
        }
    }

    fn diagnostics(&self) -> String {
        fs::read_to_string(&self.stderr).unwrap_or_default()
    }
}
