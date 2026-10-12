//! Scripts that run the installed sidecar CLI on a bootstrapped SSH host, and
//! the parser for the JSON receipt it prints back.

use serde::de::DeserializeOwned;

use crate::remote_shell::RemoteShell;

/// Which runtime profile the sidecar command targets.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SidecarProfile {
    /// No `--state-dir`: commands that inspect or create checkouts and keep
    /// no runtime state.
    Bare,
    /// `--state-dir <installDir>/data`: the satellite runtime profile the host
    /// link attaches to, so every project on a host shares one runtime
    /// instead of the retired per-project `owners/<sha256(projectId)>` ones.
    DataStateDir,
}

/// A script for `shell` that runs `<installDir>/current/alera <arguments>`.
/// `arguments` must already be quoted for `shell`. A `~/` install dir is
/// expanded on the host, and the sidecar's exit status is the script's.
pub(crate) fn sidecar_command(
    shell: RemoteShell,
    install_dir: &str,
    arguments: &str,
    profile: SidecarProfile,
) -> String {
    match shell {
        RemoteShell::Windows => {
            let (state_line, state) = match profile {
                SidecarProfile::Bare => ("", ""),
                SidecarProfile::DataStateDir => (
                    "$state = Join-Path $install 'data'\n",
                    " --state-dir $state",
                ),
            };
            format!(
                "$ErrorActionPreference = 'Stop'\n$install = [Environment]::ExpandEnvironmentVariables({})\n$current = (Get-Content -Raw -LiteralPath (Join-Path $install 'current.txt')).Trim()\n{state_line}& (Join-Path $current 'alera.exe') {arguments}{state}\nexit $LASTEXITCODE\n",
                shell.quote(install_dir)
            )
        }
        RemoteShell::Posix => {
            let state = match profile {
                SidecarProfile::Bare => "",
                SidecarProfile::DataStateDir => " --state-dir \"$install/data\"",
            };
            format!(
                "set -eu\n{}exec \"$install/current/alera\" {arguments}{state}\n",
                posix_install_prelude(install_dir)
            )
        }
    }
}

/// Sets `install` to the sidecar install dir, expanding a leading `~/`. The
/// strip pattern is quoted because an unquoted `~/` tilde-expands inside the
/// pattern on dash and macOS `/bin/sh`, and the strip silently no-ops.
pub(crate) fn posix_install_prelude(install_dir: &str) -> String {
    format!(
        "install={}\ncase \"$install\" in '~/'*) install=\"$HOME/${{install#\"~/\"}}\";; esac\n",
        RemoteShell::Posix.quote(install_dir)
    )
}

/// The receipt in a sidecar's stdout. `sh -lc` sources the user's profile,
/// which may print before the sidecar does, so this takes the last JSON
/// document that starts at the beginning of a line and runs to the end of the
/// output (the sidecar pretty-prints, so a receipt may span several lines),
/// falling back to the last single line that parses. When nothing parses, the
/// error is the one for the whole output.
pub(crate) fn parse_last_json_line<T: DeserializeOwned>(stdout: &str) -> serde_json::Result<T> {
    let trimmed = stdout.trim();
    let whole = match serde_json::from_str(trimmed) {
        Ok(value) => return Ok(value),
        Err(error) => error,
    };
    let mut starts = Vec::new();
    let mut offset = 0;
    for line in stdout.split_inclusive('\n') {
        if line.starts_with(['{', '[']) {
            starts.push(offset);
        }
        offset += line.len();
    }
    for start in starts.into_iter().rev() {
        if let Ok(value) = serde_json::from_str(stdout[start..].trim()) {
            return Ok(value);
        }
    }
    for line in stdout.lines().rev() {
        if let Ok(value) = serde_json::from_str(line.trim()) {
            return Ok(value);
        }
    }
    Err(whole)
}

#[cfg(test)]
#[path = "remote_sidecar_command_tests.rs"]
mod tests;
