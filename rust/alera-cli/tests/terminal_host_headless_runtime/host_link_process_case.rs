use super::host_link_mirror_case::hub_and_satellite_with_kind;
use super::*;

/// Tools for a remote workspace run on the satellite that owns the checkout:
/// `host.process.run` for the desktop's forge CLIs, and the pull request
/// snapshot Watch and Fix polls, which reads the hub's linked review because
/// that record is hub-owned.
#[cfg(unix)]
#[test]
fn hub_runs_processes_and_pull_request_reads_on_the_satellite() {
    let fixture = hub_and_satellite_with_kind("gitRepository");
    let remote = &fixture.remote;
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");
    let mut next_id = 0;
    let mut request = |request_type: &str, payload: Value| {
        next_id += 1;
        send(
            &mut writer,
            json!({"id": next_id, "type": request_type, "payload": payload}),
        );
        read_response(&mut reader, next_id)
    };

    let ran = request(
        "host.process.run",
        json!({
            "workspaceId": "task",
            "executable": "sh",
            "arguments": ["-c", "pwd; cat; printf '%s' \"$ALERA_PROBE\"; echo oops >&2; exit 3"],
            "stdin": "from the hub\n",
            "environment": {"ALERA_PROBE": "probe-value"},
        }),
    );
    assert_eq!(ran["ok"], true, "{ran}");
    assert_eq!(ran["payload"]["exitCode"], 3, "{ran}");
    let stdout = ran["payload"]["stdout"].as_str().unwrap();
    let canonical = std::fs::canonicalize(remote).unwrap();
    assert!(
        stdout.starts_with(canonical.to_str().unwrap())
            || stdout.starts_with(remote.to_str().unwrap()),
        "the tool must run in the satellite checkout: {stdout}"
    );
    assert!(stdout.contains("from the hub"), "{stdout}");
    assert!(stdout.ends_with("probe-value"), "{stdout}");
    assert_eq!(ran["payload"]["stderr"], "oops\n", "{ran}");

    let outside = request(
        "host.process.run",
        json!({
            "workspaceId": "task",
            "executable": "sh",
            "arguments": ["-c", "true"],
            "cwd": remote.parent().unwrap().to_str().unwrap(),
        }),
    );
    assert_eq!(outside["ok"], false, "{outside}");
    assert!(
        outside["error"]
            .as_str()
            .unwrap()
            .contains("outside workspace"),
        "{outside}"
    );

    // The satellite says what it can do when it attaches; the hub reads these
    // to decide between relayed hooks and the presence list.
    let status = request("hostLink.status", json!({}));
    assert_eq!(status["ok"], true, "{status}");
    let capabilities = status["payload"]["links"][0]["attachment"]["runtimeCapabilities"]
        .as_array()
        .unwrap_or_else(|| panic!("{status}"));
    for capability in ["remoteProcessV1", "remoteAgentHookRelayV1"] {
        assert!(
            capabilities.iter().any(|value| value == capability),
            "{capability} missing from {status}"
        );
    }

    // The hub owns the linked review; the satellite answers with the record
    // the hub sent rather than one of its own.
    let now = chrono::Utc::now();
    let linked = request(
        "linkedReview.upsert",
        json!({
            "workspaceId": "task", "dismissed": false, "provider": "github",
            "number": 41, "url": "https://github.com/o/r/pull/41", "linkedAt": now,
        }),
    );
    assert_eq!(linked["ok"], true, "{linked}");
    let snapshot = request(
        "mobile.pullRequest.snapshot",
        json!({"workspaceId": "task"}),
    );
    assert_eq!(snapshot["ok"], true, "{snapshot}");
    assert_eq!(
        snapshot["payload"]["linkedReview"]["number"], 41,
        "{snapshot}"
    );
    // The checkout has no GitHub remote, which only the satellite can know.
    assert_eq!(
        snapshot["payload"]["authStatus"], "undetectable",
        "{snapshot}"
    );

    let removed = request("linkedReview.remove", json!({"workspaceId": "task"}));
    assert_eq!(removed["ok"], true, "{removed}");
    let cleared = request(
        "mobile.pullRequest.snapshot",
        json!({"workspaceId": "task"}),
    );
    assert_eq!(cleared["ok"], true, "{cleared}");
    assert!(
        cleared["payload"]["linkedReview"].is_null(),
        "a link the hub dropped must not survive on the satellite: {cleared}"
    );
}
