use super::*;

#[test]
#[cfg(unix)]
fn readiness_spawn_exits_consume_startup_budget_until_stalled() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_360,
        "orchestration.taskCreate",
        json!({"spec": "readiness exit budget", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();

    for attempt in 1..=3 {
        let spawned = expect_ok(request(
            &mut writer,
            &mut reader,
            8_360 + attempt * 10,
            "orchestration.agentSpawn",
            json!({
                "workspace": "ws-1",
                "agent": "claude",
                "task": &task_id,
                "from": "coord",
                "command": "exit 7 #"
            }),
        ));
        let handle = spawned["terminalHandle"].as_str().unwrap().to_string();
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let shown = expect_ok(request(
                &mut writer,
                &mut reader,
                8_361 + attempt * 10,
                "orchestration.taskShow",
                json!({"id": &task_id}),
            ));
            if shown["task"]["startup_failure_count"] == json!(attempt) {
                assert_eq!(
                    shown["task"]["status"],
                    json!(if attempt == 3 { "stalled" } else { "ready" }),
                    "{shown}"
                );
                break;
            }
            assert!(Instant::now() < deadline, "{shown}");
            std::thread::sleep(Duration::from_millis(25));
        }
        let tab = expect_ok(request(
            &mut writer,
            &mut reader,
            8_362 + attempt * 10,
            "tab.find",
            json!({"id": handle}),
        ));
        assert!(tab.is_null(), "{tab}");
    }

    let dispatch = expect_ok(request(
        &mut writer,
        &mut reader,
        8_399,
        "orchestration.dispatchShow",
        json!({"task": task_id}),
    ));
    assert!(dispatch["active"].is_null(), "{dispatch}");
    // One failed startup per attempt and nothing left holding the task: the
    // exit reason lives on the dispatch, which is where the pre-dispatch path
    // records it.
    let history = dispatch["history"].as_array().unwrap();
    assert_eq!(history.len(), 3, "{dispatch}");
    for entry in history {
        assert_eq!(entry["status"], json!("startup_failed"), "{dispatch}");
        assert!(
            entry["startup_error"]
                .as_str()
                .unwrap()
                .contains("terminal exited with code 7"),
            "{dispatch}"
        );
    }
}

#[test]
#[cfg(unix)]
fn readiness_spawn_exit_honors_keep_on_failure() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_400,
        "orchestration.taskCreate",
        json!({"spec": "retain readiness diagnostics", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        8_401,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-1",
            "agent": "claude",
            "task": task["id"],
            "from": "coord",
            "command": "exit 9 #",
            "keepOnFailure": true
        }),
    ));
    let handle = spawned["terminalHandle"].as_str().unwrap().to_string();
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let terminal = expect_ok(request(
            &mut writer,
            &mut reader,
            8_402,
            "orchestration.terminalShow",
            json!({"handle": &handle}),
        ));
        if terminal["running"] == json!(false) {
            break;
        }
        assert!(Instant::now() < deadline, "{terminal}");
        std::thread::sleep(Duration::from_millis(25));
    }

    let shown = expect_ok(request(
        &mut writer,
        &mut reader,
        8_403,
        "orchestration.taskShow",
        json!({"id": task["id"]}),
    ));
    assert_eq!(shown["task"]["startup_failure_count"], json!(1), "{shown}");
    assert_eq!(shown["task"]["status"], json!("ready"), "{shown}");
    let tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_404,
        "tab.find",
        json!({"id": handle}),
    ));
    assert_eq!(tab["payload"]["spawnOnCreate"], json!(false), "{tab}");
    for consumed in [
        "initialPrompt",
        "pendingOrchestration",
        "orchestrationPreflight",
    ] {
        assert!(
            tab["payload"].get(consumed).is_none(),
            "{consumed} remained in {tab}"
        );
    }
    assert_eq!(
        tab["payload"]["orchestrationSpawn"]["startupFailureRecorded"],
        json!(true),
        "{tab}"
    );
    assert_eq!(
        tab["payload"]["orchestrationSpawn"]["retainedAfterFailure"],
        json!(true),
        "{tab}"
    );
    let waited = expect_ok(request(
        &mut writer,
        &mut reader,
        8_405,
        "orchestration.terminalWait",
        json!({"terminal": handle, "target": "agent-ready", "timeoutMs": 1_000}),
    ));
    assert_eq!(waited["outcome"], json!("failed"), "{waited}");
    assert!(waited["waitedMs"].is_number(), "{waited}");
}

