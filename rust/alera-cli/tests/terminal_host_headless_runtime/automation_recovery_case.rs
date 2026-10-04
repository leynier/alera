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
    send(writer, json!({"id":91,"type":verb,"payload":payload}));
    let response = read_response(reader, 91);
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

#[test]
fn automation_recovers_after_host_restart_without_replaying_completed_terminals() {
    let directory = tempfile::tempdir().unwrap();
    let marker = directory.path().join("launches");
    let command = write_recorder(
        directory.path(),
        "fake-agent.sh",
        &format!("printf X >> '{}'", marker.display()),
    );
    let token = "automation-restart-test";
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
    let capabilities = control["runtimeCapabilities"].as_array().unwrap();
    assert!(capabilities.contains(&json!("automationsAuthoringV1")));
    assert!(capabilities.contains(&json!("automationTerminalObserveV1")));
    let input = directory.path().join("automation.json");
    std::fs::write(&input, json!({"name":"Restart Fixture","promptTemplate":"Inspect preserved files","schedule":{"recurring":{"cron":"0 9 * * *","timezone":"UTC"}},"target":{"freshTab":{"workspaceId":"automation-workspace","agentProfileId":profile["id"]}},"retryBackoffSeconds":1}).to_string()).unwrap();
    let result = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"))
        .args(["automation", "--json", "--runtime-dir"])
        .arg(directory.path())
        .args(["create", "--file"])
        .arg(&input)
        .args(["--request-key", "restart-fixture"])
        .env_remove("ALERA_TERMINAL_HANDLE")
        .env_remove("ALERA_WORKSPACE_ID")
        .env_remove("ALERA_AUTOMATION_RUN_ID")
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "CLI create: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    let definition: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(definition["state"], "active");
    rpc(
        &mut writer,
        &mut reader,
        "automation.pause",
        json!({"id":definition["id"],"activeRuns":"continue"}),
    );
    let first = rpc(
        &mut writer,
        &mut reader,
        "automation.runNow",
        json!({"id":definition["id"]}),
    );
    assert_eq!(first["attemptCount"], 1);
    wait_for_launches(&marker, 1);
    rpc(
        &mut writer,
        &mut reader,
        "terminate",
        json!({"sessionId":first["sessionId"]}),
    );
    drop(reader);
    drop(writer);
    drop(host);
    std::fs::remove_file(directory.path().join("runtime-host.json")).unwrap();

    let (host, port) = spawn_host(directory.path(), token);
    let (mut writer, mut reader) = connect(port, token);
    let deadline = Instant::now() + Duration::from_secs(15);
    while std::fs::read(&marker).unwrap_or_default().len() < 2 {
        let state = rpc(
            &mut writer,
            &mut reader,
            "automation.runShow",
            json!({"id":first["id"]}),
        );
        assert!(
            Instant::now() < deadline,
            "Recovery did not launch: {state}"
        );
        std::thread::sleep(Duration::from_millis(250));
    }
    let recovered = rpc(
        &mut writer,
        &mut reader,
        "automation.runShow",
        json!({"id":first["id"]}),
    );
    let recovered = recovered.get("run").unwrap_or(&recovered);
    assert_eq!(recovered["attemptCount"], 2);
    assert_eq!(recovered["absoluteDeadlineAt"], first["absoluteDeadlineAt"]);
    assert_eq!(recovered["workspaceId"], first["workspaceId"]);
    assert_ne!(recovered["tabId"], first["tabId"]);
    let observed = rpc(
        &mut writer,
        &mut reader,
        "createOrAttach",
        json!({"sessionId":recovered["sessionId"],"workspaceId":recovered["workspaceId"],"tabId":recovered["tabId"],"attachmentMode":"observe"}),
    );
    assert_eq!(observed["readOnly"], true);
    let completed = rpc(
        &mut writer,
        &mut reader,
        "automation.complete",
        json!({"run":first["id"],"attemptId":recovered["attemptId"],"status":"success","summary":"Fake task completed","targetIdentity":recovered["targetIdentity"]}),
    );
    assert_eq!(completed["status"], "success");
    rpc(
        &mut writer,
        &mut reader,
        "detach",
        json!({"sessionId":recovered["sessionId"]}),
    );
    rpc(
        &mut writer,
        &mut reader,
        "terminate",
        json!({"sessionId":recovered["sessionId"]}),
    );
    drop(reader);
    drop(writer);
    drop(host);
    std::fs::remove_file(directory.path().join("runtime-host.json")).unwrap();

    let (_host, port) = spawn_host(directory.path(), token);
    let (mut writer, mut reader) = connect(port, token);
    rpc(&mut writer, &mut reader, "status.get", json!({}));
    std::thread::sleep(Duration::from_millis(1500));
    assert_eq!(
        std::fs::read(marker).unwrap().len(),
        2,
        "Completed automation terminals must never replay on startup"
    );
    let final_run = rpc(
        &mut writer,
        &mut reader,
        "automation.runShow",
        json!({"id":first["id"]}),
    );
    assert_eq!(final_run["run"]["status"], "success");
}
