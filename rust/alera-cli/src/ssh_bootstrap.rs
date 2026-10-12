use std::path::PathBuf;

use alera_core::runtime::{
    redact_known_patterns, RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget,
    SshTargetBootstrapStateUpdate, SshTargetLastStatus,
};
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::remote_shell::{normalize_platform, RemoteShell};
use crate::runtime_archive::{
    resolve_runtime_artifact, RuntimeArchiveChannel, RuntimeArtifactRequest,
};
use crate::ssh_remote_command::{run_remote_command, truncate_error, RemoteCommandBudget};

#[path = "ssh_bootstrap_install_dir.rs"]
mod ssh_bootstrap_install_dir;
use ssh_bootstrap_install_dir::{local_home_dir, prepare_remote_install_dir};

#[path = "ssh_bootstrap_plan.rs"]
mod ssh_bootstrap_plan;
pub(crate) use ssh_bootstrap_plan::build_ssh_bootstrap_plan;

#[path = "ssh_bootstrap_remote.rs"]
mod ssh_bootstrap_remote;
pub(crate) use ssh_bootstrap_remote::validate_remote_runtime;
use ssh_bootstrap_remote::{
    detect_remote_platform, install_runtime_artifact, resolve_remote_install_dir,
    upload_runtime_artifact,
};
#[cfg(test)]
use ssh_bootstrap_remote::{
    posix_install_script, posix_resolve_install_dir_script, windows_install_script,
    windows_validate_script,
};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SshTargetBootstrapRequest {
    pub target_id: String,
    #[serde(default)]
    pub channel: Option<String>,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub install_dir: Option<String>,
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub arch: Option<String>,
    #[serde(default)]
    pub archive_url: Option<String>,
    #[serde(default)]
    pub archive_path: Option<PathBuf>,
    #[serde(default)]
    pub artifact_path: Option<PathBuf>,
    #[serde(default)]
    pub manifest_public_key: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SshTargetBootstrapJob {
    pub job_id: String,
    pub target_id: String,
    pub status: SshBootstrapStatus,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SshTargetBootstrapProgress {
    pub job_id: String,
    pub target_id: String,
    pub status: SshBootstrapStatus,
    pub stage: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

pub(crate) const SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED: &str =
    "password SSH targets are not supported for bootstrap; configure SSH agent or key authentication.";

pub(crate) fn reject_password_ssh_bootstrap_auth(auth_kind: SshAuthKind) -> Result<()> {
    if matches!(auth_kind, SshAuthKind::Password) {
        bail!("{SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED}");
    }
    Ok(())
}

/// Rejects creating a password target or converting agent/key auth to
/// password. An existing password target may be re-saved so Settings can
/// still edit alias or host without forcing a conversion on every save.
pub(crate) fn reject_new_password_ssh_target(
    auth_kind: SshAuthKind,
    existing_auth_kind: Option<SshAuthKind>,
) -> Result<()> {
    if !matches!(auth_kind, SshAuthKind::Password) {
        return Ok(());
    }
    if matches!(existing_auth_kind, Some(SshAuthKind::Password)) {
        return Ok(());
    }
    bail!("{SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED}");
}

pub(crate) fn new_bootstrap_job_id() -> String {
    Uuid::new_v4().to_string()
}

pub(crate) async fn run_ssh_bootstrap<F>(
    store: RuntimeStore,
    cache_dir: PathBuf,
    request: SshTargetBootstrapRequest,
    job_id: String,
    mut emit: F,
) -> Result<SshTarget>
where
    F: FnMut(SshTargetBootstrapProgress) + Send,
{
    let target = find_target(&store, &request.target_id).await?;
    let result = async {
        reject_password_ssh_bootstrap_auth(target.auth_kind)?;
        mark_ssh_bootstrap_installing(&store, &target.id).await?;
        emit(progress(
            &job_id,
            &target.id,
            SshBootstrapStatus::Installing,
            "auth",
            "Checking SSH Authentication",
            None,
        ));
        run_ssh_bootstrap_inner(
            store.clone(),
            cache_dir,
            request,
            job_id.clone(),
            target.clone(),
            &mut emit,
        )
        .await
    }
    .await;
    match result {
        Ok(target) => Ok(target),
        Err(error) => {
            let redacted = redact_error(&format!("{error:#}"));
            let _ = store
                .update_ssh_target_bootstrap_state(
                    &target.id,
                    SshTargetBootstrapStateUpdate {
                        status: SshBootstrapStatus::Failed,
                        install_dir: None,
                        runtime_version: None,
                        runtime_platform: None,
                        runtime_arch: None,
                        last_error: Some(&redacted),
                    },
                )
                .await;
            emit(progress(
                &job_id,
                &target.id,
                SshBootstrapStatus::Failed,
                "failed",
                "Remote Runtime Install Failed",
                Some(redacted.clone()),
            ));
            Err(anyhow!(redacted))
        }
    }
}

async fn run_ssh_bootstrap_inner<F>(
    store: RuntimeStore,
    cache_dir: PathBuf,
    request: SshTargetBootstrapRequest,
    job_id: String,
    target: SshTarget,
    emit: &mut F,
) -> Result<SshTarget>
where
    F: FnMut(SshTargetBootstrapProgress) + Send,
{
    if !crate::ssh_remote_command::answers(&target, RemoteShell::Posix).await {
        run_remote_command(
            &target,
            RemoteShell::Windows,
            "Write-Output ready",
            RemoteCommandBudget::Probe,
        )
        .await
        .context(
            "SSH authentication failed; verify ssh-agent, key config, host, port, and username.",
        )?;
    }

    let configured_platform = configured_bootstrap_platform(&request, &target);
    let configured_arch = configured_bootstrap_arch(&request, &target);
    let detected = if configured_platform.is_none() || configured_arch.is_none() {
        emit(progress(
            &job_id,
            &target.id,
            SshBootstrapStatus::Installing,
            "detect",
            "Detecting Remote Platform",
            None,
        ));
        Some(detect_remote_platform(&target).await?)
    } else {
        emit(progress(
            &job_id,
            &target.id,
            SshBootstrapStatus::Installing,
            "detect",
            "Using Configured Remote Platform",
            None,
        ));
        None
    };
    let platform = configured_platform
        .or_else(|| detected.as_ref().map(|value| value.platform.clone()))
        .expect("platform is configured or detected");
    let arch = configured_arch
        .or_else(|| detected.as_ref().map(|value| value.arch.clone()))
        .expect("architecture is configured or detected");
    let Some(shell) = RemoteShell::from_platform(&platform) else {
        bail!("unsupported remote platform: {platform}");
    };
    if !matches!(arch.as_str(), "x64" | "arm64") {
        bail!("unsupported remote architecture: {arch}");
    }
    let install_dir_input = prepare_remote_install_dir(
        &platform,
        request
            .install_dir
            .as_deref()
            .or(target.install_dir.as_deref())
            .unwrap_or(""),
        local_home_dir().as_deref(),
    )?;
    let install_dir = resolve_remote_install_dir(&target, shell, &install_dir_input).await?;

    let installing = store
        .update_ssh_target_bootstrap_state(
            &target.id,
            SshTargetBootstrapStateUpdate {
                status: SshBootstrapStatus::Installing,
                install_dir: Some(&install_dir),
                runtime_version: None,
                runtime_platform: None,
                runtime_arch: None,
                last_error: None,
            },
        )
        .await?;
    emit(progress(
        &job_id,
        &target.id,
        installing.bootstrap_status,
        "artifact",
        "Resolving Runtime Artifact",
        None,
    ));
    let channel = parse_channel(request.channel.as_deref())?;
    let public_key = select_runtime_archive_public_key(
        request.manifest_public_key.clone(),
        std::env::var("ALERA_RUNTIME_ARCHIVE_PUBLIC_KEY").ok(),
        std::env::var("ALERA_UPDATE_MANIFEST_PUBLIC_KEY").ok(),
    );
    let artifact = resolve_runtime_artifact(
        RuntimeArtifactRequest {
            channel,
            version: request.version.clone(),
            platform: platform.clone(),
            arch: arch.clone(),
            archive_url: request.archive_url.clone(),
            archive_path: request.archive_path.clone(),
            artifact_path: request.artifact_path.clone(),
            manifest_public_key: public_key,
        },
        &cache_dir,
    )
    .await?;

    emit(progress(
        &job_id,
        &target.id,
        SshBootstrapStatus::Installing,
        "upload",
        "Uploading Runtime Artifact",
        None,
    ));
    upload_runtime_artifact(&target, shell, &install_dir, &job_id, &artifact).await?;

    emit(progress(
        &job_id,
        &target.id,
        SshBootstrapStatus::Installing,
        "install",
        "Installing Remote Runtime",
        None,
    ));
    install_runtime_artifact(&target, &platform, &install_dir, &job_id, &artifact).await?;

    emit(progress(
        &job_id,
        &target.id,
        SshBootstrapStatus::Installing,
        "validate",
        "Validating Remote Runtime",
        None,
    ));
    validate_remote_runtime(&target, shell, &install_dir).await?;
    let installed = store
        .update_ssh_target_bootstrap_state(
            &target.id,
            SshTargetBootstrapStateUpdate {
                status: SshBootstrapStatus::Installed,
                install_dir: Some(&install_dir),
                runtime_version: Some(&artifact.version),
                runtime_platform: Some(&platform),
                runtime_arch: Some(&arch),
                last_error: None,
            },
        )
        .await?;
    let installed = store
        .mark_ssh_target_checked(&installed.id, SshTargetLastStatus::RuntimeReady)
        .await?;
    emit(progress(
        &job_id,
        &target.id,
        SshBootstrapStatus::Installed,
        "installed",
        "Remote Runtime Installed",
        None,
    ));
    Ok(installed)
}

pub(crate) async fn mark_ssh_bootstrap_installing(
    store: &RuntimeStore,
    target_id: &str,
) -> Result<SshTarget> {
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

fn parse_channel(value: Option<&str>) -> Result<RuntimeArchiveChannel> {
    match value.unwrap_or("stable").trim().to_lowercase().as_str() {
        "" | "stable" => Ok(RuntimeArchiveChannel::Stable),
        "rc" => Ok(RuntimeArchiveChannel::Rc),
        other => bail!("unsupported runtime archive channel: {other}"),
    }
}

async fn find_target(store: &RuntimeStore, target_id: &str) -> Result<SshTarget> {
    store
        .find_ssh_target(target_id)
        .await?
        .ok_or_else(|| anyhow!("ssh target not found: {target_id}"))
}

fn default_install_dir(platform: &str) -> String {
    if platform == "windows" {
        "%LOCALAPPDATA%\\Alera\\runtime".to_string()
    } else {
        // Sidecar layout (current/, bin/, versions/, data/). Distinct from the
        // CLI runtime profile at ~/.alera/runtime (runtime.sqlite, host json).
        "~/.alera/sidecar".to_string()
    }
}

pub(crate) fn normalize_arch(value: &str) -> String {
    match value.trim().to_lowercase().as_str() {
        "x86_64" | "amd64" | "x64" => "x64".to_string(),
        "aarch64" | "arm64" => "arm64".to_string(),
        other => other.to_string(),
    }
}

fn configured_bootstrap_platform(
    request: &SshTargetBootstrapRequest,
    target: &SshTarget,
) -> Option<String> {
    request
        .platform
        .as_deref()
        .or(target.platform.as_deref())
        .map(normalize_platform)
}

fn configured_bootstrap_arch(
    request: &SshTargetBootstrapRequest,
    target: &SshTarget,
) -> Option<String> {
    request
        .arch
        .as_deref()
        .or(target.arch.as_deref())
        .map(normalize_arch)
}

fn select_runtime_archive_public_key(
    request_key: Option<String>,
    runtime_env_key: Option<String>,
    update_env_key: Option<String>,
) -> Option<String> {
    [request_key, runtime_env_key, update_env_key]
        .into_iter()
        .flatten()
        .find_map(non_empty_string)
}

fn non_empty_string(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn progress(
    job_id: &str,
    target_id: &str,
    status: SshBootstrapStatus,
    stage: &str,
    message: &str,
    error: Option<String>,
) -> SshTargetBootstrapProgress {
    SshTargetBootstrapProgress {
        job_id: job_id.to_string(),
        target_id: target_id.to_string(),
        status,
        stage: stage.to_string(),
        message: message.to_string(),
        error,
    }
}

fn redact_error(message: &str) -> String {
    // Keep real paths such as `/home/leynier` so mkdir failures stay
    // diagnosable. Replacing the SSH username used to turn that into
    // `/home/<user>`, which looked like a template bug. See #675.
    truncate_error(&redact_known_patterns(message))
}

#[cfg(test)]
#[path = "ssh_bootstrap_tests.rs"]
mod tests;
