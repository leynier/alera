use alera_core::captured_process::ProcessTreeGuard;
use alera_core::child_process::windowless_async_command;
use alera_core::login_shell_environment::{apply_login_shell_environment, login_shell_variable};
use async_trait::async_trait;
use serde::Serialize;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::pin::Pin;
use std::process::Stdio;
use tokio::io::AsyncRead;
use tokio::process::Child;

pub type TerminalReadPipe = Pin<Box<dyn AsyncRead + Send>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientTerminalCommand {
    pub command: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub env: BTreeMap<OsString, OsString>,
    pub shell: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientTerminalExitStatus {
    pub exit_code: Option<i32>,
    pub signal: Option<String>,
}

/// The process owner must terminate descendants and reap its child on drop.
#[async_trait]
pub trait ClientTerminalChild: Send {
    async fn wait(&mut self) -> Result<ClientTerminalExitStatus, String>;
    fn terminate(&self);
}

pub struct SpawnedClientTerminal {
    pub child: Box<dyn ClientTerminalChild>,
    pub stdout: TerminalReadPipe,
    pub stderr: TerminalReadPipe,
}

#[async_trait]
pub trait ClientTerminalSpawner: Send + Sync {
    async fn spawn(&self, command: ClientTerminalCommand) -> Result<SpawnedClientTerminal, String>;
}

#[derive(Debug, Default)]
pub struct NativeClientTerminalSpawner;

#[async_trait]
impl ClientTerminalSpawner for NativeClientTerminalSpawner {
    async fn spawn(&self, input: ClientTerminalCommand) -> Result<SpawnedClientTerminal, String> {
        let (executable, args) = if input.shell {
            shell_command(&input.command).await?
        } else {
            (input.command.clone(), input.args.clone())
        };
        let mut command = windowless_async_command(executable);
        let explicit = input
            .env
            .iter()
            .filter_map(|(name, value)| {
                Some((name.to_str()?.to_owned(), value.to_str()?.to_owned()))
            })
            .collect();
        apply_login_shell_environment(&mut command, &explicit).await;
        command
            .args(args)
            .envs(&input.env)
            .current_dir(input.cwd)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        ProcessTreeGuard::prepare_command(&mut command);
        let mut child = command.spawn().map_err(|error| error.to_string())?;
        let tree = match ProcessTreeGuard::attach(&child) {
            Ok(tree) => tree,
            Err(error) => {
                let _ = child.kill().await;
                let _ = child.wait().await;
                return Err(error);
            }
        };
        let mut owner = NativeTerminalChild {
            child: Some(child),
            tree,
        };
        let child = owner.child.as_mut().expect("spawned child is present");
        let stdout = child.stdout.take().ok_or("terminal stdout is not piped")?;
        let stderr = child.stderr.take().ok_or("terminal stderr is not piped")?;
        Ok(SpawnedClientTerminal {
            child: Box::new(owner),
            stdout: Box::pin(stdout),
            stderr: Box::pin(stderr),
        })
    }
}

async fn shell_command(source: &str) -> Result<(String, Vec<String>), String> {
    #[cfg(windows)]
    {
        let shell = login_shell_variable("COMSPEC")
            .await
            .unwrap_or_else(|| "cmd.exe".into());
        Ok((
            shell,
            vec!["/d".into(), "/s".into(), "/c".into(), source.into()],
        ))
    }
    #[cfg(unix)]
    {
        let shell = login_shell_variable("SHELL")
            .await
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "/bin/sh".into());
        Ok((shell, vec!["-c".into(), source.into()]))
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = source;
        Err("client terminal shell execution is unsupported on this platform".into())
    }
}

struct NativeTerminalChild {
    child: Option<Child>,
    tree: ProcessTreeGuard,
}

#[async_trait]
impl ClientTerminalChild for NativeTerminalChild {
    async fn wait(&mut self) -> Result<ClientTerminalExitStatus, String> {
        let child = self.child.as_mut().ok_or("terminal child is not present")?;
        let status = child.wait().await.map_err(|error| error.to_string())?;
        #[cfg(unix)]
        let signal = {
            use std::os::unix::process::ExitStatusExt;
            status.signal().map(signal_name)
        };
        #[cfg(not(unix))]
        let signal = None;
        Ok(ClientTerminalExitStatus {
            exit_code: status.code(),
            signal,
        })
    }

    fn terminate(&self) {
        self.tree.terminate();
    }
}

impl Drop for NativeTerminalChild {
    fn drop(&mut self) {
        self.tree.terminate();
        if let Some(mut child) = self.child.take() {
            let _ = child.start_kill();
            if let Ok(runtime) = tokio::runtime::Handle::try_current() {
                runtime.spawn(async move {
                    let _ = child.wait().await;
                });
            }
        }
    }
}

#[cfg(unix)]
fn signal_name(signal: i32) -> String {
    match signal {
        1 => "SIGHUP".into(),
        2 => "SIGINT".into(),
        3 => "SIGQUIT".into(),
        4 => "SIGILL".into(),
        5 => "SIGTRAP".into(),
        6 => "SIGABRT".into(),
        8 => "SIGFPE".into(),
        9 => "SIGKILL".into(),
        11 => "SIGSEGV".into(),
        13 => "SIGPIPE".into(),
        14 => "SIGALRM".into(),
        15 => "SIGTERM".into(),
        signal => format!("SIG{signal}"),
    }
}
