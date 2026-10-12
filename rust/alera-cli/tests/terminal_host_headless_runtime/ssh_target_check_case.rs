use super::host_link_link_status::wait_for_ssh_link;
use super::host_link_mirror_case::hub_and_satellite_with_kind;
use super::*;

fn wait_for_targets_changed(reader: &mut BufReader<TcpStream>, scope: &Value) {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        assert!(
            Instant::now() < deadline,
            "no sshTargetsChanged {scope} arrived"
        );
        let message = read_message(reader);
        if message["event"] == "sshTargetsChanged" && &message["payload"] == scope {
            return;
        }
    }
}

/// `sshTarget.check` probes the host through the real ssh launcher, records
/// what it found, answers with the host status and refreshes watchers.
#[test]
fn checking_a_host_records_its_status_and_reconnects_a_paused_link() {
    let fixture = hub_and_satellite_with_kind("folder");
    wait_for_ssh_link(fixture.hub_port, "the startup link", |link| {
        link["state"] == "attached"
    });
    let (_events_writer, mut events) = connect(fixture.hub_port, "hub-token");
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");

    // The attach records the runtime that answered from a background task.
    let deadline = Instant::now() + Duration::from_secs(30);
    let listed = loop {
        send(
            &mut writer,
            json!({"id": 1, "type": "sshTarget.list", "payload": {}}),
        );
        let listed = read_response(&mut reader, 1);
        assert_eq!(listed["ok"], true, "{listed}");
        if listed["payload"][0]["runtimeArch"].is_string() {
            break listed;
        }
        assert!(Instant::now() < deadline, "the attach was never recorded");
        std::thread::sleep(Duration::from_millis(100));
    };
    let target = &listed["payload"][0];
    assert_eq!(target["hostStatus"]["state"], "connected", "{listed}");
    assert_eq!(target["hostStatus"]["linkState"], "attached", "{listed}");
    assert_eq!(target["hostStatus"]["desired"], true, "{listed}");
    assert_eq!(target["runtimePlatform"], "linux", "{listed}");

    send(
        &mut writer,
        json!({"id": 2, "type": "hostLink.disconnect", "payload": {"hostId": "ssh"}}),
    );
    let paused = read_response(&mut reader, 2);
    assert_eq!(paused["payload"]["paused"], true, "{paused}");

    send(
        &mut writer,
        json!({"id": 3, "type": "sshTarget.check", "payload": {"id": "ssh"}}),
    );
    let checked = read_response(&mut reader, 3);
    assert_eq!(checked["ok"], true, "{checked}");
    let targets = checked["payload"]["targets"].as_array().unwrap();
    assert_eq!(targets.len(), 1, "{checked}");
    assert_eq!(targets[0]["id"], "ssh");
    assert_eq!(targets[0]["lastStatus"], "runtimeReady", "{checked}");
    assert!(targets[0]["lastCheckedAt"].is_string(), "{checked}");
    let status = &targets[0]["hostStatus"];
    assert!(
        status["lastCheckedAt"].is_string() && status["hubVersion"].is_string(),
        "{checked}"
    );
    wait_for_targets_changed(&mut events, &json!({"hostId": "ssh"}));

    let link = wait_for_ssh_link(fixture.hub_port, "the check to reconnect", |link| {
        link["state"] == "attached"
    });
    assert_eq!(link["paused"], false, "a check clears a Disconnect: {link}");

    send(
        &mut writer,
        json!({"id": 4, "type": "sshTarget.check", "payload": {}}),
    );
    let all = read_response(&mut reader, 4);
    assert_eq!(all["ok"], true, "{all}");
    assert_eq!(all["payload"]["targets"].as_array().unwrap().len(), 1);
    wait_for_targets_changed(&mut events, &json!({}));

    send(
        &mut writer,
        json!({"id": 5, "type": "sshTarget.check", "payload": {"id": "missing"}}),
    );
    let missing = read_response(&mut reader, 5);
    assert_eq!(missing["ok"], false, "{missing}");
    assert!(
        missing["error"]
            .as_str()
            .unwrap()
            .contains("ssh target not found: missing"),
        "{missing}"
    );
}
