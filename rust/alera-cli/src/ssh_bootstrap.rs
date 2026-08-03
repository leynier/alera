use std::path::{Path, PathBuf};
use std::process::Stdio;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::{
    RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget, SshTargetBootstrapStateUpdate,
};
use anyhow::{anyhow, bail, Context, Result};
use base64::prelude::*;
use serde::{Deserialize, Serialize};
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::runtime_archive::{
    resolve_runtime_artifact, ResolvedRuntimeArtifact, RuntimeArchiveChannel,
    RuntimeArtifactRequest, RuntimeArtifactTrust,
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

#[derive(Debug)]
struct RemoteCommandOutput {
    stdout: String,
}

pub(crate) fn new_bootstrap_job_id() -> String {
    Uuid::new_v4().to_string()
}

pub(crate) async fn build_ssh_bootstrap_plan(
    store: &RuntimeStore,
    request: &SshTargetBootstrapRequest,
) -> Result<SshTargetBootstrapPlan> {
    let target = find_target(store, &request.target_id).await?;
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
    let install_dir = request
        .install_dir
        .clone()
        .or(target.install_dir.clone())
        .unwrap_or_else(|| default_install_dir(&platform));
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
        if matches!(target.auth_kind, SshAuthKind::Password) {
            bail!("password SSH targets are not supported for bootstrap; configure SSH agent or key authentication.");
        }
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
            let redacted = redact_error(&error.to_string(), &target);
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
    if run_remote_command(&target, "posix", "printf ready")
        .await
        .is_err()
    {
        run_remote_command(&target, "windows", "Write-Output ready")
            .await
            .context("SSH authentication failed; verify ssh-agent, key config, host, port, and username.")?;
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
    if !matches!(platform.as_str(), "macos" | "linux" | "windows") {
        bail!("unsupported remote platform: {platform}");
    }
    if !matches!(arch.as_str(), "x64" | "arm64") {
        bail!("unsupported remote architecture: {arch}");
    }
    let install_dir_input = request
        .install_dir
        .clone()
        .or(target.install_dir.clone())
        .unwrap_or_else(|| default_install_dir(&platform));
    let install_dir = resolve_remote_install_dir(&target, &platform, &install_dir_input).await?;

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
    upload_runtime_artifact(&target, &platform, &install_dir, &job_id, &artifact).await?;

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
    validate_remote_runtime(&target, &platform, &install_dir).await?;
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
    let installed = store.mark_ssh_target_checked(&installed.id).await?;
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

#[derive(Debug)]
struct DetectedPlatform {
    platform: String,
    arch: String,
}

async fn detect_remote_platform(target: &SshTarget) -> Result<DetectedPlatform> {
    if let Ok(output) = run_remote_command(target, "posix", "uname -s; uname -m").await {
        let lines = output
            .stdout
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .collect::<Vec<_>>();
        if lines.len() >= 2 {
            let platform = normalize_platform(lines[0]);
            if !is_supported_platform(&platform) {
                return detect_remote_platform_with_powershell(target).await;
            }
            return Ok(DetectedPlatform {
                platform,
                arch: normalize_arch(lines[1]),
            });
        }
    }
    detect_remote_platform_with_powershell(target).await
}

async fn detect_remote_platform_with_powershell(target: &SshTarget) -> Result<DetectedPlatform> {
    let script = r#"
$ErrorActionPreference = 'Stop'
Write-Output 'windows'
Write-Output ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString())
"#;
    let output = run_remote_command(target, "windows", script).await?;
    let lines = output
        .stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    if lines.len() < 2 {
        bail!("could not detect remote platform and architecture.");
    }
    Ok(DetectedPlatform {
        platform: normalize_platform(lines[0]),
        arch: normalize_arch(lines[1]),
    })
}

async fn resolve_remote_install_dir(
    target: &SshTarget,
    platform: &str,
    install_dir: &str,
) -> Result<String> {
    if platform == "windows" {
        let script = format!(
            r#"
$ErrorActionPreference = 'Stop'
$install = {install_dir}
if ([string]::IsNullOrWhiteSpace($install)) {{
  $install = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Alera\runtime'
}}
$install = [Environment]::ExpandEnvironmentVariables($install)
if ($install.StartsWith('%LOCALAPPDATA%', [System.StringComparison]::OrdinalIgnoreCase)) {{
  $install = $install -replace '^%LOCALAPPDATA%', [Environment]::GetFolderPath('LocalApplicationData')
}}
New-Item -ItemType Directory -Force -Path $install | Out-Null
if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {{
  throw 'tar.exe is required on the remote Windows host.'
}}
Write-Output $install
"#,
            install_dir = powershell_string(install_dir),
        );
        let output = run_remote_command(target, platform, &script).await?;
        return output
            .stdout
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .map(windows_sftp_path)
            .ok_or_else(|| anyhow!("remote Windows install directory probe returned no path."));
    }
    let script = format!(
        r#"
set -eu
install_dir={install_dir}
case "$install_dir" in
  "~") install_dir="$HOME" ;;
  "~/"*) install_dir="$HOME/${{install_dir#~/}}" ;;
esac
mkdir -p "$install_dir"
command -v tar >/dev/null 2>&1 || {{ echo "tar is required on the remote host." >&2; exit 11; }}
printf '%s\n' "$install_dir"
"#,
        install_dir = shell_quote(install_dir),
    );
    let output = run_remote_command(target, platform, &script).await?;
    output
        .stdout
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string)
        .ok_or_else(|| anyhow!("remote install directory probe returned no path."))
}

