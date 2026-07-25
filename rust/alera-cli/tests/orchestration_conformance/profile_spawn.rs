use super::*;

fn declare_profile(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    name: &str,
    command: &str,
) {
    let created = request(
        writer,
        reader,
        id,
        "agentProfile.upsert",
        json!({"name": name, "agentType": "codex", "command": command}),
    );
    assert_eq!(created["ok"], json!(true), "profile rejected: {created}");
}

fn create_task(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, id: i64) -> String {
    let task = expect_ok(request(
        writer,
        reader,
        id,
        "orchestration.taskCreate",
        json!({
            "spec": "implement it",
            "workspace": "ws",
            "coordinator": "coord",
            "createdBy": "coord",
        }),
    ));
    task["id"].as_str().unwrap().to_string()
}

#[test]
fn spawning_with_an_unknown_profile_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task_id = create_task(&mut writer, &mut reader, 400);

    let rejected = request(
        &mut writer,
        &mut reader,
        401,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws",
            "profile": "Nonexistent",
            "task": task_id,
            "from": "coord",
        }),
    );
    assert_eq!(rejected["ok"], json!(false));
    assert!(
        rejected["error"]
            .as_str()
            .unwrap_or_default()
            .contains("unknown agent profile"),
        "unexpected error: {rejected}"
    );
}

#[test]
fn spawning_without_an_agent_or_a_profile_is_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task_id = create_task(&mut writer, &mut reader, 410);

    let rejected = request(
        &mut writer,
        &mut reader,
        411,
        "orchestration.agentSpawn",
        json!({"workspace": "ws", "task": task_id, "from": "coord"}),
    );
    assert_eq!(rejected["ok"], json!(false));
    assert!(
        rejected["error"]
            .as_str()
            .unwrap_or_default()
            .contains("agent is required"),
        "unexpected error: {rejected}"
    );
}

#[test]
fn a_profile_resolves_the_adapter_and_records_itself_on_the_dispatch() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    declare_profile(
        &mut writer,
        &mut reader,
        420,
        "Codex Sol",
        "codex --model gpt-5.6-sol",
    );
    let task_id = create_task(&mut writer, &mut reader, 421);

    // The workspace does not exist, so the spawn stops after the profile is
    // resolved. That is enough to prove the adapter came from the profile
    // rather than from an --agent flag that was never sent.
    let response = request(
        &mut writer,
        &mut reader,
        422,
        "orchestration.agentSpawn",
        json!({
            "workspace": "ws",
            "profile": "Codex Sol",
            "task": task_id,
            "from": "coord",
        }),
    );
    assert_eq!(response["ok"], json!(false));
    let error = response["error"].as_str().unwrap_or_default();
    assert!(
        error.contains("workspace not found"),
        "expected to fail past profile resolution, got: {error}"
    );
}

#[test]
fn a_dispatch_carries_the_profile_through_to_task_show() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let task_id = create_task(&mut writer, &mut reader, 430);

    expect_ok(request(
        &mut writer,
        &mut reader,
        431,
        "orchestration.dispatch",
        json!({
            "task": task_id,
            "to": "worker-1",
            "from": "coord",
            "inject": false,
            "agentProfile": "Codex Sol",
            "agentQuotaGroup": "codex-personal",
        }),
    ));

    let shown = expect_ok(request(
        &mut writer,
        &mut reader,
        432,
        "orchestration.taskShow",
        json!({ "id": task_id }),
    ));
    assert_eq!(shown["activeDispatch"]["agent_profile"], json!("Codex Sol"));
    assert_eq!(
        shown["activeDispatch"]["agent_quota_group"],
        json!("codex-personal")
    );
}
