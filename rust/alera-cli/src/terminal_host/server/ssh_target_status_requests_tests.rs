use super::*;
use crate::terminal_host::host_link_slot::RetryStatus;

fn target(bootstrap_status: &str, last_status: Option<&str>) -> SshTarget {
    serde_json::from_value(json!({
        "id": "ssh-1", "alias": "Studio Mac", "host": "10.0.0.7", "port": 2222,
        "username": "leynier", "authKind": "agent", "platform": "linux",
        "runtimePlatform": "macos", "installDir": "~/.alera-sidecar",
        "runtimeVersion": "1.4.0", "bootstrapStatus": bootstrap_status,
        "lastStatus": last_status, "lastError": "artifact download failed",
        "lastCheckedAt": "2026-07-20T00:00:00Z",
        "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
    }))
    .unwrap()
}

fn link(state: HostLinkState, failure_kind: Option<AttachFailureKind>) -> HostLinkStatus {
    HostLinkStatus {
        state,
        generation: 0,
        desired: true,
        paused: false,
        explicit: false,
        retry: None,
        idle_close_at: None,
        failure_kind,
        satellite_version: None,
        hub_version: "2.0.0".into(),
        runtime_update_available: false,
    }
}

fn attached() -> HostLinkState {
    HostLinkState::Attached {
        attachment: HostLinkAttachment {
            runtime_dir: "/sat/data".into(),
            platform: "macos".into(),
            arch: "aarch64".into(),
            host_version: Some("1.5.0".into()),
            runtime_capabilities: vec![],
        },
    }
}

fn failed() -> HostLinkState {
    HostLinkState::Failed {
        error: "ssh: connect to host 10.0.0.7 port 2222: Connection timed out".into(),
    }
}

fn job() -> InstallJobView {
    InstallJobView {
        stage: "upload".into(),
        message: "Uploading Remote Runtime".into(),
    }
}

fn status(
    target: &SshTarget,
    link: &HostLinkStatus,
    job: Option<&InstallJobView>,
) -> (HostState, Option<String>, Option<String>) {
    let status = host_status_payload(target, link, job, "2.0.0");
    (status.state, status.detail, status.stage)
}

#[test]
fn every_host_state_comes_from_one_precedence() {
    let disconnected = link(HostLinkState::Disconnected, None);
    let installed = target("installed", Some("runtimeReady"));
    let cases: Vec<(
        &str,
        SshTarget,
        HostLinkStatus,
        Option<InstallJobView>,
        HostState,
    )> = vec![
        (
            "a live install wins over everything",
            installed.clone(),
            link(attached(), None),
            Some(job()),
            HostState::Installing,
        ),
        (
            "never installed",
            target("notInstalled", None),
            disconnected.clone(),
            None,
            HostState::NeedsSetup,
        ),
        (
            "a failed install",
            target("failed", None),
            disconnected.clone(),
            None,
            HostState::NeedsSetup,
        ),
        (
            "an install the hub lost when it restarted",
            target("installing", None),
            disconnected.clone(),
            None,
            HostState::NeedsSetup,
        ),
        (
            "attached",
            installed.clone(),
            link(attached(), None),
            None,
            HostState::Connected,
        ),
        (
            "connecting",
            target("installed", Some("unreachable")),
            link(HostLinkState::Connecting, None),
            None,
            HostState::Connecting,
        ),
        (
            "a link that cannot reach the machine",
            installed.clone(),
            link(failed(), Some(AttachFailureKind::Unreachable)),
            None,
            HostState::Offline,
        ),
        (
            "the last probe found no machine",
            target("installed", Some("unreachable")),
            disconnected.clone(),
            None,
            HostState::Offline,
        ),
        (
            "a rejected key",
            installed.clone(),
            link(failed(), Some(AttachFailureKind::Authentication)),
            None,
            HostState::Error,
        ),
        (
            "installed and idle",
            installed.clone(),
            disconnected.clone(),
            None,
            HostState::Disconnected,
        ),
    ];
    for (name, target, link, job, expected) in cases {
        assert_eq!(status(&target, &link, job.as_ref()).0, expected, "{name}");
    }
}

#[test]
fn details_and_stages_follow_the_state() {
    let installed = target("installed", None);
    assert_eq!(
        status(
            &installed,
            &link(HostLinkState::Disconnected, None),
            Some(&job())
        ),
        (
            HostState::Installing,
            Some("Uploading Remote Runtime".into()),
            Some("upload".into())
        )
    );
    assert_eq!(
        status(
            &target("failed", None),
            &link(HostLinkState::Disconnected, None),
            None
        ),
        (
            HostState::NeedsSetup,
            Some("artifact download failed".into()),
            None
        )
    );
    let (state, detail, stage) = status(
        &installed,
        &link(failed(), Some(AttachFailureKind::Satellite)),
        None,
    );
    assert_eq!(state, HostState::Error);
    assert!(detail.unwrap().contains("timed out"));
    assert_eq!(stage, None);
}

