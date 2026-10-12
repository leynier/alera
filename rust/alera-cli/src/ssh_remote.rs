//! SSH helpers shared by remote workspace create, terminal attach, and files.
//!
//! Reuses the one-shot command layer in `ssh_remote_command` (`ssh_args`,
//! POSIX and PowerShell scripts, budgets). Does not invent a new bootstrap.

use std::future::Future;

use alera_core::runtime::{RuntimeStore, SshBootstrapStatus, SshTarget, LOCAL_HOST_ID};
use anyhow::{anyhow, bail, Result};

use crate::remote_shell::RemoteShell;
use crate::ssh_bootstrap::reject_password_ssh_bootstrap_auth;
use crate::ssh_remote_command::{run_remote_command, ssh_args, RemoteCommandBudget};
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

/// Runs one-shot scripts on a host; tests substitute a fake.
pub(crate) trait RemoteHostExecutor {
    /// The shell the host answers in, or `None` when it does not answer.
    fn probe_shell(&self, target: &SshTarget) -> impl Future<Output = Option<RemoteShell>> + Send;

    fn run(
        &self,
        target: &SshTarget,
        shell: RemoteShell,
        script: &str,
        budget: RemoteCommandBudget,
    ) -> impl Future<Output = Result<String>> + Send;
}

pub(crate) struct LiveSshRemoteHost;

impl RemoteHostExecutor for LiveSshRemoteHost {
    async fn probe_shell(&self, target: &SshTarget) -> Option<RemoteShell> {
        crate::ssh_remote_command::probe_shell(target).await
    }

    async fn run(
        &self,
        target: &SshTarget,
        shell: RemoteShell,
        script: &str,
        budget: RemoteCommandBudget,
    ) -> Result<String> {
        Ok(run_remote_command(target, shell, script, budget)
            .await?
            .stdout)
    }
}

pub(crate) async fn probe_or_unreachable<E: RemoteHostExecutor>(
    executor: &E,
    target: &SshTarget,
) -> Result<RemoteShell> {
    executor
        .probe_shell(target)
        .await
        .ok_or_else(|| anyhow!(host_unreachable(target)))
}

pub(crate) fn ssh_terminal_launch(
    target: &SshTarget,
    remote_cwd: &str,
    shell: RemoteShell,
) -> TerminalHostLaunch {
    let remote_command = match shell {
        RemoteShell::Windows => format!(
            "powershell -NoProfile -NoExit -Command Set-Location -LiteralPath {}",
            shell.quote(remote_cwd)
        ),
        RemoteShell::Posix => format!(
            "cd {} || true; exec ${{SHELL:-/bin/sh}} -l",
            shell.quote(remote_cwd)
        ),
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
    identity: crate::remote_owner_terminal_launch::TerminalIdentity<'_>,
) -> Result<Option<(TerminalHostLaunch, String)>> {
    let Some(workspace) = store.find_workspace(workspace_id).await? else {
        return Ok(None);
    };
    if !is_remote_host_id(Some(&workspace.host_id)) {
        return Ok(None);
    }
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    // Bootstrap validates and persists this platform. Terminal launch runs on
    // the server actor, so probing SSH here would stall unrelated sessions.
    let shell = RemoteShell::from_target(&target)?;
    if uses_owner_terminal(store, &workspace).await? {
        let launch = crate::remote_owner_terminal_launch::owned_launch(
            store, &target, &workspace, identity, shell,
        )
        .await?;
        return Ok(Some((launch, workspace.path.clone())));
    }
    Ok(Some((
        ssh_terminal_launch(&target, &workspace.path, shell),
        workspace.path.clone(),
    )))
}

pub(crate) async fn uses_owner_terminal(
    store: &RuntimeStore,
    workspace: &alera_core::runtime::Workspace,
) -> Result<bool> {
    if workspace.kind == alera_core::runtime::WorkspaceKind::Main {
        return Ok(true);
    }
    if store
        .find_project_checkout(&workspace.project_id, &workspace.host_id)
        .await?
        .is_none()
    {
        return Ok(false);
    }
    let binding = store
        .find_workspace_checkout(&workspace.id)
        .await?
        .ok_or_else(|| anyhow!("The SSH checkout binding is missing"))?;
    if binding.project_id != workspace.project_id
        || binding.host_id != workspace.host_id
        || binding.path != workspace.path
        || binding.kind != alera_core::runtime::CheckoutKind::Linked
    {
        bail!("The linked SSH checkout ownership changed");
    }
    // Registering a project folder does not verify or migrate older worktrees.
    // Keep their existing terminal transport until their origin is established.
    Ok(binding
        .repository_path
        .as_deref()
        .is_some_and(|path| !path.trim().is_empty()))
}

pub(crate) fn ssh_pty_arguments(target: &SshTarget, remote_command: &str) -> Vec<String> {
    let mut args = ssh_args(target);
    let destination = args.pop().expect("ssh_args includes the destination");
    args.push("-tt".to_string());
    args.push(destination);
    args.push(remote_command.to_string());
    args
}

#[cfg(test)]
#[path = "ssh_workspace_routing_tests.rs"]
mod workspace_routing_tests;

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
            projects_dir: None,
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
        let launch = ssh_terminal_launch(&target(), "/Users/leynier/ws", RemoteShell::Posix);
        assert_eq!(launch.shell, "ssh");
        assert!(launch.arguments.contains(&"-tt".to_string()));
        let command = launch.arguments.last().expect("remote command");
        assert!(command.contains("cd '/Users/leynier/ws'"));
        assert!(command.contains("exec ${SHELL:-/bin/sh} -l"));
    }

    #[test]
    fn windows_ssh_pty_uses_powershell_location() {
        let launch = ssh_terminal_launch(&target(), r"C:\work\ws", RemoteShell::Windows);
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
