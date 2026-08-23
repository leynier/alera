use std::time::{Duration, Instant};

use serde_json::json;

use super::startup_command_cases::{wait_for_file, write_recorder};
use super::{connect, read_response, send, spawn_host, workspace_payload};

#[test]
fn profile_snapshot_restores_after_the_profile_is_edited_and_deleted() {
    let dir = tempfile::tempdir().unwrap();
    let marker = dir.path().join("profile-restarts.txt");
    let recorder = write_recorder(
        dir.path(),
        "record-profile-restart.sh",
        &format!("printf X >> {}; sleep 30", marker.display()),
    );
    let token = "profile-snapshot-restart-token";
    let (guard, port) = spawn_host(dir.path(), token);
    let (mut writer, mut reader) = connect(port, token);

    send(
        &mut writer,
        json!({"id": 10, "type": "project.upsert", "payload": {
            "id": "project-1", "name": "Snapshot Project",
            "repoPath": dir.path().to_string_lossy(), "kind": "folder",
            "createdAt": "2026-08-22T00:00:00Z", "updatedAt": "2026-08-22T00:00:00Z"
        }}),
    );
    assert_eq!(read_response(&mut reader, 10)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("snapshot-workspace", dir.path())}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], json!(true));
    send(
        &mut writer,
        json!({"id": 2, "type": "agentProfile.upsert", "payload": {
            "name": "Stable Profile", "agentType": "codex",
            "command": recorder.to_string_lossy()
        }}),
    );
    let created = read_response(&mut reader, 2);
    assert_eq!(created["ok"], json!(true));
    let profile_id = created["payload"]["id"].as_str().unwrap().to_string();
    assert_eq!(created["payload"]["revision"], json!(0));
    send(
        &mut writer,
        json!({"id": 3, "type": "agentProfile.launchIdempotent", "payload": {
            "workspaceId": "snapshot-workspace", "profileId": profile_id,
            "prompt": "Start the work", "clientMutationId": "snapshot-launch-1"
        }}),
    );
    let launched = read_response(&mut reader, 3);
    assert_eq!(launched["ok"], json!(true), "{launched}");
    let launch = &launched["payload"]["tab"]["payload"]["agentProfileLaunchV1"];
    assert_eq!(launch["version"], json!(1));
    assert_eq!(launch["profile"]["id"], profile_id);
    assert_eq!(launch["profile"]["revision"], json!(0));
    assert_eq!(launch["launch"]["kind"], json!("command"));
    assert_eq!(
        launch["launch"]["command"],
        json!(recorder.to_string_lossy())
    );
    assert_eq!(
        launched["payload"]["tab"]["payload"].get("initialCommand"),
        None
    );
    assert!(launched["payload"]["tab"]["payload"]
        .get("initialPrompt")
        .is_none());
    assert!(launched["payload"]["tab"]["payload"]
        .get("pendingAgentPrompt")
        .is_none());
    let tab_id = launched["payload"]["tab"]["id"]
        .as_str()
        .unwrap()
        .to_string();
    send(
        &mut writer,
        json!({"id": 30, "type": "agentProfile.launchIdempotent", "payload": {
            "workspaceId": "snapshot-workspace", "profileId": profile_id,
            "prompt": "Start the work", "clientMutationId": "snapshot-launch-1"
        }}),
    );
    let replayed = read_response(&mut reader, 30);
    assert_eq!(replayed["ok"], json!(true), "{replayed}");
    assert_eq!(replayed["payload"], launched["payload"]);
    wait_for_file(&marker);

    send(
        &mut writer,
        json!({"id": 4, "type": "agentProfile.upsert", "payload": {
            "id": profile_id, "name": "Edited Profile", "agentType": "claude",
            "command": "claude --dangerously-skip-permissions", "expectedRevision": 0
        }}),
    );
    let edited = read_response(&mut reader, 4);
    assert_eq!(edited["ok"], json!(true));
    assert_eq!(edited["payload"]["revision"], json!(1));
    send(
        &mut writer,
        json!({"id": 5, "type": "agentProfile.removalImpact", "payload": {
            "id": profile_id, "expectedRevision": 1
        }}),
    );
    let impact = read_response(&mut reader, 5);
    assert_eq!(impact["ok"], json!(true), "{impact}");
    assert_eq!(impact["payload"]["tabs"][0]["tabId"], tab_id);
    send(
        &mut writer,
        json!({"id": 6, "type": "agentProfile.remove", "payload": {
            "id": profile_id, "expectedRevision": 1, "confirmed": true
        }}),
    );
    let blocked_remove = read_response(&mut reader, 6);
    assert_eq!(blocked_remove["ok"], json!(false), "{blocked_remove}");

    drop(reader);
    drop(writer);
    drop(guard);
    std::fs::remove_file(dir.path().join("runtime-host.json")).unwrap();

    // Reference-aware removal correctly blocks deleting a live snapshot tab.
    // Delete the mutable catalog row directly to model recovery of a tab
    // created by an older build whose profile is no longer present.
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(dir.path())
            .await
            .unwrap();
        sqlx::query("DELETE FROM agentProfiles WHERE id = ?")
            .bind(&profile_id)
            .execute(store.pool())
            .await
            .unwrap();
    });

    let (_restarted_guard, restarted_port) = spawn_host(dir.path(), token);
    let (_restarted_writer, _restarted_reader) = connect(restarted_port, token);
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        let contents = std::fs::read_to_string(&marker).unwrap_or_default();
        if contents == "XX" {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "snapshot launch was not restored after profile deletion: {contents:?}"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}