async fn upload_runtime_artifact(
    target: &SshTarget,
    platform: &str,
    install_dir: &str,
    job_id: &str,
    artifact: &ResolvedRuntimeArtifact,
) -> Result<()> {
    let staging_dir = remote_join(platform, install_dir, &["staging", job_id]);
    if platform == "windows" {
        let script = format!(
            r#"
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path {staging_dir} | Out-Null
"#,
            staging_dir = powershell_string(&staging_dir),
        );
        run_remote_command(target, platform, &script).await?;
    } else {
        let script = format!("set -eu\nmkdir -p {}\n", shell_quote(&staging_dir));
        run_remote_command(target, platform, &script).await?;
    }
    let remote_path = remote_join(platform, &staging_dir, &[&artifact.file_name]);
    run_sftp_put(target, &artifact.path, &remote_path).await
}

async fn install_runtime_artifact(
    target: &SshTarget,
    platform: &str,
    install_dir: &str,
    job_id: &str,
    artifact: &ResolvedRuntimeArtifact,
) -> Result<()> {
    let staging_archive = remote_join(
        platform,
        install_dir,
        &["staging", job_id, &artifact.file_name],
    );
    let entrypoint = if platform == "windows" {
        "alera.exe"
    } else {
        "alera"
    };
    let trust_note = match artifact.trust {
        RuntimeArtifactTrust::SignedArchive => "signed archive",
        RuntimeArtifactTrust::LocalOverride => "local override",
    };
    if platform == "windows" {
        let script = windows_install_script(
            install_dir,
            &artifact.version,
            platform,
            &artifact.arch,
            &staging_archive,
            entrypoint,
        );
        run_remote_command(target, platform, &script)
            .await
            .with_context(|| format!("failed installing runtime artifact ({trust_note})"))?;
        return Ok(());
    }
    let script = posix_install_script(
        install_dir,
        &artifact.version,
        platform,
        &artifact.arch,
        &staging_archive,
        entrypoint,
    );
    run_remote_command(target, platform, &script)
        .await
        .with_context(|| format!("failed installing runtime artifact ({trust_note})"))?;
    Ok(())
}

async fn validate_remote_runtime(
    target: &SshTarget,
    platform: &str,
    install_dir: &str,
) -> Result<()> {
    if platform == "windows" {
        let script = windows_validate_script(platform, install_dir);
        run_remote_command(target, platform, &script).await?;
        return Ok(());
    }
    let exe = remote_join(platform, install_dir, &["current", "alera"]);
    let data_dir = remote_join(platform, install_dir, &["data"]);
    let script = format!(
        "set -eu\n{} runtime --runtime-dir {} --json status >/dev/null\n",
        shell_quote(&exe),
        shell_quote(&data_dir),
    );
    run_remote_command(target, platform, &script).await?;
    Ok(())
}

fn windows_validate_script(platform: &str, install_dir: &str) -> String {
    let data_dir = remote_join(platform, install_dir, &["data"]);
    let current_file = remote_join(platform, install_dir, &["current.txt"]);
    format!(
        r#"
$ErrorActionPreference = 'Stop'
$current = Get-Content -Raw -Path {current_file}
& (Join-Path $current 'alera.exe') runtime --runtime-dir {data_dir} --json status | Out-Null
"#,
        current_file = powershell_string(&current_file),
        data_dir = powershell_string(&data_dir),
    )
}

