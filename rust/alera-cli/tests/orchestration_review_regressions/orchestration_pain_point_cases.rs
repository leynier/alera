use super::*;

#[test]
#[cfg(unix)]
fn timed_out_agent_spawn_cannot_dispatch_on_late_readiness() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        113,
        "orchestration.taskCreate",
        json!({"spec": "late worker", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let task_id = task["id"].as_str().unwrap();
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        114,
        "orchestration.agentSpawn",
        json!({"workspace": "ws-1", "agent": "claude", "task": task_id, "from": "coord"}),
    ));
    let handle = spawned["terminalHandle"].as_str().unwrap();
    let timeout = expect_ok(request(
        &mut writer,
        &mut reader,
        115,
        "orchestration.agentSpawnTimeout",
        json!({"terminal": handle}),
    ));
    assert_eq!(timeout["terminalRemoved"], json!(true), "{timeout}");
    let removed_tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_299,
        "tab.find",
        json!({"id": handle}),
    ));
    assert!(removed_tab.is_null(), "{removed_tab}");

    attach_shell_session(
        &mut writer,
        &mut reader,
        116,
        handle,
        "ws-1",
        handle,
        &["-c", "stty -echo; cat"],
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        117,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": handle, "agentType": "claude", "state": "done"}]}),
    ));
    let show = expect_ok(request(
        &mut writer,
        &mut reader,
        118,
        "orchestration.dispatchShow",
        json!({"task": task_id}),
    ));
    assert!(show["active"].is_null(), "{show}");
    assert!(show["history"].as_array().unwrap().is_empty(), "{show}");
}

#[test]
#[cfg(unix)]
fn codex_spawn_creates_dispatch_before_first_hook() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_300,
        "orchestration.taskCreate",
        json!({"spec": "bootstrap worker", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let gate = expect_ok(request(
        &mut writer,
        &mut reader,
        8_298,
        "orchestration.gateCreate",
        json!({
            "task": task["id"],
            "question": "Which Mode?",
            "options": ["safe", "fast"]
        }),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_299,
        "orchestration.gateResolve",
        json!({"id": gate["id"], "resolution": "safe"}),
    ));
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        8_301,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-1",
            "agent": "codex",
            "task": task["id"],
            "from": "coord",
            "command": "sh -c 'sleep 10' worker"
        }),
    ));
    assert_eq!(spawned["acceptanceState"], json!("awaiting_acceptance"));
    assert_eq!(spawned["dispatch"]["status"], json!("awaiting_acceptance"));
    let handle = spawned["terminalHandle"].as_str().unwrap();
    let tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_302,
        "tab.find",
        json!({"id": handle}),
    ));
    let prompt = tab["payload"]["initialPrompt"].as_str().unwrap();
    assert!(prompt.contains("dispatch-accept"), "{prompt}");
    assert!(prompt.contains("--json context"), "{prompt}");
    assert!(!prompt.contains("=== TASK ==="), "{prompt}");
    let context: Value =
        serde_json::from_slice(&std::fs::read(spawned["contextPath"].as_str().unwrap()).unwrap())
            .unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_303,
        "orchestration.dispatchAccept",
        json!({
            "terminal": handle,
            "contextToken": context["token"],
        }),
    ));
    let worker_context = expect_ok(request(
        &mut writer,
        &mut reader,
        8_305,
        "orchestration.context",
        json!({
            "terminal": handle,
            "contextToken": context["token"],
        }),
    ));
    assert_eq!(worker_context["task"]["spec"], json!("bootstrap worker"));
    assert_eq!(
        worker_context["gateResolution"],
        json!({"question": "Which Mode?", "resolution": "safe"})
    );
    let worker_instructions = worker_context["workerInstructions"].as_str().unwrap();
    for command in ["heartbeat", "complete", "ask", "escalate", "check"] {
        assert!(
            worker_instructions.contains(command),
            "{command} missing from {worker_instructions}"
        );
    }
    assert!(!worker_instructions.contains("bootstrap worker"));
    assert!(!worker_instructions.contains("=== TASK ==="));
    let accepted_tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_304,
        "tab.find",
        json!({"id": handle}),
    ));
    assert!(accepted_tab["payload"].get("initialPrompt").is_none());
    assert!(accepted_tab["payload"].get("orchestrationSpawn").is_none());
    assert_eq!(
        accepted_tab["payload"]["initialCommand"],
        json!("sh -c 'sleep 10' worker")
    );
    assert_eq!(accepted_tab["payload"]["spawnOnCreate"], json!(true));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_390,
        "orchestration.complete",
        json!({
            "terminal": handle,
            "contextToken": context["token"],
            "result": {
                "summary": "ready for reuse",
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": []
            }
        }),
    ));

    let reused_task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_306,
        "orchestration.taskCreate",
        json!({"spec": "reuse worker", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_307,
        "orchestration.dispatch",
        json!({
            "task": reused_task["id"],
            "to": handle,
            "from": "coord",
            "inject": false
        }),
    ));
    let timeout = expect_ok(request(
        &mut writer,
        &mut reader,
        8_308,
        "orchestration.agentSpawnTimeout",
        json!({"terminal": handle}),
    ));
    assert_eq!(timeout["terminalRemoved"], json!(false), "{timeout}");
    let retained_tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_309,
        "tab.find",
        json!({"id": handle}),
    ));
    assert!(!retained_tab.is_null(), "{retained_tab}");
}

