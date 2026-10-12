use super::*;

fn find_tab(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    tab: &str,
) -> Value {
    expect_ok(request(writer, reader, id, "tab.find", json!({"id": tab})))
}

#[test]
#[cfg(unix)]
fn run_terminals_carry_host_owned_run_identity() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let dir = tempfile::tempdir().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_699,
        "project.upsert",
        json!({
            "id": "project-1", "name": "Run Tabs", "kind": "folder",
            "repoPath": dir.path().to_string_lossy(),
            "createdAt": "2026-10-11T00:00:00Z", "updatedAt": "2026-10-11T00:00:00Z"
        }),
    ));
    seed_workspace_with_path(&mut writer, &mut reader, "ws-1", dir.path());
    let profile = expect_ok(request(
        &mut writer,
        &mut reader,
        8_700,
        "agentProfile.upsert",
        json!({"name": "Run Tab Agent", "agentType": "codex", "command": "sleep 30 #"}),
    ));
    let created = expect_ok(request(
        &mut writer,
        &mut reader,
        8_701,
        "runs.create",
        json!({
            "requestId": "run-tab-identity",
            "workspaceId": "ws-1",
            "objective": "tag the run terminals",
            "isolation": "shared",
            "coordinatorProfileId": profile["id"],
        }),
    ));
    let run_id = created["run"]["runId"].as_str().unwrap().to_string();
    let coordinator_tab = created["run"]["coordinatorTabId"]
        .as_str()
        .unwrap()
        .to_string();
    let coordinator = find_tab(&mut writer, &mut reader, 8_702, &coordinator_tab);
    assert_eq!(
        coordinator["payload"]["runId"],
        json!(run_id),
        "{coordinator}"
    );
    assert!(
        coordinator["payload"].get("runTaskId").is_none(),
        "{coordinator}"
    );

    // The coordinator's run holds ws-1, so the delegated worker gets its own
    // loopless shared run in a second workspace.
    seed_workspace_with_path(&mut writer, &mut reader, "ws-2", dir.path());
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_703,
        "orchestration.taskCreate",
        json!({"spec": "worker tab identity", "workspace": "ws-2", "coordinator": "coord", "ensureRun": true}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    let task_run = task["run_id"]
        .as_str()
        .expect("ensureRun joins a run")
        .to_string();
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        8_704,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-2",
            "agent": "claude",
            "task": &task_id,
            "from": "coord",
            "command": "sleep 30 #",
            "keepOnFailure": true
        }),
    ));
    let worker_tab = spawned["terminalHandle"].as_str().unwrap().to_string();
    let worker = find_tab(&mut writer, &mut reader, 8_705, &worker_tab);
    assert_eq!(worker["payload"]["runId"], json!(task_run), "{worker}");
    assert_eq!(worker["payload"]["runTaskId"], json!(task_id), "{worker}");

    // A client save works on the projected record: it can neither drop nor
    // rewrite the run identity.
    let mut forged = worker.clone();
    forged["payload"].as_object_mut().unwrap().remove("runId");
    forged["payload"]["runTaskId"] = json!("forged-task");
    forged["title"] = json!("Renamed Worker");
    let saved = expect_ok(request(
        &mut writer,
        &mut reader,
        8_706,
        "tab.upsert",
        forged,
    ));
    assert_eq!(saved["payload"]["runId"], json!(task_run), "{saved}");
    assert_eq!(saved["payload"]["runTaskId"], json!(task_id), "{saved}");

    // A client cannot attach an ordinary tab to a run.
    let mut stray = worker.clone();
    stray["id"] = json!("stray-tab");
    stray["payload"] = json!({"runId": run_id, "runTaskId": task_id});
    let stray = expect_ok(request(
        &mut writer,
        &mut reader,
        8_707,
        "tab.upsert",
        stray,
    ));
    assert!(stray["payload"].get("runId").is_none(), "{stray}");
    assert!(stray["payload"].get("runTaskId").is_none(), "{stray}");
}
