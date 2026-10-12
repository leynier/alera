use super::*;

fn declare_profile(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    name: &str,
    quota_group: Option<&str>,
) {
    let created = request(
        writer,
        reader,
        id,
        "agentProfile.upsert",
        json!({
            "name": name,
            "agentType": "codex",
            "command": "codex",
            "quotaGroup": quota_group,
        }),
    );
    assert_eq!(created["ok"], json!(true), "profile rejected: {created}");
}

/// A run refuses to start with no tasks, so seed one before planning.
fn start_run(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    approval_required: bool,
) -> Value {
    expect_ok(request(
        writer,
        reader,
        id,
        "orchestration.taskCreate",
        json!({
            "spec": "seed the run",
            "workspace": "ws",
            "coordinator": "coord",
            "createdBy": "coord",
        }),
    ));
    expect_ok(request(
        writer,
        reader,
        id + 1000,
        "orchestration.run",
        json!({
            "spec": "ship the feature",
            "from": "coord",
            "workspace": "ws",
            "approvalRequired": approval_required,
        }),
    ))
}

fn policy(profile: &str, fallbacks: Value) -> Value {
    json!({
        "stallPolicy": "wait",
        "stages": [
            {"id": "impl", "title": "Implementation", "profile": profile, "fallbacks": fallbacks}
        ]
    })
}

fn resolve(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    gate: &Value,
    decision: &str,
    reason: Option<&str>,
) -> Value {
    request(
        writer,
        reader,
        id,
        "runs.resolveGate",
        json!({
            "requestId": format!("resolve-{id}"),
            "gateId": gate["id"],
            "decision": decision,
            "reason": reason,
        }),
    )
}

fn pending_plan_gate(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    run_id: &str,
) -> Value {
    let gates = expect_ok(request(
        writer,
        reader,
        id,
        "orchestration.gateList",
        json!({"run": run_id, "kind": "plan", "status": "pending"}),
    ));
    let items = gates["items"].as_array().unwrap();
    assert_eq!(items.len(), 1, "{gates}");
    items[0].clone()
}

#[test]
fn a_plan_that_requires_approval_waits_behind_its_gate_until_approved() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 300, "Codex Sol", Some("codex"));
    declare_profile(&mut writer, &mut reader, 301, "Claude Big", Some("claude"));
    let started = start_run(&mut writer, &mut reader, 302, true);
    assert_eq!(started["status"], json!("planning"));
    assert_eq!(started["approvalRequired"], json!(true));
    let run_id = started["runId"].as_str().unwrap().to_string();

    let before = expect_ok(request(
        &mut writer,
        &mut reader,
        303,
        "orchestration.planContext",
        json!({ "run": run_id }),
    ));
    assert_eq!(before["currentPlan"], Value::Null);
    assert_eq!(before["isolation"], json!("shared"));

    let proposed = expect_ok(request(
        &mut writer,
        &mut reader,
        304,
        "orchestration.planPropose",
        json!({"run": run_id, "plan": policy("Codex Sol", json!(["Claude Big"])), "from": "coord"}),
    ));
    assert_eq!(proposed["status"], json!("awaitingApproval"));
    assert_eq!(proposed["revision"], json!(1));
    assert!(proposed["planGateId"].is_string());
    let context = expect_ok(request(
        &mut writer,
        &mut reader,
        3040,
        "orchestration.planContext",
        json!({ "run": run_id }),
    ));
    assert_eq!(context["stallPolicy"], json!("wait"));
    assert_eq!(
        context["currentPlan"]["stages"][0]["fallbacks"],
        json!(["Claude Big"])
    );
    let gate = pending_plan_gate(&mut writer, &mut reader, 305, &run_id);
    assert_eq!(gate["kind"], json!("plan"));
    assert_eq!(
        gate["options"],
        json!(["approve", "requestChanges", "reject"])
    );

    let invalid = resolve(&mut writer, &mut reader, 306, &gate, "Approve", None);
    assert_eq!(invalid["ok"], json!(false));
    assert_eq!(invalid["errorCode"], json!("gate_invalid_resolution"));

    let approved = expect_ok(resolve(
        &mut writer,
        &mut reader,
        307,
        &gate,
        "approve",
        None,
    ));
    assert_eq!(approved["gate"]["status"], json!("resolved"));
    assert_eq!(approved["gate"]["actorKind"], json!("cli"));
    assert_eq!(approved["runStatus"], json!("running"));

    let again = resolve(&mut writer, &mut reader, 309, &gate, "approve", None);
    assert_eq!(again["errorCode"], json!("gate_not_pending"));
}

#[test]
fn a_plan_without_required_approval_applies_at_once() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 310, "Codex Sol", None);
    let started = start_run(&mut writer, &mut reader, 311, false);
    assert_eq!(started["status"], json!("running"));
    let run_id = started["runId"].as_str().unwrap().to_string();

    let proposed = expect_ok(request(
        &mut writer,
        &mut reader,
        312,
        "orchestration.planPropose",
        json!({"run": run_id, "plan": policy("Codex Sol", json!([]))}),
    ));
    assert_eq!(proposed["planGateId"], Value::Null);
    assert_eq!(proposed["status"], json!("running"));
}

