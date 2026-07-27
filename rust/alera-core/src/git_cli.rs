//! Invocation of the system `git` binary for the operations libgit2 cannot
//! serve: the networked ones, which need the user's credential helper.
//!
//! Spawning goes through [`windowless_command`] so these calls never open a
//! console window on Windows.

use std::fmt;
use std::path::Path;
use std::process::{Output, Stdio};

use crate::child_process::windowless_command;

/// A `git` invocation that could not be started or that exited non-zero. The
/// message already carries the CLI's own diagnostics, so callers can hand it to
/// their own error type without further formatting.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitCliError {
    pub message: String,
}

impl fmt::Display for GitCliError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for GitCliError {}

/// Runs `git <args>` with `dir` as the working directory and returns stdout.
pub fn git_in_dir(dir: &Path, args: &[&str]) -> Result<String, GitCliError> {
    let mut command = windowless_command("git");
    command
        .args(args)
        .current_dir(dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        // Nothing is attached to read a terminal prompt here, and on Windows
        // there is not even a console to draw one on, so a prompt would hang
        // invisibly instead of failing. Credential helpers that bring their own
        // window (Git Credential Manager) still run.
        .env("GIT_TERMINAL_PROMPT", "0");

    let output = command.output().map_err(|error| GitCliError {
        message: format!("failed to run {}: {error}", describe(args)),
    })?;
    if !output.status.success() {
        return Err(GitCliError {
            message: failure_message(args, &output),
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn describe(args: &[&str]) -> String {
    format!("git {}", args.join(" "))
}

fn failure_message(args: &[&str], output: &Output) -> String {
    let command = describe(args);
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let detail = if stderr.is_empty() {
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    } else {
        stderr
    };
    if !detail.is_empty() {
        return format!("{command} failed: {detail}");
    }
    match output.status.code() {
        Some(code) => format!("{command} failed with exit code {code}"),
        None => format!("{command} failed"),
    }
}

#[cfg(test)]
#[path = "git_cli_tests.rs"]
mod git_cli_tests;