#[test]
#[cfg(unix)]
fn coordinator_predispatches_new_codex_worker() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_303,
        "orchestration.taskCreate",
        json!({"spec": "coordinated bootstrap", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let second_task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_307,
        "orchestration.taskCreate",
        json!({"spec": "second coordinated bootstrap", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_304,
        "orchestration.run",
        json!({
            "from": "coord",
            "workspace": "ws-1",
            "agent": "codex",
            "spec": "coordinate",
            "pollIntervalMs": 50,
            "maxConcurrent": 2
        }),
    ));
    let deadline = Instant::now() + Duration::from_secs(3);
    let handles = loop {
        let handles: Vec<String> = [&task, &second_task]
            .into_iter()
            .filter_map(|task| {
                let shown = expect_ok(request(
                    &mut writer,
                    &mut reader,
                    8_305,
                    "orchestration.taskShow",
                    json!({"id": task["id"]}),
                ));
                shown["activeDispatch"]["assignee_handle"]
                    .as_str()
                    .map(str::to_string)
            })
            .collect();
        if handles.len() == 2 {
            break handles;
        }
        assert!(
            Instant::now() < deadline,
            "coordinator did not pre-dispatch two Codex workers: {handles:?}"
        );
        std::thread::sleep(Duration::from_millis(50));
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        sqlx::query(
            "UPDATE orchestrationDispatchContexts SET dispatched_at = '2020-01-01 00:00:00' \
             WHERE status = 'awaiting_acceptance'",
        )
        .execute(store.pool())
        .await
        .unwrap();
    });
    let cleanup_deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let remaining = handles.iter().filter(|handle| {
            !expect_ok(request(
                &mut writer,
                &mut reader,
                8_306,
                "tab.find",
                json!({"id": handle}),
            ))
            .is_null()
        });
        if remaining.count() == 0 {
            break;
        }
        assert!(Instant::now() < cleanup_deadline);
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
#[cfg(unix)]
fn pre_acceptance_terminal_exit_consumes_startup_budget() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_317,
        "orchestration.taskCreate",
        json!({"spec": "exit before acceptance", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        8_318,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-1",
            "agent": "codex",
            "task": task["id"],
            "from": "coord",
            "command": "sh -c 'stty -echo; cat' worker",
            "keepOnFailure": true
        }),
    ));
    let handle = spawned["terminalHandle"].as_str().unwrap();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_319,
        "terminate",
        json!({"sessionId": handle}),
    ));
    let removed_tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_322,
        "tab.find",
        json!({"id": handle}),
    ));
    assert!(removed_tab.is_null(), "{removed_tab}");
    let shown = expect_ok(request(
        &mut writer,
        &mut reader,
        8_320,
        "orchestration.taskShow",
        json!({"id": task["id"]}),
    ));
    assert_eq!(shown["task"]["status"], json!("ready"), "{shown}");
    assert_eq!(shown["task"]["startup_failure_count"], json!(1), "{shown}");
    let dispatch = expect_ok(request(
        &mut writer,
        &mut reader,
        8_321,
        "orchestration.dispatchShow",
        json!({"task": task["id"]}),
    ));
    assert_eq!(
        dispatch["history"][0]["status"],
        json!("startup_failed"),
        "{dispatch}"
    );
    assert_eq!(
        dispatch["history"][0]["failure_count"],
        json!(0),
        "{dispatch}"
    );
}

#[test]
#[cfg(unix)]
fn kept_spawn_preserves_diagnostics_after_startup_process_exit() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_323,
        "orchestration.taskCreate",
        json!({"spec": "keep failed startup", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let spawned = expect_ok(request(
        &mut writer,
        &mut reader,
        8_324,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws-1",
            "agent": "codex",
            "task": task["id"],
            "from": "coord",
            "command": "exit 7 #",
            "keepOnFailure": true
        }),
    ));
    let handle = spawned["terminalHandle"].as_str().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut request_id = 8_325;
    loop {
        let terminal = expect_ok(request(
            &mut writer,
            &mut reader,
            request_id,
            "orchestration.terminalShow",
            json!({"handle": handle}),
        ));
        if terminal["running"] == json!(false) {
            assert_eq!(terminal["startupState"], json!("failed"), "{terminal}");
            break;
        }
        assert!(Instant::now() < deadline, "{terminal}");
        request_id += 1;
        std::thread::sleep(Duration::from_millis(50));
    }
    let retained_tab = expect_ok(request(
        &mut writer,
        &mut reader,
        8_328,
        "tab.find",
        json!({"id": handle}),
    ));
    assert!(!retained_tab.is_null(), "{retained_tab}");
    assert_eq!(
        retained_tab["payload"]["spawnOnCreate"],
        json!(false),
        "{retained_tab}"
    );
    for consumed in ["initialPrompt", "pendingOrchestration"] {
        assert!(
            retained_tab["payload"].get(consumed).is_none(),
            "{consumed} remained in {retained_tab}"
        );
    }
    assert_eq!(
        retained_tab["payload"]["orchestrationSpawn"]["retainedAfterFailure"],
        json!(true),
        "{retained_tab}"
    );
    let shown = expect_ok(request(
        &mut writer,
        &mut reader,
        8_329,
        "orchestration.taskShow",
        json!({"id": task["id"]}),
    ));
    assert_eq!(shown["task"]["status"], json!("ready"), "{shown}");
    assert_eq!(shown["task"]["startup_failure_count"], json!(1), "{shown}");
}
