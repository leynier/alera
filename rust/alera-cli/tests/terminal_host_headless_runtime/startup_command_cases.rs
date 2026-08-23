//! Startup-command delivery for `spawnOnCreate` terminal tabs.
//!
//! Split out of `terminal_host_headless_runtime.rs`, which keeps the host's
//! lifecycle cases: attaching, exiting, and reconciling on restart.

use std::time::{Duration, Instant};

use serde_json::json;

use super::{connect, post_hook_for_terminal, read_response, send, spawn_host, workspace_payload};

#[test]
#[cfg(unix)]
fn one_shot_initial_command_is_dropped_after_the_first_delivery() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("once.txt");
    let token = "once-spawn-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("once-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 2, "type": "tab.upsert", "payload": {
            "id": "once-tab", "workspaceId": "once-workspace", "kind": "terminal",
            "title": "Setup", "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {
                "terminalSessionId": "once-session",
                "initialCommand": format!("printf X >> {}; sleep 30", marker.display()),
                "initialCommandOnce": true,
                "spawnOnCreate": true
            }
        }}),
    );
    // The response already carries the spent command, so the app never sees a
    // record that would run the setup again.
    let saved = read_response(&mut reader, 2);
    let payload = &saved["payload"]["payload"];
    assert_eq!(payload.get("initialCommand"), None, "{saved}");
    assert_eq!(payload.get("initialCommandOnce"), None, "{saved}");
    assert_eq!(payload["spawnOnCreate"], json!(true), "{saved}");

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
        json!({"id": 3, "type": "tab.find", "payload": {"id": "once-tab"}}),
    );
    let found = read_response(&mut reader, 3);
    assert_eq!(found["payload"]["payload"].get("initialCommand"), None);
    assert_eq!(std::fs::read_to_string(&marker).unwrap(), "X");
}

#[test]
#[cfg(unix)]
fn auto_close_setup_tab_removes_success_and_keeps_failure() {
    let dir = tempfile::tempdir().unwrap();
    let token = "setup-auto-close-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({
            "id": 1,
            "type": "workspace.upsert",
            "payload": workspace_payload("setup-workspace", dir.path())
        }),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));

    send(
        &mut writer,
        json!({"id": 2, "type": "tab.upsert", "payload": {
            "id": "successful-setup-tab", "workspaceId": "setup-workspace",
            "kind": "terminal", "title": "Setup",
            "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {
                "terminalSessionId": "successful-setup-session",
                "initialCommand": "/bin/sh -c 'exit 0'",
                "initialCommandOnce": true,
                "spawnOnCreate": true,
                "autoCloseOnSuccess": true
            }
        }}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], json!(true));

    wait_for_tab_state(&mut writer, &mut reader, 3, "successful-setup-tab", false);

    send(
        &mut writer,
        json!({"id": 4, "type": "tab.upsert", "payload": {
            "id": "failed-setup-tab", "workspaceId": "setup-workspace",
            "kind": "terminal", "title": "Setup",
            "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {
                "terminalSessionId": "failed-setup-session",
                "initialCommand": "/bin/sh -c 'exit 7'",
                "initialCommandOnce": true,
                "spawnOnCreate": true,
                "autoCloseOnSuccess": true
            }
        }}),
    );
    assert_eq!(read_response(&mut reader, 4)["ok"], json!(true));

    let found = wait_for_tab_state(&mut writer, &mut reader, 5, "failed-setup-tab", true);
    assert_eq!(found["payload"]["payload"].get("initialCommand"), None);
}

/// The prompt reaches a non-Codex agent as the argument its own CLI accepts.
#[test]
#[cfg(unix)]
fn a_long_option_agent_receives_its_initial_prompt_as_one_argument() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("arguments.txt");
    let recorder = write_recorder(dir.path(), "record-args.sh", "printf '%s\\n' \"$@\"");
    let token = "long-option-prompt-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("prompt-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 2, "type": "tab.upsert", "payload": {
            "id": "opencode-tab", "workspaceId": "prompt-workspace", "kind": "terminal",
            "title": "OpenCode", "createdAt": "2026-08-07T00:00:00Z",
            "updatedAt": "2026-08-07T00:00:00Z", "payload": {
                "terminalSessionId": "opencode-session",
                "initialCommand": format!("{} > {}", recorder.display(), marker.display()),
                "initialPrompt": "- Review the plan",
                "initialPromptOnce": true,
                "agentType": "opencode",
                "spawnOnCreate": true
            }
        }}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], json!(true));

    let recorded = wait_for_file(&marker);
    assert_eq!(recorded, "--prompt=- Review the plan\n", "{recorded}");
    let found = wait_for_tab_state(&mut writer, &mut reader, 3, "opencode-tab", true);
    assert_eq!(found["payload"]["payload"].get("initialPrompt"), None);
}

