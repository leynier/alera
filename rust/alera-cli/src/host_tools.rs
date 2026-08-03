use std::env;
use std::path::{Path, PathBuf};

use alera_core::child_process::windowless_async_command;
use anyhow::{Context, Result};
use serde::Serialize;

use crate::login_shell_environment::setup_command_environment;

const WRAPPER_MARKER: &str = "alera-managed-cli-wrapper-v1";
const LEGACY_WRAPPER_MARKER: &str = "ALERA_CLI_WRAPPER=1";
const SKILL_REPOSITORY: &str = "https://github.com/leynier/alera";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CliRegistrationStatus {
    pub state: &'static str,
    pub ready: bool,
    pub path_configured: bool,
    pub command_path: Option<String>,
    pub detail: String,
}

pub(crate) async fn cli_registration_status(runtime_dir: &Path) -> CliRegistrationStatus {
    let Some(command_path) = command_path() else {
        return status(
            "unsupported",
            false,
            false,
            None,
            "CLI Registration Is Not Supported.",
        );
    };
    let launcher = match env::current_exe() {
        Ok(value) => value,
        Err(error) => {
            return status(
                "unsupported",
                false,
                false,
                Some(&command_path),
                &format!("Could Not Resolve The Alera Executable: {error}"),
            )
        }
    };
    let expected = wrapper_source(runtime_dir, &launcher);
    let path_resolution = resolve_path(&command_path).await;
    if !command_path.exists() {
        return status(
            "notInstalled",
            false,
            path_resolution,
            Some(&command_path),
            "Register The Alera Command To Use It From Terminals And Agents.",
        );
    }
    let content = match std::fs::read_to_string(&command_path) {
        Ok(value) => value,
        Err(_) => {
            return status(
                "conflict",
                false,
                path_resolution,
                Some(&command_path),
                "The Command Exists But Is Not Readable As Text.",
            )
        }
    };
    if content == expected {
        if !is_executable(&command_path) {
            return status(
                "stale",
                false,
                false,
                Some(&command_path),
                "The Registration Exists But Is Not Executable.",
            );
        }
        return status(
            "installed",
            path_resolution,
            path_resolution,
            Some(&command_path),
            if path_resolution {
                "The Alera Command Is Ready."
            } else {
                "The Alera Command Is Registered, But Its Directory Is Not On PATH."
            },
        );
    }
    let managed = is_managed_wrapper(&content);
    status(
        if managed { "stale" } else { "conflict" },
        false,
        path_resolution,
        Some(&command_path),
        if managed {
            "The Registration Points To An Older Alera Launcher."
        } else {
            "The Command Path Exists But Is Not Managed By Alera."
        },
    )
}

pub(crate) async fn install_cli_registration(runtime_dir: &Path) -> Result<CliRegistrationStatus> {
    let current = cli_registration_status(runtime_dir).await;
    if current.state == "conflict" || current.state == "unsupported" {
        return Ok(current);
    }
    let command_path = command_path().context("CLI registration is not supported")?;
    let launcher = env::current_exe().context("Could not resolve the Alera executable")?;
    if let Some(parent) = command_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&command_path, wrapper_source(runtime_dir, &launcher))?;
    set_executable(&command_path)?;
    Ok(cli_registration_status(runtime_dir).await)
}

#[derive(Debug, Clone, Copy)]
pub(crate) enum SkillKind {
    Cli,
    ComputerUse,
    Emulator,
    Orchestration,
    AgentCanvas,
}

