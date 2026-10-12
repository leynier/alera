use super::host_link_link_status::{recorded_link_pids, ssh_link_status, wait_for_ssh_link};
use super::host_link_mirror_case::hub_and_satellite_with_options;
use super::*;

/// A hub that starts with a workspace on a host links it without being asked.
#[test]
fn a_hub_links_hosts_that_hold_its_workspaces_at_startup() {
    let fixture = hub_and_satellite_with_options("folder", true);
    let link = wait_for_ssh_link(fixture.hub_port, "the startup link", |link| {
        link["state"] == "attached"
    });
    assert_eq!(link["desired"], true, "{link}");
    assert_eq!(link["explicit"], false, "{link}");
    assert_eq!(link["paused"], false, "{link}");
    assert_eq!(link["retry"], Value::Null, "{link}");
    assert_eq!(link["idleCloseAt"], Value::Null, "{link}");
    assert_eq!(recorded_link_pids(&fixture.link_pids).len(), 1);
}

/// A host with nothing on it stays unlinked until something needs it.
#[test]
fn a_hub_leaves_hosts_without_workspaces_unlinked() {
    let fixture = hub_and_satellite_with_options("folder", false);
    std::thread::sleep(Duration::from_secs(2));
    let link = ssh_link_status(fixture.hub_port);
    assert!(link.is_null() || link["state"] == "disconnected", "{link}");
    assert!(recorded_link_pids(&fixture.link_pids).is_empty());
}
