//! One status per remote host, folded from what the hub knows about it: the
//! install job in flight, the bootstrap record, the host link and the last
//! connectivity probe. `sshTarget.list`, `sshTarget.upsert` and
//! `sshTarget.check` carry it as `hostStatus` on every target, and
//! `mobile.hosts.list` carries its `state` as `status`, so the desktop, the
//! phone and the CLI never derive it on their own.
//!
//! Everything here is additive (`remoteHostStatusV1`); the target record keeps
//! its existing fields.

use std::collections::HashMap;

use alera_core::runtime::{SshBootstrapStatus, SshTarget};
use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::{json, Value};

use crate::ssh_target_status::{check_ssh_targets, LiveSshTargetProbe};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link::{HostLinkAttachment, HostLinkState};
use crate::terminal_host::host_link_failure::AttachFailureKind;
use crate::terminal_host::host_link_registry::HostLinkRegistry;
use crate::terminal_host::host_link_slot::{HostLinkStatus, RetryStatus};
use crate::terminal_host::runtime_build_info;

use super::{ServerActor, ServerCommand};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum HostState {
    NeedsSetup,
    Installing,
    Disconnected,
    Offline,
    Connecting,
    Connected,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct HostStatus {
    pub(crate) state: HostState,
    pub(crate) detail: Option<String>,
    pub(crate) stage: Option<String>,
    pub(crate) link_state: &'static str,
    pub(crate) satellite_version: Option<String>,
    pub(crate) hub_version: String,
    pub(crate) runtime_update_available: bool,
    pub(crate) last_checked_at: Option<DateTime<Utc>>,
    pub(crate) retry: Option<RetryStatus>,
    pub(crate) desired: bool,
}

/// What a running install job last reported.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct InstallJobView {
    pub(crate) stage: String,
    pub(crate) message: String,
}

/// The state precedence: a live install wins, then an unfinished install,
/// then the link, then the last probe.
pub(crate) fn host_status_payload(
    target: &SshTarget,
    link: &HostLinkStatus,
    job: Option<&InstallJobView>,
    hub_version: &str,
) -> HostStatus {
    let link_error = match &link.state {
        HostLinkState::Failed { error } => Some(error.clone()),
        _ => None,
    };
    let (state, detail, stage) = if let Some(job) = job {
        (
            HostState::Installing,
            Some(job.message.clone()),
            Some(job.stage.clone()),
        )
    } else if target.bootstrap_status != SshBootstrapStatus::Installed {
        // `Installing` without a job is an install the hub lost (it
        // restarted mid-way): the host still needs one.
        (HostState::NeedsSetup, target.last_error.clone(), None)
    } else {
        match &link.state {
            HostLinkState::Attached { .. } => (HostState::Connected, None, None),
            HostLinkState::Connecting => (HostState::Connecting, None, None),
            HostLinkState::Failed { .. }
                if link.failure_kind == Some(AttachFailureKind::Unreachable) =>
            {
                (HostState::Offline, link_error, None)
            }
            _ if target.last_status.as_deref() == Some("unreachable") => {
                (HostState::Offline, link_error, None)
            }
            HostLinkState::Failed { .. } => (HostState::Error, link_error, None),
            HostLinkState::Disconnected => (HostState::Disconnected, None, None),
        }
    };
    HostStatus {
        state,
        detail,
        stage,
        link_state: match link.state {
            HostLinkState::Disconnected => "disconnected",
            HostLinkState::Connecting => "connecting",
            HostLinkState::Attached { .. } => "attached",
            HostLinkState::Failed { .. } => "failed",
        },
        satellite_version: link
            .satellite_version
            .clone()
            .or_else(|| target.runtime_version.clone()),
        hub_version: hub_version.to_string(),
        runtime_update_available: false,
        last_checked_at: target.last_checked_at,
        retry: link.retry.clone(),
        desired: link.desired,
    }
}

/// The target record with its `hostStatus`.
pub(crate) fn target_with_status(target: &SshTarget, status: &HostStatus) -> HostResult<Value> {
    let mut value =
        serde_json::to_value(target).map_err(|error| HostError::format(error.to_string()))?;
    if let Some(object) = value.as_object_mut() {
        object.insert("hostStatus".into(), json!(status));
    }
    Ok(value)
}