#[test]
fn rejecting_the_plan_cancels_the_run() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 320, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 321, true)["runId"]
        .as_str()
        .unwrap()
        .to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        3220,
        "orchestration.planPropose",
        json!({"run": run_id, "plan": policy("Codex Sol", json!([]))}),
    ));
    let gate = pending_plan_gate(&mut writer, &mut reader, 322, &run_id);

    expect_ok(resolve(
        &mut writer,
        &mut reader,
        323,
        &gate,
        "reject",
        Some("wrong split"),
    ));
    let run = expect_ok(request(
        &mut writer,
        &mut reader,
        324,
        "orchestration.runShow",
        json!({"id": run_id}),
    ));
    assert_eq!(run["run"]["status"], json!("cancelled"));
    assert_eq!(run["run"]["stop_reason"], json!("wrong split"));
}

#[test]
fn a_policy_referencing_an_undeclared_profile_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 330, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 331, false)["runId"]
        .as_str()
        .unwrap()
        .to_string();

    let missing_profile = request(
        &mut writer,
        &mut reader,
        332,
        "orchestration.planPropose",
        json!({"run": run_id, "plan": policy("Nonexistent", json!([]))}),
    );
    assert_eq!(missing_profile["ok"], json!(false));
    assert!(
        missing_profile["error"]
            .as_str()
            .unwrap_or_default()
            .contains("unknown agent profile"),
        "unexpected error: {missing_profile}"
    );

    // A fallback naming an undeclared profile is just as fatal as the preferred
    // one: it would only surface at dispatch, long after the user is gone.
    let missing_fallback = request(
        &mut writer,
        &mut reader,
        333,
        "orchestration.planPropose",
        json!({"run": run_id, "plan": policy("Codex Sol", json!(["Nonexistent"]))}),
    );
    assert_eq!(missing_fallback["ok"], json!(false));
}

#[test]
fn a_malformed_policy_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 340, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 341, false)["runId"]
        .as_str()
        .unwrap()
        .to_string();

    let cases = vec![
        ("empty stages", json!({"version": 1, "stages": []})),
        (
            "duplicate stage ids",
            json!({"version": 1, "stages": [
                {"id": "impl", "profile": "Codex Sol"},
                {"id": "impl", "profile": "Codex Sol"}
            ]}),
        ),
        (
            "unknown stall policy",
            json!({"version": 1, "stallPolicy": "explode", "stages": [
                {"id": "impl", "profile": "Codex Sol"}
            ]}),
        ),
        (
            "unsupported version",
            json!({"version": 99, "stages": [{"id": "impl", "profile": "Codex Sol"}]}),
        ),
        (
            "stage without a profile",
            json!({"version": 1, "stages": [{"id": "impl"}]}),
        ),
    ];
    for (index, (label, body)) in cases.into_iter().enumerate() {
        let response = request(
            &mut writer,
            &mut reader,
            350 + index as i64,
            "orchestration.planPropose",
            json!({"run": run_id, "plan": body}),
        );
        assert_eq!(response["ok"], json!(false), "{label} was accepted");
    }
}

#[test]
fn a_task_stage_must_be_declared_by_the_run_plan() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 360, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 361, false)["runId"]
        .as_str()
        .unwrap()
        .to_string();
    expect_ok(request(
        &mut writer,
        &mut reader,
        362,
        "orchestration.planPropose",
        json!({"run": run_id, "plan": policy("Codex Sol", json!([]))}),
    ));

    let bound = expect_ok(request(
        &mut writer,
        &mut reader,
        363,
        "orchestration.taskCreate",
        json!({
            "spec": "implement it",
            "workspace": "ws",
            "run": run_id,
            "coordinator": "coord",
            "createdBy": "coord",
            "stage": "impl",
        }),
    ));
    assert_eq!(bound["stage_id"], json!("impl"));

    let undeclared = request(
        &mut writer,
        &mut reader,
        364,
        "orchestration.taskCreate",
        json!({
            "spec": "document it",
            "workspace": "ws",
            "run": run_id,
            "coordinator": "coord",
            "createdBy": "coord",
            "stage": "docs",
        }),
    );
    assert_eq!(undeclared["ok"], json!(false));
    assert!(
        undeclared["error"]
            .as_str()
            .unwrap_or_default()
            .contains("declares no stage"),
        "unexpected error: {undeclared}"
    );
}

#[test]
fn the_host_advertises_inbox_delivery_and_no_run_policy_approval() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let status = expect_ok(request(
        &mut writer,
        &mut reader,
        370,
        "status.get",
        json!({}),
    ));
    let capabilities = status["runtimeCapabilities"].as_array().unwrap();
    assert!(capabilities.contains(&json!("inboxV1")), "{capabilities:?}");
    assert!(capabilities.contains(&json!("inboxV2")), "{capabilities:?}");
    assert!(
        !capabilities.contains(&json!("orchestrationRunPolicyV1")),
        "{capabilities:?}"
    );
    assert!(capabilities.contains(&json!("runsV1")), "{capabilities:?}");
    for removed in [
        "orchestration.dispatchAccept",
        "orchestration.heartbeat",
        "orchestration.workerDone",
        "orchestration.workerHelp",
        "orchestration.runPolicyApprove",
        "orchestration.runPolicyShow",
        "orchestration.gateResolve",
        "orchestration.boardSnapshot",
        "orchestration.inbox",
    ] {
        let response = request(&mut writer, &mut reader, 371, removed, json!({}));
        assert_eq!(response["ok"], json!(false), "{removed} still answers");
    }
}
