use super::*;
use alera_core::runtime::{Project, SshTarget, Workspace};
use sha2::{Digest, Sha256};
use std::os::unix::fs::{symlink, PermissionsExt};

#[test]
fn home_retirement_preserves_terminal_on_transport_failure_then_recovers() {
    let directory = tempfile::tempdir().unwrap();
    let home = directory.path().join("home-runtime");
    let local = directory.path().join("local-project");
    let remote = directory.path().join("remote-project");
    let install = directory.path().join("sidecar");
    let commands = directory.path().join("commands");
    for path in [&home, &local, &remote, &commands, &install.join("current")] {
        std::fs::create_dir_all(path).unwrap();
    }
    symlink(env!("CARGO_BIN_EXE_alera"), install.join("current/alera")).unwrap();
    let offline = directory.path().join("offline");
    let script = format!("#!/bin/sh\nif [ -f '{}' ]; then exit 1; fi\nfor argument do command=$argument; done\nexec /bin/sh -c \"$command\"\n", offline.to_string_lossy().replace('\'', "'\\''"));
    std::fs::write(commands.join("ssh"), script).unwrap();
    std::fs::set_permissions(commands.join("ssh"), std::fs::Permissions::from_mode(0o700)).unwrap();
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        let store = RuntimeStore::open(&home).await.unwrap();
        let project: Project = serde_json::from_value(json!({"id":"project-1","name":"Project","repoPath":local,"kind":"folder",
            "createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z"})).unwrap();
        store.upsert_project(project).await.unwrap();
        store.register_project_checkout("project-1", "ssh", remote.to_str().unwrap()).await.unwrap();
        let mut task: Workspace = serde_json::from_value(workspace_payload("task", &remote)).unwrap();
        task.host_id = "ssh".into();
        store.insert_workspace(task).await.unwrap();
        let target: SshTarget = serde_json::from_value(json!({"id":"ssh","alias":"Isolated","host":"test.invalid","port":22,"username":"test","authKind":"agent",
            "createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","installDir":install,"bootstrapStatus":"installed","runtimePlatform":"linux"})).unwrap();
        store.upsert_ssh_target(target).await.unwrap();
    });
    let owner = install
        .join("owners")
        .join(hex::encode(Sha256::digest(b"project-1")));
    std::fs::create_dir_all(&owner).unwrap();
    let (_owner_guard, owner_port) = spawn_host(&owner, "owner-token");
    let path = std::env::join_paths(std::iter::once(commands).chain(std::env::split_paths(
        &std::env::var_os("PATH").unwrap_or_default(),
    )))
    .unwrap();
    let (_home_guard, home_port) = spawn_host_with_path(&home, "home-token", Some(path));
    let (mut writer, mut reader) = connect(home_port, "home-token");
    send(
        &mut writer,
        json!({"id":1,"type":"tab.upsert","payload":{"id":"tab","workspaceId":"task","kind":"terminal","title":"Remote Terminal",
        "createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","payload":{"terminalSessionId":"session"}}}),
    );
    assert_eq!(read_response(&mut reader, 1)["ok"], true);
    send(
        &mut writer,
        json!({"id":2,"type":"createOrAttach","payload":{"sessionId":"session","workspaceId":"task","tabId":"tab","workingDirectory":remote,
        "launch":{"shell":"/bin/sh","arguments":[],"environment":{}},"cols":80,"rows":24}}),
    );
    let started = read_response(&mut reader, 2);
    assert_eq!(started["ok"], true, "{started}");
    send(
        &mut writer,
        json!({"id":3,"type":"write","payload":{"sessionId":"session","dataBase64":STANDARD.encode(b"printf ready > marker\n")}}),
    );
    assert_eq!(read_response(&mut reader, 3)["ok"], true);
    wait_for_path(&remote.join("marker"));
    for (attempt, disconnected) in [(10, true), (20, false)] {
        if disconnected {
            std::fs::write(&offline, "offline").unwrap();
        } else {
            std::fs::remove_file(&offline).unwrap();
        }
        send(
            &mut writer,
            json!({"id":attempt,"type":"workspace.bufferGuard.acquire","payload":{"id":"task","operation":"removeShared"}}),
        );
        let guard = read_response(&mut reader, attempt);
        assert_eq!(guard["ok"], true, "{guard}");
        assert_eq!(guard["payload"]["ready"], true);
        send(
            &mut writer,
            json!({"id":attempt+1,"type":"workspace.removeShared","payload":{"id":"task","closeSessions":true,"bufferGuardId":guard["payload"]["guardId"]}}),
        );
        let removed = read_response(&mut reader, attempt + 1);
        assert_eq!(removed["ok"], !disconnected, "{removed}");
        send(
            &mut writer,
            json!({"id":attempt+2,"type":"workspace.find","payload":{"id":"task"}}),
        );
        assert_eq!(
            read_response(&mut reader, attempt + 2)["payload"].is_null(),
            !disconnected
        );
        send(
            &mut writer,
            json!({"id":attempt+3,"type":"tab.find","payload":{"id":"tab"}}),
        );
        assert_eq!(
            read_response(&mut reader, attempt + 3)["payload"].is_null(),
            !disconnected
        );
        if disconnected {
            send(
                &mut writer,
                json!({"id":attempt+4,"type":"write","payload":{"sessionId":"session","dataBase64":STANDARD.encode(b"printf retained > after-failure\n")}}),
            );
            assert_eq!(read_response(&mut reader, attempt + 4)["ok"], true);
            wait_for_path(&remote.join("after-failure"));
            assert_eq!(
                std::fs::read_to_string(remote.join("after-failure")).unwrap(),
                "retained"
            );
        }
    }
    let (mut owner_writer, mut owner_reader) = connect(owner_port, "owner-token");
    send(
        &mut owner_writer,
        json!({"id":1,"type":"workspace.find","payload":{"id":"task"}}),
    );
    assert!(read_response(&mut owner_reader, 1)["payload"].is_null());
    assert_eq!(
        std::fs::read_to_string(remote.join("marker")).unwrap(),
        "ready"
    );
}
