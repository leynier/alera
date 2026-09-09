//! SSH helpers shared by remote workspace create, terminal attach, and files.
//!
//! Reuses the OpenSSH path from sidecar bootstrap (`ssh_args`, posix/windows
//! remote scripts, sftp). Does not invent a new bootstrap.

use std::future::Future;
use std::path::Path;

use alera_core::runtime::{RuntimeStore, SshBootstrapStatus, SshTarget, LOCAL_HOST_ID};
use anyhow::{anyhow, bail, Result};

use crate::ssh_bootstrap::{
    normalize_platform, reject_password_ssh_bootstrap_auth, run_remote_command, run_sftp_put,
    shell_quote, ssh_args, ssh_target_answers_posix, ssh_target_answers_windows,
};
use crate::terminal_host::protocol::TerminalHostLaunch;

pub(crate) fn is_remote_host_id(host_id: Option<&str>) -> bool {
    match host_id.map(str::trim).filter(|value| !value.is_empty()) {
        None | Some(LOCAL_HOST_ID) => false,
        Some(_) => true,
    }
}

pub(crate) fn normalized_host_id(host_id: Option<&str>) -> String {
    host_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(LOCAL_HOST_ID)
        .to_string()
}

pub(crate) fn ssh_target_not_found(host_id: &str) -> String {
    format!(
        "ssh target not found: {host_id}. Add it with `alera ssh-target add`, then install the sidecar with `alera ssh-target bootstrap --id {host_id}`."
    )
}

pub(crate) fn host_not_bootstrapped(target: &SshTarget) -> String {
    format!(
        "host '{}' is not bootstrapped. Install the Alera runtime sidecar with `alera ssh-target bootstrap --id {}`.",
        target.alias, target.id
    )
}

pub(crate) fn host_unreachable(target: &SshTarget) -> String {
    format!(
        "host '{}' ({}@{}:{}) is unreachable. Check SSH agent or key authentication and network, then retry `alera ssh-target status --id {}`.",
        target.alias, target.username, target.host, target.port, target.id
    )
}

pub(crate) async fn require_bootstrapped_ssh_target(
    store: &RuntimeStore,
    host_id: &str,
) -> Result<SshTarget> {
    let target = store
        .find_ssh_target(host_id)
        .await?
        .ok_or_else(|| anyhow!(ssh_target_not_found(host_id)))?;
    reject_password_ssh_bootstrap_auth(target.auth_kind)?;
    if target.bootstrap_status != SshBootstrapStatus::Installed {
        bail!("{}", host_not_bootstrapped(&target));
    }
    Ok(target)
}

/// `true` when the remote answers Windows PowerShell, `false` for posix `sh`.
pub(crate) trait RemoteHostExecutor {
    fn probe_windows(&self, target: &SshTarget) -> impl Future<Output = Option<bool>> + Send;

    fn run(
        &self,
        target: &SshTarget,
        windows: bool,
        script: &str,
    ) -> impl Future<Output = Result<String>> + Send;

    fn upload(
        &self,
        target: &SshTarget,
        local: &Path,
        remote: &str,
    ) -> impl Future<Output = Result<()>> + Send;
}

pub(crate) struct LiveSshRemoteHost;

impl RemoteHostExecutor for LiveSshRemoteHost {
    async fn probe_windows(&self, target: &SshTarget) -> Option<bool> {
        live_probe_windows(target).await
    }

    async fn run(&self, target: &SshTarget, windows: bool, script: &str) -> Result<String> {
        let platform = if windows { "windows" } else { "posix" };
        Ok(run_remote_command(target, platform, script).await?.stdout)
    }

    async fn upload(&self, target: &SshTarget, local: &Path, remote: &str) -> Result<()> {
        run_sftp_put(target, local, remote).await
    }
}

pub(crate) async fn probe_or_unreachable<E: RemoteHostExecutor>(
    executor: &E,
    target: &SshTarget,
) -> Result<bool> {
    executor
        .probe_windows(target)
        .await
        .ok_or_else(|| anyhow!(host_unreachable(target)))
}

pub(crate) fn ssh_terminal_launch(
    target: &SshTarget,
    remote_cwd: &str,
    windows: bool,
) -> TerminalHostLaunch {
    let remote_command = if windows {
        format!(
            "powershell -NoProfile -NoExit -Command Set-Location -LiteralPath {}",
            crate::ssh_bootstrap::powershell_string(remote_cwd)
        )
    } else {
        format!(
            "cd {} || true; exec ${{SHELL:-/bin/sh}} -l",
            shell_quote(remote_cwd)
        )
    };
    TerminalHostLaunch {
        label: "ssh".to_string(),
        shell: "ssh".to_string(),
        arguments: ssh_pty_arguments(target, &remote_command),
        environment: Default::default(),
    }
}

