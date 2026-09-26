use std::collections::BTreeMap;

use crate::terminal_host::protocol::TerminalHostLaunch;

pub(crate) struct DefaultTerminalLaunch {
    pub launch: TerminalHostLaunch,
    pub interactive_shell: String,
}

#[derive(Clone, Copy)]
#[allow(dead_code)]
enum TerminalPlatform {
    Posix,
    Windows,
}

pub(crate) async fn default_terminal_launch(
    working_directory: &str,
    login_shell: bool,
) -> DefaultTerminalLaunch {
    let environment = terminal_environment().await;
    #[cfg(windows)]
    let platform = TerminalPlatform::Windows;
    #[cfg(not(windows))]
    let platform = TerminalPlatform::Posix;
    let shell = match platform {
        TerminalPlatform::Windows => {
            std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string())
        }
        TerminalPlatform::Posix => std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string()),
    };
    default_terminal_launch_for(
        platform,
        working_directory,
        &shell,
        environment,
        login_shell,
    )
}

fn default_terminal_launch_for(
    platform: TerminalPlatform,
    working_directory: &str,
    interactive_shell: &str,
    environment: BTreeMap<String, String>,
    login_shell: bool,
) -> DefaultTerminalLaunch {
    match platform {
        TerminalPlatform::Windows => DefaultTerminalLaunch {
            interactive_shell: interactive_shell.to_string(),
            launch: TerminalHostLaunch {
                label: "shell".to_string(),
                shell: interactive_shell.to_string(),
                arguments: vec![
                    "/d".to_string(),
                    "/s".to_string(),
                    "/k".to_string(),
                    format!("cd /d {}", cmd_launch_directory(working_directory)),
                ],
                environment,
            },
        },
        TerminalPlatform::Posix => {
            let mut exec_command = format!(
                "cd {} || true; exec {}",
                sh_quote(working_directory),
                sh_quote(interactive_shell)
            );
            if login_shell {
                for argument in login_shell_arguments(interactive_shell) {
                    exec_command.push(' ');
                    exec_command.push_str(&sh_quote(argument));
                }
            }
            DefaultTerminalLaunch {
                interactive_shell: interactive_shell.to_string(),
                launch: TerminalHostLaunch {
                    label: "shell".to_string(),
                    shell: "/bin/sh".to_string(),
                    arguments: vec!["-c".to_string(), exec_command],
                    environment,
                },
            }
        }
    }
}

async fn terminal_environment() -> BTreeMap<String, String> {
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if !cfg!(windows) {
        if let Some(path) = crate::login_shell_environment::login_shell_merged_path(
            environment.get("PATH").map(String::as_str),
        )
        .await
        {
            environment.insert("PATH".to_string(), path);
        }
        environment
            .entry("PATH".to_string())
            .or_insert_with(|| "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin".to_string());
        environment
            .entry("TERM".to_string())
            .or_insert_with(|| "xterm-256color".to_string());
    }
    environment
}

/// Flags that make `shell` read the login profile files (`~/.zprofile`,
/// `~/.profile`). Unknown shells are left alone rather than guessing a flag.
fn login_shell_arguments(shell: &str) -> &'static [&'static str] {
    let executable = shell.rsplit('/').next().unwrap_or(shell);
    match executable {
        "zsh" | "bash" | "sh" | "dash" | "ksh" | "ksh93" | "mksh" | "tcsh" | "csh" => &["-l"],
        "fish" | "nu" | "nushell" | "elvish" | "xonsh" => &["--login"],
        _ => &[],
    }
}

pub(super) fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

/// The directory as it must appear inside the `/k` argument of the launch.
///
/// It cannot be quoted. The whole `cd /d <dir>` string is one process argument,
/// and the standard library escapes a quote inside an argument as `\"`, which
/// `cmd.exe` does not understand: the `cd` then fails and the terminal opens in
/// whatever directory the host happened to be in, which on a remote host is
/// the user's home. Left unquoted, the argument is wrapped in one outer pair of
/// quotes that `/s` strips again, and `cd` accepts spaces without quotes. What
/// does need care are the characters `cmd.exe` would act on, which `^` escapes.
pub(super) fn cmd_launch_directory(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '"' => continue,
            '^' | '&' | '|' | '<' | '>' | '(' | ')' => {
                escaped.push('^');
                escaped.push(character);
            }
            _ => escaped.push(character),
        }
    }
    escaped
}

/// For text typed into a running `cmd.exe`, where quotes are read as quotes.
#[cfg(windows)]
pub(super) fn cmd_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_launches_are_explicit_for_posix_and_windows() {
        let posix = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo's root",
            "/bin/zsh",
            BTreeMap::new(),
            false,
        );
        assert_eq!(posix.launch.shell, "/bin/sh");
        assert_eq!(
            posix.launch.arguments,
            ["-c", "cd '/repo'\\''s root' || true; exec '/bin/zsh'"]
        );
        assert_eq!(posix.interactive_shell, "/bin/zsh");

        let windows = default_terminal_launch_for(
            TerminalPlatform::Windows,
            r#"C:\repo "main""#,
            "cmd.exe",
            BTreeMap::new(),
            false,
        );
        assert_eq!(windows.launch.shell, "cmd.exe");
        assert_eq!(
            windows.launch.arguments,
            ["/d", "/s", "/k", r"cd /d C:\repo main"],
            "no quotes inside the argument: the standard library would escape them as \\\" and cmd.exe cannot read that"
        );
        assert_eq!(
            cmd_launch_directory(r"C:\Users\me\R&D (new)^1"),
            r"C:\Users\me\R^&D ^(new^)^^1"
        );
    }

    #[test]
    fn posix_login_launch_adds_the_shell_login_flag() {
        let zsh = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo",
            "/bin/zsh",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            zsh.launch.arguments,
            ["-c", "cd '/repo' || true; exec '/bin/zsh' '-l'"]
        );

        let fish = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo",
            "/opt/homebrew/bin/fish",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            fish.launch.arguments,
            [
                "-c",
                "cd '/repo' || true; exec '/opt/homebrew/bin/fish' '--login'"
            ]
        );
    }

    #[test]
    fn unknown_login_shells_keep_their_default_arguments() {
        let launch = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo",
            "/usr/local/bin/exoticsh",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            launch.launch.arguments,
            ["-c", "cd '/repo' || true; exec '/usr/local/bin/exoticsh'"]
        );
    }

    #[test]
    fn windows_launch_ignores_the_login_shell_flag() {
        let windows = default_terminal_launch_for(
            TerminalPlatform::Windows,
            r"C:\repo",
            "cmd.exe",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            windows.launch.arguments,
            ["/d", "/s", "/k", r"cd /d C:\repo"]
        );
    }
}
