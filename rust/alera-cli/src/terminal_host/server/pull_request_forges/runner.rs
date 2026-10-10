//! Runs a forge CLI (`gh`, `glab`, `az`) for one checkout. Injected so the
//! providers can be tested against recorded CLI output, and so Watch and Fix
//! can merge a remote checkout on the host that owns it.

use std::collections::{BTreeMap, HashMap};
use std::time::Duration;

use alera_core::runtime::{RuntimeStore, Workspace};
use async_trait::async_trait;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

const FORGE_CLI_TIMEOUT: Duration = Duration::from_secs(45);
const MAX_OUTPUT_BYTES: usize = alera_core::captured_process::DEFAULT_MAX_OUTPUT_BYTES;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ForgeOutput {
    pub(crate) code: i32,
    pub(crate) stdout: String,
    pub(crate) stderr: String,
}

#[async_trait]
pub(crate) trait ForgeRunner: Send + Sync {
    /// Runs [program] with [args]. A program that cannot start answers exit
    /// code 127, the shell's "command not found", so callers classify one
    /// shape of failure.
    async fn run(
        &self,
        program: &str,
        args: &[String],
        environment: &[(String, String)],
    ) -> HostResult<ForgeOutput> {
        self.run_with_stdin(program, args, environment, None).await
    }

    /// [run] with [stdin] piped to the program. Request bodies travel this
    /// way (or in a file) and never on the command line, where free text
    /// would reach a shell or a CLI's own `@file` expansion.
    async fn run_with_stdin(
        &self,
        program: &str,
        args: &[String],
        environment: &[(String, String)],
        stdin: Option<&str>,
    ) -> HostResult<ForgeOutput>;

    /// Whether a file this process writes is visible to the program it runs.
    /// A runner for a remote checkout answers false, so callers do not hand
    /// it a path that only exists here.
    fn shares_local_files(&self) -> bool {
        true
    }
}

/// Runs in a checkout on this machine, through the login-shell environment
/// so a GUI-launched sidecar still finds Homebrew and version-manager CLIs.
pub(crate) struct LocalRunner {
    pub(crate) cwd: String,
}

#[async_trait]
impl ForgeRunner for LocalRunner {
    async fn run_with_stdin(
        &self,
        program: &str,
        args: &[String],
        environment: &[(String, String)],
        stdin: Option<&str>,
    ) -> HostResult<ForgeOutput> {
        let mut env = environment.iter().cloned().collect::<HashMap<_, _>>();
        env.entry("GH_PROMPT_DISABLED".into())
            .or_insert_with(|| "1".into());
        env.entry("NO_PROMPT".into()).or_insert_with(|| "1".into());
        env.entry("NO_COLOR".into()).or_insert_with(|| "1".into());
        let mut command = super::local_command::forge_command(program, args, &self.cwd, &env);
        crate::login_shell_environment::apply_login_shell_environment(
            &mut command,
            &env.clone().into_iter().collect::<BTreeMap<_, _>>(),
        )
        .await;
        match alera_core::captured_process::run_command(
            command,
            program,
            stdin.map(|input| input.as_bytes().to_vec()),
            MAX_OUTPUT_BYTES,
            Some(FORGE_CLI_TIMEOUT),
        )
        .await
        {
            Ok(output) => Ok(ForgeOutput {
                code: output.exit_code,
                stdout: output.stdout,
                stderr: output.stderr,
            }),
            Err(error) if error.starts_with("failed to run") => Ok(ForgeOutput {
                code: 127,
                stdout: String::new(),
                stderr: error,
            }),
            Err(error) if error.to_ascii_lowercase().contains("timed out") => {
                Err(HostError::state(format!(
                    "{program} did not answer within 45 seconds. Verify the pull request before retrying a write."
                )))
            }
            Err(error) => Err(HostError::state(error)),
        }
    }
}

/// Runs in the workspace's checkout, on the host that owns it: forwarded as
/// `host.process.run` over the host link for a remote workspace, locally
/// otherwise.
pub(crate) struct WorkspaceRunner {
    pub(crate) store: RuntimeStore,
    pub(crate) links: HostLinkRegistry,
    pub(crate) workspace: Workspace,
}

#[async_trait]
impl ForgeRunner for WorkspaceRunner {
    async fn run_with_stdin(
        &self,
        program: &str,
        args: &[String],
        environment: &[(String, String)],
        stdin: Option<&str>,
    ) -> HostResult<ForgeOutput> {
        let mut payload = json!({
            "workspaceId": self.workspace.id,
            "executable": program,
            "arguments": args,
            "environment": environment.iter().cloned().collect::<BTreeMap<_, _>>(),
            "timeoutMs": FORGE_CLI_TIMEOUT.as_millis() as u64,
        });
        if let Some(stdin) = stdin {
            payload["stdin"] = Value::String(stdin.to_string());
        }
        let forwarded = super::super::host_link_routing::forward_workspace_scoped_request(
            &self.store,
            &self.links,
            super::super::host_process_requests::HOST_PROCESS_RUN,
            &payload,
        )
        .await?;
        let Some(output) = forwarded else {
            let cwd = self.workspace.path.clone();
            // `gh` keeps the exact spawn path the runtime always used.
            return if program == "gh" {
                super::github::GhRunner { cwd }
                    .run_with_stdin(program, args, environment, stdin)
                    .await
            } else {
                LocalRunner { cwd }
                    .run_with_stdin(program, args, environment, stdin)
                    .await
            };
        };
        let text = |key: &str| output[key].as_str().unwrap_or_default().to_string();
        Ok(ForgeOutput {
            code: output
                .get("exitCode")
                .and_then(Value::as_i64)
                .and_then(|code| i32::try_from(code).ok())
                .unwrap_or(1),
            stdout: text("stdout"),
            stderr: text("stderr"),
        })
    }

