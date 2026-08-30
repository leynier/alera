use super::*;

#[tokio::test]
async fn failed_workspace_shutdown_retains_ownership_until_a_verified_retry() {
    let mut fixture = Fixture::new().await;
    #[cfg(unix)]
    let shell = start_stubborn_terminal(&mut fixture).await;
    fixture.fail_shutdown_waits = 2;

    for _ in 0..2 {
        let response = fixture
            .request(
                "workspace.removeManaged",
                json!({
                    "id": "workspace", "closeSessions": true,
                }),
            )
            .await;
        assert_eq!(response["ok"], false, "{response}");
        assert!(response["error"]
            .as_str()
            .unwrap()
            .contains("injected process inspection failure"));
        assert!(std::path::Path::new(&fixture.workspace.path).exists());
        assert!(!fixture.actor.sessions.contains_key("terminal"));
        assert!(fixture
            .actor
            .emulator_requests
            .pending_workspace_shutdowns
            .contains_key("workspace"));
        assert!(fixture.actor.sessions["other"].running());
        let tabs = fixture
            .actor
            .runtime_store
            .list_workspace_tabs("workspace")
            .await
            .unwrap();
        assert_eq!(
            tabs.iter().map(|tab| tab.id.as_str()).collect::<Vec<_>>(),
            ["editor"]
        );
        #[cfg(unix)]
        assert!(shell.is_live(), "the fixture must survive the failed wait");
    }

    let legacy = fixture
        .request("workspace.removeManaged", json!({"id": "workspace"}))
        .await;
    assert_eq!(legacy["ok"], false);
    assert!(std::path::Path::new(&fixture.workspace.path).exists());

    for (request, payload) in [
        ("workspace.remove", json!({"id": "workspace"})),
        (
            "workspace.removeForProject",
            json!({"projectId": "project"}),
        ),
        ("project.remove", json!({"id": "project"})),
    ] {
        let response = fixture.request(request, payload).await;
        assert_eq!(response["ok"], false, "{request}: {response}");
        assert!(
            response["error"]
                .as_str()
                .unwrap()
                .contains("unfinished process shutdown"),
            "{response}"
        );
        assert!(fixture
            .actor
            .runtime_store
            .find_workspace("workspace")
            .await
            .unwrap()
            .is_some());
        assert!(fixture
            .actor
            .runtime_store
            .find_project("project")
            .await
            .unwrap()
            .is_some());
        assert!(fixture
            .actor
            .emulator_requests
            .pending_workspace_shutdowns
            .contains_key("workspace"));
        assert!(std::path::Path::new(&fixture.workspace.path).exists());
    }

    let client = fixture.actor.clients.remove(&1).unwrap();
    let generation = fixture.actor.shutdown_gen;
    fixture.actor.schedule_shutdown_if_idle();
    assert_ne!(fixture.actor.shutdown_gen, generation);
    fixture
        .actor
        .handle_shutdown_tick(fixture.actor.shutdown_gen)
        .await;
    assert!(
        !fixture.actor.disposed,
        "idle shutdown must not discard pending ownership"
    );
    fixture.actor.clients.insert(1, client);

    // New sessions must join the retained shutdown instead of replacing it.
    fixture
        .actor
        .sessions
        .insert("new".into(), Session::driver_test_stub("new", 80, 24));
    let response = fixture
        .request(
            "workspace.removeManaged",
            json!({
                "id": "workspace", "closeSessions": true,
            }),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    assert!(!std::path::Path::new(&fixture.workspace.path).exists());
    assert!(fixture
        .actor
        .emulator_requests
        .pending_workspace_shutdowns
        .is_empty());
    assert!(!fixture.actor.sessions.contains_key("new"));
    #[cfg(unix)]
    tokio::time::timeout(Duration::from_secs(5), async {
        while shell.is_live() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the retained shell should be reaped before returning");
}

#[cfg(unix)]
struct StubbornTerminal(crate::terminal_host::resources::ShellProcess);

#[cfg(unix)]
impl StubbornTerminal {
    fn is_live(&self) -> bool {
        crate::terminal_host::resources::seal_shell_process(self.0.pid) == Some(self.0)
    }
}

#[cfg(unix)]
impl Drop for StubbornTerminal {
    fn drop(&mut self) {
        // The fixture owns a fresh PTY process group. Never leave its shell
        // running after a failed assertion, or signal a reused pid.
        if self.is_live() {
            unsafe {
                libc::kill(-(self.0.pid as libc::pid_t), libc::SIGKILL);
            }
        }
    }
}

#[cfg(unix)]
async fn start_stubborn_terminal(fixture: &mut Fixture) -> StubbornTerminal {
    start_terminal(
        fixture,
        "trap '' HUP TERM; : > \"$1\"; while :; do sleep 1; done",
        vec![],
    )
    .await
}

#[cfg(unix)]
async fn start_terminal(
    fixture: &mut Fixture,
    script: &str,
    extra_arguments: Vec<String>,
) -> StubbornTerminal {
    let ready = fixture._root.path().join("terminal-ready");
    let mut arguments = vec![
        "-c".into(),
        script.into(),
        "shutdown-test".into(),
        ready.to_string_lossy().into_owned(),
    ];
    arguments.extend(extra_arguments);
    let session = Session::start(
        "terminal".into(),
        "workspace".into(),
        "tab-terminal".into(),
        fixture.workspace.path.clone(),
        &crate::terminal_host::protocol::TerminalHostLaunch {
            label: "Test".into(),
            shell: "/bin/sh".into(),
            arguments,
            environment: std::collections::BTreeMap::from([(
                "PATH".into(),
                "/usr/bin:/bin".into(),
            )]),
        },
        80,
        24,
        1024,
        &[],
        0,
        &fixture.actor.store,
        |_| {},
    )
    .await
    .unwrap();
    let cleanup = StubbornTerminal(session.shell().unwrap());
    fixture.actor.sessions.insert("terminal".into(), session);
    tokio::time::timeout(Duration::from_secs(5), async {
        while !ready.exists() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("terminal should install its signal handlers");
    cleanup
}

#[cfg(unix)]
#[tokio::test]
async fn workspace_removal_waits_for_a_helper_forked_by_the_shell_hangup_handler() {
    let mut fixture = Fixture::new().await;
    let marker = fixture._root.path().join("late-helper-finished");
    let arguments = vec![
        marker.to_string_lossy().into_owned(),
        fixture.workspace.path.clone(),
    ];
    let shell = start_terminal(&mut fixture, r#"
        trap 'trap "" HUP TERM; /bin/sh -c '\''sleep 1; mkdir -p "$2"; : > "$2/late-write"; : > "$1"'\'' helper "$2" "$3" </dev/null >/dev/null 2>&1 & exit 0' HUP
        : > "$1"
        while :; do sleep 1; done
    "#, arguments).await;
    let response = fixture
        .request(
            "workspace.removeManaged",
            json!({"id": "workspace", "closeSessions": true}),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    assert!(
        marker.exists(),
        "deletion returned while the reparented shutdown helper was still running"
    );
    assert!(
        !std::path::Path::new(&fixture.workspace.path).exists(),
        "the shutdown helper recreated the deleted workspace"
    );
    tokio::time::timeout(Duration::from_secs(5), async {
        while shell.is_live() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the anchor must be released and reaped after cleanup");
}
