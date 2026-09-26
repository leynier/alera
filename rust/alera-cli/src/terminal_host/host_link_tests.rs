use alera_core::runtime::{SshAuthKind, SshBootstrapStatus, SshTarget};
use chrono::Utc;
use serde_json::json;

use super::*;

fn target(platform: &str, install_dir: Option<&str>) -> SshTarget {
    let now = Utc::now();
    SshTarget {
        id: "lab".into(),
        alias: "Lab".into(),
        host: "lab.local".into(),
        port: 22,
        username: "dev".into(),
        platform: Some(platform.into()),
        arch: None,
        auth_kind: SshAuthKind::Agent,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: install_dir.map(str::to_string),
        projects_dir: None,
        runtime_version: None,
        runtime_platform: Some(platform.into()),
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::Installed,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

#[test]
fn posix_attach_command_expands_tilde_and_uses_the_sidecar_wrapper() {
    let command = attach_remote_command("~/.alera/sidecar", false);
    assert!(command.starts_with("sh -lc '"));
    assert!(command.contains("install='\"'\"'~/.alera/sidecar'\"'\"'"));
    assert!(command.contains("exec \"$install/bin/alera\" runtime-attach --stdio"));
}

#[test]
fn windows_attach_command_avoids_powershell_and_quotes_the_wrapper() {
    let command = attach_remote_command("%LOCALAPPDATA%\\Alera\\runtime", true);
    assert_eq!(
        command,
        "\"%LOCALAPPDATA%\\Alera\\runtime\\bin\\alera.cmd\" runtime-attach --stdio"
    );
    assert!(!command.to_lowercase().contains("powershell"));
    let forward = attach_remote_command("C:/Users/dev/Alera/runtime/", true);
    assert!(forward.starts_with("\"C:\\Users\\dev\\Alera\\runtime\\bin\\alera.cmd\""));
}

#[test]
fn attach_arguments_disable_pty_and_keep_alive_the_session() {
    let args = attach_ssh_arguments(&target("linux", Some("~/.alera/sidecar"))).unwrap();
    assert!(args.contains(&"-T".to_string()));
    assert!(args.contains(&"ServerAliveInterval=15".to_string()));
    assert!(args.contains(&"BatchMode=yes".to_string()));
    let destination = args.iter().position(|a| a == "dev@lab.local").unwrap();
    assert!(args[destination + 1].starts_with("sh -lc "));
    assert_eq!(destination + 2, args.len());
}

#[test]
fn attach_arguments_require_a_bootstrapped_target() {
    let error = attach_ssh_arguments(&target("linux", None)).unwrap_err();
    assert!(error.wire_message().contains("bootstrap"), "{error}");
}

#[test]
fn parse_attached_accepts_only_the_attachment_event() {
    let line = json!({
        "event": crate::runtime_attach::ATTACHED_EVENT,
        "payload": {
            "runtimeDir": "/home/dev/.alera/sidecar/data",
            "platform": "linux",
            "arch": "x86_64",
            "hostVersion": "0.9.0",
            "runtimeCapabilities": ["runtimeStore"],
        }
    })
    .to_string();
    let attachment = parse_attached(&line).unwrap();
    assert_eq!(attachment.platform, "linux");
    assert_eq!(
        attachment.runtime_capabilities,
        vec!["runtimeStore".to_string()]
    );
    assert!(parse_attached("{\"event\":\"other\",\"payload\":{}}").is_none());
    assert!(parse_attached("not json").is_none());
    assert!(parse_attached("{\"id\":1,\"ok\":true}").is_none());
}

#[test]
fn response_result_preserves_error_shapes() {
    assert_eq!(
        response_result(&json!({"id": 1, "ok": true, "payload": {"a": 1}})).unwrap(),
        json!({"a": 1})
    );
    assert_eq!(
        response_result(&json!({"id": 1, "ok": true})).unwrap(),
        Value::Null
    );
    match response_result(&json!({"id": 1, "ok": false, "error": "FormatException: bad"})) {
        Err(HostError::Format(message)) => assert_eq!(message, "bad"),
        other => panic!("unexpected {other:?}"),
    }
    match response_result(&json!({
        "id": 1, "ok": false, "error": "busy", "errorCode": "conflict", "errorDetails": {"x": 1}
    })) {
        Err(HostError::Conflict { code, details, .. }) => {
            assert_eq!(code, "conflict");
            assert_eq!(details, json!({"x": 1}));
        }
        other => panic!("unexpected {other:?}"),
    }
    match response_result(&json!({"id": 1, "ok": false, "error": "nope"})) {
        Err(HostError::State(message)) => assert_eq!(message, "nope"),
        other => panic!("unexpected {other:?}"),
    }
}

#[test]
fn host_link_state_serializes_with_a_state_tag() {
    let attached = HostLinkState::Attached {
        attachment: HostLinkAttachment {
            runtime_dir: "/data".into(),
            platform: "macos".into(),
            arch: "aarch64".into(),
            host_version: Some("1.0.0".into()),
            runtime_capabilities: vec!["runtimeStore".into()],
        },
    };
    let value = serde_json::to_value(&attached).unwrap();
    assert_eq!(value["state"], "attached");
    assert_eq!(value["attachment"]["platform"], "macos");
    let failed = serde_json::to_value(HostLinkState::Failed {
        error: "boom".into(),
    })
    .unwrap();
    assert_eq!(failed, json!({"state": "failed", "error": "boom"}));
    assert_eq!(
        serde_json::to_value(HostLinkState::Disconnected).unwrap(),
        json!({"state": "disconnected"})
    );
}

#[cfg(unix)]
mod live {
    use std::sync::Arc;

    use alera_core::runtime::RuntimeStore;
    use tokio::sync::mpsc;

    use super::*;
    use crate::terminal_host::host_link_registry::HostLinkRegistry;
    use crate::terminal_host::server::ServerCommand;

    /// A shell stand-in for `runtime-attach`: announces, pushes one event,
    /// then echoes every request id back as an ok response.
    const FAKE_SATELLITE: &str = r#"
printf '%s\n' '{"event":"hostLink.attached","payload":{"runtimeDir":"/sat/data","platform":"linux","arch":"x86_64","hostVersion":"9.9.9","runtimeCapabilities":["runtimeStore","remoteSatelliteV1"]}}'
printf '%s\n' '{"event":"workspacesChanged","payload":{"projectId":"p1"}}'
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"type":"boom"'*) printf '{"id":%s,"ok":false,"error":"exploded"}\n' "$id" ;;
    *) printf '{"id":%s,"ok":true,"payload":{"echo":%s}}\n' "$id" "$id" ;;
  esac
done
"#;

    fn fake_launcher(script: &'static str) -> Arc<HostLinkLauncher> {
        Arc::new(move |_target: &SshTarget| {
            let mut command = alera_core::child_process::windowless_async_command("sh");
            command.arg("-c").arg(script);
            Ok(command)
        })
    }

    async fn stored_target(store: &RuntimeStore) -> SshTarget {
        let target = target("linux", Some("~/.alera/sidecar"));
        store.upsert_ssh_target(target.clone()).await.unwrap();
        target
    }

    #[tokio::test]
    async fn link_round_trips_requests_forwards_events_and_reports_close() {
        let (inbox, mut rx) = mpsc::unbounded_channel::<ServerCommand>();
        let target = target("linux", Some("~/.alera/sidecar"));
        let link = HostLink::connect_with(&target, inbox, fake_launcher(FAKE_SATELLITE).as_ref())
            .await
            .unwrap();
        assert_eq!(link.attachment().host_version.as_deref(), Some("9.9.9"));
        assert_eq!(link.attachment().platform, "linux");

        let first = link
            .request_with_timeout("status.get", json!({}), Duration::from_secs(5))
            .await
            .unwrap();
        assert_eq!(first, json!({"echo": 1}));
        let second = link
            .request_with_timeout("project.list", json!({}), Duration::from_secs(5))
            .await
            .unwrap();
        assert_eq!(second, json!({"echo": 2}));
        let failure = link
            .request_with_timeout("boom", json!({}), Duration::from_secs(5))
            .await
            .unwrap_err();
        assert_eq!(failure.wire_message(), "exploded");

        let ServerCommand::HostLinkEvent { host_id, event } = rx.recv().await.unwrap() else {
            panic!("expected the forwarded satellite event first");
        };
        assert_eq!(host_id, "lab");
        assert_eq!(event["event"], "workspacesChanged");

        link.close().await;
        assert!(link.is_closed());
        let closed = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                match rx.recv().await.unwrap() {
                    ServerCommand::HostLinkClosed { host_id, .. } => break host_id,
                    _ => continue,
                }
            }
        })
        .await
        .unwrap();
        assert_eq!(closed, "lab");
        let after = link
            .request_with_timeout("status.get", json!({}), Duration::from_secs(1))
            .await
            .unwrap_err();
        assert!(after.wire_message().contains("closed"), "{after}");
    }

    #[tokio::test]
    async fn registry_connects_once_per_host_and_publishes_states() {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        let target = stored_target(&store).await;
        let (inbox, mut rx) = mpsc::unbounded_channel::<ServerCommand>();
        let registry = HostLinkRegistry::with_launcher(store, inbox, fake_launcher(FAKE_SATELLITE));
        assert_eq!(registry.state(&target.id), HostLinkState::Disconnected);

        let (a, b) = tokio::join!(registry.link(&target.id), registry.link(&target.id));
        let (a, b) = (a.unwrap(), b.unwrap());
        assert!(Arc::ptr_eq(&a, &b), "concurrent callers share one link");
        assert!(matches!(
            registry.state(&target.id),
            HostLinkState::Attached { .. }
        ));
        let snapshot = registry.snapshot();
        assert_eq!(snapshot["links"][0]["hostId"], "lab");
        assert_eq!(snapshot["links"][0]["state"], "attached");

        let mut states = Vec::new();
        while let Ok(command) = rx.try_recv() {
            if let ServerCommand::HostLinkStateChanged { host_id } = command {
                states.push(host_id);
            }
        }
        assert_eq!(states, vec!["lab".to_string(), "lab".to_string()]);

        registry.disconnect(&target.id).await;
        assert_eq!(registry.state(&target.id), HostLinkState::Disconnected);
        assert!(a.is_closed());
    }

    #[tokio::test]
    async fn registry_records_a_failed_attach() {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        let target = stored_target(&store).await;
        let (inbox, _rx) = mpsc::unbounded_channel::<ServerCommand>();
        let registry = HostLinkRegistry::with_launcher(
            store,
            inbox,
            fake_launcher("echo 'permission denied (publickey)' >&2; exit 255"),
        );
        let error = registry.link(&target.id).await.unwrap_err();
        assert!(
            error.wire_message().contains("permission denied"),
            "{error}"
        );
        match registry.state(&target.id) {
            HostLinkState::Failed { error } => assert!(error.contains("permission denied")),
            other => panic!("unexpected {other:?}"),
        }
    }

    #[tokio::test]
    async fn registry_refuses_hosts_that_are_not_bootstrapped() {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        let mut target = target("linux", Some("~/.alera/sidecar"));
        target.bootstrap_status = SshBootstrapStatus::NotInstalled;
        store.upsert_ssh_target(target.clone()).await.unwrap();
        let (inbox, _rx) = mpsc::unbounded_channel::<ServerCommand>();
        let registry = HostLinkRegistry::with_launcher(store, inbox, fake_launcher(FAKE_SATELLITE));
        let error = registry.link(&target.id).await.unwrap_err();
        assert!(error.wire_message().contains("not bootstrapped"), "{error}");
        let missing = registry.link("ghost").await.unwrap_err();
        assert!(missing.wire_message().contains("not found"), "{missing}");
    }
}
