#![cfg(unix)]

use std::collections::HashSet;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use alera_core::runtime::{SshBootstrapStatus, SshTarget};
use serde_json::json;

use super::*;
use crate::terminal_host::host_link::tests::live::{stored_target, FAKE_SATELLITE};
use crate::terminal_host::host_link::tests::target;
use crate::terminal_host::host_link_backoff::RetrySchedule;
use crate::terminal_host::host_link_failure::AttachFailureKind;
use crate::terminal_host::host_link_slot::HostLinkStatus;

const REFUSED: &str =
    "echo 'ssh: connect to host lab.local port 22: Connection refused' >&2; exit 255";

fn fast_policy() -> HostLinkPolicy {
    HostLinkPolicy {
        retry: RetrySchedule {
            base: Duration::from_millis(20),
            factor: 2,
            cap: Duration::from_millis(200),
        },
        idle_close: Duration::from_millis(200),
        sweep_interval: Duration::from_secs(30),
        connect_stagger: Duration::from_millis(10),
    }
}

struct Fixture {
    _dir: tempfile::TempDir,
    registry: HostLinkRegistry,
    launches: Arc<AtomicUsize>,
    host: String,
    _rx: crate::terminal_host::server::ServerInboxReceiver,
}

async fn fixture_with(script: String, policy: HostLinkPolicy) -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let target = stored_target(&store).await;
    let (inbox, rx) = crate::terminal_host::ServerInbox::channel();
    let launches = Arc::new(AtomicUsize::new(0));
    let counter = launches.clone();
    let launcher: Arc<HostLinkLauncher> = Arc::new(move |_target: &SshTarget| {
        counter.fetch_add(1, Ordering::SeqCst);
        let mut command = alera_core::child_process::windowless_async_command("sh");
        command.arg("-c").arg(&script);
        Ok(command)
    });
    Fixture {
        _dir: dir,
        registry: HostLinkRegistry::with_policy(store, inbox, launcher, policy),
        launches,
        host: target.id,
        _rx: rx,
    }
}

async fn fixture(script: &str) -> Fixture {
    fixture_with(script.to_string(), fast_policy()).await
}

async fn wait_until(
    registry: &HostLinkRegistry,
    host: &str,
    what: &str,
    predicate: impl Fn(&HostLinkStatus) -> bool,
) -> HostLinkStatus {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let status = registry.status(host);
        if predicate(&status) {
            return status;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timed out waiting for {what}: {status:?}"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

fn attached(status: &HostLinkStatus) -> bool {
    matches!(status.state, HostLinkState::Attached { .. })
}

fn just(host: &str) -> HashSet<String> {
    HashSet::from([host.to_string()])
}

#[tokio::test]
async fn registry_connects_once_per_host_and_publishes_states() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let target = stored_target(&store).await;
    let (inbox, mut rx) = crate::terminal_host::ServerInbox::channel();
    let registry = HostLinkRegistry::with_launcher(
        store,
        inbox,
        crate::terminal_host::host_link::tests::live::fake_launcher(FAKE_SATELLITE),
    );
    assert_eq!(registry.state(&target.id), HostLinkState::Disconnected);

    let (a, b) = tokio::join!(registry.link(&target.id), registry.link(&target.id));
    let (a, b) = (a.unwrap(), b.unwrap());
    assert!(Arc::ptr_eq(&a, &b), "concurrent callers share one link");
    assert!(matches!(
        registry.state(&target.id),
        HostLinkState::Attached { .. }
    ));
    let snapshot = registry.snapshot();
    let link = &snapshot["links"][0];
    assert_eq!(link["hostId"], "lab");
    assert_eq!(link["state"], "attached");
    assert_eq!(link["generation"], 0);
    assert_eq!(link["desired"], false);
    assert_eq!(link["paused"], false);
    assert_eq!(link["explicit"], false);
    assert_eq!(link["retry"], json!(null));
    assert_eq!(link["failureKind"], json!(null));
    assert_eq!(link["satelliteVersion"], "9.9.9");
    assert!(link["idleCloseAt"].is_string(), "{link}");
    assert!(link["hubVersion"].is_string(), "{link}");

    let mut states = Vec::new();
    while let Ok(command) = rx.try_recv() {
        if let ServerCommand::HostLinkStateChanged {
            host_id,
            newly_attached,
        } = command
        {
            states.push((host_id, newly_attached));
        }
    }
    assert_eq!(
        states,
        vec![("lab".to_string(), false), ("lab".to_string(), true)]
    );

    registry.disconnect(&target.id).await;
    assert_eq!(registry.state(&target.id), HostLinkState::Disconnected);
    assert!(registry.status(&target.id).paused);
    assert!(a.is_closed());
}

#[tokio::test]
async fn registry_records_a_failed_attach() {
    let fixture =
        fixture("echo 'dev@lab.local: Permission denied (publickey).' >&2; exit 255").await;
    let error = fixture.registry.link(&fixture.host).await.unwrap_err();
    assert!(
        error.wire_message().contains("Permission denied"),
        "{error}"
    );
    let status = fixture.registry.status(&fixture.host);
    match &status.state {
        HostLinkState::Failed { error } => assert!(error.contains("Permission denied")),
        other => panic!("unexpected {other:?}"),
    }
    assert_eq!(status.failure_kind, Some(AttachFailureKind::Authentication));
    assert_eq!(status.retry, None, "a host nobody wants is not retried");
}

#[tokio::test]
async fn registry_refuses_hosts_that_are_not_bootstrapped() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let mut target = target("linux", Some("~/.alera/sidecar"));
    target.bootstrap_status = SshBootstrapStatus::NotInstalled;
    store.upsert_ssh_target(target.clone()).await.unwrap();
    let (inbox, _rx) = crate::terminal_host::ServerInbox::channel();
    let registry = HostLinkRegistry::with_launcher(
        store,
        inbox,
        crate::terminal_host::host_link::tests::live::fake_launcher(FAKE_SATELLITE),
    );
    registry.supervise(&just(&target.id), &HashSet::new());
    let error = registry.link(&target.id).await.unwrap_err();
    assert!(error.wire_message().contains("not bootstrapped"), "{error}");
    let status = registry.status(&target.id);
    assert_eq!(status.failure_kind, Some(AttachFailureKind::Configuration));
    assert_eq!(status.retry, None, "configuration failures do not retry");
    let missing = registry.link("ghost").await.unwrap_err();
    assert!(missing.wire_message().contains("not found"), "{missing}");
}

