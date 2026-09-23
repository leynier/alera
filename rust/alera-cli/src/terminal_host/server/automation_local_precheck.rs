use std::process::Stdio;
use std::time::Duration;

use alera_core::runtime::{
    AutomationDefinition, AutomationRun, OwnerAutomationPrecheck, OwnerAutomationPrecheckOutcome,
    OwnerAutomationPrecheckRequest, RuntimeStore, WorkspaceProcessJobPhase, LOCAL_HOST_ID,
};
use tokio::io::{AsyncRead, AsyncReadExt};

use super::automation_precheck_command_owner::PrecheckCommandOwner;

use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

pub(super) async fn run_local_precheck(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    cwd: &str,
) -> Result<bool, String> {
    let owner = PrecheckCommandOwner::Local { definition, run };
    execute_precheck(store, &owner, cwd)
        .await?
        .ok_or_else(|| "Precheck was already claimed".into())
}

pub(in crate::terminal_host::server) async fn run_owner_precheck(
    store: &RuntimeStore,
    request: &OwnerAutomationPrecheckRequest,
) -> Result<OwnerAutomationPrecheck, String> {
    let owner = PrecheckCommandOwner::remote(request);
    let result = execute_precheck(store, &owner, &request.path).await;
    let job = store
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .map_err(detail)?
        .ok_or("Owner precheck reservation disappeared")?;
    if owner.claimed() {
        let outcome = if job.cancel_requested {
            OwnerAutomationPrecheckOutcome::Cancelled
        } else {
            match result {
                Ok(Some(true)) => OwnerAutomationPrecheckOutcome::Passed,
                Ok(Some(false)) => OwnerAutomationPrecheckOutcome::Rejected,
                Err(error) if error == "automation precheck timed out" => {
                    OwnerAutomationPrecheckOutcome::TimedOut
                }
                Err(error) => OwnerAutomationPrecheckOutcome::Failed(error),
                Ok(None) => return Err("Claimed owner precheck lost its result".into()),
            }
        };
        store
            .finish_owner_automation_precheck(request, &outcome)
            .await
            .map_err(detail)?;
    } else if job.cancel_requested && job.process_id.is_none() {
        store
            .finish_owner_automation_precheck(request, &OwnerAutomationPrecheckOutcome::Cancelled)
            .await
            .map_err(detail)?;
    } else {
        result?;
    }
    store
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .map_err(detail)?
        .ok_or_else(|| "Owner precheck reservation disappeared".into())
}

