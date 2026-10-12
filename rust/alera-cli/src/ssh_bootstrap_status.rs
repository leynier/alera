//! What the hub stores about an install while it runs and once it stops.

use alera_core::runtime::{
    RuntimeStore, SshBootstrapStatus, SshTarget, SshTargetBootstrapStateUpdate,
};
use anyhow::Result;

use super::find_target;

/// The stored status once an install stops without succeeding. A host that
/// already had a runtime keeps `installed`: the old runtime is still there and
/// connectable, and every remote verb refuses a host that is not installed.
pub(super) fn status_after_interrupted_install(
    previous: SshBootstrapStatus,
    outcome: SshBootstrapStatus,
) -> SshBootstrapStatus {
    if previous == SshBootstrapStatus::Installed {
        SshBootstrapStatus::Installed
    } else {
        outcome
    }
}

/// The stored status while an install runs. An installed host stays
/// `installed` for the whole job, so a cancel or a hub restart mid-update
/// still finds the old runtime connectable.
pub(super) fn status_while_installing(previous: SshBootstrapStatus) -> SshBootstrapStatus {
    if previous == SshBootstrapStatus::Installed {
        SshBootstrapStatus::Installed
    } else {
        SshBootstrapStatus::Installing
    }
}

/// Records an install in flight. An update of an installed host leaves the
/// stored status alone and lets the job carry the in-flight state, so a hub
/// that restarts mid-update still finds the host installed.
pub(crate) async fn mark_ssh_bootstrap_installing(
    store: &RuntimeStore,
    target_id: &str,
) -> Result<SshTarget> {
    let target = find_target(store, target_id).await?;
    if status_while_installing(target.bootstrap_status) == SshBootstrapStatus::Installed {
        return Ok(target);
    }
    store
        .update_ssh_target_bootstrap_state(
            target_id,
            SshTargetBootstrapStateUpdate {
                status: SshBootstrapStatus::Installing,
                install_dir: None,
                runtime_version: None,
                runtime_platform: None,
                runtime_arch: None,
                last_error: None,
            },
        )
        .await
}

pub(crate) async fn cancel_ssh_bootstrap(
    store: &RuntimeStore,
    target_id: &str,
) -> Result<SshTarget> {
    let target = find_target(store, target_id).await?;
    if target.bootstrap_status == SshBootstrapStatus::Installed {
        return Ok(target);
    }
    store
        .update_ssh_target_bootstrap_state(
            target_id,
            SshTargetBootstrapStateUpdate {
                status: SshBootstrapStatus::Cancelled,
                install_dir: None,
                runtime_version: None,
                runtime_platform: None,
                runtime_arch: None,
                last_error: None,
            },
        )
        .await
}

#[cfg(test)]
#[path = "ssh_bootstrap_status_tests.rs"]
mod tests;
