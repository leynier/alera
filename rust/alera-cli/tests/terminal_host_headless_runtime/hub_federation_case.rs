use super::host_link_mirror_case::hub_and_satellite_with_kind;
use super::*;

fn satellite_cli(satellite: &std::path::Path, arguments: &[&str]) -> std::process::Output {
    let mut command = windowless_command(env!("CARGO_BIN_EXE_alera"));
    command.args([
        arguments[0],
        "--runtime-dir",
        satellite.to_str().unwrap(),
        "--json",
    ]);
    command.args(&arguments[1..]);
    for (name, _) in std::env::vars() {
        if name.starts_with("ALERA_") {
            command.env_remove(name);
        }
    }
    command.output().unwrap()
}

/// The CLI inside a remote terminal talks to the satellite, whose store only
/// holds copies of the workspaces it serves. Once the satellite has mirrored a
/// hub workspace its listings come from the hub over the link, and what a
/// remote host may ask stays read-only.
#[test]
fn the_satellite_cli_lists_hub_state_over_the_reverse_channel() {
    let fixture = hub_and_satellite_with_kind("gitRepository");
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");

    // A second hub workspace the satellite never hears about.
    send(
        &mut writer,
        json!({"id": 1, "type": "workspace.upsert", "payload": workspace_payload("hub-only", &fixture.remote.parent().unwrap().join("local-project"))}),
    );
    let upserted = read_response(&mut reader, 1);
    assert_eq!(upserted["ok"], true, "{upserted}");
    send(
        &mut writer,
        json!({"id": 2, "type": "hostLink.mirrorWorkspace", "payload": {"workspaceId": "task"}}),
    );
    let mirrored = read_response(&mut reader, 2);
    assert_eq!(mirrored["ok"], true, "{mirrored}");

    let listed = satellite_cli(&fixture.satellite, &["workspace", "list", "--all"]);
    let stdout = String::from_utf8_lossy(&listed.stdout);
    assert!(
        listed.status.success(),
        "{stdout}{}",
        String::from_utf8_lossy(&listed.stderr)
    );
    let value: Value = serde_json::from_str(stdout.trim()).unwrap_or_else(|_| panic!("{stdout}"));
    assert_eq!(value["source"], "hub", "{value}");
    assert_eq!(value["originHostId"], "ssh", "{value}");
    let mut ids: Vec<&str> = value["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item["id"].as_str().unwrap())
        .collect();
    ids.sort_unstable();
    assert_eq!(
        ids,
        ["hub-only", "task"],
        "the hub's list, not the mirrored copies"
    );
    let task = value["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["id"] == "task")
        .unwrap();
    assert_eq!(
        task["hostId"], "ssh",
        "hub ids and hosts, not the satellite's `local`"
    );

    let here = satellite_cli(
        &fixture.satellite,
        &["workspace", "list", "--all", "--host-id", "ssh"],
    );
    let here: Value = serde_json::from_slice(&here.stdout).unwrap();
    assert_eq!(here["items"].as_array().unwrap().len(), 1, "{here}");

    let projects = satellite_cli(&fixture.satellite, &["project", "list"]);
    let projects: Value = serde_json::from_slice(&projects.stdout).unwrap();
    assert_eq!(projects["source"], "hub", "{projects}");
    assert_eq!(
        projects["items"][0]["checkouts"].as_array().unwrap().len(),
        2,
        "{projects}"
    );
}

fn stdout_and_stderr(output: &std::process::Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}

/// `workspace.find` through a raw client connection; `Null` when unknown.
fn find_workspace(
    writer: &mut TcpStream,
    reader: &mut BufReader<TcpStream>,
    id: i64,
    workspace_id: &str,
) -> Value {
    send(
        writer,
        json!({"id": id, "type": "workspace.find", "payload": {"id": workspace_id}}),
    );
    let found = read_response(reader, id);
    assert_eq!(found["ok"], true, "{found}");
    found["payload"].clone()
}

/// Once a satellite has mirrored a hub workspace, hub-owned mutations typed
/// into its CLI go to the hub over the reverse channel and act on the hub's
/// store, with the origin host as the default host. Verbs the hub does not
/// answer are refused, and without a hub the CLI fails instead of touching
/// the satellite's copies.
#[test]
fn the_satellite_cli_manages_hub_state_over_the_reverse_channel() {
    let fixture = hub_and_satellite_with_kind("gitRepository");
    let (mut hub_writer, mut hub_reader) = connect(fixture.hub_port, "hub-token");
    let (mut satellite_writer, mut satellite_reader) =
        connect(fixture.satellite_port, "satellite-token");
    send(
        &mut hub_writer,
        json!({"id": 1, "type": "hostLink.mirrorWorkspace", "payload": {"workspaceId": "task"}}),
    );
    let mirrored = read_response(&mut hub_reader, 1);
    assert_eq!(mirrored["ok"], true, "{mirrored}");

    // (a) A shared workspace created from the remote terminal lands on the hub
    // for the host the terminal runs on, without `--host-id`.
    let added = satellite_cli(
        &fixture.satellite,
        &[
            "workspace",
            "add",
            "--id",
            "made-remotely",
            "--project-id",
            "project-1",
            "--name",
            "Made Remotely",
        ],
    );
    assert!(added.status.success(), "{}", stdout_and_stderr(&added));
    let on_hub = find_workspace(&mut hub_writer, &mut hub_reader, 2, "made-remotely");
    assert_eq!(on_hub["id"], "made-remotely", "{on_hub}");
    assert_eq!(on_hub["hostId"], "ssh", "the origin host is the default");
    assert_eq!(on_hub["projectId"], "project-1");
    assert_eq!(
        on_hub["path"],
        std::fs::canonicalize(&fixture.remote)
            .unwrap()
            .to_str()
            .unwrap(),
        "created on the host's own checkout"
    );
    let listed = satellite_cli(&fixture.satellite, &["workspace", "list", "--all"]);
    let listed: Value = serde_json::from_slice(&listed.stdout).unwrap();
    assert!(
        listed["items"]
            .as_array()
            .unwrap()
            .iter()
            .any(|item| item["id"] == "made-remotely"),
        "{listed}"
    );

    // (b) Removing it from the same terminal removes it from the hub. A
    // remote workspace asks for `--close-sessions` on the desktop CLI too.
    let removed = satellite_cli(
        &fixture.satellite,
        &[
            "workspace",
            "remove",
            "--id",
            "made-remotely",
            "--close-sessions",
        ],
    );
    assert!(removed.status.success(), "{}", stdout_and_stderr(&removed));
    assert_eq!(
        find_workspace(&mut hub_writer, &mut hub_reader, 3, "made-remotely"),
        Value::Null,
        "gone from the hub"
    );

    // (c) A verb the hub does not answer is refused before it leaves the
    // satellite, and the refusal points at the desktop.
    send(
        &mut satellite_writer,
        json!({"id": 1, "type": "hub.forward", "payload": {"type": "sshTarget.list", "payload": {}}}),
    );
    let refused = read_response(&mut satellite_reader, 1);
    assert_eq!(refused["ok"], false, "{refused}");
    assert!(
        refused["error"].as_str().unwrap().contains("desktop"),
        "{refused}"
    );

    // (d) With the link down the CLI fails loudly and creates nothing here.
    send(
        &mut hub_writer,
        json!({"id": 4, "type": "hostLink.disconnect", "payload": {"hostId": "ssh"}}),
    );
    let disconnected = read_response(&mut hub_reader, 4);
    assert_eq!(disconnected["ok"], true, "{disconnected}");
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut next_id = 2;
    loop {
        send(
            &mut satellite_writer,
            json!({"id": next_id, "type": "hub.link.status", "payload": {}}),
        );
        let status = read_response(&mut satellite_reader, next_id);
        next_id += 1;
        if status["payload"]["linked"] == false {
            break;
        }
        assert!(Instant::now() < deadline, "the satellite still sees a hub");
        std::thread::sleep(Duration::from_millis(50));
    }
    let unlinked = satellite_cli(
        &fixture.satellite,
        &[
            "workspace",
            "add",
            "--id",
            "never-made",
            "--project-id",
            "project-1",
            "--name",
            "Never Made",
        ],
    );
    assert!(
        !unlinked.status.success(),
        "{}",
        stdout_and_stderr(&unlinked)
    );
    assert!(
        stdout_and_stderr(&unlinked).contains("No Alera desktop is linked"),
        "{}",
        stdout_and_stderr(&unlinked)
    );
    // A local client of the satellite now reads the hub's records, so the
    // satellite's own copies are inspected in its store.
    let rt = tokio::runtime::Runtime::new().unwrap();
    let copies = rt.block_on(async {
        let store = RuntimeStore::open_read_only(&fixture.satellite)
            .await
            .unwrap();
        (
            store.find_workspace("never-made").await.unwrap(),
            store.find_workspace("made-remotely").await.unwrap(),
        )
    });
    assert!(
        copies.0.is_none(),
        "nothing was created on the satellite's copies"
    );
    assert!(
        copies.1.is_none(),
        "the removed workspace left no copy behind either"
    );
    assert_eq!(
        find_workspace(&mut hub_writer, &mut hub_reader, 5, "never-made"),
        Value::Null
    );
}