    fn shares_local_files(&self) -> bool {
        !crate::ssh_remote::is_remote_host_id(Some(&self.workspace.host_id))
    }
}

#[cfg(test)]
pub(crate) mod fake {
    use std::collections::VecDeque;
    use std::sync::Mutex;

    use super::*;

    /// One recorded call: the program, its argv, its environment and stdin.
    #[derive(Debug, Clone)]
    pub(crate) struct RecordedCall {
        pub(crate) program: String,
        pub(crate) args: Vec<String>,
        pub(crate) environment: Vec<(String, String)>,
        pub(crate) stdin: Option<String>,
    }

    impl RecordedCall {
        /// The value after `--name`, like the Dart fake's `optionValue`.
        pub(crate) fn option(&self, name: &str) -> Option<&str> {
            let flag = format!("--{name}");
            self.args
                .iter()
                .position(|arg| *arg == flag)
                .and_then(|index| self.args.get(index + 1))
                .map(String::as_str)
        }
    }

    /// Answers queued outputs in order and records every call. A call that
    /// names an `--in-file` also records that file's contents, read while
    /// the call runs, since the provider removes it afterwards.
    pub(crate) struct FakeRunner {
        pub(crate) outputs: Mutex<VecDeque<ForgeOutput>>,
        pub(crate) calls: Mutex<Vec<RecordedCall>>,
        pub(crate) in_files: Mutex<Vec<Option<String>>>,
        pub(crate) local_files: bool,
    }

    impl FakeRunner {
        pub(crate) fn new(outputs: impl IntoIterator<Item = ForgeOutput>) -> Self {
            Self {
                outputs: Mutex::new(outputs.into_iter().collect()),
                calls: Mutex::default(),
                in_files: Mutex::default(),
                local_files: true,
            }
        }

        /// A fake for a checkout on another host.
        pub(crate) fn remote(outputs: impl IntoIterator<Item = ForgeOutput>) -> Self {
            Self {
                local_files: false,
                ..Self::new(outputs)
            }
        }

        /// The `--in-file` contents of call [index], if it named one.
        pub(crate) fn in_file(&self, index: usize) -> Option<String> {
            self.in_files.lock().unwrap().get(index).cloned().flatten()
        }

        pub(crate) fn calls(&self) -> Vec<RecordedCall> {
            self.calls.lock().unwrap().clone()
        }
    }

    pub(crate) fn ok(stdout: &str) -> ForgeOutput {
        ForgeOutput {
            code: 0,
            stdout: stdout.to_string(),
            stderr: String::new(),
        }
    }

    pub(crate) fn failed(code: i32, stderr: &str) -> ForgeOutput {
        ForgeOutput {
            code,
            stdout: String::new(),
            stderr: stderr.to_string(),
        }
    }

    #[async_trait]
    impl ForgeRunner for FakeRunner {
        async fn run_with_stdin(
            &self,
            program: &str,
            args: &[String],
            environment: &[(String, String)],
            stdin: Option<&str>,
        ) -> HostResult<ForgeOutput> {
            let call = RecordedCall {
                program: program.to_string(),
                args: args.to_vec(),
                environment: environment.to_vec(),
                stdin: stdin.map(str::to_string),
            };
            let in_file = call
                .option("in-file")
                .and_then(|path| std::fs::read_to_string(path).ok());
            self.in_files.lock().unwrap().push(in_file);
            self.calls.lock().unwrap().push(call);
            Ok(self
                .outputs
                .lock()
                .unwrap()
                .pop_front()
                .unwrap_or_else(|| failed(1, "no fake output queued")))
        }

        fn shares_local_files(&self) -> bool {
            self.local_files
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_missing_cli_reads_as_exit_127() {
        let dir = std::env::temp_dir();
        let output = LocalRunner {
            cwd: dir.to_string_lossy().into_owned(),
        }
        .run("alera-no-such-forge-cli", &[], &[])
        .await
        .unwrap();
        assert_eq!(output.code, 127);
    }

    #[tokio::test]
    async fn stdin_reaches_the_program_and_argv_is_not_reinterpreted() {
        let dir = tempfile::tempdir().unwrap();
        let runner = LocalRunner {
            cwd: dir.path().to_string_lossy().into_owned(),
        };
        let output = runner
            .run_with_stdin("cat", &[], &[], Some("{\"body\":\"$(id) & %PATH%\"}"))
            .await
            .unwrap();
        assert_eq!(output.stdout, "{\"body\":\"$(id) & %PATH%\"}");
        let output = runner
            .run("printf", &["%s".into(), "$(id);`id`".into()], &[])
            .await
            .unwrap();
        assert_eq!(output.stdout, "$(id);`id`");
    }
}
