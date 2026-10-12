//! Restarting a host's runtime onto the version just installed: the follow
//! through of Update Runtime (`sshTarget.bootstrap.start {restartRuntime}`)
//! and of `sshTarget.restartRuntime`.
//!
//! The old runtime is stopped with `host.shutdown` over the host link rather
//! than `host.restart`, because a restart relaunches the running executable,
//! which is the old binary. The next `runtime-attach` goes through
//! `bin/alera` to `current/alera`, so it starts the new one. Everything here
//! awaits the link and runs in a spawned task, never on the actor.

use std::time::Duration;

use alera_core::runtime::SshTarget;
use async_trait::async_trait;
use serde_json::json;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link::HostLink;
use crate::terminal_host::host_link_registry::HostLinkRegistry;

pub(super) const RESTART_STAGE: &str = "restart";
pub(super) const PRUNE_STAGE: &str = "prune";
const STATUS_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, Copy)]
pub(super) struct RestartTiming {
    /// How long the old runtime has to answer `host.shutdown`.
    pub(super) shutdown_answer: Duration,
    /// How long it has to close the link once it answered.
    pub(super) link_close: Duration,
    pub(super) attach_attempts: u32,
    pub(super) attach_interval: Duration,
}

impl Default for RestartTiming {
    fn default() -> Self {
        Self {
            shutdown_answer: Duration::from_secs(30),
            link_close: Duration::from_secs(20),
            attach_attempts: 10,
            attach_interval: Duration::from_millis(1500),
        }
    }
}

/// The ssh commands a restart runs besides the link, injectable for tests.
#[async_trait]
pub(super) trait RestartRemote: Send + Sync {
    /// The version the installed binary reports, when it can be read.
    async fn installed_version(&self, target: &SshTarget) -> anyhow::Result<Option<String>>;
    async fn prune(&self, target: &SshTarget, keep: Option<&str>) -> anyhow::Result<()>;
}

pub(super) struct SshRestartRemote;

#[async_trait]
impl RestartRemote for SshRestartRemote {
    async fn installed_version(&self, target: &SshTarget) -> anyhow::Result<Option<String>> {
        crate::ssh_bootstrap::installed_runtime_version(target).await
    }

    async fn prune(&self, target: &SshTarget, keep: Option<&str>) -> anyhow::Result<()> {
        crate::ssh_bootstrap::prune_remote_versions(target, keep).await
    }
}

/// The `versions/` entry an install just wrote, kept by the prune whatever
/// `current` says.
pub(super) fn installed_version_dir(target: &SshTarget) -> Option<String> {
    Some(crate::ssh_bootstrap::version_dir_name(
        target.runtime_version.as_deref()?,
        target.runtime_platform.as_deref()?,
        target.runtime_arch.as_deref()?,
    ))
}

/// `hostBusy` when hub terminals still run on the host: stopping its runtime
/// ends them, so the client confirms and retries with `force`.
pub(super) fn host_busy_conflict(
    target: &SshTarget,
    mut session_ids: Vec<String>,
) -> Option<HostError> {
    if session_ids.is_empty() {
        return None;
    }
    session_ids.sort();
    let count = session_ids.len();
    let terminals = if count == 1 {
        "1 open terminal".to_string()
    } else {
        format!("{count} open terminals")
    };
    Some(HostError::conflict(
        "hostBusy",
        format!(
            "{} has {terminals}. Restarting its Alera runtime closes them.",
            target.alias
        ),
        json!({
            "hostId": target.id,
            "alias": target.alias,
            "activeSessions": count,
            "sessionIds": session_ids,
        }),
    ))
}

/// Clears the registry's restart flag however the restart ends, including a
/// cancelled job whose task is aborted mid-way.
struct RestartGuard<'a> {
    links: &'a HostLinkRegistry,
    host_id: &'a str,
}

impl Drop for RestartGuard<'_> {
    fn drop(&mut self) {
        self.links.end_restart(self.host_id);
    }
}