#[test]
fn the_payload_carries_link_versions_retry_and_desire() {
    let mut retrying = link(failed(), Some(AttachFailureKind::Unreachable));
    let next_retry_at = "2026-07-20T00:01:00Z".parse().unwrap();
    retrying.retry = Some(RetryStatus {
        attempt: 3,
        next_retry_at,
    });
    let value = json!(host_status_payload(
        &target("installed", None),
        &retrying,
        None,
        "2.0.0"
    ));
    assert_eq!(value["state"], "offline");
    assert_eq!(value["linkState"], "failed");
    assert_eq!(
        value["satelliteVersion"], "1.4.0",
        "falls back to the record"
    );
    assert_eq!(value["hubVersion"], "2.0.0");
    assert_eq!(value["runtimeUpdateAvailable"], false);
    assert_eq!(value["lastCheckedAt"], "2026-07-20T00:00:00Z");
    assert_eq!(value["retry"]["attempt"], 3);
    assert!(value["retry"]["nextRetryAt"].is_string());
    assert_eq!(value["desired"], true);
    for key in ["detail", "stage"] {
        assert!(value.get(key).is_some(), "{key} is always present");
    }

    let mut live = link(attached(), None);
    live.satellite_version = Some("1.5.0".into());
    let value = json!(host_status_payload(
        &target("installed", None),
        &live,
        None,
        "2.0.0"
    ));
    assert_eq!(value["state"], "connected");
    assert_eq!(value["linkState"], "attached");
    assert_eq!(value["satelliteVersion"], "1.5.0");
    assert_eq!(value["retry"], Value::Null);
}

#[test]
fn a_target_value_keeps_the_record_and_adds_its_status() {
    let target = target("installed", None);
    let status = host_status_payload(
        &target,
        &link(HostLinkState::Disconnected, None),
        None,
        "2.0.0",
    );
    let value = target_with_status(&target, &status).unwrap();
    assert_eq!(value["id"], "ssh-1");
    assert_eq!(value["host"], "10.0.0.7");
    assert_eq!(value["hostStatus"]["state"], "disconnected");
}

#[test]
fn a_phone_learns_a_host_name_system_and_state_and_nothing_about_reaching_it() {
    let target = target("installed", Some("runtimeReady"));
    let status = host_status_payload(&target, &link(attached(), None), None, "2.0.0");
    let entry = mobile_host_entry(&target, &status);
    assert_eq!(
        entry,
        json!({
            "id": "ssh-1",
            "alias": "Studio Mac",
            "platform": "macos",
            "status": "connected",
            "runtimeVersion": "1.5.0",
            "updateAvailable": true,
        }),
        "the probed platform wins over the declared one, and the version is the one the attached runtime reports"
    );
    for key in [
        "host",
        "username",
        "port",
        "installDir",
        "lastError",
        "identityFile",
    ] {
        assert!(entry.get(key).is_none(), "{key} must stay on the hub");
    }
}

#[test]
fn only_a_connected_older_runtime_offers_an_update() {
    let installed = target("installed", None);
    let with_version = |version: &str| {
        let mut live = link(attached(), None);
        live.satellite_version = Some(version.into());
        live
    };
    let offered = |status: &HostLinkStatus, hub: &str| {
        host_status_payload(&installed, status, None, hub).runtime_update_available
    };
    assert!(offered(&with_version("1.5.0"), "2.0.0"));
    assert!(!offered(&with_version("2.0.0"), "2.0.0"));
    assert!(
        !offered(&with_version("2.1.0"), "2.0.0"),
        "a newer runtime is never offered a downgrade"
    );
    assert!(
        !offered(&with_version("1.5.0"), "0.1.0-dev"),
        "a development hub offers nothing to a release"
    );
    assert!(!offered(&with_version("1.5.0"), "unknown"));
    assert!(
        offered(&link(attached(), None), "2.0.0"),
        "the attachment's version counts when the slot has none"
    );
    // Not connected: nothing to restart onto the new version yet.
    assert!(!offered(&link(HostLinkState::Disconnected, None), "2.0.0"));
    let installing = InstallJobView {
        stage: "upload".into(),
        message: "Uploading".into(),
    };
    assert!(
        !host_status_payload(
            &installed,
            &with_version("1.5.0"),
            Some(&installing),
            "2.0.0"
        )
        .runtime_update_available
    );
}
