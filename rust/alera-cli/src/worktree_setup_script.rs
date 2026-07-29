//! Generates the script a deferred worktree setup runs inside the "Setup"
//! terminal tab, plus the single line that invokes it.
//!
//! The line is typed into whatever interactive shell the user configured, so it
//! cannot use shell-specific syntax. `&&` is out: PowerShell 5.1 rejects it at
//! parse time and nushell dropped it. Sequencing lives in the script instead,
//! which also keeps the bytes off the PTY: writing one command per line up
//! front would deliver the later lines to the *foreground process* of the
//! earlier one rather than to the shell.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

/// Where the generated script lives and how the terminal invokes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeSetupScript {
    pub path: PathBuf,
    pub command: String,
}

/// Prefix every generated script shares, so a startup sweep can recognise its
/// own leftovers without tracking them.
pub const SETUP_SCRIPT_PREFIX: &str = "worktree-setup-";

pub fn setup_script_path(directory: &Path, workspace_id: &str, windows: bool) -> PathBuf {
    let extension = if windows { "cmd" } else { "sh" };
    directory.join(format!(
        "{SETUP_SCRIPT_PREFIX}{}.{extension}",
        sanitize_workspace_id(workspace_id)
    ))
}

/// Writes the script and returns it together with its invocation line.
pub fn write_setup_script(
    directory: &Path,
    alera_executable: &Path,
    workspace_id: &str,
    workspace_path: &str,
    commands: &[String],
    copies: bool,
) -> Result<WorktreeSetupScript> {
    let windows = cfg!(windows);
    let path = setup_script_path(directory, workspace_id, windows);
    std::fs::create_dir_all(directory)
        .with_context(|| format!("Could not create {}", directory.display()))?;
    let contents = if windows {
        windows_script(
            alera_executable,
            workspace_id,
            workspace_path,
            commands,
            copies,
        )
    } else {
        posix_script(
            alera_executable,
            workspace_id,
            workspace_path,
            commands,
            copies,
        )
    };
    std::fs::write(&path, contents)
        .with_context(|| format!("Could not write {}", path.display()))?;
    make_executable(&path)?;
    let command = invocation_line(&path, windows);
    Ok(WorktreeSetupScript { path, command })
}

/// Deletes every leftover setup script in `directory`.
///
/// Anything still there belongs to a previous host lifetime, so the terminal
/// that would have run it is already gone.
pub fn remove_stale_setup_scripts(directory: &Path) {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        if name.starts_with(SETUP_SCRIPT_PREFIX) {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

/// A bare launcher token plus one quoted path, which is the only shape that
/// survives sh, bash, zsh, fish, nushell, cmd.exe, PowerShell 5.1 and pwsh
/// alike. PowerShell needs `&` before a *quoted* command, so the launcher is
/// deliberately left unquoted.
pub fn invocation_line(path: &Path, windows: bool) -> String {
    let path = path.display();
    if windows {
        // `/s` is omitted on purpose: it strips the outer quotes and a path
        // with spaces then breaks apart. Without it cmd keeps the single
        // quoted pair intact.
        format!("cmd /d /c \"{path}\"")
    } else {
        format!("/bin/sh \"{path}\"")
    }
}

fn posix_script(
    alera_executable: &Path,
    workspace_id: &str,
    workspace_path: &str,
    commands: &[String],
    copies: bool,
) -> String {
    let mut script = String::from("#!/bin/sh\n");
    if copies {
        script.push_str(&format!(
            "{} workspace setup --id {} --copies-only\n",
            posix_quote(&alera_executable.display().to_string()),
            posix_quote(workspace_id),
        ));
    }
    script.push_str(&format!("cd {} || exit 1\n", posix_quote(workspace_path)));
    for command in commands {
        // No `set -e` and no `||`: every command runs even after a failure.
        script.push_str(&format!("echo {}\n", posix_quote(&format!("> {command}"))));
        script.push_str(command);
        script.push('\n');
    }
    // Last line on purpose: unlink is safe while the fd stays open.
    script.push_str("rm -f -- \"$0\"\n");
    script
}

fn windows_script(
    alera_executable: &Path,
    workspace_id: &str,
    workspace_path: &str,
    commands: &[String],
    copies: bool,
) -> String {
    let mut script = String::from("@echo off\r\n");
    if copies {
        script.push_str(&format!(
            "\"{}\" workspace setup --id \"{}\" --copies-only\r\n",
            alera_executable.display(),
            workspace_id,
        ));
    }
    script.push_str(&format!("cd /d \"{workspace_path}\"\r\n"));
    for command in commands {
        script.push_str(&format!("echo {}\r\n", cmd_echo_marker(command)));
        script.push_str(command);
        script.push_str("\r\n");
    }
    // Last line on purpose: cmd re-reads the file by offset, so deleting it
    // earlier would truncate the run.
    script.push_str("del /q \"%~f0\"\r\n");
    script
}

/// Wraps in single quotes, which makes every other character inert in POSIX
/// shells, and closes/reopens the quoting around embedded single quotes.
fn posix_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

/// Builds the `> <command>` marker line for cmd.exe. `echo` there has no
/// quoting, so every shell metacharacter has to be escaped one by one with `^`.
fn cmd_echo_marker(value: &str) -> String {
    let mut escaped = String::from("^> ");
    for character in value.chars() {
        if matches!(
            character,
            '^' | '&' | '|' | '<' | '>' | '(' | ')' | '%' | '!' | '"'
        ) {
            escaped.push('^');
        }
        escaped.push(character);
    }
    escaped
}

/// Keeps a workspace id from steering the script anywhere but the target
/// directory. Ids are uuids in practice, so this never rewrites a real one.
fn sanitize_workspace_id(workspace_id: &str) -> String {
    workspace_id
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '-' || character == '_' {
                character
            } else {
                '_'
            }
        })
        .collect()
}

