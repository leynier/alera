use super::*;

#[test]
#[cfg(unix)]
fn server_side_waits_observe_dispatch_and_task_transitions() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let (mut wait_writer, mut wait_reader) = connect(host.port);
    handshake(&mut wait_writer, &mut wait_reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-1");
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_310,
        "wait-worker",
        "ws-1",
        "wait-tab",
        &["-c", "stty -echo; cat"],
    );
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_311,
        "orchestration.taskCreate",
        json!({"spec": "wait transitions", "workspace": "ws-1", "coordinator": "coord"}),
    ));
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_312,
        "orchestration.dispatch",
        json!({"task": task["id"], "to": "wait-worker", "from": "coord"}),
    ));
    send(
        &mut wait_writer,
        json!({
            "id": 8_313,
            "type": "orchestration.terminalWait",
            "payload": {
                "terminal": "wait-worker",
                "target": "dispatch-accepted",
                "timeoutMs": 2_000
            }
        }),
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_314,
        "orchestration.dispatchAccept",
        json!({
            "terminal": "wait-worker",
            "contextToken": dispatched["contextToken"]
        }),
    ));
    let terminal_wait = read_response(&mut wait_reader, 8_313);
    assert_eq!(terminal_wait["payload"]["outcome"], json!("reached"));
    assert!(terminal_wait["payload"]["waitedMs"].is_number());

    send(
        &mut wait_writer,
        json!({
            "id": 8_315,
            "type": "orchestration.taskWait",
            "payload": {
                "task": task["id"],
                "targets": ["completed"],
                "timeoutMs": 2_000
            }
        }),
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_316,
        "orchestration.complete",
        json!({
            "terminal": "wait-worker",
            "contextToken": dispatched["contextToken"],
            "result": {
                "summary": "done",
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": []
            }
        }),
    ));
    let task_wait = read_response(&mut wait_reader, 8_315);
    assert_eq!(task_wait["payload"]["outcome"], json!("reached"));
    assert_eq!(task_wait["payload"]["state"], json!("completed"));
    assert!(task_wait["payload"]["waitedMs"].is_number());
}

#[test]
#[cfg(unix)]
fn dispatch_acceptance_wait_recognizes_a_later_stalled_state() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    seed_workspace(&mut writer, &mut reader, "ws-stalled");
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_320,
        "stalled-worker",
        "ws-stalled",
        "stalled-tab",
        &["-c", "stty -echo; cat"],
    );
    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        8_321,
        "orchestration.taskCreate",
        json!({
            "spec": "recognize accepted dispatch after stall",
            "workspace": "ws-stalled",
            "coordinator": "coord"
        }),
    ));
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        8_322,
        "orchestration.dispatch",
        json!({"task": task["id"], "to": "stalled-worker", "from": "coord"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_323,
        "orchestration.dispatchAccept",
        json!({
            "terminal": "stalled-worker",
            "contextToken": dispatched["contextToken"]
        }),
    ));

    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let store = alera_core::runtime::RuntimeStore::open(host._dir.path())
            .await
            .unwrap();
        sqlx::query("UPDATE orchestrationTasks SET status = 'stalled' WHERE id = ?")
            .bind(task["id"].as_str().unwrap())
            .execute(store.pool())
            .await
            .unwrap();
        sqlx::query("UPDATE orchestrationDispatchContexts SET status = 'stalled' WHERE id = ?")
            .bind(dispatched["dispatch"]["id"].as_str().unwrap())
            .execute(store.pool())
            .await
            .unwrap();
    });

    let wait = expect_ok(request(
        &mut writer,
        &mut reader,
        8_324,
        "orchestration.terminalWait",
        json!({
            "terminal": "stalled-worker",
            "target": "dispatch-accepted",
            "timeoutMs": 1
        }),
    ));
    assert_eq!(wait["outcome"], json!("reached"), "{wait}");
    assert_eq!(wait["state"], json!("stalled"), "{wait}");
    assert!(wait["waitedMs"].is_number(), "{wait}");
}

#[test]
#[cfg(unix)]
fn terminal_submit_waits_for_paste_before_sending_enter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_330,
        "submit-worker",
        "ws-1",
        "submit-tab",
        &["-c", "stty -echo; cat"],
    );
    std::thread::sleep(Duration::from_millis(300));
    let _ = collect_output(&mut reader, "submit-worker", Duration::from_millis(200));
    let started = Instant::now();
    expect_ok(request(
        &mut writer,
        &mut reader,
        8_331,
        "write",
        json!({
            "sessionId": "submit-worker",
            "dataBase64": STANDARD.encode(b"hello tui"),
            "deferredEnter": true,
            "bracketedPaste": true
        }),
    ));
    assert!(
        started.elapsed() >= Duration::from_millis(400),
        "write acknowledged before deferred Enter"
    );
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut request_id = 8_332;
    loop {
        let output = expect_ok(request(
            &mut writer,
            &mut reader,
            request_id,
            "terminal.read",
            json!({"sessionId": "submit-worker"}),
        ));
        if output["text"].as_str().unwrap().contains("hello tui") {
            break;
        }
        assert!(Instant::now() < deadline, "{output}");
        request_id += 1;
        std::thread::sleep(Duration::from_millis(25));
    }

    expect_ok(request(
        &mut writer,
        &mut reader,
        8_339,
        "write",
        json!({
            "sessionId": "submit-worker",
            "dataBase64": STANDARD.encode(b"line one\r\nline two"),
            "bracketedPaste": true,
            "deferredEnter": true
        }),
    ));
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        let output = expect_ok(request(
            &mut writer,
            &mut reader,
            8_338,
            "terminal.read",
            json!({"sessionId": "submit-worker"}),
        ));
        let text = output["text"].as_str().unwrap();
        if text.contains("line two") {
            assert!(!text.contains("<0x0D>"), "{text}");
            break;
        }
        assert!(Instant::now() < deadline, "{output}");
        std::thread::sleep(Duration::from_millis(25));
    }
}

#[test]
#[cfg(unix)]
fn empty_terminal_submit_sends_exactly_one_enter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    attach_shell_session(
        &mut writer,
        &mut reader,
        8_340,
        "empty-submit-worker",
        "ws-1",
        "empty-submit-tab",
        &[
            "-c",
            "stty raw -echo; printf 'ready-marker\\n'; first=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' '); printf 'first-%s\\n' \"$first\"; second=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' '); printf 'second-%s\\n' \"$second\"; cat",
        ],
    );
    let ready = collect_output(&mut reader, "empty-submit-worker", Duration::from_secs(1));
    assert!(ready.contains("ready-marker"), "{ready}");
    for (request_id, bracketed_paste, marker) in
        [(8_341, false, "first-0d"), (8_342, true, "second-0d")]
    {
        expect_ok(request(
            &mut writer,
            &mut reader,
            request_id,
            "write",
            json!({
                "sessionId": "empty-submit-worker",
                "dataBase64": STANDARD.encode(b""),
                "deferredEnter": true,
                "bracketedPaste": bracketed_paste
            }),
        ));
        let output = collect_output(&mut reader, "empty-submit-worker", Duration::from_secs(1));
        assert!(output.contains(marker), "{output}");
    }
}