/// Amp has no argument for an initial prompt, so it reads one from stdin.
#[test]
#[cfg(unix)]
fn amp_receives_its_initial_prompt_on_standard_input() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("stdin.txt");
    let recorder = write_recorder(dir.path(), "record-stdin.sh", "cat");
    let token = "amp-stdin-prompt-token";
    let (_guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("amp-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 2, "type": "tab.upsert", "payload": {
            "id": "amp-tab", "workspaceId": "amp-workspace", "kind": "terminal",
            "title": "Amp", "createdAt": "2026-08-07T00:00:00Z",
            "updatedAt": "2026-08-07T00:00:00Z", "payload": {
                "terminalSessionId": "amp-session",
                "initialCommand": format!("{} > {}", recorder.display(), marker.display()),
                "initialPrompt": "- Review the plan\n- It's ready",
                "initialPromptOnce": true,
                "agentType": "amp",
                "spawnOnCreate": true
            }
        }}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], json!(true));

    // Verbatim, with no shell quoting anywhere between the tab and the agent.
    let recorded = wait_for_file(&marker);
    assert_eq!(recorded, "- Review the plan\n- It's ready", "{recorded}");
}

#[test]
#[cfg(unix)]
fn orchestration_fx_rearms_its_bootstrap_once_per_restarted_pty() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("fx-bootstrap.txt");
    let ready = dir.path().join("fx-ready.txt");
    let recorder = write_recorder(
        dir.path(),
        "record-fx-bootstrap.sh",
        &format!(
            "printf ready > {}; cat >> {}",
            ready.display(),
            marker.display()
        ),
    );
    let token = "fx-bootstrap-restart-token";
    let (guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 10, "type": "project.upsert", "payload": {
            "id": "project-1", "name": "fx Restart Project",
            "repoPath": dir.path().to_string_lossy(), "kind": "folder",
            "createdAt": "2026-08-22T00:00:00Z", "updatedAt": "2026-08-22T00:00:00Z"
        }}),
    );
    assert_eq!(read_response(&mut reader, 10)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("fx-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 2, "type": "agentProfile.upsert", "payload": {
            "name": "fx Restart", "agentType": "fx",
            "command": recorder.to_string_lossy()
        }}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 3, "type": "orchestration.taskCreate", "payload": {
            "spec": "verify fx restart delivery", "workspace": "fx-workspace",
            "coordinator": "coordinator", "createdBy": "coordinator"
        }}),
    );
    let task = read_response(&mut reader, 3);
    assert_eq!(task["ok"], json!(true), "{task}");
    let task_id = task["payload"]["id"].as_str().unwrap();
    send(
        &mut writer,
        json!({"id": 4, "type": "orchestration.agentSpawn", "payload": {
            "workspace": "fx-workspace", "profile": "fx Restart",
            "task": task_id, "from": "coordinator"
        }}),
    );
    let spawned = read_response(&mut reader, 4);
    assert_eq!(spawned["ok"], json!(true), "{spawned}");
    let session_id = spawned["payload"]["terminalHandle"]
        .as_str()
        .unwrap()
        .to_string();

    wait_for_file(&ready);
    post_hook_for_terminal(
        dir.path(),
        "fx",
        "Idle",
        &session_id,
        "fx-workspace",
        &session_id,
    );
    wait_for_occurrences(
        &marker,
        "You have an active Alera orchestration dispatch",
        1,
    );
    // Model a failed pending-clear write by restoring the consumed durable
    // value. The PTY-instance guard must still reject another ready event.
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(dir.path())
            .await
            .unwrap();
        let mut tab = store
            .find_workspace_tab(&session_id)
            .await
            .unwrap()
            .unwrap();
        let prompt = tab.payload["initialPrompt"].clone();
        tab.payload["pendingAgentPrompt"] = json!({"agent": "fx", "prompt": prompt});
        store.upsert_workspace_tab(tab).await.unwrap();
    });
    post_hook_for_terminal(
        dir.path(),
        "fx",
        "Idle",
        &session_id,
        "fx-workspace",
        &session_id,
    );
    // Two 500ms deferred-submit windows plus margin: a duplicate accepted by
    // the PTY queue must have reached the recorder before this assertion.
    std::thread::sleep(Duration::from_millis(1_200));
    assert_eq!(
        occurrence_count(&marker, "You have an active Alera orchestration dispatch"),
        1,
        "the same PTY received its bootstrap twice"
    );
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(dir.path())
            .await
            .unwrap();
        let mut tab = store
            .find_workspace_tab(&session_id)
            .await
            .unwrap()
            .unwrap();
        tab.payload["pendingAgentPrompt"] = serde_json::Value::Null;
        store.upsert_workspace_tab(tab).await.unwrap();
    });

    send(
        &mut writer,
        json!({"id": 5, "type": "tab.find", "payload": {"id": session_id}}),
    );
    let projected = read_response(&mut reader, 5);
    assert!(projected["payload"]["payload"]
        .get("initialPrompt")
        .is_none());
    assert!(projected["payload"]["payload"]
        .get("pendingAgentPrompt")
        .is_none());

    drop(reader);
    drop(writer);
    drop(guard);
    std::fs::remove_file(dir.path().join("runtime-host.json")).unwrap();
    std::fs::remove_file(&ready).unwrap();

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(dir.path())
            .await
            .unwrap();
        let tab = store
            .find_workspace_tab(&session_id)
            .await
            .unwrap()
            .unwrap();
        assert!(tab.payload["initialPrompt"]
            .as_str()
            .unwrap()
            .contains("active Alera orchestration dispatch"));
        assert!(tab.payload["pendingAgentPrompt"].is_null());
        assert_eq!(
            tab.payload["agentProfileLaunchV1"]["initialDelivery"]["replay"],
            "onRestart"
        );
    });

    let (_restarted_guard, restarted_port) = spawn_host(dir.path(), token);
    let (_restarted_writer, _restarted_reader) = connect(restarted_port, token);
    wait_for_file(&ready);
    post_hook_for_terminal(
        dir.path(),
        "fx",
        "Idle",
        &session_id,
        "fx-workspace",
        &session_id,
    );
    wait_for_occurrences(
        &marker,
        "You have an active Alera orchestration dispatch",
        2,
    );
    post_hook_for_terminal(
        dir.path(),
        "fx",
        "Idle",
        &session_id,
        "fx-workspace",
        &session_id,
    );
    std::thread::sleep(Duration::from_millis(1_200));
    assert_eq!(
        occurrence_count(&marker, "You have an active Alera orchestration dispatch"),
        2,
        "the restarted PTY received its bootstrap twice"
    );
}

