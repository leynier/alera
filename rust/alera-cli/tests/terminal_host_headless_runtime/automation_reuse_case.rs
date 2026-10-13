use super::startup_command_cases::write_recorder;
use super::{connect, read_response, send, spawn_host, workspace_payload};
use serde_json::{json, Value};
use std::io::BufReader;
use std::net::TcpStream;
use std::time::{Duration, Instant};

fn rpc(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    verb: &str,
    payload: Value,
) -> Value {
    send(writer, json!({"id":92,"type":verb,"payload":payload}));
    let response = read_response(reader, 92);
    assert_eq!(response["ok"], true, "{verb}: {response}");
    response["payload"].clone()
}

fn wait_for_launches(marker: &std::path::Path, count: usize) {
    let deadline = Instant::now() + Duration::from_secs(15);
    while std::fs::read(marker).unwrap_or_default().len() < count {
        assert!(
            Instant::now() < deadline,
            "Automation agent did not launch {count} times"
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn cli(directory: &std::path::Path, args: &[&str]) -> Value {
    let result = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args(["automation", "--json", "--runtime-dir"])
        .arg(directory)
        .args(args)
        .env_remove("ALERA_TERMINAL_HANDLE")
        .env_remove("ALERA_WORKSPACE_ID")
        .env_remove("ALERA_AUTOMATION_RUN_ID")
        .env_remove("ALERA_AUTOMATION_ATTEMPT_ID")
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "CLI {args:?}: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    serde_json::from_slice(&result.stdout).unwrap()
}

fn complete(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, run: &Value) {
    let completed = rpc(
        writer,
        reader,
        "automation.complete",
        json!({"run":run["id"],"attemptId":run["attemptId"],"status":"success","summary":"Fake task completed","targetIdentity":run["targetIdentity"]}),
    );
    assert_eq!(completed["status"], "success");
}

fn bound_tab(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, id: &Value) -> Value {
    rpc(writer, reader, "automation.show", json!({"id": id}))["automation"]["boundTarget"].clone()
}

#[test]
fn reusing_automation_returns_to_its_workspace_and_rebinds_after_unbind() {
    let directory = tempfile::tempdir().unwrap();
    let marker = directory.path().join("launches");
    let command = write_recorder(
        directory.path(),
        "fake-agent.sh",
        &format!("printf X >> '{}'", marker.display()),
    );
    let token = "automation-reuse-test";
    let (host, port) = spawn_host(directory.path(), token);
    let (mut writer, mut reader) = connect(port, token);
    rpc(
        &mut writer,
        &mut reader,
        "project.upsert",
        json!({"id":"project-1","name":"Folder","repoPath":directory.path(),"kind":"folder","createdAt":"2026-10-04T00:00:00Z","updatedAt":"2026-10-04T00:00:00Z"}),
    );
    rpc(
        &mut writer,
        &mut reader,
        "workspace.upsert",
        workspace_payload("automation-workspace", directory.path()),
    );
    let profile = rpc(
        &mut writer,
        &mut reader,
        "agentProfile.upsert",
        json!({"name":"Fake Agent","agentType":"codex","command":command}),
    );
    let control: Value =
        serde_json::from_slice(&std::fs::read(directory.path().join("runtime-host.json")).unwrap())
            .unwrap();
    assert!(control["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!("automationReuseV1")));
    let input = directory.path().join("automation.json");
    std::fs::write(&input, json!({"name":"Reuse Fixture","promptTemplate":"Continue the report","schedule":{"recurring":{"cron":"0 9 * * *","timezone":"UTC"}},"target":{"freshTab":{"workspaceId":"automation-workspace","agentProfileId":profile["id"]}}}).to_string()).unwrap();
    let definition = cli(
        directory.path(),
        &[
            "create",
            "--file",
            input.to_str().unwrap(),
            "--reuse",
            "conversation",
            "--request-key",
            "reuse-fixture",
        ],
    );
    assert_eq!(definition["reusePolicy"], "reuseConversation");
    assert!(definition["boundTarget"].is_null());
    let id = definition["id"].clone();
    rpc(
        &mut writer,
        &mut reader,
        "automation.pause",
        json!({"id":id,"activeRuns":"continue-active"}),
    );

    let first = rpc(
        &mut writer,
        &mut reader,
        "automation.runNow",
        json!({"id":id}),
    );
    assert_eq!(first["reuse"], "bound");
    wait_for_launches(&marker, 1);
    assert_eq!(
        bound_tab(&mut writer, &mut reader, &id)["tabId"],
        first["tabId"]
    );
    complete(&mut writer, &mut reader, &first);
    rpc(
        &mut writer,
        &mut reader,
        "terminate",
        json!({"sessionId":first["sessionId"]}),
    );

    let second = rpc(
        &mut writer,
        &mut reader,
        "automation.runNow",
        json!({"id":id}),
    );
    assert_eq!(second["reuse"], "resumedConversation", "{second}");
    assert_eq!(second["workspaceId"], first["workspaceId"]);
    assert_ne!(second["tabId"], first["tabId"]);
    wait_for_launches(&marker, 2);
    let bound = bound_tab(&mut writer, &mut reader, &id);
    assert_eq!(bound["tabId"], second["tabId"]);
    assert_eq!(bound["lastRunId"], second["id"]);
    complete(&mut writer, &mut reader, &second);

    // The binding is durable: a restarted runtime still knows where to go.
    drop(reader);
    drop(writer);
    drop(host);
    std::fs::remove_file(directory.path().join("runtime-host.json")).unwrap();
    let (_host, port) = spawn_host(directory.path(), token);
    let (mut writer, mut reader) = connect(port, token);
    assert_eq!(bound_tab(&mut writer, &mut reader, &id), bound);

    let unbound = cli(
        directory.path(),
        &[
            "unbind",
            "--id",
            id.as_str().unwrap(),
            "--reason",
            "fresh start",
        ],
    );
    assert!(unbound["boundTarget"].is_null());
    let third = rpc(
        &mut writer,
        &mut reader,
        "automation.runNow",
        json!({"id":id}),
    );
    assert_eq!(third["reuse"], "bound");
    assert_ne!(third["tabId"], second["tabId"]);
    wait_for_launches(&marker, 3);
    assert_eq!(
        bound_tab(&mut writer, &mut reader, &id)["tabId"],
        third["tabId"]
    );
}