fn posix_install_script(
    install_dir: &str,
    version: &str,
    platform: &str,
    arch: &str,
    staging_archive: &str,
    entrypoint: &str,
) -> String {
    let version_dir = remote_join(
        platform,
        install_dir,
        &["versions", &format!("{version}-{platform}-{arch}")],
    );
    format!(
        r#"set -eu
install_dir={install_dir}
version_dir={version_dir}
	staging_archive={staging_archive}
	entrypoint={entrypoint}
	previous=""
	committed=0
	if [ -L "$install_dir/current" ]; then
	  previous="$(readlink "$install_dir/current" || true)"
	fi
	rollback() {{
	  if [ "$committed" -eq 0 ] && [ -n "$previous" ]; then
	    ln -sfn "$previous" "$install_dir/current"
	  fi
	}}
	trap rollback EXIT
	rm -rf "$version_dir"
	mkdir -p "$version_dir" "$install_dir/bin" "$install_dir/data"
	tar -xzf "$staging_archive" -C "$version_dir"
chmod 755 "$version_dir/$entrypoint"
ln -sfn "$version_dir" "$install_dir/current"
	cat > "$install_dir/bin/alera" <<-'SH'
#!/bin/sh
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export ALERA_RUNTIME_DIR="$DIR/data"
exec "$DIR/current/alera" "$@"
	SH
	chmod 755 "$install_dir/bin/alera"
	rm -rf "$install_dir/staging"
	committed=1
	trap - EXIT
	printf '%s\n' installed
	"#,
        install_dir = shell_quote(install_dir),
        version_dir = shell_quote(&version_dir),
        staging_archive = shell_quote(staging_archive),
        entrypoint = shell_quote(entrypoint),
    )
}

fn windows_install_script(
    install_dir: &str,
    version: &str,
    platform: &str,
    arch: &str,
    staging_archive: &str,
    entrypoint: &str,
) -> String {
    let version_dir = remote_join(
        platform,
        install_dir,
        &["versions", &format!("{version}-{platform}-{arch}")],
    );
    format!(
        r#"
$ErrorActionPreference = 'Stop'
$installDir = {install_dir}
$versionDir = {version_dir}
$stagingArchive = {staging_archive}
$entrypoint = {entrypoint}
$currentFile = Join-Path $installDir 'current.txt'
$previous = $null
if (Test-Path $currentFile) {{
  $previous = Get-Content -Raw -Path $currentFile
}}
try {{
  if (Test-Path $versionDir) {{ Remove-Item -Recurse -Force $versionDir }}
  New-Item -ItemType Directory -Force -Path $versionDir | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $installDir 'bin') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $installDir 'data') | Out-Null
  tar.exe -xzf $stagingArchive -C $versionDir
  if (-not (Test-Path (Join-Path $versionDir $entrypoint))) {{
    throw "Runtime entrypoint missing after extraction: $entrypoint"
  }}
	  Set-Content -Path $currentFile -Value $versionDir -NoNewline
	  $wrapper = Join-Path $installDir 'bin\alera.cmd'
	  Set-Content -Path $wrapper -Value '@echo off
set /p ALERA_CURRENT=<"%~dp0..\current.txt"
set "ALERA_RUNTIME_DIR=%~dp0..\data"
"%ALERA_CURRENT%\alera.exe" %*
' -NoNewline
  Remove-Item -Recurse -Force (Join-Path $installDir 'staging') -ErrorAction SilentlyContinue
  Write-Output 'installed'
}} catch {{
  if ($null -ne $previous) {{
    Set-Content -Path $currentFile -Value $previous -NoNewline
  }}
  throw
}}
"#,
        install_dir = powershell_string(install_dir),
        version_dir = powershell_string(&version_dir),
        staging_archive = powershell_string(staging_archive),
        entrypoint = powershell_string(entrypoint),
    )
}

async fn run_remote_command(
    target: &SshTarget,
    platform: &str,
    script: &str,
) -> Result<RemoteCommandOutput> {
    let mut args = ssh_args(target);
    let command = if platform == "windows" {
        format!(
            "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {}",
            powershell_encoded(script)
        )
    } else {
        format!("sh -lc {}", shell_quote(script))
    };
    args.push(command);
    run_checked("ssh", &args).await
}

