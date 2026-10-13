use super::*;

#[test]
fn task_dag_dispatch_and_completion() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let task_a = expect_ok(request(
        &mut writer,
        &mut reader,
        40,
        "orchestration.taskCreate",
        json!({"spec": "implement A"}),
    ));
    let a_id = task_a["id"].as_str().unwrap().to_string();
    assert_eq!(task_a["status"], json!("ready"));
    let task_b = expect_ok(request(
        &mut writer,
        &mut reader,
        41,
        "orchestration.taskCreate",
        json!({"spec": "test A", "deps": [a_id]}),
    ));
    assert_eq!(task_b["status"], json!("pending"));
    let b_id = task_b["id"].as_str().unwrap().to_string();

    // Dry-run builds a preamble without mutating anything.
    let dry = expect_ok(request(
        &mut writer,
        &mut reader,
        42,
        "orchestration.dispatch",
        json!({"task": a_id, "to": "w1", "from": "coord", "dryRun": true}),
    ));
    let dry_preamble = dry["preamble"].as_str().unwrap();
    assert!(dry_preamble.contains("NEVER use AskUserQuestion"));
    assert!(dry_preamble.contains("Exit the shell after completion"));
    assert!(!dry_preamble.contains("return to an idle prompt"));

    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        43,
        "orchestration.dispatch",
        json!({"task": a_id, "to": "w1", "from": "coord"}),
    ));
    let context_token = dispatched["contextToken"].as_str().unwrap().to_string();
    assert_eq!(dispatched["preamble"], dispatched["bootstrap"]);
    let manual_bootstrap = dispatched["preamble"].as_str().unwrap();
    assert!(!manual_bootstrap.contains("dispatch-accept"));
    assert!(manual_bootstrap.contains("orchestration --json context"));
    assert!(manual_bootstrap.contains("complete --summary"));
    assert!(!manual_bootstrap.contains("=== TASK ==="));

    expect_ok(request(
        &mut writer,
        &mut reader,
        44,
        "orchestration.context",
        json!({"terminal": "w1", "contextToken": context_token}),
    ));
    // Dedicated completion from the assignee completes A and promotes B.
    expect_ok(request(
        &mut writer,
        &mut reader,
        46,
        "orchestration.complete",
        json!({"terminal": "w1", "contextToken": context_token, "result": {
            "summary": "done", "completionKind": "success",
            "artifacts": [], "filesModified": [], "validation": []
        }}),
    ));
    let tasks = expect_ok(request(
        &mut writer,
        &mut reader,
        45,
        "orchestration.taskList",
        json!({}),
    ));
    let by_id: std::collections::HashMap<&str, &str> = tasks["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .map(|task| {
            (
                task["id"].as_str().unwrap(),
                task["status"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(by_id[a_id.as_str()], "completed");
    assert_eq!(by_id[b_id.as_str()], "ready");
}

#[test]
fn gate_blocks_and_resolution_feeds_next_preamble() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let task = expect_ok(request(
        &mut writer,
        &mut reader,
        50,
        "orchestration.taskCreate",
        json!({"spec": "risky change"}),
    ));
    let task_id = task["id"].as_str().unwrap().to_string();
    let gate = expect_ok(request(
        &mut writer,
        &mut reader,
        51,
        "orchestration.gateCreate",
        json!({"task": task_id, "question": "Proceed?", "options": ["yes", "no"]}),
    ));
    let gate_id = gate["id"].as_str().unwrap().to_string();

    let blocked = expect_ok(request(
        &mut writer,
        &mut reader,
        52,
        "orchestration.taskList",
        json!({"status": "blocked"}),
    ));
    assert_eq!(blocked["tasks"][0]["id"], json!(task_id));

    // A gate with options only takes one of them.
    let free_text = request(
        &mut writer,
        &mut reader,
        53,
        "runs.resolveGate",
        json!({"requestId": "resolve-free-text", "gateId": gate_id, "decision": "yes, carefully"}),
    );
    assert_eq!(free_text["errorCode"], json!("gate_invalid_resolution"));
    expect_ok(request(
        &mut writer,
        &mut reader,
        530,
        "runs.resolveGate",
        json!({"requestId": "resolve-yes", "gateId": gate_id, "decision": "yes"}),
    ));
    let dispatched = expect_ok(request(
        &mut writer,
        &mut reader,
        54,
        "orchestration.dispatch",
        json!({"task": task_id, "to": "w1", "from": "coord", "returnPreamble": true}),
    ));
    let preamble = dispatched["preamble"].as_str().unwrap();
    assert!(preamble.contains("DECISION GATE RESOLVED"));
    assert!(preamble.contains("Resolution: yes"));
}
