use std::collections::BTreeMap;
use std::process::Stdio;
use std::time::Duration;

use async_trait::async_trait;
use tokio::time::timeout;

#[path = "forge_cli_executable.rs"]
mod executable;

const FORGE_CLI_TIMEOUT: Duration = Duration::from_secs(45);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ForgeCliOutput {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Runs a forge CLI. Injected so provider tests can assert the argv and feed
/// canned output without spawning anything.
#[async_trait]
pub trait ForgeCliRunner: Send + Sync {
    async fn run(&self, program: &str, args: &[String]) -> std::io::Result<ForgeCliOutput>;
}

pub struct SystemForgeCliRunner;

#[async_trait]
impl ForgeCliRunner for SystemForgeCliRunner {
    async fn run(&self, program: &str, args: &[String]) -> std::io::Result<ForgeCliOutput> {
        let path = crate::login_shell_environment::login_shell_variable("PATH").await;
        let directories = path
            .as_deref()
            .map(std::env::split_paths)
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
        let executable = executable::resolve(program, cfg!(windows), &directories);
        let mut command = alera_core::child_process::windowless_async_command(executable);
        command
            .args(args)
            // Every fetch passes a full URL or organization, so the working
            // directory must not let a CLI infer a different repository.
            .current_dir(std::env::temp_dir())
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        // The sidecar starts detached, so a GUI launch would miss the PATH
        // entries (Homebrew, version managers) where these CLIs live.
        let overrides = BTreeMap::from([
            ("GH_PROMPT_DISABLED".to_string(), "1".to_string()),
            ("NO_PROMPT".to_string(), "1".to_string()),
            ("NO_COLOR".to_string(), "1".to_string()),
        ]);
        crate::login_shell_environment::apply_login_shell_environment(&mut command, &overrides)
            .await;
        let output = timeout(FORGE_CLI_TIMEOUT, command.output())
            .await
            .map_err(|_| {
                std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    format!("{program} did not answer within 45 seconds"),
                )
            })??;
        Ok(ForgeCliOutput {
            code: output.status.code().unwrap_or(1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;

    #[tokio::test]
    async fn windows_forge_runner_executes_a_command_shim_with_literal_arguments() {
        let root = tempfile::tempdir().unwrap();
        let shim = root.path().join("forge fixture.cmd");
        std::fs::write(&shim, "@echo off\r\necho %~1\r\n").unwrap();
        let argument = "work item with spaces";
        let output = SystemForgeCliRunner
            .run(shim.to_str().unwrap(), &[argument.into()])
            .await
            .unwrap();
        assert_eq!(output.code, 0);
        assert_eq!(output.stdout.trim(), argument);
    }
}