async fn run_sftp_put(target: &SshTarget, local_path: &Path, remote_path: &str) -> Result<()> {
    let mut command = windowless_async_command("sftp");
    command
        .arg("-P")
        .arg(target.port.to_string())
        .arg("-o")
        .arg("BatchMode=yes")
        .arg("-o")
        .arg("ConnectTimeout=15")
        .arg(ssh_destination(target))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command.spawn().context("failed to start sftp")?;
    let batch = format!(
        "put {} {}\n",
        sftp_quote(&local_path.display().to_string()),
        sftp_quote(remote_path)
    );
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| anyhow!("failed opening sftp stdin"))?;
    stdin.write_all(batch.as_bytes()).await?;
    drop(stdin);
    let output = child.wait_with_output().await?;
    if output.status.success() {
        return Ok(());
    }
    bail!(
        "sftp upload failed: {}{}",
        String::from_utf8_lossy(&output.stderr),
        String::from_utf8_lossy(&output.stdout)
    )
}

async fn run_checked(program: &str, args: &[String]) -> Result<RemoteCommandOutput> {
    let output = windowless_async_command(program)
        .args(args)
        .kill_on_drop(true)
        .output()
        .await
        .with_context(|| format!("failed to start {program}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        bail!(
            "{program} failed: {}",
            truncate_error(&format!("{stderr}{stdout}"))
        );
    }
    Ok(RemoteCommandOutput { stdout })
}

pub(crate) fn ssh_args(target: &SshTarget) -> Vec<String> {
    vec![
        "-p".to_string(),
        target.port.to_string(),
        "-o".to_string(),
        "BatchMode=yes".to_string(),
        "-o".to_string(),
        "ConnectTimeout=15".to_string(),
        "-o".to_string(),
        "StrictHostKeyChecking=accept-new".to_string(),
        ssh_destination(target),
    ]
}

fn ssh_destination(target: &SshTarget) -> String {
    if target.username.trim().is_empty() {
        target.host.clone()
    } else {
        format!("{}@{}", target.username, target.host)
    }
}

fn default_install_dir(platform: &str) -> String {
    if platform == "windows" {
        "%LOCALAPPDATA%\\Alera\\runtime".to_string()
    } else {
        "~/.alera/runtime".to_string()
    }
}

pub(crate) fn normalize_platform(value: &str) -> String {
    let normalized = value.trim().to_lowercase();
    match normalized.as_str() {
        "darwin" | "mac" | "macos" => "macos".to_string(),
        "linux" => "linux".to_string(),
        "win32" | "windows" | "windows_nt" => "windows".to_string(),
        other if other.starts_with("mingw") => "windows".to_string(),
        other if other.starts_with("msys") => "windows".to_string(),
        other if other.starts_with("cygwin") => "windows".to_string(),
        other => other.to_string(),
    }
}

fn is_supported_platform(value: &str) -> bool {
    matches!(value, "macos" | "linux" | "windows")
}

