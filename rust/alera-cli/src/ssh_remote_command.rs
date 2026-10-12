//! One-shot commands on a bootstrapped SSH host: the `ssh`/`sftp` argument
//! vectors, the shell-specific quoting, and a runner that always has a
//! deadline and keeps what the remote side printed when it fails.

use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;
use std::process::{Output, Stdio};
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::SshTarget;
use anyhow::{anyhow, Result};
use base64::prelude::*;
use tokio::io::AsyncWriteExt;

use crate::remote_shell::RemoteShell;

/// Matches the host link's stderr tail, so both transports report the same
/// amount of remote output.
pub(crate) const REMOTE_OUTPUT_TAIL_BYTES: usize = 4096;

/// How long a one-shot remote command may run before it is killed. Every
/// caller names one: an SSH session that never answers would otherwise hold
/// its caller forever.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RemoteCommandBudget {
    /// Reachability and platform probes.
    Probe,
    /// Ordinary sidecar commands (inspection, worktree create and remove).
    Command,
    /// Runtime install and validation during bootstrap.
    Install,
    /// File uploads over sftp.
    Transfer,
    /// Clones, which are bounded by repository size and network speed.
    Provision,
    #[cfg(test)]
    Custom(Duration),
}

impl RemoteCommandBudget {
    pub(crate) fn duration(self) -> Duration {
        match self {
            RemoteCommandBudget::Probe => Duration::from_secs(20),
            RemoteCommandBudget::Command => Duration::from_secs(60),
            RemoteCommandBudget::Install => Duration::from_secs(10 * 60),
            RemoteCommandBudget::Transfer => Duration::from_secs(15 * 60),
            RemoteCommandBudget::Provision => Duration::from_secs(30 * 60),
            #[cfg(test)]
            RemoteCommandBudget::Custom(duration) => duration,
        }
    }

    fn name(self) -> &'static str {
        match self {
            RemoteCommandBudget::Probe => "probe",
            RemoteCommandBudget::Command => "command",
            RemoteCommandBudget::Install => "install",
            RemoteCommandBudget::Transfer => "transfer",
            RemoteCommandBudget::Provision => "provision",
            #[cfg(test)]
            RemoteCommandBudget::Custom(_) => "custom",
        }
    }
}

