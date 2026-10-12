//! The remote half of a sidecar bootstrap: platform detection, the install
//! directory, and the scripts that upload, install and validate the runtime.

use alera_core::runtime::SshTarget;
use anyhow::{anyhow, bail, Context, Result};

use super::normalize_arch;
use crate::remote_shell::{normalize_platform, RemoteShell};
use crate::runtime_archive::{ResolvedRuntimeArtifact, RuntimeArtifactTrust};
use crate::ssh_remote_command::{
    powershell_string, run_remote_command, run_sftp_put, shell_quote, windows_sftp_path,
    RemoteCommandBudget,
};

#[derive(Debug)]
pub(super) struct DetectedPlatform {
    pub(super) platform: String,
    pub(super) arch: String,
}

pub(super) async fn detect_remote_platform(target: &SshTarget) -> Result<DetectedPlatform> {
    if let Ok(output) = run_remote_command(
        target,
        RemoteShell::Posix,
        "uname -s; uname -m",
        RemoteCommandBudget::Probe,
    )
    .await
    {
        let lines = output
            .stdout
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .collect::<Vec<_>>();
        if lines.len() >= 2 {
            let platform = normalize_platform(lines[0]);
            if RemoteShell::from_platform(&platform).is_none() {
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
    let output = run_remote_command(
        target,
        RemoteShell::Windows,
        script,
        RemoteCommandBudget::Probe,
    )
    .await?;
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

pub(super) async fn resolve_remote_install_dir(
    target: &SshTarget,
    shell: RemoteShell,
    install_dir: &str,
) -> Result<String> {
    if shell.is_windows() {
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
        let output =
            run_remote_command(target, shell, &script, RemoteCommandBudget::Command).await?;
        return output
            .stdout
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .map(windows_sftp_path)
            .ok_or_else(|| anyhow!("remote Windows install directory probe returned no path."));
    }
    let script = posix_resolve_install_dir_script(install_dir);
    let output = run_remote_command(target, shell, &script, RemoteCommandBudget::Command).await?;
    output
        .stdout
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string)
        .ok_or_else(|| anyhow!("remote install directory probe returned no path."))
}

pub(super) async fn upload_runtime_artifact(
    target: &SshTarget,
    shell: RemoteShell,
    install_dir: &str,
    job_id: &str,
    artifact: &ResolvedRuntimeArtifact,
) -> Result<()> {
    let staging_dir = shell.join(install_dir, &["staging", job_id]);
    let script = if shell.is_windows() {
        format!(
            r#"
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path {staging_dir} | Out-Null
"#,
            staging_dir = powershell_string(&staging_dir),
        )
    } else {
        format!("set -eu\nmkdir -p {}\n", shell_quote(&staging_dir))
    };
    run_remote_command(target, shell, &script, RemoteCommandBudget::Command).await?;
    let remote_path = shell.join(&staging_dir, &[&artifact.file_name]);
    run_sftp_put(
        target,
        &artifact.path,
        &remote_path,
        RemoteCommandBudget::Transfer,
    )
    .await
}

pub(super) async fn install_runtime_artifact(
    target: &SshTarget,
    platform: &str,
    install_dir: &str,
    job_id: &str,
    artifact: &ResolvedRuntimeArtifact,
) -> Result<()> {
    let shell = RemoteShell::from_platform(platform).unwrap_or(RemoteShell::Posix);
    let staging_archive = shell.join(install_dir, &["staging", job_id, &artifact.file_name]);
    let entrypoint = if shell.is_windows() {
        "alera.exe"
    } else {
        "alera"
    };
    let trust_note = match artifact.trust {
        RuntimeArtifactTrust::SignedArchive => "signed archive",
        RuntimeArtifactTrust::LocalOverride => "local override",
    };
    let script = if shell.is_windows() {
        windows_install_script(
            install_dir,
            &artifact.version,
            platform,
            &artifact.arch,
            &staging_archive,
            entrypoint,
        )
    } else {
        posix_install_script(
            install_dir,
            &artifact.version,
            platform,
            &artifact.arch,
            &staging_archive,
            entrypoint,
        )
    };
    run_remote_command(target, shell, &script, RemoteCommandBudget::Install)
        .await
        .with_context(|| format!("failed installing runtime artifact ({trust_note})"))?;
    Ok(())
}

pub(crate) async fn validate_remote_runtime(
    target: &SshTarget,
    shell: RemoteShell,
    install_dir: &str,
) -> Result<()> {
    let script = if shell.is_windows() {
        windows_validate_script(install_dir)
    } else {
        let exe = shell.join(install_dir, &["current", "alera"]);
        let data_dir = shell.join(install_dir, &["data"]);
        format!(
            "set -eu\n{} runtime --runtime-dir {} --json status >/dev/null\n",
            shell_quote(&exe),
            shell_quote(&data_dir),
        )
    };
    run_remote_command(target, shell, &script, RemoteCommandBudget::Command).await?;
    Ok(())
}

pub(super) fn windows_validate_script(install_dir: &str) -> String {
    let data_dir = RemoteShell::Windows.join(install_dir, &["data"]);
    let current_file = RemoteShell::Windows.join(install_dir, &["current.txt"]);
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

pub(super) fn posix_install_script(
    install_dir: &str,
    version: &str,
    platform: &str,
    arch: &str,
    staging_archive: &str,
    entrypoint: &str,
) -> String {
    let version_dir = RemoteShell::Posix.join(
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

pub(super) fn windows_install_script(
    install_dir: &str,
    version: &str,
    platform: &str,
    arch: &str,
    staging_archive: &str,
    entrypoint: &str,
) -> String {
    let version_dir = RemoteShell::Windows.join(
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

pub(super) fn posix_resolve_install_dir_script(install_dir: &str) -> String {
    // Quote/escape the `~/` prefix strip. Unquoted `#~/` tilde-expands the
    // pattern on macOS /bin/sh and Linux dash, so the strip no-ops and the
    // path becomes `$HOME/~/.alera/...` (literal `~` directory). See #666.
    format!(
        r#"
set -eu
install_dir={install_dir}
case "$install_dir" in
  "~") install_dir="$HOME" ;;
  "~/"*) install_dir="$HOME/${{install_dir#"~/"}}" ;;
esac
mkdir -p "$install_dir"
command -v tar >/dev/null 2>&1 || {{ echo "tar is required on the remote host." >&2; exit 11; }}
printf '%s\n' "$install_dir"
"#,
        install_dir = shell_quote(install_dir),
    )
}
