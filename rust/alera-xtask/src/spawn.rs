//! Process spawn helpers for developer tooling.
//!
//! Windows makefile flows used Dart `runInShell: true` so `.cmd` / `.bat`
//! shims such as `flutter.bat` resolve. Argument quoting matches
//! `rust/src/api/process_shell.rs`, but a plain program name stays bare,
//! because `cmd.exe` resolves `%~dp0` of a quoted batch file found through
//! PATH against the working directory, which makes `flutter.bat` compute
//! `FLUTTER_ROOT` from the repository.

use std::collections::HashMap;
use std::ffi::OsStr;
use std::io;
use std::path::Path;
use std::process::{Output, Stdio};

use alera_core::child_process::{console_command, windowless_command};

#[derive(Debug, Clone)]
pub struct CapturedOutput {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

impl CapturedOutput {
    fn from_output(output: Output) -> Self {
        Self {
            status: output.status.code().unwrap_or(1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        }
    }
}

pub fn quote_for_log(value: &str) -> String {
    if value.contains(char::is_whitespace) {
        format!("\"{value}\"")
    } else {
        value.to_string()
    }
}

pub fn format_command_line(program: &str, args: &[impl AsRef<str>]) -> String {
    let mut parts = Vec::with_capacity(args.len() + 1);
    parts.push(quote_for_log(program));
    for arg in args {
        parts.push(quote_for_log(arg.as_ref()));
    }
    parts.join(" ")
}

/// Spawn a child that stays on this console so Windows makefile debug
/// targets keep TTY detection, hot-reload keys, and Ctrl+C.
pub fn run_inherit(
    program: &str,
    args: &[impl AsRef<OsStr>],
    cwd: &Path,
    environment: Option<&HashMap<String, String>>,
    windows_shell: bool,
) -> io::Result<i32> {
    let mut command = spawn_command(program, args, windows_shell, true);
    command.current_dir(cwd);
    if let Some(environment) = environment {
        command.envs(environment);
    }
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    Ok(command.status()?.code().unwrap_or(1))
}

pub fn run_captured(
    program: &str,
    args: &[impl AsRef<OsStr>],
    cwd: Option<&Path>,
    windows_shell: bool,
) -> io::Result<CapturedOutput> {
    let mut command = spawn_command(program, args, windows_shell, false);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    Ok(CapturedOutput::from_output(command.output()?))
}

/// Like `run_inherit`, but captures stdout so a caller can read cargo's JSON
/// messages while progress and diagnostics still reach the console on stderr.
pub fn run_with_captured_stdout(
    program: &str,
    args: &[impl AsRef<OsStr>],
    cwd: &Path,
    windows_shell: bool,
) -> io::Result<CapturedOutput> {
    let mut command = spawn_command(program, args, windows_shell, true);
    command
        .current_dir(cwd)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    Ok(CapturedOutput::from_output(command.output()?))
}

fn spawn_command(
    program: &str,
    args: &[impl AsRef<OsStr>],
    windows_shell: bool,
    inherit_console: bool,
) -> std::process::Command {
    #[cfg(windows)]
    if windows_shell {
        return windows_shell_command(program, args, inherit_console);
    }
    let _ = windows_shell;
    let mut command = if inherit_console {
        console_command(program)
    } else {
        windowless_command(program)
    };
    command.args(args.iter().map(AsRef::as_ref));
    command
}

#[cfg(any(windows, test))]
fn windows_shell_line(program: &str, args: &[impl AsRef<OsStr>]) -> String {
    let mut line = String::from("/d /s /c \"");
    line.push_str(&cmd_program_token(program));
    for arg in args {
        line.push(' ');
        line.push_str(&double_quoted(&arg.as_ref().to_string_lossy()));
    }
    line.push('"');
    line
}

/// A quoted batch file found through PATH gets the working directory as its
/// `%~dp0`, so plain names stay bare; paths and anything `cmd.exe` would
/// split or expand keep their quotes.
#[cfg(any(windows, test))]
fn cmd_program_token(program: &str) -> String {
    let plain = !program.is_empty()
        && program.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-' | '+')
        });
    if plain {
        program.to_string()
    } else {
        double_quoted(program)
    }
}

#[cfg(any(windows, test))]
fn double_quoted(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\\\""))
}

