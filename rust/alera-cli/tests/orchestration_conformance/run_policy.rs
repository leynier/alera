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
fn start_run(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, id: i64) -> String {
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
    let run = expect_ok(request(
        writer,
        reader,
        id + 1000,
        "orchestration.run",
        json!({"spec": "ship the feature", "from": "coord", "workspace": "ws"}),
    ));
    run["runId"].as_str().unwrap().to_string()
}

fn policy(profile: &str, fallbacks: Value) -> Value {
    json!({
        "version": 1,
        "stallPolicy": "ask",
        "stages": [
            {"id": "impl", "title": "Implementation", "profile": profile, "fallbacks": fallbacks}
        ]
    })
}

#[test]
fn a_policy_is_proposed_then_approved() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 300, "Codex Sol", Some("codex"));
    declare_profile(&mut writer, &mut reader, 301, "Claude Big", Some("claude"));
    let run_id = start_run(&mut writer, &mut reader, 302);

    let before = expect_ok(request(
        &mut writer,
        &mut reader,
        303,
        "orchestration.runPolicyShow",
        json!({ "run": run_id }),
    ));
    assert_eq!(before["status"], json!("none"));
    assert_eq!(before["blocksDispatch"], json!(false));

    let proposed = expect_ok(request(
        &mut writer,
        &mut reader,
        304,
        "orchestration.runPolicyPropose",
        json!({"run": run_id, "policy": policy("Codex Sol", json!(["Claude Big"]))}),
    ));
    assert_eq!(proposed["status"], json!("draft"));
    assert_eq!(proposed["blocksDispatch"], json!(true));
    assert_eq!(proposed["policy"]["stages"][0]["id"], json!("impl"));
    assert_eq!(
        proposed["policy"]["stages"][0]["fallbacks"],
        json!(["Claude Big"])
    );

    let approved = expect_ok(request(
        &mut writer,
        &mut reader,
        305,
        "orchestration.runPolicyApprove",
        json!({"run": run_id, "actor": "coord"}),
    ));
    assert_eq!(approved["status"], json!("approved"));
    assert_eq!(approved["blocksDispatch"], json!(false));
}

#[test]
fn a_policy_referencing_an_undeclared_profile_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 310, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 311);

    let missing_profile = request(
        &mut writer,
        &mut reader,
        312,
        "orchestration.runPolicyPropose",
        json!({"run": run_id, "policy": policy("Nonexistent", json!([]))}),
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
        313,
        "orchestration.runPolicyPropose",
        json!({"run": run_id, "policy": policy("Codex Sol", json!(["Nonexistent"]))}),
    );
    assert_eq!(missing_fallback["ok"], json!(false));
}

#[test]
fn a_malformed_policy_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 320, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 321);

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
            330 + index as i64,
            "orchestration.runPolicyPropose",
            json!({"run": run_id, "policy": body}),
        );
        assert_eq!(response["ok"], json!(false), "{label} was accepted");
    }
}

#[test]
fn approving_twice_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 340, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 341);
    expect_ok(request(
        &mut writer,
        &mut reader,
        342,
        "orchestration.runPolicyPropose",
        json!({"run": run_id, "policy": policy("Codex Sol", json!([]))}),
    ));
    expect_ok(request(
        &mut writer,
        &mut reader,
        343,
        "orchestration.runPolicyApprove",
        json!({"run": run_id, "actor": "coord"}),
    ));

    let again = request(
        &mut writer,
        &mut reader,
        344,
        "orchestration.runPolicyApprove",
        json!({"run": run_id, "actor": "coord"}),
    );
    assert_eq!(again["ok"], json!(false));
}

#[test]
fn rejecting_requires_a_reason() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 350, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 351);
    expect_ok(request(
        &mut writer,
        &mut reader,
        352,
        "orchestration.runPolicyPropose",
        json!({"run": run_id, "policy": policy("Codex Sol", json!([]))}),
    ));

    let no_reason = request(
        &mut writer,
        &mut reader,
        353,
        "orchestration.runPolicyReject",
        json!({"run": run_id, "actor": "coord"}),
    );
    assert_eq!(no_reason["ok"], json!(false));

    let rejected = expect_ok(request(
        &mut writer,
        &mut reader,
        354,
        "orchestration.runPolicyReject",
        json!({"run": run_id, "actor": "coord", "reason": "wrong split"}),
    ));
    assert_eq!(rejected["status"], json!("rejected"));
    // A rejected plan stops holding scheduling; the run is simply unplanned.
    assert_eq!(rejected["blocksDispatch"], json!(false));
}

#[test]
fn a_task_stage_must_be_declared_by_the_run_policy() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(&mut writer, &mut reader, 360, "Codex Sol", None);
    let run_id = start_run(&mut writer, &mut reader, 361);
    expect_ok(request(
        &mut writer,
        &mut reader,
        362,
        "orchestration.runPolicyPropose",
        json!({"run": run_id, "policy": policy("Codex Sol", json!([]))}),
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
fn the_host_advertises_the_run_policy_capability() {
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
    assert!(
        capabilities.contains(&json!("orchestrationRunPolicyV1")),
        "capability missing: {capabilities:?}"
    );
}
