use super::*;

#[test]
#[cfg(unix)]
fn push_on_idle_does_not_duplicate_in_flight_batches() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "orchestration-review-pty";

    attach_shell_session(
        &mut writer,
        &mut reader,
        30,
        session_id,
        "ws-1",
        "tab-1",
        &["-lc", "stty -echo; cat"],
    );
    std::thread::sleep(Duration::from_millis(700));
    let _ = collect_output(&mut reader, session_id, Duration::from_millis(400));
    expect_ok(request(
        &mut writer,
        &mut reader,
        31,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        32,
        "orchestration.send",
        json!({"from": "coord", "to": session_id, "subject": "first", "body": "one"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        33,
        "orchestration.send",
        json!({"from": "coord", "to": session_id, "subject": "second", "body": "two"}),
    ));

    let output = collect_output(&mut reader, session_id, Duration::from_secs(4));
    assert_eq!(occurrences(&output, "Subject: first"), 1, "{output}");
    assert_eq!(occurrences(&output, "Subject: second"), 1, "{output}");
}

#[test]
#[cfg(unix)]
fn waiting_status_does_not_push_into_approval_prompt() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "waiting-approval-session";

    attach_shell_session(
        &mut writer,
        &mut reader,
        331,
        session_id,
        "ws-1",
        "tab-1",
        &["-lc", "stty -echo; cat"],
    );
    std::thread::sleep(Duration::from_millis(700));
    let _ = collect_output(&mut reader, session_id, Duration::from_millis(400));
    expect_ok(request(
        &mut writer,
        &mut reader,
        332,
        "orchestration.send",
        json!({"from": "coord", "to": session_id, "subject": "approval-safe", "body": "do not inject yet"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        333,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "waiting"}]}),
    ));

    let waiting_output = collect_output(&mut reader, session_id, Duration::from_millis(900));
    assert!(
        !waiting_output.contains("approval-safe"),
        "waiting approval prompt received injected banner: {waiting_output}"
    );

    expect_ok(request(
        &mut writer,
        &mut reader,
        334,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}),
    ));
    let done_output = collect_output(&mut reader, session_id, Duration::from_secs(3));
    assert!(
        done_output.contains("Subject: approval-safe"),
        "done transition did not receive queued banner: {done_output}"
    );
}

#[test]
#[cfg(unix)]
fn deferred_delivery_requeues_when_session_instance_is_replaced() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "replaced-delivery-session";

    attach_shell_session(
        &mut writer,
        &mut reader,
        34,
        session_id,
        "ws-1",
        "tab-old",
        &["-lc", "stty -echo; sleep 10"],
    );
    expect_ok(request(
        &mut writer,
        &mut reader,
        35,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}),
    ));
    send_batch(
        &mut writer,
        &[
            json!({"id": 36, "type": "orchestration.send", "payload": {"from": "coord", "to": session_id, "subject": "replacement delivery", "body": "redeliver me"}}),
            json!({"id": 37, "type": "terminate", "payload": {"sessionId": session_id}}),
            json!({"id": 38, "type": "createOrAttach", "payload": {
                "sessionId": session_id,
                "workspaceId": "ws-1",
                "tabId": "tab-new",
                "workingDirectory": "/tmp",
                "launch": {
                    "shell": "/bin/sh",
                    "arguments": ["-lc", "stty -echo; cat"],
                    "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}
                },
                "cols": 120,
                "rows": 40
            }}),
            json!({"id": 39, "type": "orchestration.agentStatus", "payload": {"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}}),
        ],
    );
    for id in 36..=39 {
        expect_ok(read_response(&mut reader, id));
    }

    let output = collect_output(&mut reader, session_id, Duration::from_secs(3));
    assert!(
        output.contains("Subject: replacement delivery"),
        "replacement session did not receive the queued banner: {output}"
    );
}

#[test]
#[cfg(unix)]
fn coordinator_promotion_waits_for_deferred_delivery() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let session_id = "promoted-coordinator-session";

    attach_shell_session(
        &mut writer,
        &mut reader,
        340,
        session_id,
        "ws-1",
        "tab-1",
        &["-lc", "stty -echo; cat"],
    );
    std::thread::sleep(Duration::from_millis(700));
    let _ = collect_output(&mut reader, session_id, Duration::from_millis(400));
    expect_ok(request(
        &mut writer,
        &mut reader,
        341,
        "orchestration.agentStatus",
        json!({"entries": [{"terminalSessionId": session_id, "agentType": "claude", "state": "done"}]}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        342,
        "orchestration.send",
        json!({"from": "coord", "to": session_id, "subject": "do not submit", "body": "queued"}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        343,
        "orchestration.taskCreate",
        json!({"spec": "keep the coordinator active"}),
    ));
    let promotion = request(
        &mut writer,
        &mut reader,
        344,
        "orchestration.run",
        json!({"from": session_id, "spec": "coordinate", "pollIntervalMs": 60000}),
    );
    assert_eq!(promotion["ok"], json!(false), "{promotion}");
    assert!(
        promotion["error"]
            .as_str()
            .unwrap()
            .contains("prompt delivery in flight"),
        "{promotion}"
    );

    std::thread::sleep(Duration::from_millis(900));
    let output = collect_output(&mut reader, session_id, Duration::from_millis(400));
    assert_eq!(
        occurrences(&output, "Subject: do not submit"),
        1,
        "{output}"
    );
    let checked = expect_ok(request(
        &mut writer,
        &mut reader,
        345,
        "orchestration.check",
        json!({"terminal": session_id, "all": true}),
    ));
    assert_eq!(checked["messages"][0]["subject"], json!("do not submit"));
    assert_ne!(checked["messages"][0]["delivered_at"], Value::Null);
    expect_ok(request(
        &mut writer,
        &mut reader,
        346,
        "orchestration.run",
        json!({"from": session_id, "spec": "coordinate", "pollIntervalMs": 60000}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        347,
        "orchestration.runStop",
        json!({}),
    ));
}
