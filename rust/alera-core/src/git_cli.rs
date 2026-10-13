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
    git_in_dir_with_environment(dir, args, &std::collections::BTreeMap::new())
}

pub fn git_in_dir_with_environment(
    dir: &Path,
    args: &[&str],
    environment: &std::collections::BTreeMap<String, String>,
) -> Result<String, GitCliError> {
    let mut command = windowless_command("git");
    command
        .args(args)
        .envs(environment)
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

/// Runs a network command while draining both pipes and emitting bounded,
/// credential-redacted lines. The callback runs on this worker thread.
pub fn git_in_dir_with_progress(
    dir: &Path,
    args: &[&str],
    on_output: &(dyn Fn(String) + Send + Sync),
) -> Result<String, GitCliError> {
    use std::io::Read;
    let mut command = windowless_command("git");
    command
        .args(args)
        .current_dir(dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("GIT_TERMINAL_PROMPT", "0");
    let mut child = command.spawn().map_err(|error| GitCliError {
        message: format!("failed to run {}: {error}", describe(args)),
    })?;
    let stdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take().expect("piped stderr");
    let (sender, receiver) = std::sync::mpsc::sync_channel::<(bool, Vec<u8>)>(64);
    let mut out = Vec::new();
    let mut err = Vec::new();
    std::thread::scope(|scope| {
        fn drain(
            mut pipe: impl Read,
            stderr: bool,
            sender: std::sync::mpsc::SyncSender<(bool, Vec<u8>)>,
        ) {
            let mut bytes = [0; 2048];
            loop {
                match pipe.read(&mut bytes) {
                    Ok(0) | Err(_) => break,
                    Ok(size) => {
                        if sender.send((stderr, bytes[..size].to_vec())).is_err() {
                            break;
                        }
                    }
                }
            }
        }
        let second = sender.clone();
        scope.spawn(move || drain(stdout, false, sender));
        scope.spawn(move || drain(stderr, true, second));
        let mut lines = [Vec::new(), Vec::new()];
        let mut last_emitted = std::time::Instant::now() - std::time::Duration::from_secs(1);
        let mut latest = String::new();
        for (stderr, bytes) in receiver {
            let captured = if stderr { &mut err } else { &mut out };
            captured.extend_from_slice(&bytes);
            if captured.len() > 65536 {
                captured.drain(..captured.len() - 65536);
            }
            let line = &mut lines[usize::from(stderr)];
            for byte in bytes {
                if byte == b'\r' || byte == b'\n' {
                    if !line.is_empty() {
                        latest = redact_progress_line(&String::from_utf8_lossy(line));
                        line.clear();
                        if !latest.is_empty()
                            && last_emitted.elapsed() >= std::time::Duration::from_millis(100)
                        {
                            on_output(latest.clone());
                            last_emitted = std::time::Instant::now();
                        }
                    }
                } else if line.len() < 4096 {
                    line.push(byte);
                }
            }
        }
        for line in lines {
            if !line.is_empty() {
                latest = redact_progress_line(&String::from_utf8_lossy(&line));
            }
        }
        if !latest.is_empty() {
            on_output(latest);
        }
    });
    let status = child.wait().map_err(|error| GitCliError {
        message: error.to_string(),
    })?;
    let output = Output {
        status,
        stdout: out,
        stderr: err,
    };
    if !status.success() {
        return Err(GitCliError {
            message: failure_message(args, &output),
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn redact_progress_line(line: &str) -> String {
    let lower = line.to_ascii_lowercase();
    if lower.contains("authorization:")
        || lower.contains("password=")
        || lower.contains("token=")
        || lower.contains("bearer ")
    {
        return "[redacted authentication output]".to_string();
    }
    line.split_whitespace()
        .map(|word| {
            if let Some(scheme) = word.find("://") {
                if let Some(at) = word[scheme + 3..].find('@') {
                    return format!(
                        "{}[redacted]@{}",
                        &word[..scheme + 3],
                        &word[scheme + 3 + at + 1..]
                    );
                }
            }
            word.to_string()
        })
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .filter(|c| !c.is_control())
        .take(512)
        .collect()
}

fn describe(args: &[&str]) -> String {
    redact_progress_line(&format!("git {}", args.join(" ")))
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
        let detail = detail
            .split(['\r', '\n'])
            .map(redact_progress_line)
            .collect::<Vec<_>>()
            .join("\n");
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
