//! The dry-run plan for a sidecar bootstrap: what would be installed where,
//! resolved from the request and the stored target without touching the host.

use alera_core::runtime::RuntimeStore;
use anyhow::Result;
use serde::{Deserialize, Serialize};

use super::ssh_bootstrap_install_dir::{local_home_dir, prepare_remote_install_dir};
use super::{
    find_target, normalize_arch, parse_channel, reject_password_ssh_bootstrap_auth,
    SshTargetBootstrapRequest,
};
use crate::remote_shell::normalize_platform;

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SshTargetBootstrapPlan {
    pub target_id: String,
    pub alias: String,
    pub host: String,
    pub port: i64,
    pub username: String,
    pub auth_kind: String,
    pub channel: String,
    pub version: Option<String>,
    pub platform: String,
    pub arch: String,
    pub install_dir: String,
    pub artifact_source: String,
    pub trust: String,
    pub status: String,
    pub steps: Vec<String>,
}

pub(crate) async fn build_ssh_bootstrap_plan(
    store: &RuntimeStore,
    request: &SshTargetBootstrapRequest,
) -> Result<SshTargetBootstrapPlan> {
    let target = find_target(store, &request.target_id).await?;
    reject_password_ssh_bootstrap_auth(target.auth_kind)?;
    let channel = parse_channel(request.channel.as_deref())?;
    let platform = request
        .platform
        .as_deref()
        .or(target.platform.as_deref())
        .or(target.runtime_platform.as_deref())
        .map(normalize_platform)
        .unwrap_or_else(|| "auto".to_string());
    let arch = request
        .arch
        .as_deref()
        .or(target.arch.as_deref())
        .or(target.runtime_arch.as_deref())
        .map(normalize_arch)
        .unwrap_or_else(|| "auto".to_string());
    let install_dir = prepare_remote_install_dir(
        &platform,
        request
            .install_dir
            .as_deref()
            .or(target.install_dir.as_deref())
            .unwrap_or(""),
        local_home_dir().as_deref(),
    )?;
    let local_override = request.artifact_path.is_some();
    Ok(SshTargetBootstrapPlan {
        target_id: target.id,
        alias: target.alias,
        host: target.host,
        port: target.port,
        username: target.username,
        auth_kind: target.auth_kind.as_str().to_string(),
        channel: channel.as_str().to_string(),
        version: request.version.clone(),
        platform,
        arch,
        install_dir,
        artifact_source: if local_override {
            "localArtifactPath".to_string()
        } else if request.archive_path.is_some() {
            "localArchivePath".to_string()
        } else {
            "githubRelease".to_string()
        },
        trust: if local_override {
            "localOverride".to_string()
        } else {
            "signedArchive".to_string()
        },
        status: "planned".to_string(),
        steps: vec![
            "Validate SSH Key Or Agent Authentication".to_string(),
            "Detect Remote Platform And Architecture".to_string(),
            "Verify Signed Runtime Archive Or Local Override".to_string(),
            "Upload Runtime Tarball To Remote Staging".to_string(),
            "Extract Runtime Sidecar And Update Remote Wrapper".to_string(),
            "Validate Installed Runtime Binary".to_string(),
        ],
    })
}
