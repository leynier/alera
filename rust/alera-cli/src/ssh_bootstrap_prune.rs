//! After an update, the runtime versions the host no longer runs. Each
//! install extracts into `versions/<version>-<platform>-<arch>` and points
//! `current` (POSIX symlink) or `current.txt` (Windows) at it, so without a
//! prune every update leaves another full runtime behind.
//!
//! The scripts always keep the version `current` resolves to, besides the one
//! the caller names, and refuse to delete anything when neither is known, so
//! a prune can never take the running runtime with it.

use alera_core::runtime::SshTarget;
use anyhow::{anyhow, Result};

use crate::remote_shell::RemoteShell;
use crate::remote_sidecar_command::{parse_last_json_line, posix_install_prelude, sidecar_command};
use crate::ssh_remote_command::{run_remote_command, RemoteCommandBudget};

/// Removes every `versions/*` entry except `keep` and the one `current`
/// points at.
pub(crate) fn prune_versions_script(
    shell: RemoteShell,
    install_dir: &str,
    keep: Option<&str>,
) -> String {
    let keep = keep.unwrap_or_default();
    match shell {
        RemoteShell::Posix => format!(
            r#"set -eu
{prelude}versions="$install/versions"
keep={keep}
[ -d "$versions" ] || {{ printf '%s\n' pruned; exit 0; }}
current=""
if [ -L "$install/current" ]; then
  current="$(basename "$(readlink "$install/current")")"
fi
if [ -z "$current" ] && [ -z "$keep" ]; then
  echo "no current runtime version to keep" >&2
  exit 3
fi
for entry in "$versions"/* "$versions"/.[!.]*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  name="$(basename "$entry")"
  if [ "$name" = "$current" ] || [ "$name" = "$keep" ]; then
    continue
  fi
  rm -rf -- "$entry"
done
printf '%s\n' pruned
"#,
            prelude = posix_install_prelude(install_dir),
            keep = shell.quote(keep),
        ),
        RemoteShell::Windows => format!(
            r#"$ErrorActionPreference = 'Stop'
$install = [Environment]::ExpandEnvironmentVariables({install_dir})
$versions = Join-Path $install 'versions'
if (-not (Test-Path -LiteralPath $versions)) {{ Write-Output 'pruned'; exit 0 }}
$keep = @()
$currentFile = Join-Path $install 'current.txt'
if (Test-Path -LiteralPath $currentFile) {{
  $current = (Get-Content -Raw -LiteralPath $currentFile).Trim().TrimEnd('\')
  if ($current) {{ $keep += (Split-Path -Leaf $current) }}
}}
$extra = {keep}
if ($extra) {{ $keep += $extra }}
if ($keep.Count -eq 0) {{ throw 'no current runtime version to keep' }}
Get-ChildItem -LiteralPath $versions -Force |
  Where-Object {{ $keep -notcontains $_.Name }} |
  ForEach-Object {{ Remove-Item -LiteralPath $_.FullName -Recurse -Force }}
Write-Output 'pruned'
"#,
            install_dir = shell.quote(install_dir),
            keep = shell.quote(keep),
        ),
    }
}

/// Runs [`prune_versions_script`] on the target's install directory.
pub(crate) async fn prune_remote_versions(target: &SshTarget, keep: Option<&str>) -> Result<()> {
    let (shell, install_dir) = shell_and_install_dir(target)?;
    let script = prune_versions_script(shell, install_dir, keep);
    run_remote_command(target, shell, &script, RemoteCommandBudget::Command).await?;
    Ok(())
}

/// The version the installed runtime binary reports (`alera version --json`
/// through `current`), which is what the restarted runtime must attach with.
pub(crate) fn installed_version_script(shell: RemoteShell, install_dir: &str) -> String {
    let arguments = match shell {
        RemoteShell::Posix => "version --json --runtime-dir \"$install/data\"",
        RemoteShell::Windows => "version --json --runtime-dir (Join-Path $install 'data')",
    };
    sidecar_command(
        shell,
        install_dir,
        arguments,
        crate::remote_sidecar_command::SidecarProfile::Bare,
    )
}

pub(crate) async fn installed_runtime_version(target: &SshTarget) -> Result<Option<String>> {
    let (shell, install_dir) = shell_and_install_dir(target)?;
    let script = installed_version_script(shell, install_dir);
    let output = run_remote_command(target, shell, &script, RemoteCommandBudget::Command).await?;
    Ok(parse_installed_version(&output.stdout))
}

pub(crate) fn parse_installed_version(stdout: &str) -> Option<String> {
    let value: serde_json::Value = parse_last_json_line(stdout).ok()?;
    value
        .get("cliVersion")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|version| !version.is_empty())
        .map(str::to_string)
}

fn shell_and_install_dir(target: &SshTarget) -> Result<(RemoteShell, &str)> {
    let shell = RemoteShell::from_target(target)?;
    let install_dir = target
        .install_dir
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!(crate::ssh_remote::host_not_bootstrapped(target)))?;
    Ok((shell, install_dir))
}

#[cfg(test)]
#[path = "ssh_bootstrap_prune_tests.rs"]
mod tests;
