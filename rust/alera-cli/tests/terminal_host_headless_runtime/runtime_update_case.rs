use super::host_link_link_status::wait_for_ssh_link;
use super::host_link_mirror_case::hub_and_satellite;
use super::*;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};

/// The install layout a bootstrap leaves (`versions/<dir>` with `current`
/// pointing at it) in place of the fixture's plain `current` directory, plus
/// an `sftp` stand-in that copies the uploaded artifact locally.
fn versioned_install(fixture_satellite: &Path) -> PathBuf {
    let install = fixture_satellite.parent().unwrap().to_path_buf();
    std::fs::remove_dir_all(install.join("current")).unwrap();
    let old = install.join("versions/old-linux-x64");
    std::fs::create_dir_all(&old).unwrap();
    symlink(env!("CARGO_BIN_EXE_alera"), old.join("alera")).unwrap();
    symlink(&old, install.join("current")).unwrap();
    install
}

fn executable(path: &Path, script: &str) {
    std::fs::write(path, script).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700)).unwrap();
}

/// A runtime archive whose `alera` entry runs the binary under test, so the
/// upload stays small while the installed runtime is the real one.
fn runtime_archive(directory: &Path) -> PathBuf {
    let payload = directory.join("payload");
    std::fs::create_dir_all(&payload).unwrap();
    executable(
        &payload.join("alera"),
        &format!("#!/bin/sh\nexec '{}' \"$@\"\n", env!("CARGO_BIN_EXE_alera")),
    );
    let archive = directory.join("alera-runtime-linux-x64.tar.gz");
    let status = windowless_command("tar")
        .arg("-czf")
        .arg(&archive)
        .arg("-C")
        .arg(&payload)
        .arg("alera")
        .status()
        .unwrap();
    assert!(status.success());
    archive
}

fn install_fake_sftp(install: &Path) {
    // The fixture puts its `ssh` stand-in in `<tmp>/commands`, on the hub's PATH.
    let commands = install.parent().unwrap().join("commands");
    executable(
        &commands.join("sftp"),
        "#!/bin/sh\nread -r line\nsource=$(printf '%s' \"$line\" | sed -n 's/^put \"\\([^\"]*\\)\" \"\\([^\"]*\\)\"$/\\1/p')\ndestination=$(printf '%s' \"$line\" | sed -n 's/^put \"\\([^\"]*\\)\" \"\\([^\"]*\\)\"$/\\2/p')\ncp \"$source\" \"$destination\"\n",
    );
}

fn satellite_pid(satellite: &Path) -> Option<u64> {
    let control = std::fs::read_to_string(satellite.join("runtime-host.json")).ok()?;
    serde_json::from_str::<Value>(&control).ok()?["pid"].as_u64()
}