#[cfg(windows)]
fn windows_shell_command(
    program: &str,
    args: &[impl AsRef<OsStr>],
    inherit_console: bool,
) -> std::process::Command {
    use std::os::windows::process::CommandExt;

    let mut command = if inherit_console {
        console_command("cmd.exe")
    } else {
        windowless_command("cmd.exe")
    };
    command.raw_arg(windows_shell_line(program, args));
    command
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_for_log_wraps_whitespace() {
        assert_eq!(quote_for_log("git"), "git");
        assert_eq!(quote_for_log("a b"), "\"a b\"");
        assert_eq!(quote_for_log("a\tb"), "\"a\tb\"");
    }

    #[cfg(unix)]
    #[test]
    fn run_captured_records_success() {
        let output = super::run_captured("true", &[] as &[&str], None, false).unwrap();
        assert_eq!(output.status, 0);
    }

    #[cfg(unix)]
    #[test]
    fn run_with_captured_stdout_keeps_stderr_inherited() {
        let output = super::run_with_captured_stdout(
            "sh",
            &["-c", "printf out; printf err >&2"],
            Path::new("."),
            false,
        )
        .unwrap();
        assert_eq!(output.status, 0);
        assert_eq!(output.stdout, "out");
        assert!(output.stderr.is_empty());
    }

    #[test]
    fn windows_shell_line_leaves_plain_program_bare() {
        assert_eq!(
            windows_shell_line("flutter", &["run", "-d", "windows"]),
            r#"/d /s /c "flutter "run" "-d" "windows"""#
        );
        assert_eq!(
            windows_shell_line("flutter.bat", &["run"]),
            r#"/d /s /c "flutter.bat "run"""#
        );
        assert_eq!(
            windows_shell_line("cargo", &["build", "--locked"]),
            r#"/d /s /c "cargo "build" "--locked"""#
        );
    }

    #[test]
    fn windows_shell_line_quotes_program_paths() {
        assert_eq!(
            windows_shell_line(r"C:\flutter\bin\flutter.bat", &["run"]),
            r#"/d /s /c ""C:\flutter\bin\flutter.bat" "run"""#
        );
        assert_eq!(
            windows_shell_line(r"C:\Program Files\Rust\cargo.exe", &[] as &[&str]),
            r#"/d /s /c ""C:\Program Files\Rust\cargo.exe"""#
        );
        assert_eq!(
            windows_shell_line(r"tool\flutter.bat", &["run"]),
            r#"/d /s /c ""tool\flutter.bat" "run"""#
        );
    }

    #[test]
    fn windows_shell_line_quotes_unsafe_program_names() {
        assert_eq!(
            windows_shell_line("my tool", &[] as &[&str]),
            r#"/d /s /c ""my tool"""#
        );
        assert_eq!(
            windows_shell_line("a&b", &[] as &[&str]),
            r#"/d /s /c ""a&b"""#
        );
        assert_eq!(
            windows_shell_line("x%PATH%", &[] as &[&str]),
            r#"/d /s /c ""x%PATH%"""#
        );
        assert_eq!(windows_shell_line("", &[] as &[&str]), r#"/d /s /c """""#);
    }

    #[test]
    fn windows_shell_line_keeps_argument_quoting() {
        assert_eq!(
            windows_shell_line("flutter", &[r#"--dart-define=A="b""#]),
            r#"/d /s /c "flutter "--dart-define=A=\"b\""""#
        );
    }

    #[cfg(windows)]
    #[test]
    fn windows_shell_resolves_batch_directory_through_path() {
        let bin = tempfile::tempdir().unwrap();
        let cwd = tempfile::tempdir().unwrap();
        let script = bin.path().join("xtask850probe.bat");
        std::fs::write(&script, "@echo off\r\necho %~dp0\r\n").unwrap();
        let inherited = std::env::var("PATH").unwrap_or_default();
        let path = format!("{};{inherited}", bin.path().display());
        let output = super::spawn_command("xtask850probe", &["run"], true, false)
            .env("PATH", path)
            .current_dir(cwd.path())
            .stdout(std::process::Stdio::piped())
            .output()
            .unwrap();
        let printed = normalize_cmd_dir(&String::from_utf8_lossy(&output.stdout));
        let canonical = bin.path().canonicalize().unwrap();
        let expected = normalize_cmd_dir(&canonical.to_string_lossy());
        let marker = canonical
            .file_name()
            .unwrap()
            .to_string_lossy()
            .into_owned();
        let cwd_text = normalize_cmd_dir(&cwd.path().to_string_lossy());
        let resolved = printed.eq_ignore_ascii_case(&expected)
            || printed
                .to_ascii_lowercase()
                .ends_with(&marker.to_ascii_lowercase());
        assert!(
            output.status.success() && resolved && !printed.eq_ignore_ascii_case(&cwd_text),
            "{printed} expected {expected} cwd {cwd_text} {output:?}"
        );
    }

    #[cfg(windows)]
    fn normalize_cmd_dir(value: &str) -> String {
        let trimmed = value.trim().trim_end_matches(['\\', '/']);
        trimmed.strip_prefix(r"\\?\").unwrap_or(trimmed).to_string()
    }
}