#[cfg(unix)]
fn make_executable(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(path, permissions)
        .with_context(|| format!("Could not mark {} executable", path.display()))
}

#[cfg(not(unix))]
fn make_executable(_path: &Path) -> Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn commands() -> Vec<String> {
        vec!["pnpm install".to_string(), "pnpm build".to_string()]
    }

    #[test]
    fn posix_script_runs_every_command_without_chaining() {
        let script = posix_script(
            Path::new("/opt/alera/alera"),
            "ws-1",
            "/home/u/work space",
            &commands(),
            true,
        );
        assert!(script.starts_with("#!/bin/sh\n"), "{script}");
        assert!(
            script.contains("'/opt/alera/alera' workspace setup --id 'ws-1' --copies-only\n"),
            "{script}"
        );
        assert!(
            script.contains("cd '/home/u/work space' || exit 1\n"),
            "{script}"
        );
        assert!(
            script.contains("echo '> pnpm install'\npnpm install\n"),
            "{script}"
        );
        assert!(
            script.contains("echo '> pnpm build'\npnpm build\n"),
            "{script}"
        );
        assert!(!script.contains("&&"), "{script}");
        assert!(!script.contains("set -e"), "{script}");
        assert!(script.ends_with("rm -f -- \"$0\"\n"), "{script}");
    }

    #[test]
    fn posix_script_skips_the_copy_step_when_there_are_no_rules() {
        let script = posix_script(
            Path::new("/opt/alera/alera"),
            "ws-1",
            "/tmp/ws",
            &commands(),
            false,
        );
        assert!(!script.contains("--copies-only"), "{script}");
    }

    #[test]
    fn posix_script_quotes_paths_containing_single_quotes() {
        let script = posix_script(Path::new("/opt/alera"), "ws-1", "/tmp/it's", &[], false);
        assert!(
            script.contains(r#"cd '/tmp/it'\''s' || exit 1"#),
            "{script}"
        );
    }

    #[test]
    fn windows_script_runs_every_command_without_chaining() {
        let script = windows_script(
            Path::new(r"C:\Program Files\Alera\alera.exe"),
            "ws-1",
            r"C:\work space\ws",
            &commands(),
            true,
        );
        assert!(script.starts_with("@echo off\r\n"), "{script}");
        assert!(
            script.contains(
                "\"C:\\Program Files\\Alera\\alera.exe\" workspace setup --id \"ws-1\" --copies-only\r\n"
            ),
            "{script}"
        );
        assert!(
            script.contains("cd /d \"C:\\work space\\ws\"\r\n"),
            "{script}"
        );
        assert!(
            script.contains("echo ^> pnpm install\r\npnpm install\r\n"),
            "{script}"
        );
        assert!(!script.contains("&&"), "{script}");
        assert!(script.ends_with("del /q \"%~f0\"\r\n"), "{script}");
    }

    #[test]
    fn cmd_echo_marker_escapes_shell_metacharacters() {
        assert_eq!(cmd_echo_marker("a & b > c"), "^> a ^& b ^> c");
    }

    #[test]
    fn invocation_keeps_the_launcher_unquoted_and_the_path_quoted() {
        assert_eq!(
            invocation_line(Path::new("/run/alera/worktree-setup-ws 1.sh"), false),
            "/bin/sh \"/run/alera/worktree-setup-ws 1.sh\""
        );
        let windows = invocation_line(Path::new(r"C:\a b\worktree-setup-ws.cmd"), true);
        assert_eq!(windows, "cmd /d /c \"C:\\a b\\worktree-setup-ws.cmd\"");
        assert!(!windows.contains("/s"), "{windows}");
    }

    #[test]
    fn script_name_cannot_escape_the_target_directory() {
        let path = setup_script_path(Path::new("/run/alera"), "../../etc/passwd", false);
        assert_eq!(
            path,
            PathBuf::from("/run/alera/worktree-setup-______etc_passwd.sh")
        );
    }

    #[test]
    fn stale_scripts_are_swept_and_other_files_are_left_alone() {
        let directory = tempfile::tempdir().expect("tempdir");
        let stale = setup_script_path(directory.path(), "ws-1", false);
        std::fs::write(&stale, "#!/bin/sh\n").expect("write");
        let control = directory.path().join("runtime-host.json");
        std::fs::write(&control, "{}").expect("write");

        remove_stale_setup_scripts(directory.path());

        assert!(!stale.exists());
        assert!(control.exists());
    }
}
