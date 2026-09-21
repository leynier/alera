use super::host_link_mirror_case::hub_and_satellite_with_kind;
use super::*;
use std::os::unix::fs::PermissionsExt;

/// One project on several hosts: the hub lists where a project lives, refuses
/// to forget a host that still has workspaces, and adds a new host by asking
/// it to clone the project into its own default projects folder.
#[test]
fn a_project_is_listed_added_to_and_removed_from_hosts() {
    let fixture = hub_and_satellite_with_kind("gitRepository");
    let root = fixture.remote.parent().unwrap().to_path_buf();
    let install = root.join("sidecar");

    // The clone lands under the remote user's home, so the stand-in `ssh`
    // gives the remote command a home of its own instead of the developer's.
    let home = root.join("remote-home");
    std::fs::create_dir_all(&home).unwrap();
    let ssh = root.join("commands/ssh");
    std::fs::write(
        &ssh,
        format!(
            "#!/bin/sh\nfor argument do command=$argument; done\nHOME='{}' exec /bin/sh -c \"$command\"\n",
            home.display()
        ),
    )
    .unwrap();
    std::fs::set_permissions(&ssh, std::fs::Permissions::from_mode(0o700)).unwrap();

    // A source with history: an empty repository has no branch to inspect.
    let source = root.join("source-repository");
    std::fs::create_dir_all(&source).unwrap();
    let repository = git2::Repository::init(&source).unwrap();
    std::fs::write(source.join("readme.md"), "# Source\n").unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(std::path::Path::new("readme.md")).unwrap();
    index.write().unwrap();
    let tree = repository.find_tree(index.write_tree().unwrap()).unwrap();
    let author = git2::Signature::now("Alera Test", "alera@example.com").unwrap();
    repository
        .commit(
            Some("HEAD"),
            &author,
            &author,
            "docs: add readme",
            &tree,
            &[],
        )
        .unwrap();

    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");
    let mut next_id = 0;
    let mut request = |request_type: &str, payload: Value| {
        next_id += 1;
        send(
            &mut writer,
            json!({"id": next_id, "type": request_type, "payload": payload}),
        );
        read_response(&mut reader, next_id)
    };

    let listed = request("project.hosts.list", json!({"projectId": "project-1"}));
    assert_eq!(listed["ok"], true, "{listed}");
    assert_eq!(listed["payload"]["primaryHostId"], "local", "{listed}");
    let hosts = listed["payload"]["hosts"].as_array().unwrap();
    assert_eq!(hosts.len(), 2, "{listed}");
    let remote = hosts.iter().find(|host| host["hostId"] == "ssh").unwrap();
    assert_eq!(remote["workspaceCount"], 1, "{listed}");

    let projects = request("project.list", json!({}));
    assert_eq!(projects["ok"], true, "{projects}");
    assert_eq!(
        projects["payload"][0]["primaryHostId"], "local",
        "{projects}"
    );
    assert_eq!(
        projects["payload"][0]["checkouts"]
            .as_array()
            .unwrap()
            .len(),
        2,
        "{projects}"
    );

    let busy = request(
        "project.hosts.remove",
        json!({"projectId": "project-1", "hostId": "ssh"}),
    );
    assert_eq!(busy["ok"], false, "{busy}");
    assert!(
        busy["error"].as_str().unwrap().contains("workspace"),
        "{busy}"
    );

    let target = request(
        "sshTarget.upsert",
        json!({"id": "ssh-2", "alias": "Second", "host": "second.invalid", "port": 22,
            "username": "test", "authKind": "agent",
            "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
            "installDir": install, "bootstrapStatus": "installed", "runtimePlatform": "linux"}),
    );
    assert_eq!(target["ok"], true, "{target}");

    let added = request(
        "project.hosts.add",
        json!({"projectId": "project-1", "hostId": "ssh-2", "cloneUrl": source}),
    );
    assert_eq!(added["ok"], true, "{added}");
    assert_eq!(added["payload"]["hostId"], "ssh-2", "{added}");
    let cloned = std::path::PathBuf::from(added["payload"]["path"].as_str().unwrap());
    assert_eq!(
        cloned,
        std::fs::canonicalize(&home)
            .unwrap()
            .join("alera-projects/local-project"),
        "the host names the clone after the project folder, under its own home"
    );
    assert!(cloned.join("readme.md").is_file());

    let again = request(
        "project.hosts.add",
        json!({"projectId": "project-1", "hostId": "ssh-2", "cloneUrl": source}),
    );
    assert_eq!(again["ok"], false, "{again}");
    assert!(
        again["error"]
            .as_str()
            .unwrap()
            .contains("already on this host"),
        "{again}"
    );

    // A project that exists only on a host: cloned there, nothing here.
    let remote_only = request(
        "project.registerRemote",
        json!({"hostId": "ssh-2", "cloneUrl": source, "name": "Server Only"}),
    );
    assert_eq!(remote_only["ok"], true, "{remote_only}");
    let remote_project = &remote_only["payload"]["project"];
    let remote_path = remote_project["repoPath"].as_str().unwrap();
    assert!(
        remote_path.ends_with("alera-projects/source-repository"),
        "named after the repository, under the host's home: {remote_path}"
    );
    assert_eq!(remote_only["payload"]["checkout"]["hostId"], "ssh-2");
    let listed = request("project.list", json!({}));
    let entry = listed["payload"]
        .as_array()
        .unwrap()
        .iter()
        .find(|project| project["id"] == remote_project["id"])
        .unwrap_or_else(|| panic!("{listed}"));
    assert_eq!(entry["name"], "Server Only");
    assert_eq!(entry["primaryHostId"], "ssh-2", "{entry}");
    assert_eq!(entry["checkouts"].as_array().unwrap().len(), 1, "{entry}");
    // No host named: the workspace goes where the project lives.
    let shared = request(
        "workspace.createShared",
        json!({"projectId": remote_project["id"], "name": "On The Server"}),
    );
    assert_eq!(shared["ok"], true, "{shared}");
    assert_eq!(
        shared["payload"]["workspace"]["hostId"], "ssh-2",
        "{shared}"
    );
    assert_eq!(
        shared["payload"]["workspace"]["path"], remote_path,
        "{shared}"
    );

    let twice = request(
        "project.registerRemote",
        json!({"hostId": "ssh-2", "path": remote_path}),
    );
    assert_eq!(twice["ok"], false, "{twice}");
    assert!(
        twice["error"]
            .as_str()
            .unwrap()
            .contains("already the project"),
        "{twice}"
    );

    let removed = request(
        "project.hosts.remove",
        json!({"projectId": "project-1", "hostId": "ssh-2"}),
    );
    assert_eq!(removed["ok"], true, "{removed}");
    assert_eq!(removed["payload"]["hosts"].as_array().unwrap().len(), 2);
    assert!(
        cloned.join("readme.md").is_file(),
        "removing a host never deletes files"
    );
}
