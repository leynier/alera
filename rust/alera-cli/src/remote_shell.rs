//! The shell a bootstrapped SSH host runs our scripts in.
//!
//! One type decides quoting, path joining and the platform precedence, so the
//! callers that build remote scripts cannot disagree about which shell a host
//! has.

use alera_core::runtime::SshTarget;
use anyhow::{bail, Result};

use crate::ssh_remote_command::{powershell_string, remote_join, shell_quote};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RemoteShell {
    /// `sh -lc` on Linux and macOS.
    Posix,
    /// Windows PowerShell behind OpenSSH for Windows.
    Windows,
}

impl RemoteShell {
    pub(crate) fn from_platform(platform: &str) -> Option<Self> {
        match normalize_platform(platform).as_str() {
            "windows" => Some(RemoteShell::Windows),
            "linux" | "macos" => Some(RemoteShell::Posix),
            _ => None,
        }
    }

    /// The shell recorded for a host, if any. The platform the bootstrap
    /// validated (`runtime_platform`) wins over the one the user typed
    /// (`platform`), even when the validated value is unrecognized.
    pub(crate) fn recorded(target: &SshTarget) -> Option<Self> {
        target
            .runtime_platform
            .as_deref()
            .or(target.platform.as_deref())
            .and_then(Self::from_platform)
    }

    /// Like [`RemoteShell::recorded`], but an unknown platform is an error.
    /// Callers on the server actor rely on this not touching the network.
    pub(crate) fn from_target(target: &SshTarget) -> Result<Self> {
        match Self::recorded(target) {
            Some(shell) => Ok(shell),
            None => bail!(
                "The platform of SSH host '{}' is unknown. Run `alera ssh-target bootstrap --id {}` before opening its terminal.",
                target.alias,
                target.id
            ),
        }
    }

    pub(crate) fn quote(&self, value: &str) -> String {
        match self {
            RemoteShell::Posix => shell_quote(value),
            RemoteShell::Windows => powershell_string(value),
        }
    }

    pub(crate) fn join(&self, base: &str, parts: &[&str]) -> String {
        remote_join(*self, base, parts)
    }

    pub(crate) fn is_windows(&self) -> bool {
        matches!(self, RemoteShell::Windows)
    }

    /// The platform name stored and compared for this shell when nothing more
    /// specific is known (a POSIX host defaults to `linux`).
    pub(crate) fn default_platform(&self) -> &'static str {
        match self {
            RemoteShell::Posix => "linux",
            RemoteShell::Windows => "windows",
        }
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

#[cfg(test)]
#[path = "remote_shell_tests.rs"]
mod tests;
