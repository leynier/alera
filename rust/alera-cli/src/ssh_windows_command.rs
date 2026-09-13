use std::{collections::BTreeMap, process::Stdio};

use alera_core::{child_process::windowless_async_command, runtime::SshTarget};
use anyhow::{anyhow, bail, Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use tokio::io::AsyncWriteExt;

use crate::ssh_bootstrap::{powershell_encoded, ssh_args, RemoteCommandOutput};

fn launcher() -> String {
    // OpenSSH on Windows may invoke cmd.exe, whose command line limit is 8191
    // characters. Read the payload before executing it so child stdin is EOF.
    let script = "$ErrorActionPreference = 'Stop'; $encoded = [Console]::In.ReadToEnd(); $script = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)); & ([ScriptBlock]::Create($script))";
    format!(
        "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {}",
        powershell_encoded(script)
    )
}

pub(crate) async fn run(target: &SshTarget, script: &str) -> Result<RemoteCommandOutput> {
    let mut args = ssh_args(target);
    args.push(launcher());
    let mut command = windowless_async_command("ssh");
    crate::login_shell_environment::apply_login_shell_environment(&mut command, &BTreeMap::new())
        .await;
    let mut child = command
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .context("failed to start ssh")?;
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| anyhow!("SSH stdin unavailable"))?;
    let payload = STANDARD.encode(script.as_bytes());
    let write = async move {
        stdin.write_all(payload.as_bytes()).await?;
        stdin.shutdown().await
    };
    // Drain both output streams concurrently with the payload write.
    let (written, output) = tokio::join!(write, child.wait_with_output());
    let output = output.context("failed waiting for ssh")?;
    if !output.status.success() {
        let error = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stderr),
            String::from_utf8_lossy(&output.stdout)
        );
        bail!(
            "ssh failed: {}",
            error.chars().take(4096).collect::<String>()
        );
    }
    written.context("failed sending remote Windows script")?;
    Ok(RemoteCommandOutput {
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launcher_fits_windows_command_line_and_payload_preserves_unicode() {
        assert!(launcher().len() < 2048);
        let script = "Write-Output 'á 漢字'\n".repeat(1000);
        let payload = STANDARD.encode(script.as_bytes());
        assert_eq!(STANDARD.decode(payload).unwrap(), script.as_bytes());
        assert!(!launcher().contains("Write-Output"));
    }
}
