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
    assert_eq!(payload(&created)["revision"], json!(0));

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

    let impact = request(
        &mut writer,
        &mut reader,
        203,
        "agentProfile.removalImpact",
        json!({ "id": profile_id, "expectedRevision": 0 }),
    );
    assert_eq!(impact["ok"], json!(true));
    assert_eq!(payload(&impact)["revision"], json!(0));
    assert_eq!(payload(&impact)["referenceCount"], json!(0));
    assert_eq!(payload(&impact)["automationIds"], json!([]));
    assert_eq!(payload(&impact)["executionPolicyRunIds"], json!([]));
    assert_eq!(payload(&impact)["tabs"], json!([]));
    assert!(payload(&impact).get("command").is_none());
    assert!(payload(&impact).get("customPrompt").is_none());

    let unconfirmed = request(
        &mut writer,
        &mut reader,
        204,
        "agentProfile.remove",
        json!({ "id": profile_id, "expectedRevision": 0 }),
    );
    assert_eq!(unconfirmed["ok"], json!(false));

    let removed = request(
        &mut writer,
        &mut reader,
        205,
        "agentProfile.remove",
        json!({
            "id": profile_id,
            "expectedRevision": 0,
            "confirmed": true
        }),
    );
    assert_eq!(removed["ok"], json!(true));
    assert_eq!(payload(&removed)["removed"], json!(true));

    let after = request(
        &mut writer,
        &mut reader,
        206,
        "agentProfile.list",
        json!({}),
    );
    assert_eq!(payload(&after)["items"], json!([]));
}

#[test]
fn agent_profile_order_can_be_reordered_through_the_host() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let first = request(
        &mut writer,
        &mut reader,
        250,
        "agentProfile.upsert",
        json!({"name": "Alpha", "agentType": "codex", "command": "codex"}),
    );
    let first_id = payload(&first)["id"].as_str().unwrap().to_string();
    let second = request(
        &mut writer,
        &mut reader,
        251,
        "agentProfile.upsert",
        json!({"name": "Beta", "agentType": "codex", "command": "codex"}),
    );
    let second_id = payload(&second)["id"].as_str().unwrap().to_string();

    let reordered = request(
        &mut writer,
        &mut reader,
        252,
        "agentProfile.reorder",
        json!({
            "ids": [second_id.clone(), first_id.clone()],
            "expectedRevisions": {(first_id): 0, (second_id): 0}
        }),
    );
    assert_eq!(
        reordered["ok"],
        json!(true),
        "reorder rejected: {reordered}"
    );
    assert_eq!(payload(&reordered)["items"][0]["name"], json!("Beta"));
    assert_eq!(payload(&reordered)["items"][1]["name"], json!("Alpha"));
    assert_eq!(payload(&reordered)["items"][0]["revision"], json!(1));
    assert_eq!(payload(&reordered)["items"][1]["revision"], json!(1));
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
fn managed_grok_agent_profiles_round_trip_structured_configuration() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let created = request(
        &mut writer,
        &mut reader,
        210,
        "agentProfile.upsert",
        json!({
            "name": "Managed Grok",
            "agentType": "grok",
            "launchMode": "managed",
            "managedConfig": {
                "model": "grok-4.6",
                "effort": "high",
                "permissionMode": "acceptEdits",
                "sandbox": "workspace"
            }
        }),
    );
    assert_eq!(created["ok"], json!(true), "upsert rejected: {created}");
    assert_eq!(payload(&created)["launchMode"], json!("managed"));
    assert_eq!(payload(&created)["agentType"], json!("grok"));
    assert_eq!(
        payload(&created)["managedConfig"],
        json!({
            "model": "grok-4.6",
            "effort": "high",
            "permissionMode": "acceptEdits",
            "sandbox": "workspace"
        })
    );
    assert!(
        payload(&created)["command"]
            .as_str()
            .unwrap_or_default()
            .contains("--model"),
        "managed preview missing: {created}"
    );
}

#[test]
fn agent_profile_upsert_rejects_an_unknown_adapter() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let rejected = request(
        &mut writer,
        &mut reader,
        211,
        "agentProfile.upsert",
        json!({"name": "Unknown", "agentType": "not-an-adapter", "command": "unknown"}),
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
        json!({"id": profile_id, "expectedRevision": 0, "confirmed": true}),
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
        capabilities.contains(&json!("orchestrationAgentProfileOrderingV1")),
        "ordering capability missing: {capabilities:?}"
    );
    assert!(
        capabilities.contains(&json!("orchestrationManagedAgentProfilesV1")),
        "managed capability missing: {capabilities:?}"
    );
    assert!(
        capabilities.contains(&json!("orchestrationAgentProfileRevisionsV1")),
        "revision capability missing: {capabilities:?}"
    );
    assert!(
        capabilities.contains(&json!("orchestrationAgentProfileRemovalV1")),
        "removal capability missing: {capabilities:?}"
    );
}

#[test]
fn stale_agent_profile_mutations_return_typed_conflicts() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let created = request(
        &mut writer,
        &mut reader,
        260,
        "agentProfile.upsert",
        json!({"name": "Original", "agentType": "codex", "command": "codex"}),
    );
    let id = payload(&created)["id"].as_str().unwrap().to_string();
    let updated = request(
        &mut writer,
        &mut reader,
        261,
        "agentProfile.upsert",
        json!({
            "id": id.clone(),
            "expectedRevision": 0,
            "name": "Current",
            "agentType": "codex",
            "command": "codex"
        }),
    );
    assert_eq!(payload(&updated)["revision"], json!(1));

    for (request_id, verb, mutation) in [
        (
            262,
            "agentProfile.upsert",
            json!({
                "id": id.clone(),
                "expectedRevision": 0,
                "name": "Stale",
                "agentType": "codex",
                "command": "codex"
            }),
        ),
        (
            263,
            "agentProfile.remove",
            json!({"id": id.clone(), "expectedRevision": 0, "confirmed": true}),
        ),
        (
            264,
            "agentProfile.removalImpact",
            json!({"id": id.clone(), "expectedRevision": 0}),
        ),
    ] {
        let conflict = request(&mut writer, &mut reader, request_id, verb, mutation);
        assert_eq!(conflict["ok"], json!(false));
        assert_eq!(
            conflict["errorCode"],
            json!("agent_profile_revision_conflict")
        );
        assert_eq!(conflict["errorDetails"]["profileId"], json!(id));
        assert_eq!(conflict["errorDetails"]["expectedRevision"], json!(0));
        assert_eq!(conflict["errorDetails"]["currentRevision"], json!(1));
    }
}