pub(crate) async fn remote_workspace_terminal_override(
    store: &RuntimeStore,
    workspace_id: &str,
) -> Result<Option<(TerminalHostLaunch, String)>> {
    let Some(workspace) = store.find_workspace(workspace_id).await? else {
        return Ok(None);
    };
    if !is_remote_host_id(Some(&workspace.host_id)) {
        return Ok(None);
    }
    // Metadata-only foreign hostId on a local path must not rewrite to SSH.
    if std::path::Path::new(&workspace.path).exists() {
        return Ok(None);
    }
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let windows = probe_or_unreachable(&LiveSshRemoteHost, &target).await?;
    Ok(Some((
        ssh_terminal_launch(&target, &workspace.path, windows),
        workspace.path.clone(),
    )))
}

pub(crate) fn ssh_pty_arguments(target: &SshTarget, remote_command: &str) -> Vec<String> {
    let mut args = ssh_args(target);
    let destination = args.pop().expect("ssh_args includes the destination");
    args.push("-tt".to_string());
    args.push(destination);
    args.push(remote_command.to_string());
    args
}

pub(crate) fn sftp_bundle_path(windows: bool, staging_dir: &str, file_name: &str) -> String {
    let platform = if windows { "windows" } else { "posix" };
    crate::ssh_bootstrap::remote_join(platform, staging_dir, &[file_name])
}

async fn live_probe_windows(target: &SshTarget) -> Option<bool> {
    let windows_first = configured_windows(target);
    let order = if windows_first {
        [true, false]
    } else {
        [false, true]
    };
    for windows in order {
        let answered = if windows {
            ssh_target_answers_windows(target).await
        } else {
            ssh_target_answers_posix(target).await
        };
        if answered {
            return Some(windows);
        }
    }
    None
}

fn configured_windows(target: &SshTarget) -> bool {
    target
        .runtime_platform
        .as_deref()
        .or(target.platform.as_deref())
        .map(normalize_platform)
        .as_deref()
        == Some("windows")
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_core::runtime::SshAuthKind;
    use chrono::Utc;

    fn target() -> SshTarget {
        let now = Utc::now();
        SshTarget {
            id: "build-mac".to_string(),
            alias: "build-mac".to_string(),
            host: "mac.example.test".to_string(),
            port: 22,
            username: "leynier".to_string(),
            platform: Some("macos".to_string()),
            arch: None,
            auth_kind: SshAuthKind::Agent,
            created_at: now,
            updated_at: now,
            last_status: None,
            install_dir: None,
            runtime_version: None,
            runtime_platform: Some("macos".to_string()),
            runtime_arch: None,
            bootstrap_status: SshBootstrapStatus::Installed,
            last_bootstrap_at: None,
            last_checked_at: None,
            last_error: None,
        }
    }

    #[test]
    fn local_host_ids_are_not_remote() {
        assert!(!is_remote_host_id(None));
        assert!(!is_remote_host_id(Some("")));
        assert!(!is_remote_host_id(Some("local")));
        assert!(!is_remote_host_id(Some("  local  ")));
        assert!(is_remote_host_id(Some("build-mac")));
    }

    #[test]
    fn posix_ssh_pty_forces_a_tty_and_cds() {
        let launch = ssh_terminal_launch(&target(), "/Users/leynier/ws", false);
        assert_eq!(launch.shell, "ssh");
        assert!(launch.arguments.contains(&"-tt".to_string()));
        let command = launch.arguments.last().expect("remote command");
        assert!(command.contains("cd '/Users/leynier/ws'"));
        assert!(command.contains("exec ${SHELL:-/bin/sh} -l"));
    }

    #[test]
    fn windows_ssh_pty_uses_powershell_location() {
        let launch = ssh_terminal_launch(&target(), r"C:\work\ws", true);
        let command = launch.arguments.last().expect("remote command");
        assert!(command.contains("powershell"));
        assert!(command.contains("Set-Location"));
        assert!(command.contains(r"C:\work\ws") || command.contains("C:\\work\\ws"));
    }

    #[test]
    fn not_bootstrapped_error_names_the_bootstrap_command() {
        let mut remote = target();
        remote.bootstrap_status = SshBootstrapStatus::NotInstalled;
        let message = host_not_bootstrapped(&remote);
        assert!(message.contains("not bootstrapped"));
        assert!(message.contains("alera ssh-target bootstrap --id build-mac"));
    }

    #[test]
    fn unreachable_error_names_status_and_destination() {
        let message = host_unreachable(&target());
        assert!(message.contains("unreachable"));
        assert!(message.contains("leynier@mac.example.test:22"));
        assert!(message.contains("alera ssh-target status --id build-mac"));
    }
}