impl fmt::Display for RemoteCommandBudget {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let duration = self.duration();
        if duration.as_secs() > 0 {
            write!(f, "{} ({}s)", self.name(), duration.as_secs())
        } else {
            write!(f, "{} ({}ms)", self.name(), duration.as_millis())
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum RemoteCommandError {
    #[error("failed to start {program}")]
    Spawn {
        program: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{program} did not finish within its {budget} budget and was stopped")]
    Timeout {
        budget: RemoteCommandBudget,
        program: String,
    },
    /// `summary` is the short form shown in the message; the tails keep up to
    /// [`REMOTE_OUTPUT_TAIL_BYTES`] of each stream for structured errors.
    #[error("{program} failed: {summary}")]
    Exit {
        program: String,
        code: Option<i32>,
        summary: String,
        stderr_tail: String,
        stdout_tail: String,
    },
}

impl RemoteCommandError {
    pub(crate) fn exit(
        program: &str,
        output: &Output,
        summary: impl FnOnce(&str) -> String,
    ) -> Self {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        RemoteCommandError::Exit {
            program: program.to_string(),
            code: output.status.code(),
            summary: summary(&format!("{stderr}{stdout}")),
            stderr_tail: output_tail(&stderr),
            stdout_tail: output_tail(&stdout),
        }
    }
}

#[derive(Debug)]
pub(crate) struct RemoteCommandOutput {
    pub(crate) stdout: String,
}

pub(crate) async fn run_remote_command(
    target: &SshTarget,
    shell: RemoteShell,
    script: &str,
    budget: RemoteCommandBudget,
) -> Result<RemoteCommandOutput> {
    if shell.is_windows() {
        return crate::ssh_windows_command::run(target, script, budget).await;
    }
    let mut args = ssh_args(target);
    args.push(format!("sh -lc {}", shell_quote(script)));
    run_checked("ssh", &args, budget).await
}

/// Whether the host answers a trivial script in `shell`.
pub(crate) async fn answers(target: &SshTarget, shell: RemoteShell) -> bool {
    let script = match shell {
        RemoteShell::Posix => "printf ready",
        RemoteShell::Windows => "Write-Output ready",
    };
    run_remote_command(target, shell, script, RemoteCommandBudget::Probe)
        .await
        .is_ok()
}

/// The shell the host answers in, trying the recorded one first: Windows
/// OpenSSH with Git for Windows also answers `sh`, so a Windows host must be
/// asked in PowerShell before it is mistaken for a POSIX one.
pub(crate) async fn probe_shell(target: &SshTarget) -> Option<RemoteShell> {
    for shell in shell_probe_order(target) {
        if answers(target, shell).await {
            return Some(shell);
        }
    }
    None
}

pub(crate) fn shell_probe_order(target: &SshTarget) -> [RemoteShell; 2] {
    if RemoteShell::recorded(target) == Some(RemoteShell::Windows) {
        [RemoteShell::Windows, RemoteShell::Posix]
    } else {
        [RemoteShell::Posix, RemoteShell::Windows]
    }
}

/// Runs `program` to completion within `budget`. The child gets the user's
/// login-shell environment, as the Windows path and the host link do, so an
/// `ssh` configured through rc-file exports behaves the same from a GUI launch.
pub(crate) async fn run_checked(
    program: &str,
    args: &[String],
    budget: RemoteCommandBudget,
) -> Result<RemoteCommandOutput> {
    let mut command = windowless_async_command(program);
    crate::login_shell_environment::apply_login_shell_environment(&mut command, &BTreeMap::new())
        .await;
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let child = command
        .spawn()
        .map_err(|source| RemoteCommandError::Spawn {
            program: program.to_string(),
            source,
        })?;
    // Dropping the future on expiry drops the child, and `kill_on_drop` kills it.
    let output = tokio::time::timeout(budget.duration(), child.wait_with_output())
        .await
        .map_err(|_| RemoteCommandError::Timeout {
            budget,
            program: program.to_string(),
        })?
        .map_err(|source| RemoteCommandError::Spawn {
            program: program.to_string(),
            source,
        })?;
    if !output.status.success() {
        return Err(RemoteCommandError::exit(program, &output, truncate_error).into());
    }
    Ok(RemoteCommandOutput {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
    })
}

pub(crate) async fn run_sftp_put(
    target: &SshTarget,
    local_path: &Path,
    remote_path: &str,
    budget: RemoteCommandBudget,
) -> Result<()> {
    let mut command = windowless_async_command("sftp");
    crate::login_shell_environment::apply_login_shell_environment(&mut command, &BTreeMap::new())
        .await;
    command
        .args(sftp_args(target))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command
        .spawn()
        .map_err(|source| RemoteCommandError::Spawn {
            program: "sftp".to_string(),
            source,
        })?;
    let batch = format!(
        "put {} {}\n",
        sftp_quote(&local_path.display().to_string()),
        sftp_quote(remote_path)
    );
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| anyhow!("failed opening sftp stdin"))?;
    let upload = async move {
        stdin.write_all(batch.as_bytes()).await?;
        drop(stdin);
        child.wait_with_output().await
    };
    let output = tokio::time::timeout(budget.duration(), upload)
        .await
        .map_err(|_| RemoteCommandError::Timeout {
            budget,
            program: "sftp".to_string(),
        })??;
    if output.status.success() {
        return Ok(());
    }
    Err(RemoteCommandError::exit("sftp upload", &output, truncate_error).into())
}

pub(crate) fn ssh_args(target: &SshTarget) -> Vec<String> {
    let mut args = vec!["-p".to_string(), target.port.to_string()];
    args.extend(connection_options());
    args.push(ssh_destination(target));
    args
}

/// Same connection policy as [`ssh_args`]; `sftp` spells the port `-P`.
pub(crate) fn sftp_args(target: &SshTarget) -> Vec<String> {
    let mut args = vec!["-P".to_string(), target.port.to_string()];
    args.extend(connection_options());
    args.push(ssh_destination(target));
    args
}

fn connection_options() -> [String; 6] {
    [
        "-o".to_string(),
        "BatchMode=yes".to_string(),
        "-o".to_string(),
        "ConnectTimeout=15".to_string(),
        "-o".to_string(),
        "StrictHostKeyChecking=accept-new".to_string(),
    ]
}

fn ssh_destination(target: &SshTarget) -> String {
    if target.username.trim().is_empty() {
        target.host.clone()
    } else {
        format!("{}@{}", target.username, target.host)
    }
}

pub(crate) fn remote_join(shell: RemoteShell, base: &str, parts: &[&str]) -> String {
    let separator = "/";
    let mut value = if shell.is_windows() {
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

pub(crate) fn windows_sftp_path(value: &str) -> String {
    // OpenSSH on Windows treats bare `C:/...` as relative to the remote home
    // (nesting as `/C:/Users/<user>/C:/...`). Force the absolute SFTP form
    // `/X:/...` so puts land at the intended drive path.
    let normalized = value.replace('\\', "/");
    let trimmed = normalized.trim_end_matches('/');
    let without_leading = trimmed.trim_start_matches('/');
    let mut chars = without_leading.chars();
    match (chars.next(), chars.next()) {
        (Some(drive), Some(':')) if drive.is_ascii_alphabetic() => {
            format!("/{without_leading}")
        }
        _ => trimmed.to_string(),
    }
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

pub(crate) fn truncate_error(message: &str) -> String {
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

/// The last [`REMOTE_OUTPUT_TAIL_BYTES`] of `text`, cut on a char boundary.
pub(crate) fn output_tail(text: &str) -> String {
    if text.len() <= REMOTE_OUTPUT_TAIL_BYTES {
        return text.to_string();
    }
    let cut = text.len() - REMOTE_OUTPUT_TAIL_BYTES;
    let boundary = (cut..=text.len())
        .find(|index| text.is_char_boundary(*index))
        .unwrap_or(text.len());
    text[boundary..].to_string()
}

#[cfg(test)]
#[path = "ssh_remote_command_tests.rs"]
mod tests;
