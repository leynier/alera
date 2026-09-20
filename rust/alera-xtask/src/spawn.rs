//! Process spawn helpers for developer tooling.
//!
//! Windows makefile flows used Dart `runInShell: true` so `.cmd` / `.bat`
//! shims such as `flutter.bat` resolve. The quoting here matches
//! `rust/src/api/process_shell.rs`.

use std::collections::HashMap;
use std::ffi::OsStr;
use std::io;
use std::path::Path;
use std::process::{Output, Stdio};

use alera_core::child_process::windowless_command;

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

pub fn run_inherit(
    program: &str,
    args: &[impl AsRef<OsStr>],
    cwd: &Path,
    environment: Option<&HashMap<String, String>>,
    windows_shell: bool,
) -> io::Result<i32> {
    let mut command = spawn_command(program, args, windows_shell);
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
    let mut command = spawn_command(program, args, windows_shell);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    Ok(CapturedOutput::from_output(command.output()?))
}

fn spawn_command(
    program: &str,
    args: &[impl AsRef<OsStr>],
    windows_shell: bool,
) -> std::process::Command {
    #[cfg(windows)]
    if windows_shell {
        return windows_shell_command(program, args);
    }
    let _ = windows_shell;
    let mut command = windowless_command(program);
    command.args(args.iter().map(AsRef::as_ref));
    command
}

#[cfg(windows)]
fn windows_shell_command(program: &str, args: &[impl AsRef<OsStr>]) -> std::process::Command {
    use std::os::windows::process::CommandExt;

    let mut line = String::from("/d /s /c \"");
    line.push_str(&double_quoted(program));
    for arg in args {
        line.push(' ');
        line.push_str(&double_quoted(&arg.as_ref().to_string_lossy()));
    }
    line.push('"');
    let mut command = windowless_command("cmd.exe");
    command.raw_arg(line);
    command
}

#[cfg(windows)]
fn double_quoted(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\\\""))
}

#[cfg(test)]
mod tests {
    use super::quote_for_log;

    #[test]
    fn quote_for_log_wraps_whitespace() {
        assert_eq!(quote_for_log("git"), "git");
        assert_eq!(quote_for_log("a b"), "\"a b\"");
        assert_eq!(quote_for_log("a\tb"), "\"a\tb\"");
    }
}