#[cfg(unix)]
pub(super) fn write_recorder(
    directory: &std::path::Path,
    name: &str,
    body: &str,
) -> std::path::PathBuf {
    use std::os::unix::fs::PermissionsExt;

    let path = directory.join(name);
    std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
    let mut permissions = std::fs::metadata(&path).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&path, permissions).unwrap();
    path
}

#[cfg(unix)]
pub(super) fn wait_for_file(path: &std::path::Path) -> String {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Ok(contents) = std::fs::read_to_string(path) {
            if !contents.is_empty() {
                return contents;
            }
        }
        assert!(
            Instant::now() < deadline,
            "{} was never written",
            path.display()
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

#[cfg(unix)]
fn occurrence_count(path: &std::path::Path, needle: &str) -> usize {
    std::fs::read_to_string(path)
        .unwrap_or_default()
        .matches(needle)
        .count()
}

#[cfg(unix)]
fn wait_for_occurrences(path: &std::path::Path, needle: &str, expected: usize) {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let actual = occurrence_count(path, needle);
        if actual >= expected {
            assert_eq!(actual, expected, "bootstrap was delivered too many times");
            return;
        }
        assert!(
            Instant::now() < deadline,
            "expected {expected} bootstrap deliveries, observed {actual}"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

#[cfg(unix)]
fn wait_for_tab_state(
    writer: &mut std::net::TcpStream,
    reader: &mut std::io::BufReader<std::net::TcpStream>,
    mut request_id: i64,
    tab_id: &str,
    expected_present: bool,
) -> serde_json::Value {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        send(
            writer,
            json!({"id": request_id, "type": "tab.find", "payload": {"id": tab_id}}),
        );
        let response = read_response(reader, request_id);
        let present = !response["payload"].is_null();
        if present == expected_present {
            return response;
        }
        assert!(
            Instant::now() < deadline,
            "unexpected tab state for {tab_id}"
        );
        request_id += 1;
        std::thread::sleep(Duration::from_millis(25));
    }
}
