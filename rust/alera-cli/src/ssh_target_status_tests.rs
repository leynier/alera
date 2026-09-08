use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use alera_core::runtime::{
    RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget, SshTargetLastStatus,
};
use chrono::Utc;

use super::{
    collect_ssh_target_status, probe_ssh_target_status, refresh_ssh_target_status,
    runtime_probe_platform, RemoteShellKind, SshTargetProbe,
};

struct MapProbe {
    connectivity: HashMap<String, Option<RemoteShellKind>>,
    runtime: HashMap<String, bool>,
    runtime_calls: Arc<AtomicUsize>,
}

impl SshTargetProbe for MapProbe {
    async fn probe_connectivity(&self, target: &SshTarget) -> Option<RemoteShellKind> {
        self.connectivity.get(&target.id).copied().flatten()
    }

    async fn probe_runtime(&self, target: &SshTarget, _platform: &str, _install_dir: &str) -> bool {
        self.runtime_calls.fetch_add(1, Ordering::SeqCst);
        self.runtime.get(&target.id).copied().unwrap_or(false)
    }
}

impl MapProbe {
    fn new() -> Self {
        Self {
            connectivity: HashMap::new(),
            runtime: HashMap::new(),
            runtime_calls: Arc::new(AtomicUsize::new(0)),
        }
    }

    fn with_target(
        mut self,
        id: &str,
        connectivity: Option<RemoteShellKind>,
        runtime: bool,
    ) -> Self {
        self.connectivity.insert(id.to_string(), connectivity);
        self.runtime.insert(id.to_string(), runtime);
        self
    }
}

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn target(id: &str) -> SshTarget {
    let now = Utc::now();
    SshTarget {
        id: id.to_string(),
        alias: id.to_string(),
        host: format!("{id}.example.test"),
        port: 22,
        username: "alera".to_string(),
        platform: None,
        arch: None,
        auth_kind: SshAuthKind::Agent,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::NotInstalled,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

#[test]
fn runtime_probe_platform_prefers_matching_configured_values() {
    let mut posix = target("remote");
    posix.runtime_platform = Some("Darwin".to_string());
    assert_eq!(
        runtime_probe_platform(&posix, RemoteShellKind::Posix),
        "macos"
    );

    let mut windows = target("remote");
    windows.platform = Some("windows".to_string());
    assert_eq!(
        runtime_probe_platform(&windows, RemoteShellKind::Windows),
        "windows"
    );
}

#[test]
fn runtime_probe_platform_falls_back_to_the_shell_that_answered() {
    let mut mismatched = target("remote");
    mismatched.platform = Some("windows".to_string());
    assert_eq!(
        runtime_probe_platform(&mismatched, RemoteShellKind::Posix),
        "linux"
    );
    assert_eq!(
        runtime_probe_platform(&target("remote"), RemoteShellKind::Windows),
        "windows"
    );
}

#[tokio::test]
async fn missing_target_keeps_the_existing_not_found_error() {
    let (_dir, store) = store().await;
    let probe = MapProbe::new();
    let error = collect_ssh_target_status(&store, Some("missing"), &probe)
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), "ssh target not found: missing");
}

#[tokio::test]
async fn unreachable_probe_stamps_last_status_and_checked_at() {
    let (_dir, store) = store().await;
    store.upsert_ssh_target(target("remote")).await.unwrap();
    let probe = MapProbe::new().with_target("remote", None, false);

    let value = collect_ssh_target_status(&store, Some("remote"), &probe)
        .await
        .unwrap();

    assert_eq!(value["lastStatus"], "unreachable");
    assert!(value["lastCheckedAt"].as_str().is_some());
    let stored = store.find_ssh_target("remote").await.unwrap().unwrap();
    assert_eq!(stored.last_status.as_deref(), Some("unreachable"));
    assert!(stored.last_checked_at.is_some());
}

#[tokio::test]
async fn reachable_host_without_install_dir_skips_the_runtime_probe() {
    let probe = MapProbe::new().with_target("remote", Some(RemoteShellKind::Posix), true);
    let status = probe_ssh_target_status(&target("remote"), &probe).await;
    assert_eq!(status, SshTargetLastStatus::Reachable);
    assert_eq!(probe.runtime_calls.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn reachable_host_with_failed_runtime_stays_reachable() {
    let mut remote = target("remote");
    remote.install_dir = Some("/home/alera/.alera/sidecar".to_string());
    remote.runtime_platform = Some("linux".to_string());
    let probe = MapProbe::new().with_target("remote", Some(RemoteShellKind::Posix), false);
    let status = probe_ssh_target_status(&remote, &probe).await;
    assert_eq!(status, SshTargetLastStatus::Reachable);
    assert_eq!(probe.runtime_calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn reachable_runtime_probe_stamps_runtime_ready() {
    let (_dir, store) = store().await;
    let mut remote = target("remote");
    remote.install_dir = Some("/home/alera/.alera/sidecar".to_string());
    remote.runtime_platform = Some("linux".to_string());
    store.upsert_ssh_target(remote).await.unwrap();
    let probe = MapProbe::new().with_target("remote", Some(RemoteShellKind::Posix), true);

    let refreshed = refresh_ssh_target_status(
        &store,
        store.find_ssh_target("remote").await.unwrap().unwrap(),
        &probe,
    )
    .await
    .unwrap();

    assert_eq!(
        refreshed.last_status.as_deref(),
        Some(SshTargetLastStatus::RuntimeReady.as_str())
    );
    assert!(refreshed.last_checked_at.is_some());
}

#[tokio::test]
async fn status_updates_last_checked_at_on_every_call() {
    let (_dir, store) = store().await;
    store.upsert_ssh_target(target("remote")).await.unwrap();
    let probe = MapProbe::new().with_target("remote", Some(RemoteShellKind::Posix), false);

    let first = collect_ssh_target_status(&store, Some("remote"), &probe)
        .await
        .unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    let second = collect_ssh_target_status(&store, Some("remote"), &probe)
        .await
        .unwrap();

    assert_eq!(first["lastStatus"], "reachable");
    assert_eq!(second["lastStatus"], "reachable");
    assert_ne!(first["lastCheckedAt"], second["lastCheckedAt"]);
}

#[tokio::test]
async fn list_status_probes_each_target_and_keeps_array_shape() {
    let (_dir, store) = store().await;
    store.upsert_ssh_target(target("alpha")).await.unwrap();
    let mut beta = target("beta");
    beta.install_dir = Some("~/.alera/sidecar".to_string());
    store.upsert_ssh_target(beta).await.unwrap();
    let probe = MapProbe::new()
        .with_target("alpha", None, false)
        .with_target("beta", Some(RemoteShellKind::Posix), true);

    let value = collect_ssh_target_status(&store, None, &probe)
        .await
        .unwrap();

    assert!(value.is_array());
    assert_eq!(value.as_array().unwrap().len(), 2);
    let by_id = value
        .as_array()
        .unwrap()
        .iter()
        .map(|item| {
            (
                item["id"].as_str().unwrap().to_string(),
                item["lastStatus"].as_str().unwrap().to_string(),
            )
        })
        .collect::<HashMap<_, _>>();
    assert_eq!(by_id.get("alpha").map(String::as_str), Some("unreachable"));
    assert_eq!(by_id.get("beta").map(String::as_str), Some("runtimeReady"));
}
