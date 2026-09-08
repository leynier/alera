use std::future::Future;

use alera_core::runtime::{RuntimeStore, SshTarget, SshTargetLastStatus};
use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::ssh_bootstrap::{
    normalize_platform, ssh_target_answers_posix, ssh_target_answers_windows,
    validate_remote_runtime,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RemoteShellKind {
    Posix,
    Windows,
}

pub(crate) trait SshTargetProbe {
    fn probe_connectivity(
        &self,
        target: &SshTarget,
    ) -> impl Future<Output = Option<RemoteShellKind>> + Send;

    fn probe_runtime(
        &self,
        target: &SshTarget,
        platform: &str,
        install_dir: &str,
    ) -> impl Future<Output = bool> + Send;
}

pub(crate) struct LiveSshTargetProbe;

impl SshTargetProbe for LiveSshTargetProbe {
    async fn probe_connectivity(&self, target: &SshTarget) -> Option<RemoteShellKind> {
        if ssh_target_answers_posix(target).await {
            return Some(RemoteShellKind::Posix);
        }
        if ssh_target_answers_windows(target).await {
            return Some(RemoteShellKind::Windows);
        }
        None
    }

    async fn probe_runtime(&self, target: &SshTarget, platform: &str, install_dir: &str) -> bool {
        validate_remote_runtime(target, platform, install_dir)
            .await
            .is_ok()
    }
}

pub(crate) async fn collect_ssh_target_status<P: SshTargetProbe>(
    store: &RuntimeStore,
    id: Option<&str>,
    probe: &P,
) -> Result<Value> {
    if let Some(id) = id {
        let target = store
            .find_ssh_target(id)
            .await?
            .ok_or_else(|| anyhow!("ssh target not found: {id}"))?;
        let target = refresh_ssh_target_status(store, target, probe).await?;
        return Ok(json!(target));
    }
    let targets = store.list_ssh_targets().await?;
    let mut refreshed = Vec::with_capacity(targets.len());
    for target in targets {
        refreshed.push(refresh_ssh_target_status(store, target, probe).await?);
    }
    Ok(json!(refreshed))
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

fn runtime_probe_platform(target: &SshTarget, shell: RemoteShellKind) -> String {
    let configured = target
        .runtime_platform
        .as_deref()
        .or(target.platform.as_deref())
        .map(normalize_platform);
    match (configured.as_deref(), shell) {
        (Some("windows"), RemoteShellKind::Windows) => "windows".to_string(),
        (Some(platform), RemoteShellKind::Posix) if platform != "windows" => platform.to_string(),
        (_, RemoteShellKind::Windows) => "windows".to_string(),
        (_, RemoteShellKind::Posix) => "linux".to_string(),
    }
}

#[cfg(test)]
#[path = "ssh_target_status_tests.rs"]
mod tests;