/// Stops the host's runtime, waits for the new one to attach with the
/// installed version, then prunes old versions (best effort). Returns the
/// version the restarted runtime reported.
pub(super) async fn restart_satellite_runtime<F>(
    links: &HostLinkRegistry,
    target: &SshTarget,
    force: bool,
    keep: Option<String>,
    remote: &dyn RestartRemote,
    timing: RestartTiming,
    mut emit: F,
) -> HostResult<Option<String>>
where
    F: FnMut(&str, &str),
{
    let host_id = target.id.as_str();
    emit(RESTART_STAGE, "Restarting Alera Runtime");
    let expected = match remote.installed_version(target).await {
        Ok(version) => version,
        Err(error) => {
            tracing::warn!(
                target: "host_link",
                host_id,
                "could not read the installed runtime version: {error:#}"
            );
            None
        }
    };
    links.begin_restart(host_id);
    let guard = RestartGuard { links, host_id };
    stop_runtime(links, host_id, force, timing).await?;
    let version = reattach(links, target, expected.as_deref(), timing).await?;
    drop(guard);

    emit(PRUNE_STAGE, "Removing Old Runtime Versions");
    if let Err(error) = remote.prune(target, keep.as_deref()).await {
        tracing::warn!(
            target: "host_link",
            host_id,
            "could not remove old runtime versions: {error:#}"
        );
    }
    Ok(version)
}

async fn stop_runtime(
    links: &HostLinkRegistry,
    host_id: &str,
    force: bool,
    timing: RestartTiming,
) -> HostResult<()> {
    let link = links.link(host_id).await?;
    let answer = link
        .request_with_timeout(
            "host.shutdown",
            json!({ "force": force }),
            timing.shutdown_answer,
        )
        .await;
    // A runtime that exits before its answer arrives has done what was asked.
    if let Err(error) = answer {
        if !link.is_closed() {
            return Err(error);
        }
    }
    if !links.wait_closed(host_id, timing.link_close).await {
        links.close_for_restart(host_id).await;
    }
    Ok(())
}

/// The version the attached runtime runs. Runtimes before this release
/// announced no version on attach, so those are asked with `status.get`.
async fn reported_version(link: &HostLink) -> Option<String> {
    if let Some(version) = link.attachment().host_version.clone() {
        return Some(version);
    }
    link.request_with_timeout("status.get", json!({}), STATUS_TIMEOUT)
        .await
        .ok()?
        .get("runtimeHostVersion")?
        .as_str()
        .map(str::to_string)
}

async fn reattach(
    links: &HostLinkRegistry,
    target: &SshTarget,
    expected: Option<&str>,
    timing: RestartTiming,
) -> HostResult<Option<String>> {
    let host_id = target.id.as_str();
    let mut reported: Option<Option<String>> = None;
    let mut last_error = None;
    for attempt in 0..timing.attach_attempts {
        if attempt > 0 {
            tokio::time::sleep(timing.attach_interval).await;
        }
        match links.link(host_id).await {
            Ok(link) => {
                let version = reported_version(&link).await;
                if expected.is_none_or(|expected| version.as_deref() == Some(expected)) {
                    return Ok(version);
                }
                // The old runtime answered (it had not exited yet, or
                // something restarted it): drop this link and ask again.
                reported = Some(version);
                links.close_for_restart(host_id).await;
            }
            Err(error) => last_error = Some(error),
        }
    }
    Err(match (reported, last_error) {
        (Some(version), _) => HostError::state(format!(
            "The runtime on {alias} still reports version {version} after the update. Expected {expected}. Stop any other Alera runtime running on {alias} and try again.",
            alias = target.alias,
            version = version.as_deref().unwrap_or("unknown"),
            expected = expected.unwrap_or("unknown"),
        )),
        (None, Some(error)) => HostError::state(format!(
            "The runtime on {} did not come back after the restart: {}",
            target.alias,
            error.wire_message()
        )),
        (None, None) => HostError::state(format!(
            "The runtime on {} did not come back after the restart.",
            target.alias
        )),
    })
}
