use super::*;
use alera_core::runtime::{Project, SshTarget, Workspace};
use std::os::unix::fs::{symlink, PermissionsExt};

pub(super) struct HubAndSatellite {
    _directory: tempfile::TempDir,
    pub(super) remote: std::path::PathBuf,
    pub(super) satellite: std::path::PathBuf,
    _satellite_guard: HostGuard,
    pub(super) satellite_port: u16,
    _hub_guard: HostGuard,
    pub(super) hub_port: u16,
}

/// A hub runtime and a satellite runtime in one process. `ssh` is a script
/// that runs the remote command locally, and the sidecar `bin/alera` wrapper
/// points at the satellite profile at `<installDir>/data`, exactly as the
/// bootstrap installs it, so the hub's real launcher and `runtime-attach` are
/// exercised. The hub holds one remote workspace `task` on host `ssh`.
pub(super) fn hub_and_satellite() -> HubAndSatellite {
    hub_and_satellite_with_kind("folder")
}

/// `kind` is the hub project's kind. A `gitRepository` project gets a repository with a
/// configured identity at both checkouts, so the satellite's mirror validation
/// and the `git.*` verbs see what a real clone would give them.
pub(super) fn hub_and_satellite_with_kind(kind: &str) -> HubAndSatellite {
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
        &remote.join("src"),
        &commands,
        &satellite,
        &install.join("bin"),
        &install.join("current"),
    ] {
        std::fs::create_dir_all(path).unwrap();
    }
    std::fs::write(remote.join("src/main.rs"), "fn main() {}\n").unwrap();
    std::fs::write(remote.join("readme.md"), "# Remote\n").unwrap();
    if kind == "gitRepository" {
        for checkout in [&local, &remote] {
            let repo = git2::Repository::init(checkout).unwrap();
            let mut config = repo.config().unwrap();
            config.set_str("user.name", "Alera Test").unwrap();
            config.set_str("user.email", "alera@example.com").unwrap();
        }
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
        let project: Project = serde_json::from_value(json!({"id":"project-1","name":"Project","repoPath":local,"kind":kind,
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
    let (satellite_guard, satellite_port) = spawn_host(&satellite, "satellite-token");
    let path = std::env::join_paths(std::iter::once(commands).chain(std::env::split_paths(
        &std::env::var_os("PATH").unwrap_or_default(),
    )))
    .unwrap();
    let (hub_guard, hub_port) = spawn_host_with_path(&hub, "hub-token", Some(path));
    HubAndSatellite {
        _directory: directory,
        remote,
        satellite,
        _satellite_guard: satellite_guard,
        satellite_port,
        _hub_guard: hub_guard,
        hub_port,
    }
}

#[test]
fn hub_mirrors_a_remote_workspace_onto_its_satellite_over_the_link() {
    let fixture = hub_and_satellite();
    let remote = &fixture.remote;
    let satellite = &fixture.satellite;
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");

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
            std::fs::canonicalize(remote).unwrap().to_str().unwrap()
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

    let (mut satellite_writer, mut satellite_reader) =
        connect(fixture.satellite_port, "satellite-token");
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
        std::fs::canonicalize(remote).unwrap().to_str().unwrap()
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

/// Host-scoped verbs sent to the hub for a remote workspace are answered by
/// the satellite: the hub mirrors the workspace, forwards the request over the
/// link, and hands the answer back unchanged.
#[test]
fn hub_forwards_file_and_search_verbs_for_a_remote_workspace_to_its_satellite() {
    let fixture = hub_and_satellite();
    let remote = &fixture.remote;
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");
    let mut next_id = 0;
    let mut request = |verb: &str, payload: Value| {
        next_id += 1;
        send(
            &mut writer,
            json!({"id": next_id, "type": verb, "payload": payload}),
        );
        read_response(&mut reader, next_id)
    };

    let listed = request(
        "workspace.files.list",
        json!({"workspaceId": "task", "relativePath": "", "hideIgnored": true}),
    );
    assert_eq!(listed["ok"], true, "{listed}");
    let names: Vec<&str> = listed["payload"]["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["src", "readme.md"], "{listed}");

    let read = request(
        "workspace.files.read",
        json!({"workspaceId": "task", "relativePath": "src/main.rs", "offset": 0, "length": 65536}),
    );
    assert_eq!(read["ok"], true, "{read}");
    assert_eq!(read["payload"]["isText"], true);
    assert_eq!(
        STANDARD
            .decode(read["payload"]["dataBase64"].as_str().unwrap())
            .unwrap(),
        b"fn main() {}\n"
    );
    let token = read["payload"]["contentToken"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(token.contains(':'), "{read}");

    let stale = request(
        "workspace.files.write",
        json!({"workspaceId": "task", "relativePath": "src/main.rs",
            "contentBase64": STANDARD.encode("fn main() { changed(); }\n"), "expectedContentToken": "0:0"}),
    );
    assert_eq!(stale["ok"], false, "{stale}");
    assert_eq!(stale["errorCode"], "workspaceFile", "{stale}");
    assert_eq!(stale["errorDetails"]["kind"], "conflict", "{stale}");
    let written = request(
        "workspace.files.write",
        json!({"workspaceId": "task", "relativePath": "src/main.rs",
            "contentBase64": STANDARD.encode("fn main() { changed(); }\n"), "expectedContentToken": token}),
    );
    assert_eq!(written["ok"], true, "{written}");
    assert_eq!(
        std::fs::read_to_string(remote.join("src/main.rs")).unwrap(),
        "fn main() { changed(); }\n"
    );

    let created = request(
        "workspace.files.create",
        json!({"workspaceId": "task", "parentRelativePath": "src", "name": "lib.rs"}),
    );
    assert_eq!(created["ok"], true, "{created}");
    assert_eq!(created["payload"]["relativePath"], "src/lib.rs");
    assert!(remote.join("src/lib.rs").is_file());
    let renamed = request(
        "workspace.files.rename",
        json!({"workspaceId": "task", "relativePath": "src/lib.rs", "newName": "util.rs"}),
    );
    assert_eq!(
        renamed["payload"]["relativePath"], "src/util.rs",
        "{renamed}"
    );
    let deleted = request(
        "workspace.files.delete",
        json!({"workspaceId": "task", "relativePath": "src/util.rs", "useTrash": false}),
    );
    assert_eq!(deleted["ok"], true, "{deleted}");
    assert!(!remote.join("src/util.rs").exists());
    let escape = request(
        "workspace.files.delete",
        json!({"workspaceId": "task", "relativePath": "../remote-project", "useTrash": false}),
    );
    assert_eq!(escape["ok"], false);
    assert_eq!(escape["errorCode"], "workspaceFile", "{escape}");
    assert!(remote.exists());

    let started = request(
        "mobile.workspaceQuickOpen.start",
        json!({"workspaceId": "task"}),
    );
    assert_eq!(started["ok"], true, "{started}");
    let session_id = started["payload"]["sessionId"]
        .as_str()
        .unwrap()
        .to_string();
    assert_eq!(started["payload"]["indexedFileCount"], 2, "{started}");
    let matched = request(
        "mobile.workspaceQuickOpen.search",
        json!({"sessionId": session_id, "indexedFileCount": 2, "query": "main", "limit": 10}),
    );
    assert_eq!(matched["ok"], true, "{matched}");
    assert_eq!(
        matched["payload"]["items"][0]["relativePath"],
        "src/main.rs"
    );
    let stopped = request(
        "mobile.workspaceQuickOpen.stop",
        json!({"sessionId": session_id}),
    );
    assert_eq!(stopped["ok"], true, "{stopped}");

    let searched = request(
        "mobile.workspaceSearch.run",
        json!({"workspaceId": "task", "query": "changed", "requestId": "s1"}),
    );
    assert_eq!(searched["ok"], true, "{searched}");
    assert_eq!(searched["payload"]["totalMatches"], 1, "{searched}");
    assert_eq!(
        searched["payload"]["files"][0]["relativePath"],
        "src/main.rs"
    );
    let replaced = request(
        "mobile.workspaceSearch.replace",
        json!({"workspaceId": "task", "query": "changed", "replacement": "replaced",
            "matchIds": [], "expectedFiles": [{"relativePath": "src/main.rs",
            "contentToken": searched["payload"]["files"][0]["contentToken"]}]}),
    );
    assert_eq!(replaced["ok"], true, "{replaced}");
    assert_eq!(replaced["payload"]["filesChanged"], 1, "{replaced}");
    assert_eq!(
        std::fs::read_to_string(remote.join("src/main.rs")).unwrap(),
        "fn main() { replaced(); }\n"
    );
}
