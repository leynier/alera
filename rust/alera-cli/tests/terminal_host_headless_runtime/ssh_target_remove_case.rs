use super::host_link_link_status::wait_for_ssh_link;
use super::host_link_mirror_case::hub_and_satellite_with_kind;
use super::*;

fn satellite_of_hub(satellite: &std::path::Path) -> Option<String> {
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        RuntimeStore::open_read_only(satellite)
            .await
            .unwrap()
            .get_metadata("satelliteOfHub")
            .await
            .unwrap()
    })
}

/// A host that still holds work is refused with what lives there; once it is
/// empty the hub forgets it, drops its link and unlinks the satellite.
#[test]
fn removing_a_host_refuses_while_in_use_then_unlinks_its_satellite() {
    let fixture = hub_and_satellite_with_kind("folder");
    wait_for_ssh_link(fixture.hub_port, "the startup link", |link| {
        link["state"] == "attached"
    });
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");
    send(
        &mut writer,
        json!({"id": 1, "type": "hostLink.mirrorWorkspace", "payload": {"workspaceId": "task"}}),
    );
    let mirrored = read_response(&mut reader, 1);
    assert_eq!(mirrored["ok"], true, "{mirrored}");
    assert_eq!(
        satellite_of_hub(&fixture.satellite).as_deref(),
        Some("1"),
        "a mirror makes the host a satellite"
    );

    send(
        &mut writer,
        json!({"id": 2, "type": "sshTarget.remove", "payload": {"id": "ssh"}}),
    );
    let refused = read_response(&mut reader, 2);
    assert_eq!(refused["ok"], false, "{refused}");
    assert_eq!(refused["errorCode"], "sshTargetInUse", "{refused}");
    let details = &refused["errorDetails"];
    assert_eq!(details["hostId"], "ssh", "{refused}");
    assert_eq!(details["alias"], "Lab", "{refused}");
    assert_eq!(details["workspaceCount"], 1, "{refused}");
    assert_eq!(details["checkoutCount"], 1, "{refused}");
    assert_eq!(details["projectIds"], json!(["project-1"]), "{refused}");
    assert_eq!(details["remoteOnlyProjectIds"], json!([]), "{refused}");

    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let store = RuntimeStore::open(&fixture.hub).await.unwrap();
        store.remove_workspace("task", true).await.unwrap();
        store
            .remove_project_checkout("project-1", "ssh")
            .await
            .unwrap();
    });

    send(
        &mut writer,
        json!({"id": 3, "type": "sshTarget.remove", "payload": {"id": "ssh"}}),
    );
    let removed = read_response(&mut reader, 3);
    assert_eq!(removed["ok"], true, "{removed}");
    wait_for_ssh_link(fixture.hub_port, "the slot to go", Value::is_null);

    let deadline = Instant::now() + Duration::from_secs(30);
    while satellite_of_hub(&fixture.satellite).is_some() {
        assert!(
            Instant::now() < deadline,
            "the satellite still serves the hub"
        );
        std::thread::sleep(Duration::from_millis(100));
    }

    send(
        &mut writer,
        json!({"id": 4, "type": "sshTarget.list", "payload": {}}),
    );
    let listed = read_response(&mut reader, 4);
    assert_eq!(listed["payload"], json!([]), "{listed}");
}
