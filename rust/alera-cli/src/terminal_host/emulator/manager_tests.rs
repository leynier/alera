use std::time::Instant;

use super::*;

#[cfg(unix)]
fn install_visual_snapshot_fixture(manager: &mut EmulatorManager, directory: &Path) {
    use std::os::unix::fs::PermissionsExt as _;

    fn write_frame(path: &Path, color: [u8; 4]) {
        let file = std::fs::File::create(path).unwrap();
        let mut encoder = png::Encoder::new(file, 1, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        writer.write_image_data(&color).unwrap();
    }

    write_frame(&directory.join("first.png"), [0, 0, 0, 255]);
    write_frame(&directory.join("second.png"), [255, 255, 255, 255]);
    std::fs::write(directory.join("current-frame"), "first").unwrap();
    let script = directory.join("fake-adb");
    std::fs::write(
        &script,
        format!(
            "#!/bin/sh\nif [ \"$4\" = \"screencap\" ]; then\n  cat \"{0}/$(cat \"{0}/current-frame\").png\"\nelse\n  printf '%s' '<hierarchy><node class=\"android.view.View\" text=\"Unchanged\" bounds=\"[0,0][1,1]\" /></hierarchy>'\nfi\n",
            directory.display(),
        ),
    )
    .unwrap();
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o700)).unwrap();
    manager.android.adb = script;
    manager.sessions.insert(
        "tab".into(),
        EmulatorSession {
            workspace_id: "workspace".into(),
            tab_id: "tab".into(),
            platform: EmulatorPlatform::Android,
            device_id: "android:test".into(),
            device_name: "Test".into(),
            attached: AttachedDevice::Android(Box::new(AndroidAttached {
                device_name: "Test".into(),
                serial: "emulator-5554".into(),
                owned: false,
                process: None,
            })),
            helper: None,
            stream_url: None,
            generation: 1,
            leases: HashSet::new(),
            active_pointer: None,
        },
    );
}

#[cfg(unix)]
fn snapshot_id(value: &Value) -> String {
    value["snapshot"]["snapshotId"]
        .as_str()
        .unwrap()
        .to_string()
}

fn ios_session(leases: impl IntoIterator<Item = u64>) -> EmulatorSession {
    EmulatorSession {
        workspace_id: "workspace".into(),
        tab_id: "tab".into(),
        platform: EmulatorPlatform::Ios,
        device_id: "ios:device".into(),
        device_name: "iPhone".into(),
        attached: AttachedDevice::Ios(IosAttached {
            udid: "device".into(),
            name: "iPhone".into(),
            owned: false,
        }),
        helper: None,
        stream_url: None,
        generation: 1,
        leases: leases.into_iter().collect(),
        active_pointer: None,
    }
}

#[test]
fn session_payload_never_contains_a_control_endpoint() {
    let session = ios_session([]);
    let value = session_value(&session);
    assert!(value.pointer("/stream/controlUrl").is_none());
    assert_eq!(value["state"], "parked");
}

#[tokio::test]
async fn automation_requires_a_current_snapshot_and_invalidates_it_after_use() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.sessions.insert("tab".into(), ios_session([]));

    let missing = manager.validate_snapshot("tab", None).unwrap_err();
    assert_eq!(missing.code, "snapshot_required");

    manager.snapshots.insert(
        "current".into(),
        SnapshotProof {
            tab_id: "tab".into(),
            generation: 1,
            created_at: Instant::now(),
            tree_digest: [0; 32],
            frame_digest: [0; 32],
            screenshot_path: None,
        },
    );
    manager.validate_snapshot("tab", Some("current")).unwrap();
    manager.invalidate_snapshots("tab").unwrap();
    let stale = manager
        .validate_snapshot("tab", Some("current"))
        .unwrap_err();
    assert_eq!(stale.code, "snapshot_stale");
}

#[tokio::test]
async fn snapshot_proofs_expire_with_the_screenshot_contract() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.sessions.insert("tab".into(), ios_session([]));
    manager.snapshots.insert(
        "expired".into(),
        SnapshotProof {
            tab_id: "tab".into(),
            generation: 1,
            created_at: Instant::now() - SNAPSHOT_TTL - Duration::from_secs(1),
            tree_digest: [0; 32],
            frame_digest: [0; 32],
            screenshot_path: None,
        },
    );

    let error = manager
        .validate_snapshot("tab", Some("expired"))
        .unwrap_err();

    assert_eq!(error.code, "snapshot_stale");
    assert!(!manager.snapshots.contains_key("expired"));
}

