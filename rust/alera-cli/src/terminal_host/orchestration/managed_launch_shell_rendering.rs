//! Turning a built launch into one line the user's interactive shell will run.
//!
//! The host writes the line into a PTY that already holds whatever shell the
//! user configured, so quoting is the shell's rule set, not ours: a model name
//! with spaces or a prompt with an apostrophe has to survive verbatim.

use super::managed_agent_launch::ManagedAgentLaunch;

pub fn render_managed_launch(launch: &ManagedAgentLaunch, shell: &str) -> String {
    let family = shell_family(shell);
    std::iter::once(launch.executable.as_str())
        .chain(launch.arguments.iter().map(String::as_str))
        .map(|value| quote_argument(value, family))
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn managed_launch_preview(launch: &ManagedAgentLaunch) -> String {
    #[cfg(windows)]
    let shell = std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string());
    #[cfg(not(windows))]
    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
    render_managed_launch(launch, &shell)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShellFamily {
    Posix,
    PowerShell,
    Cmd,
}

fn shell_family(shell: &str) -> ShellFamily {
    let normalized = shell.replace('\\', "/").to_ascii_lowercase();
    let executable = normalized.rsplit('/').next().unwrap_or(&normalized);
    if matches!(
        executable,
        "powershell" | "powershell.exe" | "pwsh" | "pwsh.exe"
    ) {
        ShellFamily::PowerShell
    } else if matches!(executable, "cmd" | "cmd.exe") {
        ShellFamily::Cmd
    } else {
        ShellFamily::Posix
    }
}

fn quote_argument(value: &str, family: ShellFamily) -> String {
    match family {
        ShellFamily::Posix => format!("'{}'", value.replace('\'', "'\"'\"'")),
        ShellFamily::PowerShell => format!("'{}'", value.replace('\'', "''")),
        ShellFamily::Cmd => format!("\"{}\"", value.replace('"', "\"\"")),
    }
}

#[cfg(test)]
#[path = "managed_launch_shell_rendering_tests.rs"]
mod tests;
