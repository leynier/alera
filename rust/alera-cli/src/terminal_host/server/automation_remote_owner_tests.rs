use std::sync::Arc;
use std::time::{Duration, Instant};

use super::*;
use crate::terminal_host::host_link::HostLinkLauncher;
use crate::terminal_host::host_link_registry::HostLinkRegistry;

/// A host whose ssh never answers must not hold up reconciliation: the run is
/// marked unreachable for this tick while the connect continues on its own.
#[tokio::test]
async fn reconciliation_never_waits_on_a_slow_host_link() {
    let mut fixture = harness().await;
    let run = super::experience::owned_run(&mut fixture).await;
    sqlx::query("UPDATE workspaces SET hostId = 'lab' WHERE id = 'workspace-1'")
        .execute(fixture.actor.runtime_store.pool())
        .await
        .unwrap();
    let target = crate::terminal_host::host_link::tests::target("linux", Some("~/.alera/sidecar"));
    fixture
        .actor
        .runtime_store
        .upsert_ssh_target(target)
        .await
        .unwrap();
    let launcher: Arc<HostLinkLauncher> = Arc::new(|_target| {
        let mut command = alera_core::child_process::windowless_async_command("sh");
        command.arg("-c").arg("sleep 5");
        Ok(command)
    });
    fixture.actor.host_links = HostLinkRegistry::with_launcher(
        fixture.actor.runtime_store.clone(),
        fixture.actor.inbox.clone(),
        launcher,
    );

    let started = Instant::now();
    fixture.actor.reconcile_automation_runs().await;
    assert!(
        started.elapsed() < Duration::from_secs(1),
        "reconciliation waited {:?} on the host link",
        started.elapsed()
    );
    let reconciled = fixture
        .actor
        .runtime_store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .unwrap();
    let recovery = reconciled.recovery.expect("the run is reconnecting");
    assert_eq!(recovery.status, "reconnecting");
    assert_eq!(recovery.code.as_deref(), Some("hostUnreachable"));
    assert!(reconciled.owner_reserved);
    assert_eq!(
        fixture.actor.host_links.state("lab"),
        crate::terminal_host::host_link::HostLinkState::Connecting,
        "the connect keeps going after the tick"
    );
}