async fn execute_precheck(
    store: &RuntimeStore,
    owner: &PrecheckCommandOwner<'_>,
    cwd: &str,
) -> Result<Option<bool>, String> {
    let precheck = owner.precheck()?;
    let deadline =
        tokio::time::Instant::now() + Duration::from_secs(precheck.timeout_seconds.max(1) as u64);
    let (program, arguments) = owner.command(cfg!(windows))?;
    #[cfg(unix)]
    let mut command = alera_core::child_process::detached_windowless_async_command(program);
    #[cfg(unix)]
    command.args(&arguments);
    #[cfg(windows)]
    let job = crate::terminal_host::session::windows_process_job::WindowsProcessJob::create()
        .map_err(detail)?;
    #[cfg(windows)]
    let mut command = job
        .command_bootstrap(
            program,
            &arguments
                .iter()
                .map(|arg| arg.to_string())
                .collect::<Vec<_>>(),
        )
        .map_err(detail)?;
    command
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    tokio::time::timeout_at(
        deadline,
        crate::login_shell_environment::apply_login_shell_environment(
            &mut command,
            &Default::default(),
        ),
    )
    .await
    .map_err(|_| "automation precheck timed out before launch")?;
    let boot = tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id)
        .await
        .map_err(detail)?
        .map_err(detail)?;
    let Some(mut record) = owner.begin(store, boot).await? else {
        return Ok(None);
    };
    if record.host_id != LOCAL_HOST_ID
        || record.path != cwd
        || tokio::time::Instant::now() >= deadline
    {
        store
            .record_automation_precheck_phase(&record, WorkspaceProcessJobPhase::SpawnFailed)
            .await
            .map_err(detail)?;
        return Err("Automation precheck location changed or its launch deadline expired".into());
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            store
                .record_automation_precheck_phase(&record, WorkspaceProcessJobPhase::SpawnFailed)
                .await
                .map_err(detail)?;
            return Err(detail(error));
        }
    };
    let pid = child.id().ok_or("Precheck process PID is unavailable")?;
    // Keep the direct child unreaped until the captured process scope is closed.
    #[cfg(unix)]
    let captured = WorkspaceShutdown::capture_command(pid).await;
    #[cfg(windows)]
    let captured = WorkspaceShutdown::capture_command_job(&job);
    let mut scope = match captured {
        Ok(scope) => scope,
        Err(error) => {
            let _ = child.kill().await;
            return Err(detail(error));
        }
    };
    let identity = tokio::task::spawn_blocking(move || SystemProcessIdentityProbe.lookup(pid))
        .await
        .map_err(detail)?;
    let marker = match identity {
        ProcessLookup::Live(identity) => Some(identity.start_marker),
        _ => None,
    };
    record = match store
        .record_automation_precheck_spawn(&record, pid, marker)
        .await
    {
        Ok(record) => record,
        Err(error) => {
            let _ = child.start_kill();
            wait_for_owned_closure(store, owner, &mut scope).await;
            let _ = child.wait().await;
            return Err(detail(error));
        }
    };
    #[cfg(windows)]
    if let Err(error) = job.assign_command_and_release(&child) {
        let _ = child.start_kill();
        wait_for_owned_closure(store, owner, &mut scope).await;
        let _ = child.wait().await;
        return Err(detail(error));
    }
    let stdout = child
        .stdout
        .take()
        .ok_or("Precheck stdout is unavailable")?;
    let stderr = child
        .stderr
        .take()
        .ok_or("Precheck stderr is unavailable")?;
    let result = {
        let exit = async {
            #[cfg(unix)]
            {
                WorkspaceShutdown::wait_command_root(pid)
                    .await
                    .map_err(detail)?;
                wait_for_owned_closure(store, owner, &mut scope).await;
            }
            let status = child.wait().await.map_err(detail)?;
            #[cfg(windows)]
            wait_for_owned_closure(store, owner, &mut scope).await;
            Ok::<_, String>(status)
        };
        let exchange = async {
            let (stdout, stderr, status) =
                tokio::try_join!(read_tail(stdout), read_tail(stderr), exit)?;
            if !status.success() {
                let stdout = super::automation_dispatch_helpers::bounded_text(&stdout);
                let stderr = super::automation_dispatch_helpers::bounded_text(&stderr);
                tracing::info!("automation precheck failed: stdout={stdout:?} stderr={stderr:?}");
            }
            Ok::<_, String>(status.success())
        };
        tokio::select! {
            reason = owner.cancellation(store) => Err(reason),
            _ = tokio::time::sleep_until(deadline) => Err("automation precheck timed out".into()),
            result = exchange => result,
        }
    };
    if result.is_err() {
        child.start_kill().map_err(detail)?;
        // The execution deadline must not drop shutdown before closure is proven.
        wait_for_owned_closure(store, owner, &mut scope).await;
        tokio::time::timeout(Duration::from_secs(5), child.wait())
            .await
            .map_err(|_| "Automation precheck process reaping is unverified")?
            .map_err(detail)?;
    }
    record = store
        .record_automation_precheck_phase(&record, WorkspaceProcessJobPhase::RootExited)
        .await
        .map_err(detail)?;
    store
        .record_automation_precheck_phase(&record, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .map_err(detail)?;
    result.map(Some)
}

#[cfg(test)]
pub(in crate::terminal_host::server) async fn wait_for_closure(
    store: &RuntimeStore,
    run: &AutomationRun,
    scope: &mut WorkspaceShutdown,
) {
    let definition = store
        .find_automation(&run.automation_id)
        .await
        .expect("fixture automation lookup")
        .expect("fixture automation exists");
    let owner = PrecheckCommandOwner::Local {
        definition: &definition,
        run,
    };
    wait_for_owned_closure(store, &owner, scope).await;
}

async fn wait_for_owned_closure(
    store: &RuntimeStore,
    owner: &PrecheckCommandOwner<'_>,
    scope: &mut WorkspaceShutdown,
) {
    let mut reported = false;
    loop {
        match scope.wait().await {
            Ok(()) => return,
            Err(error) => {
                if !reported {
                    reported = owner
                        .report_unverified_closure(store, &error.to_string())
                        .await;
                }
                // Keep the native guard and unreaped child alive across failed
                // inspections; releasing either would weaken a later retry.
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }
    }
}

async fn read_tail(mut pipe: impl AsyncRead + Unpin) -> Result<Vec<u8>, String> {
    let mut tail = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        let count = pipe.read(&mut chunk).await.map_err(detail)?;
        if count == 0 {
            return Ok(tail);
        }
        tail.extend_from_slice(&chunk[..count]);
        let excess = tail
            .len()
            .saturating_sub(super::AUTOMATION_PRECHECK_OUTPUT_BYTES);
        tail.drain(..excess);
    }
}

fn detail(error: impl std::fmt::Display) -> String {
    error.to_string()
}
