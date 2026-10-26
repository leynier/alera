use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use async_trait::async_trait;
use tokio::time::timeout;

use super::cleanup_context::AgentCommandRunner;

const AGENT_COMMAND_TIMEOUT: Duration = Duration::from_secs(60);
const STDERR_EXCERPT_CHARS: usize = 160;

pub(super) struct SystemAgentCommandRunner;

#[async_trait]
impl AgentCommandRunner for SystemAgentCommandRunner {
    async fn run(
        &self,
        program: &str,
        args: &[String],
        env: &BTreeMap<String, String>,
    ) -> Result<(), String> {
        let path = crate::login_shell_environment::login_shell_command_environment()
            .await
            .and_then(|environment| environment.get("PATH").cloned())
            .or_else(|| std::env::var("PATH").ok());
        let executable = resolve_executable(program, path.as_deref());
        let mut command = alera_core::child_process::windowless_async_command(executable);
        command
            .args(args)
            // The workspace directory may already be gone, and no deletion
            // should depend on the project a CLI would infer from its cwd.
            .current_dir(std::env::temp_dir())
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        let mut overrides = BTreeMap::from([("NO_COLOR".to_string(), "1".to_string())]);
        overrides.extend(env.clone());
        crate::login_shell_environment::apply_login_shell_environment(&mut command, &overrides)
            .await;
        let output = match timeout(AGENT_COMMAND_TIMEOUT, command.output()).await {
            Ok(Ok(output)) => output,
            Ok(Err(error)) => return Err(format!("failed to start {program}: {error}")),
            Err(_) => return Err(format!("{program} did not finish within 60 seconds")),
        };
        if output.status.success() {
            return Ok(());
        }
        let code = output
            .status
            .code()
            .map_or_else(|| "a signal".to_string(), |code| code.to_string());
        Err(match stderr_excerpt(&output.stderr) {
            Some(excerpt) => format!("{program} exited with {code}: {excerpt}"),
            None => format!("{program} exited with {code}"),
        })
    }
}

/// The last non-empty stderr line, shortened: enough to tell "not found"
/// from "permission denied" without carrying a CLI's whole report.
fn stderr_excerpt(stderr: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(stderr);
    let line = text.lines().map(str::trim).rfind(|line| !line.is_empty())?;
    Some(line.chars().take(STDERR_EXCERPT_CHARS).collect())
}

/// Rust only appends `.exe` on a bare-name lookup, so the npm `.cmd` shims
/// several agents install on Windows have to be found explicitly.
fn resolve_executable(program: &str, path: Option<&str>) -> PathBuf {
    let candidate = Path::new(program);
    if !cfg!(windows) || candidate.extension().is_some() || candidate.components().count() != 1 {
        return candidate.to_path_buf();
    }
    let directories = path.map(std::env::split_paths).into_iter().flatten();
    for directory in directories.filter(|directory| directory.is_absolute()) {
        for extension in ["exe", "cmd", "bat"] {
            let shim = directory.join(format!("{program}.{extension}"));
            if shim.is_file() {
                return shim;
            }
        }
    }
    candidate.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stderr_excerpt_keeps_the_last_line_only() {
        assert_eq!(
            stderr_excerpt(b"warning: x\nerror: session not found\n\n").as_deref(),
            Some("error: session not found")
        );
        assert_eq!(stderr_excerpt(b"  \n"), None);
        let long = "e".repeat(400);
        assert_eq!(
            stderr_excerpt(long.as_bytes()).unwrap().len(),
            STDERR_EXCERPT_CHARS
        );
    }

    #[test]
    fn executable_resolution_leaves_posix_names_alone() {
        if !cfg!(windows) {
            assert_eq!(
                resolve_executable("codex", Some("/usr/bin")),
                PathBuf::from("codex")
            );
        }
    }
}
