use super::*;

fn payload(response: &Value) -> &Value {
    &response["payload"]
}

#[test]
fn agent_profiles_round_trip_through_the_host() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let empty = request(
        &mut writer,
        &mut reader,
        200,
        "agentProfile.list",
        json!({}),
    );
    assert_eq!(empty["ok"], json!(true), "list rejected: {empty}");
    assert_eq!(payload(&empty)["kind"], json!("agentProfiles"));
    assert_eq!(payload(&empty)["items"], json!([]));

    let created = request(
        &mut writer,
        &mut reader,
        201,
        "agentProfile.upsert",
        json!({
            "name": "Codex Sol",
            "agentType": "codex",
            "command": "codex --model gpt-5.6-sol",
            "description": "Backend implementation",
            "quotaGroup": "codex-personal"
        }),
    );
    assert_eq!(created["ok"], json!(true), "upsert rejected: {created}");
    let profile_id = payload(&created)["id"].as_str().unwrap().to_string();
    assert!(
        profile_id.starts_with("prof_"),
        "unexpected id: {profile_id}"
    );
    assert_eq!(payload(&created)["quotaGroup"], json!("codex-personal"));

    let listed = request(
        &mut writer,
        &mut reader,
        202,
        "agentProfile.list",
        json!({}),
    );
    let items = payload(&listed)["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["name"], json!("Codex Sol"));

    let removed = request(
        &mut writer,
        &mut reader,
        203,
        "agentProfile.remove",
        json!({ "id": profile_id }),
    );
    assert_eq!(removed["ok"], json!(true));
    assert_eq!(payload(&removed)["removed"], json!(true));

    let after = request(
        &mut writer,
        &mut reader,
        204,
        "agentProfile.list",
        json!({}),
    );
    assert_eq!(payload(&after)["items"], json!([]));
}

#[test]
fn managed_agent_profiles_round_trip_structured_configuration() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let created = request(
        &mut writer,
        &mut reader,
        205,
        "agentProfile.upsert",
        json!({
            "name": "Managed Codex",
            "agentType": "codex",
            "launchMode": "managed",
            "managedConfig": {
                "model": "gpt-5.6-sol",
                "sandbox": "workspace-write",
                "webSearch": true
            }
        }),
    );
    assert_eq!(created["ok"], json!(true), "upsert rejected: {created}");
    assert_eq!(payload(&created)["launchMode"], json!("managed"));
    assert_eq!(
        payload(&created)["managedConfig"],
        json!({
            "model": "gpt-5.6-sol",
            "sandbox": "workspace-write",
            "webSearch": true
        })
    );
    assert!(
        payload(&created)["command"]
            .as_str()
            .unwrap_or_default()
            .contains("--model"),
        "managed preview missing: {created}"
    );

    let listed = request(
        &mut writer,
        &mut reader,
        206,
        "agentProfile.list",
        json!({}),
    );
    assert_eq!(payload(&listed)["items"][0]["launchMode"], json!("managed"));
    assert_eq!(
        payload(&listed)["items"][0]["managedConfig"]["model"],
        json!("gpt-5.6-sol")
    );
}

#[test]
fn agent_profile_upsert_rejects_an_unknown_adapter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    // grok is a supported agent-status hook agent but has no spawn adapter, so
    // a profile pointing at it could never be made ready.
    let rejected = request(
        &mut writer,
        &mut reader,
        210,
        "agentProfile.upsert",
        json!({"name": "Grok", "agentType": "grok", "command": "grok"}),
    );
    assert_eq!(rejected["ok"], json!(false));
    assert!(
        rejected["error"]
            .as_str()
            .unwrap_or_default()
            .contains("unsupported agent type"),
        "unexpected error: {rejected}"
    );
}

#[test]
fn agent_profile_upsert_rejects_a_duplicate_name() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let first = request(
        &mut writer,
        &mut reader,
        220,
        "agentProfile.upsert",
        json!({"name": "Codex Sol", "agentType": "codex", "command": "codex"}),
    );
    assert_eq!(first["ok"], json!(true));

    let duplicate = request(
        &mut writer,
        &mut reader,
        221,
        "agentProfile.upsert",
        json!({"name": "codex sol", "agentType": "codex", "command": "codex"}),
    );
    assert_eq!(duplicate["ok"], json!(false));
    assert!(
        duplicate["error"]
            .as_str()
            .unwrap_or_default()
            .contains("already exists"),
        "unexpected error: {duplicate}"
    );
}

#[test]
fn default_agent_profile_is_stored_and_cleared_with_the_profile() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let created = request(
        &mut writer,
        &mut reader,
        222,
        "agentProfile.upsert",
        json!({"name": "Codex Sol", "agentType": "codex", "command": "codex"}),
    );
    assert_eq!(created["ok"], json!(true));
    let profile_id = payload(&created)["id"].as_str().unwrap().to_string();

    let updated = request(
        &mut writer,
        &mut reader,
        223,
        "runtimeSettings.update",
        json!({"defaultAgentProfileId": profile_id}),
    );
    assert_eq!(updated["ok"], json!(true), "update rejected: {updated}");
    assert_eq!(
        payload(&updated)["defaultAgentProfileId"],
        json!(profile_id)
    );

    let removed = request(
        &mut writer,
        &mut reader,
        224,
        "agentProfile.remove",
        json!({"id": profile_id}),
    );
    assert_eq!(removed["ok"], json!(true));

    let settings = request(
        &mut writer,
        &mut reader,
        225,
        "runtimeSettings.get",
        json!({}),
    );
    assert_eq!(payload(&settings)["defaultAgentProfileId"], Value::Null);
}

#[test]
fn command_agent_profile_upsert_requires_a_name_and_command() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let no_command = request(
        &mut writer,
        &mut reader,
        230,
        "agentProfile.upsert",
        json!({"name": "Codex Sol", "agentType": "codex"}),
    );
    assert_eq!(no_command["ok"], json!(false));

    let no_name = request(
        &mut writer,
        &mut reader,
        231,
        "agentProfile.upsert",
        json!({"agentType": "codex", "command": "codex"}),
    );
    assert_eq!(no_name["ok"], json!(false));
}

#[test]
fn the_host_advertises_the_agent_profiles_capability() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let status = request(&mut writer, &mut reader, 240, "status.get", json!({}));
    let capabilities = payload(&status)["runtimeCapabilities"].as_array().unwrap();
    assert!(
        capabilities.contains(&json!("orchestrationAgentProfilesV1")),
        "capability missing: {capabilities:?}"
    );
    assert!(
        capabilities.contains(&json!("orchestrationManagedAgentProfilesV1")),
        "managed capability missing: {capabilities:?}"
    );
}
