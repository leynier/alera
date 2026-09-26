use std::time::{Duration, Instant};

use serde_json::json;

use super::startup_command_cases::{wait_for_file, write_recorder};
use super::{connect, read_response, send, spawn_host, workspace_payload};

#[test]
fn profile_resume_binds_before_launch_and_survives_a_host_restart() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("resume-args.txt");
    let recorder = write_recorder(
        dir.path(),
        "resume-recorder.sh",
        &format!("printf '%s\\n' \"$@\" >> '{}'", marker.display()),
    );
    let token = "profile-resume-test";
    let (guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);
    send(
        &mut writer,
        json!({"id": 1, "type": "project.upsert", "payload": {
            "id": "project-1", "name": "Resume", "kind": "folder", "repoPath": dir.path().to_string_lossy(),
            "createdAt": "2026-08-22T00:00:00Z", "updatedAt": "2026-08-22T00:00:00Z"
        }}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], true);
    send(
        &mut writer,
        json!({"id": 2, "type": "workspace.upsert", "payload": workspace_payload("resume-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 2)["ok"], true);
    send(
        &mut writer,
        json!({"id": 3, "type": "agentProfile.upsert", "payload": {
            "name": "Resume Profile", "agentType": "codex",
            "command": format!("{} --model test-model --sandbox read-only", recorder.display()),
            "customPrompt": "Never send this automatically on resume"
        }}),
    );
    let profile = read_response(&mut reader, 3);
    assert_eq!(profile["ok"], true, "{profile}");
    let profile_id = &profile["payload"]["id"];
    for (index, invalid) in [
        json!({"resumeSessionId": "--last"}),
        json!({"resumeSessionId": "sess-123", "prompt": "Unexpected prompt"}),
    ]
    .into_iter()
    .enumerate()
    {
        let mut invalid = invalid;
        invalid["workspaceId"] = json!("resume-workspace");
        invalid["profileId"] = profile_id.clone();
        invalid["clientMutationId"] = json!(format!("invalid-{index}"));
        send(
            &mut writer,
            json!({"id": 20, "type": "agentProfile.launchIdempotent", "payload": invalid}),
        );
        assert_eq!(read_response(&mut reader, 20)["ok"], false);
    }
    send(
        &mut writer,
        json!({"id": 21, "type": "tab.list", "payload": {"workspaceId": "resume-workspace"}}),
    );
    assert!(read_response(&mut reader, 21)["payload"]
        .as_array()
        .unwrap()
        .is_empty());
    let request = json!({"workspaceId": "resume-workspace", "profileId": profile_id,
        "resumeSessionId": " sess-123 ", "clientMutationId": "resume-mutation"});
    send(
        &mut writer,
        json!({"id": 4, "type": "agentProfile.launchIdempotent", "payload": request}),
    );
    let launched = read_response(&mut reader, 4);
    assert_eq!(launched["ok"], true, "{launched}");
    let mut tab = launched["payload"]["tab"].clone();
    assert_eq!(tab["payload"]["agentNativeSessionId"], "sess-123");
    assert_eq!(tab["payload"]["agentNativeSessionAgent"], "codex");
    let expected = "resume\nsess-123\n--model\ntest-model\n--sandbox\nread-only\n";
    assert_eq!(wait_for_file(&marker), expected);

    send(
        &mut writer,
        json!({"id": 5, "type": "agentProfile.launchIdempotent", "payload": request}),
    );
    let replay = read_response(&mut reader, 5);
    assert_eq!(replay["payload"]["tab"]["id"], tab["id"]);

    let mut conflict = request.clone();
    conflict["resumeSessionId"] = json!("another-session");
    send(
        &mut writer,
        json!({"id": 6, "type": "agentProfile.launchIdempotent", "payload": conflict}),
    );
    assert_eq!(read_response(&mut reader, 6)["ok"], false);

    // A stale client projection cannot erase the binding or launch snapshot.
    tab["title"] = json!("Renamed Resume");
    tab["payload"] =
        json!({"terminalSessionId": tab["id"], "manualTitle": true, "spawnOnCreate": true});
    send(
        &mut writer,
        json!({"id": 7, "type": "tab.upsert", "payload": tab}),
    );
    assert_eq!(read_response(&mut reader, 7)["ok"], true);

    let mut second_request = request.clone();
    second_request["clientMutationId"] = json!("second-tab-same-conversation");
    send(
        &mut writer,
        json!({"id": 8, "type": "agentProfile.launchIdempotent", "payload": second_request}),
    );
    let second = read_response(&mut reader, 8);
    assert_eq!(second["ok"], true, "{second}");
    assert_ne!(second["payload"]["tab"]["id"], tab["id"]);
    assert_eq!(
        second["payload"]["tab"]["payload"]["agentNativeSessionId"],
        "sess-123"
    );
    wait_for_output(&marker, &expected.repeat(2));

    drop(reader);
    drop(writer);
    drop(guard);
    std::fs::remove_file(dir.path().join("runtime-host.json")).unwrap();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(dir.path())
            .await
            .unwrap();
        let saved = store
            .find_workspace_tab(tab["id"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(saved.payload["agentNativeSessionId"], "sess-123");
        assert_eq!(
            saved.payload["agentProfileLaunchV1"]["profile"]["id"],
            *profile_id
        );
        assert!(saved.payload["initialPrompt"].is_null());
        assert!(saved.payload["pendingAgentPrompt"].is_null());
        assert_eq!(saved.title, "Renamed Resume");
        // Recovery uses the stored snapshot, even when the catalog changes.
        sqlx::query("DELETE FROM agentProfiles WHERE id = ?")
            .bind(profile_id.as_str().unwrap())
            .execute(store.pool())
            .await
            .unwrap();
    });
    let (_guard, port) = spawn_host(dir.path(), token);
    let (_writer, _reader) = connect(port, token);
    wait_for_output(&marker, &expected.repeat(4));
}

fn wait_for_output(marker: &std::path::Path, expected: &str) {
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let output = std::fs::read_to_string(&marker).unwrap_or_default();
        if output == expected {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "Resume was not restored: {output:?}"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}
