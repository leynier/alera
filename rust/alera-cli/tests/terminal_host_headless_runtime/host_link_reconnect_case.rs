use super::host_link_link_status::{recorded_link_pids, wait_for_ssh_link};
use super::host_link_mirror_case::hub_and_satellite;
use super::*;
use std::io::ErrorKind;

/// The next host message before `deadline`. The socket's 10 second read
/// timeout is shorter than a reconnect can take on a loaded machine, so a
/// quiet stretch is retried instead of failing the read.
fn next_message(reader: &mut BufReader<TcpStream>, deadline: Instant, what: &str) -> Value {
    let mut line = String::new();
    loop {
        assert!(Instant::now() < deadline, "{what}");
        match reader.read_line(&mut line) {
            Ok(0) => panic!("host closed the connection unexpectedly"),
            Ok(_) => return serde_json::from_str(line.trim_end()).unwrap(),
            Err(error) if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
            Err(error) => panic!("reading the host failed: {error}"),
        }
    }
}

/// A link that dies under a host the hub still needs fails, schedules a
/// retry, and comes back on a new ssh process.
#[test]
fn a_dropped_link_to_a_desired_host_reconnects_with_backoff() {
    let fixture = hub_and_satellite();
    wait_for_ssh_link(fixture.hub_port, "the startup link", |link| {
        link["state"] == "attached"
    });
    let first = recorded_link_pids(&fixture.link_pids);
    assert_eq!(first.len(), 1, "{first:?}");
    let (_writer, mut reader) = connect(fixture.hub_port, "hub-token");

    let killed = windowless_command("kill")
        .args(["-9", &first[0]])
        .status()
        .unwrap();
    assert!(killed.success());

    let deadline = Instant::now() + Duration::from_secs(30);
    let mut saw_retry = None;
    loop {
        let message = next_message(&mut reader, deadline, "the link never came back");
        if message["event"] != "hostLinkChanged" || message["payload"]["hostId"] != "ssh" {
            continue;
        }
        let payload = &message["payload"];
        if payload["state"] == "failed" && payload["retry"].is_object() {
            saw_retry = Some(payload.clone());
        }
        if payload["state"] == "attached" && saw_retry.is_some() {
            break;
        }
    }
    // The attach records the runtime that answered and says so, scoped to
    // the host.
    loop {
        let message = next_message(
            &mut reader,
            deadline,
            "the reattach never refreshed the target",
        );
        if message["event"] == "sshTargetsChanged" && message["payload"]["hostId"] == "ssh" {
            break;
        }
    }
    let retry = saw_retry.unwrap();
    assert_eq!(retry["retry"]["attempt"], 1, "{retry}");
    assert!(retry["retry"]["nextRetryAt"].is_string(), "{retry}");
    assert!(
        retry["error"].as_str().unwrap().contains("closed"),
        "{retry}"
    );

    let pids = recorded_link_pids(&fixture.link_pids);
    assert_eq!(pids.len(), 2, "{pids:?}");
    assert_ne!(pids[0], pids[1]);
    let link = wait_for_ssh_link(fixture.hub_port, "attached", |link| {
        link["state"] == "attached"
    });
    assert_eq!(
        link["retry"],
        Value::Null,
        "a successful attach resets the backoff"
    );
}
