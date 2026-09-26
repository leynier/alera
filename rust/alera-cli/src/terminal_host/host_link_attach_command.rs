//! The remote command a host link runs, shaped for the satellite's shell.

use alera_core::runtime::SshTarget;

use super::host_error::{HostError, HostResult};

/// The `ssh` argument vector for the link. No PTY (`-T`), keep-alives so a
/// dropped network fails the link instead of hanging it, and the remote
/// command shaped for the satellite's shell.
pub(crate) fn attach_ssh_arguments(target: &SshTarget) -> HostResult<Vec<String>> {
    let install_dir = target
        .install_dir
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::state(crate::ssh_remote::host_not_bootstrapped(target)))?;
    let windows = crate::ssh_remote::terminal_platform_windows(target)
        .map_err(|error| HostError::state(error.to_string()))?;
    let mut args = crate::ssh_bootstrap::ssh_args(target);
    let destination = args.pop().expect("ssh_args includes the destination");
    args.push("-T".to_string());
    args.push("-o".to_string());
    args.push("ServerAliveInterval=15".to_string());
    args.push("-o".to_string());
    args.push("ServerAliveCountMax=3".to_string());
    args.push(destination);
    args.push(attach_remote_command(install_dir, windows));
    Ok(args)
}

/// The command the satellite's sshd runs. Both shapes go through the sidecar's
/// `bin/alera` wrapper, which exports `ALERA_RUNTIME_DIR` to the sidecar data
/// directory, so the attach reaches the same runtime the bootstrap validated.
///
/// Windows deliberately avoids PowerShell: when its own stdin is redirected,
/// PowerShell hands a native command a fresh pipe it never feeds unless the
/// command is on the right side of `|`, so the frames the hub writes would
/// never reach `alera.exe`. `cmd.exe` (the sshd default shell) passes the
/// handles straight through and expands `%LOCALAPPDATA%` in the install dir.
pub(crate) fn attach_remote_command(install_dir: &str, windows: bool) -> String {
    if windows {
        let wrapper = format!(
            "{}\\bin\\alera.cmd",
            install_dir.replace('/', "\\").trim_end_matches('\\')
        );
        // sshd runs this as `cmd.exe /c "<line>"`; with more than two quotes
        // cmd strips only the outer pair, which leaves the wrapper path quoted.
        return format!("\"{wrapper}\" runtime-attach --stdio");
    }
    format!(
        "sh -lc {}",
        crate::ssh_bootstrap::shell_quote(&format!(
            "install={}; case \"$install\" in '~/'*) install=\"$HOME/${{install#\"~/\"}}\";; esac; exec \"$install/bin/alera\" runtime-attach --stdio",
            crate::ssh_bootstrap::shell_quote(install_dir)
        ))
    )
}
