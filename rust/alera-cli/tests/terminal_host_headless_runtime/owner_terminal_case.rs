use super::*;
use std::process::Stdio;

fn bridge(directory: &std::path::Path, metadata: &str, session: &str) -> HostGuard {
    HostGuard(
        windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args([
                "project",
                "owner-terminal",
                "--state-dir",
                directory.to_str().unwrap(),
                "--metadata-base64",
                metadata,
                "--session-id",
                session,
                "--tab-id",
                session,
            ])
            .env("HOME", directory.join("test-home"))
            .env("SHELL", "/bin/sh")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    )
}

#[track_caller]
fn wait_exit(child: &mut Child) -> std::process::ExitStatus {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        assert!(
            Instant::now() < deadline,
            "owner terminal bridge did not exit"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn retirement_command(directory: &std::path::Path) -> HostGuard {
    HostGuard(
        windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args([
                "project",
                "retire-owner-workspace",
                "--state-dir",
                directory.to_str().unwrap(),
                "--workspace-id",
                "owned-workspace",
                "--instance-id",
                "owned-workspace-instance",
                "--close-sessions",
            ])
            .env("HOME", directory.join("test-home"))
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    )
}

#[test]
fn owner_terminal_disconnect_preserves_shell_and_reattaches_same_session() {
    exercise_owner_lifecycle(false);
}

#[test]
fn owner_retirement_closes_only_its_task_and_preserves_shared_files() {
    exercise_owner_lifecycle(true);
}

fn exercise_owner_lifecycle(retire: bool) {
    let directory = tempfile::tempdir().unwrap();
    let folder = directory.path().join("project");
    std::fs::create_dir(&folder).unwrap();
    let token = "isolated-owner-token";
    let (_host, port) = spawn_host(directory.path(), token);
    let metadata = STANDARD.encode(json!({
        "project": {"id":"project-1", "name":"Project", "repoPath":folder,
            "kind":"folder", "createdAt":"2026-07-19T00:00:00Z", "updatedAt":"2026-07-19T00:00:00Z"},
        "workspace":workspace_payload("owned-workspace", &folder),
    }).to_string());
    let mut first = bridge(directory.path(), &metadata, "owner-session");
    first
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"printf '%s' \"$$\" > first-pid\n")
        .unwrap();
    wait_for_path(&folder.join("first-pid"));
    let original_pid = std::fs::read_to_string(folder.join("first-pid")).unwrap();
    assert!(!original_pid.is_empty());
    tokio::runtime::Runtime::new().unwrap().block_on(async {
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            store
                .workspace_terminal_launch_attempted("owned-workspace", "owned-workspace-instance")
                .await
                .unwrap(),
            Some(true)
        );
    });
    let peer_metadata = STANDARD.encode(json!({
        "project": {"id":"project-1", "name":"Project", "repoPath":folder,
            "kind":"folder", "createdAt":"2026-07-19T00:00:00Z", "updatedAt":"2026-07-19T00:00:00Z"},
        "workspace":workspace_payload("peer-workspace", &folder),
    }).to_string());
    let mut peer = bridge(directory.path(), &peer_metadata, "peer-session");
    peer.0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"printf '%s' \"$$\" > peer-pid\n")
        .unwrap();
    wait_for_path(&folder.join("peer-pid"));
    let peer_pid = std::fs::read_to_string(folder.join("peer-pid")).unwrap();
    assert!(!peer_pid.is_empty());
    assert_ne!(peer_pid, original_pid);
    drop(first.0.stdin.take());
    assert!(
        !wait_exit(&mut first.0).success(),
        "disconnect must not report a verified remote exit"
    );

    let mut second = bridge(directory.path(), &metadata, "owner-session");
    second
        .0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"printf '%s' \"$$\" > second-pid\n")
        .unwrap();
    wait_for_path(&folder.join("second-pid"));
    assert_eq!(
        std::fs::read_to_string(folder.join("second-pid")).unwrap(),
        original_pid
    );
    if retire {
        for _ in 0..2 {
            let mut command = retirement_command(directory.path());
            assert!(wait_exit(&mut command.0).success());
            let mut output = String::new();
            std::io::Read::read_to_string(command.0.stdout.as_mut().unwrap(), &mut output).unwrap();
            let receipt: Value = serde_json::from_str(&output).unwrap();
            assert_eq!(receipt["processClosureVerified"], true);
            assert_eq!(
                receipt["workspace"]["instanceId"],
                "owned-workspace-instance"
            );
        }
        wait_exit(&mut second.0);
        let mut stale = bridge(directory.path(), &metadata, "owner-session");
        assert!(!wait_exit(&mut stale.0).success());
        assert_eq!(
            std::fs::read_to_string(folder.join("first-pid")).unwrap(),
            original_pid
        );
    } else {
        second
            .0
            .stdin
            .as_mut()
            .unwrap()
            .write_all(b"exit 0\n")
            .unwrap();
        assert!(wait_exit(&mut second.0).success());
    }
    peer.0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"printf '%s' \"$$\" > peer-retained-pid\n")
        .unwrap();
    wait_for_path(&folder.join("peer-retained-pid"));
    assert_eq!(
        std::fs::read_to_string(folder.join("peer-retained-pid")).unwrap(),
        peer_pid
    );
    peer.0
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"exit 0\n")
        .unwrap();
    assert!(wait_exit(&mut peer.0).success());
    let (mut writer, mut reader) = connect(port, token);
    assert_session_is_not_attached(&mut writer, &mut reader, 1, "owner-session");
    if retire {
        drop(writer);
        drop(reader);
        drop(_host);
        let control_path = directory.path().join("runtime-host.json");
        let control = std::fs::read(&control_path).unwrap();
        let mut command = retirement_command(directory.path());
        assert!(wait_exit(&mut command.0).success());
        let mut output = String::new();
        std::io::Read::read_to_string(command.0.stdout.as_mut().unwrap(), &mut output).unwrap();
        let receipt: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(
            receipt["workspace"]["instanceId"],
            "owned-workspace-instance"
        );
        assert_eq!(receipt["processClosureVerified"], true);
        assert_eq!(std::fs::read(control_path).unwrap(), control);
    }
}
