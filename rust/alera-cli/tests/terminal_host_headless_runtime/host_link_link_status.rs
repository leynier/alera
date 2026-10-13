use super::*;

/// The hub's view of the `ssh` host from `hostLink.status`, or null when the
/// registry has not seen it.
pub(super) fn ssh_link_status(port: u16) -> Value {
    let (mut writer, mut reader) = connect(port, "hub-token");
    send(
        &mut writer,
        json!({"id": 1, "type": "hostLink.status", "payload": {}}),
    );
    let status = read_response(&mut reader, 1);
    assert_eq!(status["ok"], true, "{status}");
    status["payload"]["links"]
        .as_array()
        .unwrap()
        .iter()
        .find(|link| link["hostId"] == "ssh")
        .cloned()
        .unwrap_or(Value::Null)
}

pub(super) fn wait_for_ssh_link(
    port: u16,
    what: &str,
    predicate: impl Fn(&Value) -> bool,
) -> Value {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        let link = ssh_link_status(port);
        if predicate(&link) {
            return link;
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for {what}: {link}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

pub(super) fn recorded_link_pids(path: &std::path::Path) -> Vec<String> {
    std::fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
}
