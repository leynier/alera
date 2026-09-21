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
