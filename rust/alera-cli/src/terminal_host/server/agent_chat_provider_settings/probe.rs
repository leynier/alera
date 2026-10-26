use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use async_trait::async_trait;

const TIMEOUT: Duration = Duration::from_secs(8);
const MAX_BYTES: usize = 1024 * 1024;

pub(crate) struct ProbeCommand {
    pub executable: PathBuf,
    pub args: Vec<String>,
    pub environment: BTreeMap<String, String>,
    pub cwd: Option<PathBuf>,
}

pub(crate) struct ProbeOutput {
    pub success: bool,
    pub stdout: String,
}

#[async_trait]
pub(crate) trait ProviderProbe: Send + Sync {
    async fn run(&self, command: ProbeCommand) -> Result<ProbeOutput, String>;
}

#[derive(Default)]
pub(crate) struct WindowlessProviderProbe;

#[async_trait]
impl ProviderProbe for WindowlessProviderProbe {
    async fn run(&self, command: ProbeCommand) -> Result<ProbeOutput, String> {
        let mut process = alera_core::child_process::windowless_async_command(&command.executable);
        process
            .args(&command.args)
            .env_clear()
            .envs(&command.environment)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        if let Some(cwd) = command.cwd {
            process.current_dir(cwd);
        }
        let output = alera_core::captured_process::run_command(
            process,
            "provider probe",
            None,
            MAX_BYTES,
            Some(TIMEOUT),
        )
        .await
        .map_err(|_| "Provider probe failed or timed out.".to_owned())?;
        Ok(ProbeOutput {
            success: output.exit_code == 0,
            stdout: output.stdout,
        })
    }
}