#[test]
#[cfg(unix)]
fn timeout_keeps_codex_spawn_inert() {
    timeout_keeps_spawn_inert("codex", 8_410);
}

#[test]
#[cfg(unix)]
fn timeout_keeps_readiness_spawn_inert() {
    timeout_keeps_spawn_inert("claude", 8_420);
}

#[cfg(unix)]
fn timeout_keeps_spawn_inert(agent: &str, request_id: i64) {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id,
        "orchestration.taskCreate",
        json!({"spec": "retain timed out worker", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id + 1,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-1",
            "agent": agent,
            "task": task["id"],
            "from": "coord",
            "command": "sleep 1; exit 0 #",
            "keepOnFailure": true
        }),
    ));
    let handle = spawned["terminalHandle"].as_str().unwrap();
    let timeout = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id + 2,
        "orchestration.agentSpawnTimeout",
        json!({"terminal": handle}),
    ));
    assert_eq!(timeout["terminalRemoved"], json!(false), "{timeout}");
    let tab = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id + 3,
        "tab.find",
        json!({"id": handle}),
    ));
    assert_eq!(tab["payload"]["spawnOnCreate"], json!(false), "{tab}");
    for consumed in [
        "initialPrompt",
        "pendingOrchestration",
        "orchestrationPreflight",
    ] {
        assert!(
            tab["payload"].get(consumed).is_none(),
            "{consumed} remained in {tab}"
        );
    }
    assert_eq!(
        tab["payload"]["orchestrationSpawn"]["keepOnFailure"],
        json!(true),
        "{tab}"
    );
    assert_eq!(
        tab["payload"]["orchestrationSpawn"]["startupFailureRecorded"],
        json!(true),
        "{tab}"
    );
    assert_eq!(
        tab["payload"]["orchestrationSpawn"]["retainedAfterFailure"],
        json!(true),
        "{tab}"
    );
    let repeated = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id + 4,
        "orchestration.agentSpawnTimeout",
        json!({"terminal": handle}),
    ));
    assert_eq!(repeated["terminalRemoved"], json!(false), "{repeated}");
    let shown = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id + 5,
        "orchestration.taskShow",
        json!({"id": task["id"]}),
    ));
    assert_eq!(shown["task"]["startup_failure_count"], json!(1), "{shown}");
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let terminal = expect_ok(request(
            &mut writer,
            &mut reader,
            request_id + 6,
            "orchestration.terminalShow",
            json!({"handle": handle}),
        ));
        if terminal["running"] == json!(false) {
            break;
        }
        assert!(Instant::now() < deadline, "{terminal}");
        std::thread::sleep(Duration::from_millis(25));
    }
    let retained = expect_ok(request(
        &mut writer,
        &mut reader,
        request_id + 7,
        "tab.find",
        json!({"id": handle}),
    ));
    assert!(!retained.is_null(), "{retained}");
}

#[test]
#[cfg(unix)]
fn removed_readiness_agent_and_timeout_count_one_startup_failure() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_430,
        "orchestration.taskCreate",
        json!({"spec": "single readiness failure", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        8_431,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-1",
            "agent": "claude",
            "task": task["id"],
            "from": "coord",
            "command": "sh -c 'sleep 10' worker",
            "keepOnFailure": true
        }),
    ));
    let handle = spawned["terminalHandle"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_432,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": handle, "removed": true}]}),
    ));
    let terminal = expect_ok(request(
        &mut writer,
        &mut reader,
        8_433,
        "orchestration.terminalShow",
        json!({"handle": handle}),
    ));
    assert_eq!(terminal["startupState"], json!("failed"), "{terminal}");
    for request_id in [8_434, 8_435] {
        expect_ok(request(
            &mut writer,
            &mut reader,
            request_id,
            "orchestration.agentSpawnTimeout",
            json!({"terminal": handle}),
        ));
    }
    let shown = expect_ok(request(
        &mut writer,
        &mut reader,
        8_436,
        "orchestration.taskShow",
        json!({"id": task["id"]}),
    ));
    assert_eq!(shown["task"]["startup_failure_count"], json!(1), "{shown}");
    assert_eq!(shown["task"]["status"], json!("ready"), "{shown}");
}
