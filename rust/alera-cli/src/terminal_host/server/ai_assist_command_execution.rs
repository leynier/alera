use super::ai_assist_failure_detail::ai_assist_failure_detail;
use super::ai_assist_process_journal::AiAssistProcessOwner;
use super::ai_assist_requests::AiAssistCommandPlan;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::child_process::windowless_async_command;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::sync::oneshot;
const MAX_OUTPUT_BYTES: usize = 1024 * 1024;

pub(super) async fn run_command(
    plan: AiAssistCommandPlan,
    working_directory: &str,
    timeout_seconds: u64,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<String> {
    execute_command(plan, working_directory, timeout_seconds, cancel_rx, None).await
}

pub(super) async fn run_workspace_command(
    plan: AiAssistCommandPlan,
    owner: AiAssistProcessOwner,
    timeout_seconds: u64,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<String> {
    execute_command(
        plan,
        &owner.workspace.path,
        timeout_seconds,
        cancel_rx,
        Some(&owner),
    )
    .await
}

async fn execute_command(
    plan: AiAssistCommandPlan,
    working_directory: &str,
    timeout_seconds: u64,
    mut cancel_rx: oneshot::Receiver<()>,
    owner: Option<&AiAssistProcessOwner>,
) -> HostResult<String> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(timeout_seconds);
    let mut command = if cfg!(unix) && owner.is_some() {
        alera_core::child_process::detached_windowless_async_command(&plan.binary)
    } else {
        windowless_async_command(&plan.binary)
    };
    #[cfg(windows)]
    let process_job = if owner.is_some() {
        Some(crate::terminal_host::session::windows_process_job::WindowsProcessJob::create()?)
    } else {
        None
    };
    #[cfg(windows)]
    if let Some(job) = &process_job {
        command = job.command_bootstrap(&plan.binary, &plan.arguments)?;
    } else {
        command.args(&plan.arguments);
    }
    #[cfg(not(windows))]
    command.args(&plan.arguments);
    command
        .current_dir(working_directory)
        .kill_on_drop(true)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(if plan.stdin_payload.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    let environment = plan
        .environment
        .iter()
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect();
    tokio::select! {
        biased;
        _ = &mut cancel_rx => return Err(before_spawn_error(&plan, HostError::state("AI Assist was canceled."))),
        _ = tokio::time::sleep_until(deadline) => return Err(before_spawn_error(&plan, timeout_error(timeout_seconds))),
        _ = crate::login_shell_environment::apply_login_shell_environment(
            &mut command, &environment,
        ) => {}
    }
    // Internal generation must never identify as a user terminal or emit its hooks.
    for key in [
        "ALERA_TERMINAL_SESSION_ID",
        "ALERA_WORKSPACE_ID",
        "ALERA_TAB_ID",
        "ALERA_AGENT_HOOK_ENDPOINT",
        "ALERA_AGENT_HOOK_PORT",
        "ALERA_AGENT_HOOK_TOKEN",
        "ALERA_RUNTIME_DIR",
    ] {
        command.env_remove(key);
    }
    if !matches!(
        cancel_rx.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    ) {
        return Err(before_spawn_error(
            &plan,
            HostError::state("AI Assist was canceled."),
        ));
    }
    if tokio::time::Instant::now() >= deadline {
        return Err(before_spawn_error(&plan, timeout_error(timeout_seconds)));
    }
    let mut journal = if let Some(owner) = owner {
        Some(
            owner
                .begin()
                .await
                .map_err(|error| before_spawn_error(&plan, error))?,
        )
    } else {
        None
    };
    let canceled = !matches!(
        cancel_rx.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    );
    if canceled || tokio::time::Instant::now() >= deadline {
        if let Some(journal) = &mut journal {
            journal
                .spawn_failed()
                .await
                .map_err(|error| before_spawn_error(&plan, error))?;
        }
        return Err(before_spawn_error(
            &plan,
            if canceled {
                HostError::state("AI Assist was canceled.")
            } else {
                timeout_error(timeout_seconds)
            },
        ));
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(_) => {
            if let Some(journal) = &mut journal {
                journal
                    .spawn_failed()
                    .await
                    .map_err(|error| before_spawn_error(&plan, error))?;
            }
            return Err(before_spawn_error(
                &plan,
                HostError::state(format!(
                    "{} could not be started. Check that {} is installed and on PATH.",
                    plan.label, plan.binary,
                )),
            ));
        }
    };
    if let Some(journal) = &mut journal {
        let recorded = match child.id() {
            Some(pid) => journal.spawned(pid).await,
            None => Err(HostError::state("AI Assist process PID is unavailable.")),
        };
        if let Err(error) = recorded {
            // Keep unresolved intent if ownership persistence failed after spawn.
            let _ = tokio::time::timeout(Duration::from_secs(5), child.kill()).await;
            return Err(error);
        }
    }
    #[cfg(windows)]
    let mut scope = if let Some(job) = &process_job {
        let prepared = job.assign_command_and_release(&child).and_then(|()| {
            crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown::capture_command_job(job)
        });
        match prepared {
            Ok(scope) => Some(scope),
            Err(error) => {
                let _ = tokio::time::timeout(Duration::from_secs(5), child.kill()).await;
                return Err(error);
            }
        }
    } else {
        None
    };
    #[cfg(unix)]
    let mut scope = if owner.is_some() {
        match crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown::capture_command(
            child
                .id()
                .ok_or_else(|| HostError::state("AI Assist process PID is unavailable."))?,
        )
        .await
        {
            Ok(scope) => Some(scope),
            Err(error) => {
                let _ = tokio::time::timeout(Duration::from_secs(5), child.kill()).await;
                return Err(error);
            }
        }
    } else {
        None
    };
    #[cfg(unix)]
    let root_pid = child.id();
    #[cfg(unix)]
    let mut unix_scope_closed = false;
    let stdin = child.stdin.take();
    let stdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take().expect("piped stderr");
    let output = {
        let exchange = async {
            let input = async {
                if let Some(payload) = &plan.stdin_payload {
                    let mut stdin = stdin.ok_or_else(|| {
                        std::io::Error::other("AI Assist process stdin is unavailable.")
                    })?;
                    stdin.write_all(payload.as_bytes()).await?;
                    stdin.shutdown().await?;
                }
                Ok::<_, std::io::Error>(())
            };
            // Drain both pipes while writing: an agent can emit output before reading input.
            let exit = async {
                #[cfg(unix)]
                if let Some(scope) = &mut scope {
                    crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown::wait_command_root(root_pid.expect("captured command PID"))
                        .await.map_err(std::io::Error::other)?;
                    scope.wait().await.map_err(std::io::Error::other)?;
                    unix_scope_closed = true;
                }
                let status = child.wait().await?;
                #[cfg(windows)]
                if let Some(scope) = &mut scope {
                    scope.wait().await.map_err(std::io::Error::other)?;
                }
                Ok::<_, std::io::Error>(status)
            };
            let (_, stdout, stderr, status) =
                tokio::try_join!(input, read_bounded(stdout), read_bounded(stderr), exit,)?;
            Ok::<_, std::io::Error>(std::process::Output {
                status,
                stdout,
                stderr,
            })
        };
        tokio::select! {
            biased;
            _ = &mut cancel_rx => Err(HostError::state("AI Assist was canceled.")),
            _ = tokio::time::sleep_until(deadline) => Err(timeout_error(timeout_seconds)),
            result = exchange => result.map_err(|error| HostError::state(error.to_string())),
        }
    };
    if output.is_err() {
        // Reap the direct child before releasing the operation registration. Descendant
        // ownership still needs separate verification before workspace retirement.
        #[cfg(any(unix, windows))]
        if let Some(scope) = &mut scope {
            #[cfg(unix)]
            let must_close = !unix_scope_closed;
            #[cfg(windows)]
            let must_close = true;
            if must_close {
                child
                    .start_kill()
                    .map_err(|error| HostError::state(error.to_string()))?;
                scope.wait().await?;
                #[cfg(unix)]
                {
                    unix_scope_closed = true;
                }
            }
        }
        match tokio::time::timeout(Duration::from_secs(5), child.kill()).await {
            Ok(Ok(())) => {}
            Ok(Err(error)) => {
                return Err(HostError::state(format!(
                    "AI Assist process closure could not be verified: {error}"
                )))
            }
            Err(_) => {
                return Err(HostError::state(
                    "AI Assist process closure could not be verified before the deadline.",
                ))
            }
        }
    }
    if let Some(journal) = &mut journal {
        journal.root_exited().await?;
        #[cfg(unix)]
        if unix_scope_closed {
            journal.unix_session_closed().await?;
        }
        #[cfg(windows)]
        if let Some(scope) = &mut scope {
            journal.windows_job_closed(scope).await?;
        }
    }
    let result = output.and_then(|output| {
        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        if output.status.success() {
            Ok(stdout)
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let detail = ai_assist_failure_detail(&stdout, &stderr);
            Err(HostError::state(match detail {
                Some(detail) => format!("{} failed: {detail}", plan.label),
                None => format!(
                    "{} failed. Check the agent CLI configuration and try again.",
                    plan.label
                ),
            }))
        }
    });
    if let Some(directory) = plan.temporary_directory {
        let _ = std::fs::remove_dir_all(directory);
    }
    result
}

fn before_spawn_error(plan: &AiAssistCommandPlan, error: HostError) -> HostError {
    if let Some(directory) = &plan.temporary_directory {
        let _ = std::fs::remove_dir_all(directory);
    }
    error
}

fn timeout_error(seconds: u64) -> HostError {
    HostError::state(format!("AI Assist timed out after {seconds}s."))
}

async fn read_bounded(reader: impl AsyncRead + Unpin) -> std::io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader
        .take((MAX_OUTPUT_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .await?;
    if bytes.len() > MAX_OUTPUT_BYTES {
        return Err(std::io::Error::other("AI Assist returned too much output."));
    }
    Ok(bytes)
}

#[cfg(test)]
#[path = "ai_assist_command_execution_tests.rs"]
mod tests;