impl SkillKind {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "cli" => Some(Self::Cli),
            "computer-use" => Some(Self::ComputerUse),
            "emulator" => Some(Self::Emulator),
            "orchestration" => Some(Self::Orchestration),
            "agent-canvas" | "canvas" => Some(Self::AgentCanvas),
            _ => None,
        }
    }

    fn package_name(self) -> &'static str {
        match self {
            Self::Cli => "alera-cli",
            Self::ComputerUse => "computer-use",
            Self::Emulator => "alera-emulator",
            Self::Orchestration => "alera-orchestration",
            Self::AgentCanvas => "alera-agent-canvas",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum SkillRunner {
    Auto,
    Npx,
    Bunx,
}

impl SkillRunner {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "auto" => Some(Self::Auto),
            "npx" => Some(Self::Npx),
            "bunx" => Some(Self::Bunx),
            _ => None,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SkillInstallResult {
    pub succeeded: bool,
    pub summary: String,
    pub attempts: Vec<SkillInstallAttempt>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SkillInstallAttempt {
    pub runner: SkillRunner,
    pub exit_code: i32,
    pub output: String,
    pub runner_missing: bool,
}

pub(crate) async fn install_skill(kind: SkillKind, runner: SkillRunner) -> SkillInstallResult {
    let environment = setup_command_environment().await;
    let runners = match runner {
        SkillRunner::Auto => vec![SkillRunner::Npx, SkillRunner::Bunx],
        value => vec![value],
    };
    let mut attempts = Vec::new();
    for candidate in runners {
        let attempt = run_skill_install(kind, candidate, &environment).await;
        let done = attempt.exit_code == 0 || !attempt.runner_missing;
        attempts.push(attempt);
        if done {
            break;
        }
    }
    let succeeded = attempts
        .last()
        .is_some_and(|attempt| attempt.exit_code == 0);
    let summary = if succeeded {
        format!("{} Installed", kind.package_name())
    } else {
        attempts
            .last()
            .map(|attempt| {
                if attempt.output.is_empty() {
                    format!("{} Install Failed", kind.package_name())
                } else {
                    format!("{} Install Failed: {}", kind.package_name(), attempt.output)
                }
            })
            .unwrap_or_else(|| format!("{} Install Failed", kind.package_name()))
    };
    SkillInstallResult {
        succeeded,
        summary,
        attempts,
    }
}

async fn run_skill_install(
    kind: SkillKind,
    runner: SkillRunner,
    environment: &[(String, String)],
) -> SkillInstallAttempt {
    let executable = match (cfg!(windows), runner) {
        (true, SkillRunner::Npx) => "npx.cmd",
        (_, SkillRunner::Npx) => "npx",
        (_, SkillRunner::Bunx) => "bunx",
        (_, SkillRunner::Auto) => unreachable!(),
    };
    let result = windowless_async_command(executable)
        .args([
            "skills",
            "add",
            SKILL_REPOSITORY,
            "--skill",
            kind.package_name(),
            "--global",
        ])
        .envs(environment.iter().cloned())
        .output()
        .await;
    match result {
        Ok(output) => {
            let combined = format!(
                "{}\n{}",
                String::from_utf8_lossy(&output.stderr),
                String::from_utf8_lossy(&output.stdout)
            );
            let detail = output_tail(&combined);
            let exit_code = output.status.code().unwrap_or(1);
            let lower = detail.to_lowercase();
            SkillInstallAttempt {
                runner,
                exit_code,
                runner_missing: exit_code == 127
                    || exit_code == 9009
                    || lower.contains("command not found")
                    || lower.contains("not recognized as an internal or external command"),
                output: detail,
            }
        }
        Err(error) => SkillInstallAttempt {
            runner,
            exit_code: if error.kind() == std::io::ErrorKind::NotFound {
                127
            } else {
                1
            },
            output: output_tail(&error.to_string()),
            runner_missing: error.kind() == std::io::ErrorKind::NotFound,
        },
    }
}

fn status(
    state: &'static str,
    ready: bool,
    path_configured: bool,
    command_path: Option<&Path>,
    detail: &str,
) -> CliRegistrationStatus {
    CliRegistrationStatus {
        state,
        ready,
        path_configured,
        command_path: command_path.map(|value| value.to_string_lossy().into_owned()),
        detail: detail.to_string(),
    }
}

fn command_path() -> Option<PathBuf> {
    if let Some(path) = env::var_os("ALERA_CLI_INSTALL_PATH") {
        return Some(PathBuf::from(path));
    }
    if cfg!(windows) {
        env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .or_else(|| dirs::home_dir().map(|home| home.join("AppData/Local")))
            .map(|root| root.join("Programs/Alera/bin/alera.cmd"))
    } else {
        dirs::home_dir().map(|home| home.join(".local/bin/alera"))
    }
}

async fn resolve_path(command_path: &Path) -> bool {
    let environment = setup_command_environment().await;
    let path = environment
        .iter()
        .find(|(key, _)| key.eq_ignore_ascii_case("PATH"))
        .map(|(_, value)| value);
    path.is_some_and(|value| {
        env::split_paths(value).any(|entry| entry == command_path.parent().unwrap_or(Path::new("")))
    })
}

fn wrapper_source(runtime_dir: &Path, launcher: &Path) -> String {
    if cfg!(windows) {
        format!(
            "@echo off\r\nrem Generated by Alera. Do not edit.\r\nrem {WRAPPER_MARKER}\r\nset \"ALERA_RUNTIME_DIR={}\"\r\n\"{}\" %*\r\nexit /b %ERRORLEVEL%\r\n",
            cmd_value(runtime_dir),
            cmd_value(launcher),
        )
    } else {
        format!(
            "#!/bin/sh\n# Generated by Alera. Do not edit.\n# {WRAPPER_MARKER}\nexport ALERA_RUNTIME_DIR={}\nexec {} \"$@\"\n",
            sh_quote(runtime_dir),
            sh_quote(launcher),
        )
    }
}

fn is_managed_wrapper(content: &str) -> bool {
    content.contains(WRAPPER_MARKER) || content.contains(LEGACY_WRAPPER_MARKER)
}

fn sh_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "'\"'\"'"))
}

fn cmd_value(path: &Path) -> String {
    path.to_string_lossy()
        .replace('%', "%%")
        .replace('"', "\"\"")
}

fn is_executable(path: &Path) -> bool {
    if cfg!(windows) {
        return true;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    true
}

fn set_executable(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(path)?.permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(path, permissions)?;
    }
    Ok(())
}

fn output_tail(value: &str) -> String {
    const MAX_CHARS: usize = 1_000;
    let value = value.trim();
    if value.chars().count() <= MAX_CHARS {
        return value.to_string();
    }
    value
        .chars()
        .rev()
        .take(MAX_CHARS)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrapper_contains_runtime_and_managed_marker() {
        let wrapper = wrapper_source(Path::new("/tmp/runtime"), Path::new("/opt/alera"));
        assert!(wrapper.contains(WRAPPER_MARKER));
        assert!(wrapper.contains("ALERA_RUNTIME_DIR"));
        assert!(wrapper.contains("/opt/alera"));
    }

    #[test]
    fn legacy_flutter_wrapper_is_still_managed() {
        let wrapper =
            "#!/bin/sh\n# ALERA_CLI_WRAPPER=1\nexec '/Applications/Alera.app/alera' \"$@\"\n";
        assert!(is_managed_wrapper(wrapper));
    }

    #[test]
    fn output_tail_is_bounded_on_unicode_boundaries() {
        let output = format!("{}ñ", "a".repeat(1_001));
        let tail = output_tail(&output);
        assert_eq!(tail.chars().count(), 1_000);
        assert!(tail.ends_with('ñ'));
    }

    #[test]
    fn emulator_skill_uses_its_repository_package_name() {
        let kind = SkillKind::parse("emulator").expect("emulator skill");
        assert_eq!(kind.package_name(), "alera-emulator");
    }
}