/// A phone labels a remote workspace with a name, a system and whether the
/// host is usable. How to reach the host (address, user, port, install
/// directory) and its raw errors stay on the hub.
pub(crate) fn mobile_host_entry(target: &SshTarget, status: &HostStatus) -> Value {
    json!({
        "id": target.id,
        "alias": target.alias,
        "platform": target.runtime_platform.as_ref().or(target.platform.as_ref()),
        "status": status.state,
        "runtimeVersion": target.runtime_version,
        "updateAvailable": status.runtime_update_available,
    })
}

fn status_with(
    links: &HostLinkRegistry,
    jobs: &HashMap<String, InstallJobView>,
    target: &SshTarget,
) -> HostStatus {
    host_status_payload(
        target,
        &links.status(&target.id),
        jobs.get(&target.id),
        runtime_build_info::version(),
    )
}

impl ServerActor {
    fn install_job_views(&self) -> HashMap<String, InstallJobView> {
        self.ssh_bootstrap_jobs
            .iter()
            .map(|(id, job)| {
                (
                    id.clone(),
                    InstallJobView {
                        stage: job.stage.clone(),
                        message: job.message.clone(),
                    },
                )
            })
            .collect()
    }

    pub(super) fn ssh_target_value(&self, target: &SshTarget) -> HostResult<Value> {
        let status = status_with(&self.host_links, &self.install_job_views(), target);
        target_with_status(target, &status)
    }

    async fn ssh_targets(&self) -> HostResult<Vec<SshTarget>> {
        self.runtime_store
            .list_ssh_targets()
            .await
            .map_err(|error| HostError::from_anyhow(&error))
    }

    pub(super) async fn ssh_target_list(&mut self) -> HostResult<Value> {
        let jobs = self.install_job_views();
        let items = self
            .ssh_targets()
            .await?
            .iter()
            .map(|target| target_with_status(target, &status_with(&self.host_links, &jobs, target)))
            .collect::<HostResult<Vec<_>>>()?;
        Ok(Value::Array(items))
    }

    pub(super) async fn mobile_host_list(&mut self) -> HostResult<Value> {
        let jobs = self.install_job_views();
        let items = self
            .ssh_targets()
            .await?
            .iter()
            .map(|target| mobile_host_entry(target, &status_with(&self.host_links, &jobs, target)))
            .collect();
        Ok(Value::Array(items))
    }

    /// `sshTarget.check {id?}`: probes off the actor, persists the result,
    /// and answers with the refreshed targets. A check also counts as the
    /// user asking for the host, so a Disconnect no longer holds and a host
    /// that should be linked connects now instead of after its backoff.
    pub(super) fn start_ssh_target_check(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) {
        let id = payload
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|id| !id.is_empty())
            .map(str::to_string);
        let store = self.runtime_store.clone();
        let links = self.host_links.clone();
        let jobs = self.install_job_views();
        let inbox = self.inbox.clone();
        self.spawn_deferred_request(client_id, request_id, async move {
            let targets = check_ssh_targets(&store, id.as_deref(), &LiveSshTargetProbe)
                .await
                .map_err(|error| HostError::from_anyhow(&error))?;
            for target in &targets {
                links.check_requested(&target.id);
            }
            let items = targets
                .iter()
                .map(|target| target_with_status(target, &status_with(&links, &jobs, target)))
                .collect::<HostResult<Vec<_>>>()?;
            let _ = inbox
                .send_wait(ServerCommand::SshTargetsChanged { host_id: id })
                .await;
            Ok(json!({ "targets": items }))
        });
    }

    /// Every attach reports the runtime that answered; recording it keeps the
    /// target's version, platform and architecture true after an update made
    /// outside Alera.
    pub(super) fn record_host_attachment(&self, host_id: &str, attachment: &HostLinkAttachment) {
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let host_id = host_id.to_string();
        let version = attachment.host_version.clone();
        let platform = crate::remote_shell::normalize_platform(&attachment.platform);
        let arch = crate::ssh_bootstrap::normalize_arch(&attachment.arch);
        tokio::spawn(async move {
            let recorded = store
                .mark_ssh_target_attached(
                    &host_id,
                    version.as_deref(),
                    Some(&platform),
                    Some(&arch),
                )
                .await;
            if let Err(error) = recorded {
                tracing::warn!(target: "host_link", host_id, "could not record the attached runtime: {error:#}");
                return;
            }
            let _ = inbox
                .send_wait(ServerCommand::SshTargetsChanged {
                    host_id: Some(host_id),
                })
                .await;
        });
    }
}

#[cfg(test)]
#[path = "ssh_target_status_requests_tests.rs"]
mod tests;
