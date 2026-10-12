use std::future::Future;

use alera_core::runtime::{RuntimeStore, SshTarget, SshTargetLastStatus};
use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::remote_shell::{normalize_platform, RemoteShell};
use crate::ssh_bootstrap::validate_remote_runtime;
#[cfg(test)]
use crate::ssh_remote_command::shell_probe_order as connectivity_shell_order;

pub(crate) trait SshTargetProbe {
    fn probe_connectivity(
        &self,
        target: &SshTarget,
    ) -> impl Future<Output = Option<RemoteShell>> + Send;

    fn probe_runtime(
        &self,
        target: &SshTarget,
        platform: &str,
        install_dir: &str,
    ) -> impl Future<Output = bool> + Send;
}

pub(crate) struct LiveSshTargetProbe;

impl SshTargetProbe for LiveSshTargetProbe {
    async fn probe_connectivity(&self, target: &SshTarget) -> Option<RemoteShell> {
        crate::ssh_remote_command::probe_shell(target).await
    }

    async fn probe_runtime(&self, target: &SshTarget, platform: &str, install_dir: &str) -> bool {
        let shell = RemoteShell::from_platform(platform).unwrap_or(RemoteShell::Posix);
        validate_remote_runtime(target, shell, install_dir)
            .await
            .is_ok()
    }
}

pub(crate) async fn collect_ssh_target_status<P: SshTargetProbe>(
    store: &RuntimeStore,
    id: Option<&str>,
    probe: &P,
) -> Result<Value> {
    let refreshed = check_ssh_targets(store, id, probe).await?;
    match id {
        Some(_) => Ok(json!(refreshed.into_iter().next())),
        None => Ok(json!(refreshed)),
    }
}

/// Probes one target (or every target without an id) and persists what it
/// found as `lastStatus` / `lastCheckedAt`.
pub(crate) async fn check_ssh_targets<P: SshTargetProbe>(
    store: &RuntimeStore,
    id: Option<&str>,
    probe: &P,
) -> Result<Vec<SshTarget>> {
    let targets = match id {
        Some(id) => vec![store
            .find_ssh_target(id)
            .await?
            .ok_or_else(|| anyhow!("ssh target not found: {id}"))?],
        None => store.list_ssh_targets().await?,
    };
    let mut refreshed = Vec::with_capacity(targets.len());
    for target in targets {
        refreshed.push(refresh_ssh_target_status(store, target, probe).await?);
    }
    Ok(refreshed)
}

pub(crate) async fn refresh_ssh_target_status<P: SshTargetProbe>(
    store: &RuntimeStore,
    target: SshTarget,
    probe: &P,
) -> Result<SshTarget> {
    let status = probe_ssh_target_status(&target, probe).await;
    store.mark_ssh_target_checked(&target.id, status).await
}

pub(crate) async fn probe_ssh_target_status<P: SshTargetProbe>(
    target: &SshTarget,
    probe: &P,
) -> SshTargetLastStatus {
    let Some(shell) = probe.probe_connectivity(target).await else {
        return SshTargetLastStatus::Unreachable;
    };
    let Some(install_dir) = target
        .install_dir
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return SshTargetLastStatus::Reachable;
    };
    let platform = runtime_probe_platform(target, shell);
    if probe.probe_runtime(target, &platform, install_dir).await {
        SshTargetLastStatus::RuntimeReady
    } else {
        SshTargetLastStatus::Reachable
    }
}

fn configured_status_platform(target: &SshTarget) -> Option<String> {
    target
        .runtime_platform
        .as_deref()
        .or(target.platform.as_deref())
        .map(normalize_platform)
}

fn runtime_probe_platform(target: &SshTarget, shell: RemoteShell) -> String {
    match (configured_status_platform(target).as_deref(), shell) {
        // Windows OpenSSH with Git for Windows also answers `sh`: keep the
        // stored windows runtime path when that false POSIX answer wins.
        (Some("windows"), _) => "windows".to_string(),
        (Some(platform), RemoteShell::Posix) => platform.to_string(),
        (_, shell) => shell.default_platform().to_string(),
    }
}

#[cfg(test)]
#[path = "ssh_target_status_tests.rs"]
mod tests;