#[tokio::test]
async fn a_dropped_caller_does_not_leave_the_host_connecting() {
    let fixture = fixture(&format!("sleep 0.3\n{FAKE_SATELLITE}")).await;
    let gave_up = tokio::time::timeout(
        Duration::from_millis(1),
        fixture.registry.link(&fixture.host),
    )
    .await;
    assert!(gave_up.is_err(), "the caller timed out");
    assert_eq!(
        fixture.registry.state(&fixture.host),
        HostLinkState::Connecting
    );
    wait_until(&fixture.registry, &fixture.host, "attached", attached).await;
    assert_eq!(fixture.launches.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn a_disconnect_during_a_slow_attach_wins() {
    let fixture = fixture(&format!("sleep 0.5\n{FAKE_SATELLITE}")).await;
    let registry = fixture.registry.clone();
    let host = fixture.host.clone();
    let caller = tokio::spawn(async move { registry.link(&host).await });
    tokio::time::sleep(Duration::from_millis(50)).await;
    fixture.registry.disconnect(&fixture.host).await;
    let error = caller.await.unwrap().unwrap_err();
    assert!(error.wire_message().contains("cancelled"), "{error}");
    tokio::time::sleep(Duration::from_millis(800)).await;
    let status = fixture.registry.status(&fixture.host);
    assert_eq!(status.state, HostLinkState::Disconnected);
    assert_eq!(status.generation, 1);
    assert!(fixture.registry.attached_host_ids().is_empty());
}

#[tokio::test]
async fn a_desired_host_whose_ssh_fails_retries_with_a_growing_attempt() {
    let fixture = fixture(REFUSED).await;
    fixture
        .registry
        .supervise(&just(&fixture.host), &HashSet::new());
    let status = wait_until(&fixture.registry, &fixture.host, "third retry", |status| {
        status
            .retry
            .as_ref()
            .is_some_and(|retry| retry.attempt >= 3)
    })
    .await;
    assert!(status.desired);
    assert_eq!(status.failure_kind, Some(AttachFailureKind::Unreachable));
    assert!(fixture.launches.load(Ordering::SeqCst) >= 3);

    fixture.registry.disconnect(&fixture.host).await;
    let paused = fixture.registry.status(&fixture.host);
    assert!(paused.paused);
    assert_eq!(paused.retry, None);
    let launches = fixture.launches.load(Ordering::SeqCst);
    tokio::time::sleep(Duration::from_millis(400)).await;
    fixture
        .registry
        .supervise(&just(&fixture.host), &HashSet::new());
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(
        fixture.launches.load(Ordering::SeqCst),
        launches,
        "a paused host is left alone"
    );
}

#[tokio::test]
async fn idle_links_close_unless_the_user_asked_for_them() {
    let fixture = fixture(FAKE_SATELLITE).await;
    fixture.registry.link(&fixture.host).await.unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    let busy = just(&fixture.host);
    fixture.registry.supervise(&HashSet::new(), &busy);
    assert!(
        attached(&fixture.registry.status(&fixture.host)),
        "a host with hub sessions stays linked"
    );
    fixture.registry.supervise(&HashSet::new(), &HashSet::new());
    let closed = fixture.registry.status(&fixture.host);
    assert_eq!(closed.state, HostLinkState::Disconnected, "{closed:?}");
    assert_eq!(closed.failure_kind, None);
    assert_eq!(closed.retry, None);

    fixture
        .registry
        .connect_explicitly(&fixture.host)
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    fixture.registry.supervise(&HashSet::new(), &HashSet::new());
    let explicit = fixture.registry.status(&fixture.host);
    assert!(attached(&explicit), "{explicit:?}");
    assert!(explicit.explicit);
    assert_eq!(explicit.idle_close_at, None);
}

#[tokio::test]
async fn a_close_during_a_restart_is_expected() {
    let fixture = fixture(FAKE_SATELLITE).await;
    let link = fixture
        .registry
        .connect_explicitly(&fixture.host)
        .await
        .unwrap();
    fixture.registry.begin_restart(&fixture.host);
    link.close().await;
    assert!(
        fixture
            .registry
            .wait_closed(&fixture.host, Duration::from_secs(1))
            .await
    );
    let restarting = wait_until(
        &fixture.registry,
        &fixture.host,
        "restart retry",
        |status| status.retry.is_some(),
    )
    .await;
    assert_eq!(restarting.state, HostLinkState::Disconnected);
    assert_eq!(restarting.failure_kind, None);
    assert_eq!(restarting.retry.as_ref().unwrap().attempt, 0);
    wait_until(&fixture.registry, &fixture.host, "reattached", attached).await;
    fixture.registry.end_restart(&fixture.host);
    assert_eq!(fixture.launches.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn request_connect_does_nothing_while_an_attempt_runs() {
    let fixture = fixture(&format!("sleep 0.3\n{FAKE_SATELLITE}")).await;
    for _ in 0..3 {
        fixture.registry.request_connect(&fixture.host);
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(fixture.launches.load(Ordering::SeqCst), 1);
    wait_until(&fixture.registry, &fixture.host, "attached", attached).await;
    fixture.registry.request_connect(&fixture.host);
    assert_eq!(fixture.launches.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn the_supervisor_connects_desired_hosts() {
    let fixture = fixture(FAKE_SATELLITE).await;
    fixture
        .registry
        .supervise(&just(&fixture.host), &HashSet::new());
    let status = wait_until(&fixture.registry, &fixture.host, "attached", attached).await;
    assert!(status.desired);
    assert_eq!(status.idle_close_at, None, "a desired link never idles out");
}

#[tokio::test]
async fn the_mirror_cache_belongs_to_one_link() {
    let fixture = fixture(FAKE_SATELLITE).await;
    let first = fixture
        .registry
        .connect_explicitly(&fixture.host)
        .await
        .unwrap();
    let record = json!({"id": "task"});
    fixture
        .registry
        .note_mirrored(&fixture.host, &first, "task", 7, record.clone());
    assert_eq!(
        fixture.registry.mirrored(&fixture.host, &first, "task", 7),
        Some(record)
    );
    assert_eq!(
        fixture.registry.mirrored(&fixture.host, &first, "task", 8),
        None
    );

    fixture.registry.disconnect(&fixture.host).await;
    let second = fixture
        .registry
        .connect_explicitly(&fixture.host)
        .await
        .unwrap();
    assert!(!Arc::ptr_eq(&first, &second));
    assert_eq!(
        fixture.registry.mirrored(&fixture.host, &second, "task", 7),
        None
    );
    assert_eq!(
        fixture.registry.mirrored(&fixture.host, &first, "task", 7),
        None
    );
}
