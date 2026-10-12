#![cfg(unix)]

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use alera_core::runtime::{RuntimeStore, SshTarget};

use super::ssh_bootstrap_restart::*;
use crate::terminal_host::host_link::tests::live::stored_target;
use crate::terminal_host::host_link::{HostLinkLauncher, HostLinkState};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

/// A satellite whose version comes from a file. `host.shutdown` is logged,
/// answered, and, when an `upgrade` file exists, installs that version for the
/// next attach before exiting, as a real update leaves `current` behind.
fn fake_satellite(dir: &Path) -> String {
    let version = dir.join("version");
    let upgrade = dir.join("upgrade");
    let shutdowns = dir.join("shutdowns");
    format!(
        r#"
version=$(cat '{version}')
printf '{{"event":"hostLink.attached","payload":{{"runtimeDir":"/sat/data","platform":"linux","arch":"x86_64","hostVersion":"%s","runtimeCapabilities":[]}}}}\n' "$version"
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"type":"host.shutdown"'*)
      printf '%s\n' "$line" >> '{shutdowns}'
      printf '{{"id":%s,"ok":true,"payload":{{"stopped":true}}}}\n' "$id"
      if [ -f '{upgrade}' ]; then cp '{upgrade}' '{version}'; fi
      exit 0 ;;
    *) printf '{{"id":%s,"ok":true,"payload":{{}}}}\n' "$id" ;;
  esac
done
"#,
        version = version.display(),
        upgrade = upgrade.display(),
        shutdowns = shutdowns.display(),
    )
}

#[derive(Default)]
struct FakeRemote {
    installed: Option<String>,
    prunes: Mutex<Vec<Option<String>>>,
}

#[async_trait::async_trait]
impl RestartRemote for FakeRemote {
    async fn installed_version(&self, _target: &SshTarget) -> anyhow::Result<Option<String>> {
        Ok(self.installed.clone())
    }

    async fn prune(&self, _target: &SshTarget, keep: Option<&str>) -> anyhow::Result<()> {
        self.prunes.lock().unwrap().push(keep.map(str::to_string));
        Ok(())
    }
}

struct Fixture {
    dir: tempfile::TempDir,
    registry: HostLinkRegistry,
    target: SshTarget,
    _rx: crate::terminal_host::server::ServerInboxReceiver,
}

impl Fixture {
    async fn new(version: &str, upgrade: Option<&str>) -> Self {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("version"), version).unwrap();
        if let Some(upgrade) = upgrade {
            std::fs::write(dir.path().join("upgrade"), upgrade).unwrap();
        }
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        let target = stored_target(&store).await;
        let (inbox, rx) = crate::terminal_host::ServerInbox::channel();
        let script = fake_satellite(dir.path());
        let launcher: Arc<HostLinkLauncher> = Arc::new(move |_target: &SshTarget| {
            let mut command = alera_core::child_process::windowless_async_command("sh");
            command.arg("-c").arg(&script);
            Ok(command)
        });
        Self {
            registry: HostLinkRegistry::with_launcher(store, inbox, launcher),
            target,
            dir,
            _rx: rx,
        }
    }

    fn shutdowns(&self) -> Vec<String> {
        let path: PathBuf = self.dir.path().join("shutdowns");
        std::fs::read_to_string(path)
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn restarting(&self) -> bool {
        self.registry.slot(&self.target.id).lock().restarting
    }
}

fn fast() -> RestartTiming {
    RestartTiming {
        shutdown_answer: Duration::from_secs(5),
        link_close: Duration::from_secs(5),
        attach_attempts: 3,
        attach_interval: Duration::from_millis(20),
    }
}

