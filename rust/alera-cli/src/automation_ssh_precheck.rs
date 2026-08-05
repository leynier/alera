use std::process::Stdio;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::{redact_known_patterns, AutomationPrecheck, SshTarget};

use crate::ssh_bootstrap::{
    normalize_platform, powershell_encoded, powershell_string, shell_quote, ssh_args,
};

pub(crate) async fn run_remote_precheck(
    target: &SshTarget,
    platform: &str,
    precheck: &AutomationPrecheck,
    cwd: &str,
) -> Result<bool, String> {
    let normalized = normalize_platform(platform);
    let script = if normalized == "windows" {
        format!(
            "$ErrorActionPreference = 'Stop'\nSet-Location -LiteralPath {}\n& powershell -NoProfile -NonInteractive -Command {}\nexit $LASTEXITCODE\n",
            powershell_string(cwd),
            powershell_string(&precheck.command),
        )
    } else {
        format!(
            "set -eu\ncd -- {}\nsh -lc {}\n",
            shell_quote(cwd),
            shell_quote(&precheck.command),
        )
    };
    let mut args = ssh_args(target);
    let command = if normalized == "windows" {
        format!(
            "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {}",
            powershell_encoded(&script)
        )
    } else {
        format!("sh -lc {}", shell_quote(&script))
    };
    args.push(command);
    let child = windowless_async_command("ssh")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|error| format!("failed to start remote precheck: {error}"))?;
    let timeout_duration = std::time::Duration::from_secs(precheck.timeout_seconds.max(1) as u64);
    let output = match tokio::time::timeout(timeout_duration, child.wait_with_output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(error)) => return Err(format!("remote precheck failed to wait: {error}")),
        Err(_) => {
            // The child is killed on drop, and the SSH process owns the remote
            // command. This keeps a timed-out precheck from surviving its run.
            return Err("automation precheck timed out".to_string());
        }
    };
    let stdout = bounded_precheck_output(&output.stdout);
    let stderr = bounded_precheck_output(&output.stderr);
    if !output.status.success() {
        tracing::info!("remote automation precheck failed: stdout={stdout:?} stderr={stderr:?}");
        let diagnostic = format!("{stdout}\n{stderr}").to_ascii_lowercase();
        if [
            "permission denied",
            "authentication",
            "password",
            "passphrase",
            "host key",
        ]
        .iter()
        .any(|pattern| diagnostic.contains(pattern))
        {
            return Err("remote interactive authentication required".to_string());
        }
    }
    Ok(output.status.success())
}

fn bounded_precheck_output(bytes: &[u8]) -> String {
    const MAX_BYTES: usize = 16 * 1024;
    let start = bytes.len().saturating_sub(MAX_BYTES);
    redact_known_patterns(&String::from_utf8_lossy(&bytes[start..]))
}