fn normalize_arch(value: &str) -> String {
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

fn remote_join(platform: &str, base: &str, parts: &[&str]) -> String {
    let separator = "/";
    let mut value = if platform == "windows" {
        windows_sftp_path(base)
    } else {
        base.trim_end_matches('/').to_string()
    };
    for part in parts {
        let trimmed = part.trim_matches(|ch| ch == '/' || ch == '\\');
        if !value.ends_with(separator) {
            value.push_str(separator);
        }
        value.push_str(trimmed);
    }
    value
}

fn windows_sftp_path(value: &str) -> String {
    value.replace('\\', "/")
}

pub(crate) fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

pub(crate) fn powershell_string(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

pub(crate) fn powershell_encoded(script: &str) -> String {
    let bytes = script
        .encode_utf16()
        .flat_map(u16::to_le_bytes)
        .collect::<Vec<u8>>();
    BASE64_STANDARD.encode(bytes)
}

fn sftp_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
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

fn redact_error(message: &str, target: &SshTarget) -> String {
    truncate_error(
        &message
            .replace(&target.host, "<host>")
            .replace(&target.username, "<user>"),
    )
}

fn truncate_error(message: &str) -> String {
    const MAX_ERROR_CHARS: usize = 600;
    let compact = message.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut chars = compact.chars();
    let truncated = chars.by_ref().take(MAX_ERROR_CHARS).collect::<String>();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        compact
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_common_platform_and_arch_values() {
        assert_eq!(normalize_platform("Darwin"), "macos");
        assert_eq!(normalize_platform("Windows_NT"), "windows");
        assert_eq!(normalize_platform("MINGW64_NT-10.0-22631"), "windows");
        assert_eq!(normalize_platform("MSYS_NT-10.0-22631"), "windows");
        assert_eq!(normalize_platform("CYGWIN_NT-10.0-22631"), "windows");
        assert_eq!(normalize_arch("x86_64"), "x64");
        assert_eq!(normalize_arch("AARCH64"), "arm64");
    }

    #[test]
    fn posix_install_script_repoints_current_symlink_and_runtime_data_dir() {
        let script = posix_install_script(
            "/home/me/.alera/runtime",
            "1.2.3",
            "linux",
            "x64",
            "/home/me/.alera/runtime/staging/job/alera-runtime.tar.gz",
            "alera",
        );
        assert!(script.contains("ln -sfn \"$version_dir\" \"$install_dir/current\""));
        assert!(!script.contains("current.tmp"));
        assert!(script.contains("trap rollback EXIT"));
        assert!(!script.contains("trap rollback ERR"));
        assert!(
            script.contains("mkdir -p \"$version_dir\" \"$install_dir/bin\" \"$install_dir/data\"")
        );
        assert!(script.contains("export ALERA_RUNTIME_DIR=\"$DIR/data\""));
        assert!(script.contains("exec \"$DIR/current/alera\" \"$@\""));
        assert!(script.contains("<<-'SH'"));
        assert!(script.contains("\n\tSH\n"));
    }

    #[test]
    fn configured_platform_and_arch_prevent_detection_requirement() {
        let target = SshTarget {
            id: "target-1".to_string(),
            alias: "remote".to_string(),
            host: "remote.example.test".to_string(),
            port: 22,
            username: "alera".to_string(),
            platform: Some("Darwin".to_string()),
            arch: Some("AARCH64".to_string()),
            auth_kind: SshAuthKind::Agent,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
            last_status: None,
            install_dir: None,
            runtime_version: None,
            runtime_platform: None,
            runtime_arch: None,
            bootstrap_status: SshBootstrapStatus::NotInstalled,
            last_bootstrap_at: None,
            last_checked_at: None,
            last_error: None,
        };
        let request = SshTargetBootstrapRequest {
            target_id: target.id.clone(),
            install_dir: None,
            platform: Some("linux".to_string()),
            arch: Some("x86_64".to_string()),
            channel: None,
            version: None,
            archive_url: None,
            archive_path: None,
            artifact_path: None,
            manifest_public_key: None,
        };

        assert_eq!(
            configured_bootstrap_platform(&request, &target).as_deref(),
            Some("linux")
        );
        assert_eq!(
            configured_bootstrap_arch(&request, &target).as_deref(),
            Some("x64")
        );
    }

    #[test]
    fn runtime_archive_public_key_selection_ignores_empty_values() {
        assert_eq!(
            select_runtime_archive_public_key(
                Some(" ".to_string()),
                Some("\t".to_string()),
                Some(" update-key ".to_string()),
            )
            .as_deref(),
            Some("update-key")
        );
        assert_eq!(
            select_runtime_archive_public_key(
                Some(" request-key ".to_string()),
                Some("runtime-key".to_string()),
                Some("update-key".to_string()),
            )
            .as_deref(),
            Some("request-key")
        );
    }

    #[test]
    fn windows_install_script_avoids_symlink_privileges() {
        let script = windows_install_script(
            "C:/Users/me/AppData/Local/Alera/runtime",
            "1.2.3",
            "windows",
            "x64",
            "C:/Users/me/AppData/Local/Alera/runtime/staging/job/alera-runtime.tar.gz",
            "alera.exe",
        );
        assert!(script.contains("current.txt"));
        assert!(script.contains("alera.cmd"));
        assert!(script.contains("set \"ALERA_RUNTIME_DIR=%~dp0..\\data\""));
        assert!(script.contains("tar.exe -xzf $stagingArchive"));
    }

    #[test]
    fn windows_validate_script_uses_current_file_layout() {
        let script = windows_validate_script("windows", "C:/Users/me/AppData/Local/Alera/runtime");
        assert!(script.contains("current.txt"));
        assert!(script.contains("Join-Path $current 'alera.exe'"));
        assert!(!script.contains("current/alera.exe"));
    }

    #[test]
    fn truncate_error_handles_multibyte_text() {
        let message = "falló ".repeat(200);
        let truncated = truncate_error(&message);

        assert!(truncated.ends_with("..."));
        assert_eq!(truncated.trim_end_matches("...").chars().count(), 600);
    }
}