fn versions(install: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(install.join("versions"))
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

/// Stops the persistent satellite the restart started, which no guard owns.
struct SatelliteCleanup(PathBuf);

impl Drop for SatelliteCleanup {
    fn drop(&mut self) {
        if let Some(pid) = satellite_pid(&self.0) {
            let _ = windowless_command("kill")
                .args(["-9", &pid.to_string()])
                .status();
        }
    }
}

fn open_remote_terminal(writer: &mut TcpStream, reader: &mut BufReader<TcpStream>, remote: &Path) {
    send(
        writer,
        json!({"id": 10, "type": "tab.upsert", "payload": {
            "id": "remote-tab", "workspaceId": "task", "kind": "terminal",
            "title": "Remote", "createdAt": "2026-07-19T00:00:00Z",
            "updatedAt": "2026-07-19T00:00:00Z", "payload": {"terminalSessionId": "remote-session"}
        }}),
    );
    assert_eq!(read_response(reader, 10)["ok"], json!(true));
    send(
        writer,
        json!({"id": 11, "type": "createOrAttach", "payload": {
            "sessionId": "remote-session", "workspaceId": "task", "tabId": "remote-tab",
            "workingDirectory": remote, "launch": {"shell": "/bin/sh", "arguments": [],
            "environment": {"PATH": "/usr/bin:/bin", "TERM": "xterm"}}, "cols": 80, "rows": 24
        }}),
    );
    let created = read_response(reader, 11);
    assert_eq!(created["ok"], json!(true), "{created}");
}

/// Update Runtime installs a new version, refuses while a hub terminal runs
/// on the host unless forced, restarts the satellite onto the new binary,
/// reattaches the link, and leaves only the version it installed.
#[test]
fn updating_a_host_restarts_its_runtime_onto_the_new_version_and_prunes_the_old_one() {
    let fixture = hub_and_satellite();
    let install = versioned_install(&fixture.satellite);
    install_fake_sftp(&install);
    let archive_dir = tempfile::tempdir().unwrap();
    let archive = runtime_archive(archive_dir.path());
    let _cleanup = SatelliteCleanup(fixture.satellite.clone());
    wait_for_ssh_link(fixture.hub_port, "the startup link", |link| {
        link["state"] == "attached"
    });
    let old_pid = satellite_pid(&fixture.satellite).expect("the satellite wrote its pid");

    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");
    reader
        .get_ref()
        .set_read_timeout(Some(Duration::from_secs(90)))
        .unwrap();
    open_remote_terminal(&mut writer, &mut reader, &fixture.remote);

    let update = json!({
        "id": "ssh", "restartRuntime": true, "artifactPath": archive,
        "platform": "linux", "arch": "x64",
    });
    send(
        &mut writer,
        json!({"id": 1, "type": "sshTarget.bootstrap.start", "payload": update}),
    );
    let refused = read_response(&mut reader, 1);
    assert_eq!(refused["ok"], false, "{refused}");
    assert_eq!(refused["errorCode"], "hostBusy", "{refused}");
    assert_eq!(refused["errorDetails"]["hostId"], "ssh", "{refused}");
    assert_eq!(refused["errorDetails"]["alias"], "Lab", "{refused}");
    assert_eq!(refused["errorDetails"]["activeSessions"], 1, "{refused}");
    assert_eq!(
        refused["errorDetails"]["sessionIds"],
        json!(["remote-session"]),
        "{refused}"
    );
    send(
        &mut writer,
        json!({"id": 2, "type": "sshTarget.restartRuntime", "payload": {"id": "ssh"}}),
    );
    let refused = read_response(&mut reader, 2);
    assert_eq!(refused["errorCode"], "hostBusy", "{refused}");
    assert_eq!(versions(&install), vec!["old-linux-x64"], "nothing ran");

    let mut forced = update.clone();
    forced["force"] = json!(true);
    send(
        &mut writer,
        json!({"id": 3, "type": "sshTarget.bootstrap.start", "payload": forced}),
    );
    let started = read_response(&mut reader, 3);
    assert_eq!(started["ok"], true, "{started}");
    let job_id = started["payload"]["jobId"].clone();

    let deadline = Instant::now() + Duration::from_secs(180);
    let mut stages = Vec::new();
    let finished = loop {
        assert!(
            Instant::now() < deadline,
            "the update never finished: {stages:?}"
        );
        let message = read_message(&mut reader);
        if message["event"] != "sshTargetBootstrapProgress" || message["payload"]["jobId"] != job_id
        {
            continue;
        }
        let stage = message["payload"]["stage"].as_str().unwrap().to_string();
        stages.push(stage.clone());
        if matches!(stage.as_str(), "installed" | "failed" | "cancelled") {
            break message["payload"].clone();
        }
    };
    assert_eq!(finished["status"], "installed", "{finished} {stages:?}");
    let position = |name: &str| stages.iter().position(|stage| stage == name);
    let validate = position("validate").expect("validated");
    let restart = position("restart").expect("restarted");
    let prune = position("prune").expect("pruned");
    assert!(validate < restart && restart < prune, "{stages:?}");
    assert_eq!(
        stages.iter().filter(|stage| *stage == "installed").count(),
        1,
        "installed is only the final word: {stages:?}"
    );

    assert_eq!(versions(&install), vec!["local-linux-x64"]);
    let link = wait_for_ssh_link(fixture.hub_port, "the restarted runtime", |link| {
        link["state"] == "attached"
    });
    assert!(link["satelliteVersion"].is_string(), "{link}");
    assert_eq!(link["runtimeUpdateAvailable"], false, "{link}");
    let new_pid = satellite_pid(&fixture.satellite).expect("the new satellite wrote its pid");
    assert_ne!(new_pid, old_pid, "a new runtime process answers");
}