#[cfg(unix)]
#[tokio::test]
async fn identical_accessibility_tree_does_not_hide_a_visual_frame_change() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    install_visual_snapshot_fixture(&mut manager, dir.path());

    let snapshot = manager.snapshot("tab", true).await.unwrap();
    let snapshot_id = snapshot_id(&snapshot);
    assert!(snapshot["snapshot"]["screenshot"]["path"].is_string());
    std::fs::write(dir.path().join("current-frame"), "second").unwrap();

    let error = manager
        .validate_snapshot_state("tab", Some(&snapshot_id))
        .await
        .unwrap_err();

    assert_eq!(error.code, "snapshot_stale");
    assert!(error.message.contains("visual or accessibility"));
    manager.invalidate_snapshots("tab").unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn snapshot_without_returned_png_still_proves_the_visual_frame() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    install_visual_snapshot_fixture(&mut manager, dir.path());

    let snapshot = manager.snapshot("tab", false).await.unwrap();
    let snapshot_id = snapshot_id(&snapshot);
    assert!(snapshot["snapshot"]["screenshot"].is_null());
    assert!(manager.snapshots[&snapshot_id].screenshot_path.is_none());
    assert_eq!(
        std::fs::read_dir(&manager.snapshot_dir)
            .unwrap()
            .flatten()
            .count(),
        0
    );
    std::fs::write(dir.path().join("current-frame"), "second").unwrap();

    let error = manager
        .validate_snapshot_state("tab", Some(&snapshot_id))
        .await
        .unwrap_err();

    assert_eq!(error.code, "snapshot_stale");
}

#[tokio::test]
async fn ios_rejects_android_activity_selection_before_launching() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.sessions.insert("tab".into(), ios_session([]));

    let error = manager
        .launch("tab", "dev.alera.app", Some(".MainActivity"))
        .await
        .unwrap_err();

    assert_eq!(error.code, "unsupported_capability");
}

#[tokio::test]
async fn one_virtual_device_cannot_be_attached_to_multiple_workspaces() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.sessions.insert("first".into(), ios_session([]));

    let error = manager
        .attach(
            "other-workspace".into(),
            "second".into(),
            EmulatorPlatform::Ios,
            "ios:device".into(),
        )
        .await
        .unwrap_err();

    assert_eq!(error.code, "device_in_use");
}

#[tokio::test]
async fn release_and_disconnect_park_only_after_the_last_client_lease() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    let mut session = ios_session([1, 2]);
    session.stream_url = Some("still-active".into());
    manager.sessions.insert("tab".into(), session);

    manager.release("tab", 1).await.unwrap();
    let session = manager.sessions.get("tab").unwrap();
    assert_eq!(session.leases, HashSet::from([2]));
    assert_eq!(session.stream_url.as_deref(), Some("still-active"));

    manager.release_client(2, false).await;
    let session = manager.sessions.get("tab").unwrap();
    assert!(session.leases.is_empty());
    assert!(session.stream_url.is_none());
}

#[tokio::test]
async fn helper_parking_does_not_invalidate_observation_proofs() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.sessions.insert("tab".into(), ios_session([]));
    manager.snapshots.insert(
        "current".into(),
        SnapshotProof {
            tab_id: "tab".into(),
            generation: 1,
            created_at: Instant::now(),
            tree_digest: [0; 32],
            frame_digest: [0; 32],
            screenshot_path: None,
        },
    );

    manager.park("tab").await.unwrap();

    manager.validate_snapshot("tab", Some("current")).unwrap();
}

#[tokio::test]
async fn disconnect_removes_the_client_lease_from_every_tab() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    for (tab_id, other_client) in [("first", 2), ("second", 3)] {
        let mut session = ios_session([1, other_client]);
        session.tab_id = tab_id.into();
        session.stream_url = Some(format!("{tab_id}-active"));
        manager.sessions.insert(tab_id.into(), session);
    }

    manager.release_client(1, false).await;

    for (tab_id, other_client) in [("first", 2), ("second", 3)] {
        let session = manager.sessions.get(tab_id).unwrap();
        let expected_url = format!("{tab_id}-active");
        assert_eq!(session.leases, HashSet::from([other_client]));
        assert_eq!(session.stream_url.as_deref(), Some(expected_url.as_str()));
    }
}

#[tokio::test]
async fn disconnect_synthetically_ends_an_owned_pointer() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    let mut session = ios_session([1]);
    session.active_pointer = Some(ActivePointer {
        client_id: 1,
        x: 0.4,
        y: 0.6,
    });
    manager.sessions.insert("tab".into(), session);

    manager.release_client(1, false).await;

    assert!(manager.sessions["tab"].active_pointer.is_none());
}

#[tokio::test]
async fn failed_owned_shutdown_keeps_the_session_recoverable() {
    let dir = tempfile::tempdir().unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.insert_owned_android_session_for_shutdown_failure_test(
        "workspace",
        "tab",
        dir.path().join("missing-adb"),
    );
    let session = manager.sessions.get_mut("tab").unwrap();
    session.stream_url = Some("http://127.0.0.1/active".into());
    session.leases.insert(7);

    let warnings = manager.close_tab("tab").await;

    assert!(!warnings.is_empty());
    let session = &manager.sessions["tab"];
    assert_eq!(
        session.stream_url.as_deref(),
        Some("http://127.0.0.1/active")
    );
    assert_eq!(session.leases, HashSet::from([7]));
}

#[test]
fn combined_inventory_keeps_the_available_backend() {
    let device = EmulatorDevice {
        id: "ios:device".into(),
        name: "iPhone".into(),
        platform: EmulatorPlatform::Ios,
        state: "shutdown".into(),
        available: true,
        runtime: None,
    };
    let android_error = EmulatorFailure::unsupported("Android unavailable.");

    let devices = combine_device_results(Err(android_error), Ok(vec![device])).unwrap();

    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0].id, "ios:device");
}
