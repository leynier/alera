use super::*;
use alera_core::runtime::{Project, SshTarget, Workspace};
use std::os::unix::fs::{symlink, PermissionsExt};

/// A hub runtime mirrors one of its remote workspaces onto a satellite runtime
/// over the host link. `ssh` is a script that runs the remote command locally,
/// and the sidecar `bin/alera` wrapper points at the satellite profile at
/// `<installDir>/data`, exactly as the bootstrap installs it.
#[test]
fn hub_mirrors_a_remote_workspace_onto_its_satellite_over_the_link() {
    let directory = tempfile::tempdir().unwrap();
    let hub = directory.path().join("hub-runtime");
    let local = directory.path().join("local-project");
    let remote = directory.path().join("remote-project");
    let install = directory.path().join("sidecar");
    let satellite = install.join("data");
    let commands = directory.path().join("commands");
    for path in [
        &hub,
        &local,
        &remote,
        &commands,
        &satellite,
        &install.join("bin"),
        &install.join("current"),
    ] {
        std::fs::create_dir_all(path).unwrap();
    }
    symlink(env!("CARGO_BIN_EXE_alera"), install.join("current/alera")).unwrap();
    let executable = |path: &std::path::Path, script: String| {
        std::fs::write(path, script).unwrap();
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700)).unwrap();
    };
    executable(
        &install.join("bin/alera"),
        format!(
            "#!/bin/sh\nexport ALERA_RUNTIME_DIR='{}'\nexec '{}' \"$@\"\n",
            satellite.display(),
            install.join("current/alera").display()
        ),
    );
    executable(
        &commands.join("ssh"),
        "#!/bin/sh\nfor argument do command=$argument; done\nexec /bin/sh -c \"$command\"\n".into(),
    );
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        let store = RuntimeStore::open(&hub).await.unwrap();
        let project: Project = serde_json::from_value(json!({"id":"project-1","name":"Project","repoPath":local,"kind":"folder",
            "createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z"})).unwrap();
        store.upsert_project(project).await.unwrap();
        store
            .register_project_checkout("project-1", "ssh", remote.to_str().unwrap())
            .await
            .unwrap();
        let mut task: Workspace =
            serde_json::from_value(workspace_payload("task", &remote)).unwrap();
        task.host_id = "ssh".into();
        store.insert_workspace(task).await.unwrap();
        let target: SshTarget = serde_json::from_value(json!({"id":"ssh","alias":"Lab","host":"test.invalid","port":22,"username":"test","authKind":"agent",
            "createdAt":"2026-07-19T00:00:00Z","updatedAt":"2026-07-19T00:00:00Z","installDir":install,"bootstrapStatus":"installed","runtimePlatform":"linux"})).unwrap();
        store.upsert_ssh_target(target).await.unwrap();
    });
    let (_satellite_guard, satellite_port) = spawn_host(&satellite, "satellite-token");
    let path = std::env::join_paths(std::iter::once(commands).chain(std::env::split_paths(
        &std::env::var_os("PATH").unwrap_or_default(),
    )))
    .unwrap();
    let (_hub_guard, hub_port) = spawn_host_with_path(&hub, "hub-token", Some(path));
    let (mut writer, mut reader) = connect(hub_port, "hub-token");

    for id in [1, 2] {
        send(
            &mut writer,
            json!({"id":id,"type":"hostLink.mirrorWorkspace","payload":{"workspaceId":"task"}}),
        );
        let mirrored = read_response(&mut reader, id);
        assert_eq!(mirrored["ok"], true, "{mirrored}");
        assert_eq!(mirrored["payload"]["id"], "task");
        assert_eq!(mirrored["payload"]["instanceId"], "task-instance");
        assert_eq!(mirrored["payload"]["hostId"], "local");
        assert_eq!(
            mirrored["payload"]["path"],
            std::fs::canonicalize(&remote).unwrap().to_str().unwrap()
        );
    }
    send(
        &mut writer,
        json!({"id":3,"type":"hostLink.status","payload":{}}),
    );
    let status = read_response(&mut reader, 3);
    assert_eq!(status["ok"], true, "{status}");
    let link = &status["payload"]["links"][0];
    assert_eq!(link["hostId"], "ssh", "{status}");
    assert_eq!(link["state"], "attached", "{status}");
    assert_eq!(
        link["attachment"]["runtimeDir"],
        satellite.to_str().unwrap(),
        "{status}"
    );

    let (mut satellite_writer, mut satellite_reader) = connect(satellite_port, "satellite-token");
    send(
        &mut satellite_writer,
        json!({"id":1,"type":"workspace.find","payload":{"id":"task"}}),
    );
    let found = read_response(&mut satellite_reader, 1);
    assert_eq!(found["payload"]["projectId"], "project-1", "{found}");
    assert_eq!(found["payload"]["hostId"], "local");
    send(
        &mut satellite_writer,
        json!({"id":2,"type":"project.list","payload":{}}),
    );
    let projects = read_response(&mut satellite_reader, 2);
    assert_eq!(projects["payload"][0]["id"], "project-1", "{projects}");
    assert_eq!(
        projects["payload"][0]["repoPath"],
        std::fs::canonicalize(&remote).unwrap().to_str().unwrap()
    );

    send(
        &mut writer,
        json!({"id":4,"type":"hostLink.mirrorWorkspace","payload":{"workspaceId":"missing"}}),
    );
    let missing = read_response(&mut reader, 4);
    assert_eq!(missing["ok"], false);
    assert!(
        missing["error"]
            .as_str()
            .unwrap()
            .contains("Unknown workspace"),
        "{missing}"
    );
}
