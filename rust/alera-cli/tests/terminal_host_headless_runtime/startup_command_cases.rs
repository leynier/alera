//! Startup-command delivery for `spawnOnCreate` terminal tabs.
//!
//! Split out of `terminal_host_headless_runtime.rs`, which keeps the host's
//! lifecycle cases: attaching, exiting, and reconciling on restart.

use std::time::{Duration, Instant};

use serde_json::json;

use super::{connect, read_response, send, spawn_host, workspace_payload};

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

#[cfg(unix)]
fn write_recorder(directory: &std::path::Path, name: &str, body: &str) -> std::path::PathBuf {
    use std::os::unix::fs::PermissionsExt;

    let path = directory.join(name);
    std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
    let mut permissions = std::fs::metadata(&path).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&path, permissions).unwrap();
    path
}

#[cfg(unix)]
fn wait_for_file(path: &std::path::Path) -> String {
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
