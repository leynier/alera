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

    // Which agents report status is a hub setting, but the satellite is what
    // wires hooks into a terminal, and it starts with every agent off.
    let configured = request(
        "runtimeSettings.update",
        json!({"agentStatusHooks": {"claude": true, "codex": true}}),
    );
    assert_eq!(configured["ok"], true, "{configured}");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(20);
    loop {
        let settings = tokio::runtime::Runtime::new().unwrap().block_on(async {
            RuntimeStore::open(&fixture.satellite)
                .await
                .unwrap()
                .agent_status_hook_settings()
                .await
                .unwrap()
        });
        if settings.claude && settings.codex && !settings.cursor {
            break;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "the satellite never received the hub's agent status settings: {settings:?}"
        );
        std::thread::sleep(std::time::Duration::from_millis(200));
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

/// `mobile.pullRequest.summaries` spans every project. A project with a folder
/// on the hub keeps the local batch, remote workspaces included; a project
/// that lives only on a host is asked there through the per-workspace
/// snapshot, so the hub never opens its `repoPath` on this machine.
#[cfg(unix)]
#[test]
fn hub_summarizes_pull_requests_of_a_remote_only_project_through_its_host() {
    let fixture = hub_and_satellite_with_kind("gitRepository");
    // A second checkout on the "host" with history: an empty repository has
    // no branch for the registration to inspect.
    let remote_only = fixture.remote.parent().unwrap().join("remote-only-project");
    std::fs::create_dir_all(&remote_only).unwrap();
    let repository = git2::Repository::init(&remote_only).unwrap();
    std::fs::write(remote_only.join("readme.md"), "# Remote only\n").unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(std::path::Path::new("readme.md")).unwrap();
    index.write().unwrap();
    let tree = repository.find_tree(index.write_tree().unwrap()).unwrap();
    let author = git2::Signature::now("Alera Test", "alera@example.com").unwrap();
    repository
        .commit(
            Some("HEAD"),
            &author,
            &author,
            "docs: add readme",
            &tree,
            &[],
        )
        .unwrap();

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

    let registered = request(
        "project.registerRemote",
        json!({"hostId": "ssh", "path": remote_only.to_str().unwrap(), "name": "Server Only"}),
    );
    assert_eq!(registered["ok"], true, "{registered}");
    assert_eq!(
        registered["payload"]["project"]["primaryHostId"], "ssh",
        "{registered}"
    );
    let remote_workspace = &registered["payload"]["initialWorkspace"];
    assert_eq!(remote_workspace["hostId"], "ssh", "{registered}");
    let remote_workspace_id = remote_workspace["id"].as_str().unwrap().to_string();

    let summaries = request("mobile.pullRequest.summaries", json!({}));
    assert_eq!(summaries["ok"], true, "{summaries}");
    let ids = |key: &str| {
        summaries["payload"][key]
            .as_array()
            .unwrap_or_else(|| panic!("{summaries}"))
            .iter()
            .map(|id| id.as_str().unwrap().to_string())
            .collect::<Vec<_>>()
    };
    let eligible = ids("eligibleWorkspaceIds");
    assert!(eligible.contains(&"task".to_string()), "{summaries}");
    assert!(eligible.contains(&remote_workspace_id), "{summaries}");
    // Neither checkout has a GitHub remote: the local project's batch is a
    // quiet empty group for every workspace, and the remote-only project's
    // snapshot answers `undetectable` from the satellite, which evaluates the
    // workspace with no review rather than leaving it unknown.
    let evaluated = ids("evaluatedWorkspaceIds");
    assert!(evaluated.contains(&"task".to_string()), "{summaries}");
    assert!(
        evaluated.contains(&remote_workspace_id),
        "the host answered for the remote-only workspace: {summaries}"
    );
    assert_eq!(summaries["payload"]["summaries"], json!([]), "{summaries}");

    // The host, not the hub, read the checkout: the satellite now holds the
    // mirrored copy of the remote-only workspace.
    let mirrored = tokio::runtime::Runtime::new().unwrap().block_on(async {
        RuntimeStore::open(&fixture.satellite)
            .await
            .unwrap()
            .find_workspace(&remote_workspace_id)
            .await
            .unwrap()
    });
    assert!(
        mirrored.is_some(),
        "the summaries batch must reach the satellite for a remote-only project"
    );
}