#[tokio::test]
async fn restarts_onto_the_installed_version_and_then_prunes() {
    let fixture = Fixture::new("1.4.0", Some("1.5.0")).await;
    let old = fixture.registry.link(&fixture.target.id).await.unwrap();
    assert_eq!(old.attachment().host_version.as_deref(), Some("1.4.0"));
    let remote = FakeRemote {
        installed: Some("1.5.0".into()),
        ..Default::default()
    };
    let mut stages = Vec::new();
    let version = restart_satellite_runtime(
        &fixture.registry,
        &fixture.target,
        false,
        Some("1.5.0-linux-x64".into()),
        &remote,
        fast(),
        |stage, _| stages.push(stage.to_string()),
    )
    .await
    .unwrap();

    assert_eq!(version.as_deref(), Some("1.5.0"));
    assert_eq!(stages, vec![RESTART_STAGE, PRUNE_STAGE]);
    let shutdowns = fixture.shutdowns();
    assert_eq!(shutdowns.len(), 1, "{shutdowns:?}");
    assert!(shutdowns[0].contains(r#""force":false"#), "{shutdowns:?}");
    assert!(old.is_closed(), "the old runtime's link is gone");
    let HostLinkState::Attached { attachment } = fixture.registry.state(&fixture.target.id) else {
        panic!("the new runtime is attached");
    };
    assert_eq!(attachment.host_version.as_deref(), Some("1.5.0"));
    assert_eq!(
        fixture
            .registry
            .status(&fixture.target.id)
            .satellite_version
            .as_deref(),
        Some("1.5.0")
    );
    assert_eq!(
        *remote.prunes.lock().unwrap(),
        vec![Some("1.5.0-linux-x64".to_string())]
    );
    assert!(!fixture.restarting(), "the restart flag is cleared");
}

#[tokio::test]
async fn force_reaches_the_satellite_and_an_unknown_installed_version_accepts_any_new_attach() {
    let fixture = Fixture::new("1.4.0", Some("1.4.1")).await;
    let remote = FakeRemote::default();
    let version = restart_satellite_runtime(
        &fixture.registry,
        &fixture.target,
        true,
        None,
        &remote,
        fast(),
        |_, _| {},
    )
    .await
    .unwrap();
    assert_eq!(version.as_deref(), Some("1.4.1"));
    assert!(fixture.shutdowns()[0].contains(r#""force":true"#));
    assert_eq!(*remote.prunes.lock().unwrap(), vec![None]);
}

#[tokio::test]
async fn a_runtime_that_keeps_the_old_version_exhausts_the_attempts() {
    let fixture = Fixture::new("1.4.0", None).await;
    let remote = FakeRemote {
        installed: Some("1.5.0".into()),
        ..Default::default()
    };
    let mut stages = Vec::new();
    let error = restart_satellite_runtime(
        &fixture.registry,
        &fixture.target,
        false,
        None,
        &remote,
        fast(),
        |stage, _| stages.push(stage.to_string()),
    )
    .await
    .unwrap_err();

    let message = error.wire_message();
    assert!(
        message.starts_with("The runtime on Lab still reports version 1.4.0 after the update."),
        "{message}"
    );
    assert!(message.contains("Expected 1.5.0"), "{message}");
    assert_eq!(
        stages,
        vec![RESTART_STAGE],
        "no prune after a failed restart"
    );
    assert!(remote.prunes.lock().unwrap().is_empty());
    assert!(
        !fixture.restarting(),
        "a failed restart clears the flag too"
    );
}

fn named(alias: &str) -> SshTarget {
    let mut target = crate::terminal_host::host_link::tests::target("linux", Some("~/sidecar"));
    target.alias = alias.into();
    target
}

#[test]
fn busy_hosts_are_refused_with_the_sessions_that_would_close() {
    let target = named("Studio Mac");
    assert!(host_busy_conflict(&target, Vec::new()).is_none());

    let conflict = host_busy_conflict(&target, vec!["s2".into(), "s1".into()]).unwrap();
    let response = conflict.wire_response(7);
    assert_eq!(response["errorCode"], "hostBusy");
    assert_eq!(
        response["error"],
        "Studio Mac has 2 open terminals. Restarting its Alera runtime closes them."
    );
    assert_eq!(response["errorDetails"]["hostId"], target.id);
    assert_eq!(response["errorDetails"]["alias"], "Studio Mac");
    assert_eq!(response["errorDetails"]["activeSessions"], 2);
    assert_eq!(
        response["errorDetails"]["sessionIds"],
        serde_json::json!(["s1", "s2"])
    );

    let single = host_busy_conflict(&target, vec!["s1".into()]).unwrap();
    assert!(single.wire_message().contains("has 1 open terminal."));
}

#[test]
fn the_installed_version_dir_is_named_like_the_install_script_names_it() {
    let mut target = named("Lab");
    assert_eq!(installed_version_dir(&target), None);
    target.runtime_version = Some("1.5.0".into());
    target.runtime_platform = Some("linux".into());
    target.runtime_arch = Some("arm64".into());
    assert_eq!(
        installed_version_dir(&target).as_deref(),
        Some("1.5.0-linux-arm64")
    );
}
