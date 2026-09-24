use alera_core::runtime::{
    redact_known_patterns, AutomationDefinition, AutomationPrecheckProcess, AutomationRun,
    AutomationRunStatus, OwnerAutomationPrecheck, OwnerAutomationPrecheckOutcome, RuntimeStore,
    SshTarget, WorkspaceProcessJobPhase,
};
use anyhow::{bail, Context, Result};
use base64::Engine;

use crate::remote_owner_precheck::OwnerPrecheckEnvelope;
use crate::ssh_remote::{require_bootstrapped_ssh_target, RemoteHostExecutor};

pub(crate) async fn run_remote_precheck<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    host_id: &str,
    cwd: &str,
    executor: &E,
) -> Result<bool, String> {
    execute(store, definition, run, host_id, cwd, executor)
        .await
        .map_err(|error| error.to_string())
}

async fn execute<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    host_id: &str,
    cwd: &str,
    executor: &E,
) -> Result<bool> {
    let records = store.automation_precheck_processes(&run.id).await?;
    if let [intent] = records.as_slice() {
        if intent.host_id != host_id || intent.path != cwd {
            bail!("The retained precheck owner or checkout changed; closure remains unverified");
        }
        if intent.phase == WorkspaceProcessJobPhase::ClosureVerified {
            let job = store
                .remote_precheck_result(&intent.id)
                .await?
                .context("The retained owner result is missing")?;
            return outcome(&job);
        }
    }
    let target = require_bootstrapped_ssh_target(store, host_id).await?;
    let install = target
        .install_dir
        .as_deref()
        .filter(|path| !path.trim().is_empty())
        .context("Bootstrap the SSH runtime before executing owner prechecks")?;
    let platform = crate::ssh_bootstrap::normalize_platform(
        target
            .runtime_platform
            .as_deref()
            .or(target.platform.as_deref())
            .context("The precheck owner platform is unknown")?,
    );
    if !matches!(platform.as_str(), "linux" | "macos" | "windows") {
        bail!("The precheck owner platform is unsupported");
    }
    let (intent, mut action) = match records.as_slice() {
        [] => {
            if let Some(id) = definition.target.source_workspace_id() {
                let workspace = store
                    .find_workspace(id)
                    .await?
                    .context("The precheck source workspace is missing")?;
                if workspace.host_id != host_id || workspace.path != cwd {
                    bail!("The precheck source location changed before inspection");
                }
                crate::remote_project_checkout::ensure_linked_origin(
                    store,
                    &workspace,
                    &target,
                    platform == "windows",
                    install,
                    executor,
                )
                .await?;
            }
            let preview = linked_preview(store, definition, run, host_id, cwd, &platform).await?;
            if let Some(preview) = &preview {
                let response = owner_response(executor, &target, platform == "windows", install, preview, "probe")
                    .await.context("The SSH owner does not support the required linked precheck; verify access and update its runtime before retrying. No precheck command was started")?;
                if response["version"] != 1 || response["request"] != serde_json::to_value(&preview.request)?
                    || response["capability"] != crate::terminal_host::protocol::RUNTIME_HOST_LINKED_OWNER_PRECHECK_CAPABILITY
                    || !response["runtimeRunning"].is_boolean() {
                    bail!("The SSH owner did not confirm linked precheck support; no command was started");
                }
            }
            let operation_id = preview
                .as_ref()
                .map(|preview| preview.request.operation_id.clone())
                .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
            let intent = store
                .begin_automation_precheck_process(run, definition, &operation_id, &platform, None)
                .await?;
            if intent.host_id != host_id || intent.path != cwd || intent.platform != platform {
                store
                    .record_automation_precheck_phase(
                        &intent,
                        WorkspaceProcessJobPhase::SpawnFailed,
                    )
                    .await?;
                bail!("The precheck source location changed before launch; no command was started");
            }
            if let Some(preview) = preview {
                if intent.remote_owner_request()? != preview.request {
                    store
                        .record_automation_precheck_phase(
                            &intent,
                            WorkspaceProcessJobPhase::SpawnFailed,
                        )
                        .await?;
                    bail!("The linked precheck scope changed after inspection; no command was started");
                }
            }
            (intent, "start")
        }
        [intent] => (intent.clone(), "status"),
        _ => bail!("Multiple retained precheck operations require recovery before continuing"),
    };
    if intent.host_id != host_id || intent.path != cwd || intent.platform != platform {
        bail!("The retained precheck owner or checkout changed; closure remains unverified");
    }
    let envelope = owner_envelope(store, &intent).await?;
    let windows = platform == "windows";
    let deadline = tokio::time::Instant::now()
        + std::time::Duration::from_secs(intent.precheck.timeout_seconds.max(1) as u64 + 60);
    let mut attention = None;
    let mut cancel_for_failure = false;
    loop {
        let current = store
            .find_automation_run(&run.id)
            .await?
            .context("The reserved precheck run is missing")?;
        if current.cancel_requested_at.is_some()
            || current.attempt_count != intent.attempt_count
            || !matches!(
                current.status,
                AutomationRunStatus::Dispatching | AutomationRunStatus::WaitingForUser
            )
            || tokio::time::Instant::now() >= deadline
            || cancel_for_failure
        {
            action = "cancel";
        }
        let response = request(executor, &target, windows, install, &envelope, action).await;
        match response {
            Ok((job, processes)) => {
                if job.outcome.is_some() {
                    store
                        .record_remote_precheck_result(&intent, &job, &processes)
                        .await?;
                    if cancel_for_failure {
                        bail!(
                            "{}",
                            attention
                                .as_deref()
                                .unwrap_or("Owner precheck authorization failed")
                        );
                    }
                    return outcome(&job);
                }
                action = "status";
                if let Some(reason) = job.attention {
                    cancel_for_failure |= job.process_id.is_none();
                    retain_attention(store, run, &mut attention, &reason).await?;
                }
            }
            Err(error) => {
                // Dropping SSH only ends the transport. Keep Home's intent and
                // retry the same operation until the owner proves closure.
                retain_attention(store, run, &mut attention,
                    &format!("Owner precheck response is unavailable; process closure remains unverified: {error}")).await?;
            }
        }
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }
}

async fn retain_attention(
    store: &RuntimeStore,
    run: &AutomationRun,
    previous: &mut Option<String>,
    reason: &str,
) -> Result<()> {
    let reason = redact_known_patterns(&reason.chars().take(2048).collect::<String>());
    if previous.as_ref() != Some(&reason) {
        store
            .update_automation_run_status(
                &run.id,
                AutomationRunStatus::WaitingForUser,
                Some(reason.clone()),
            )
            .await?;
        *previous = Some(reason);
    }
    Ok(())
}

async fn request<E: RemoteHostExecutor>(
    executor: &E,
    target: &SshTarget,
    windows: bool,
    install: &str,
    envelope: &OwnerPrecheckEnvelope,
    action: &str,
) -> Result<(OwnerAutomationPrecheck, Vec<AutomationPrecheckProcess>)> {
    let response = owner_response(executor, target, windows, install, envelope, action).await?;
    let job: OwnerAutomationPrecheck = serde_json::from_value(response["job"].clone())?;
    if response["version"] != 1 || job.request != envelope.request {
        bail!("The owner precheck response does not match the retained operation");
    }
    let processes = serde_json::from_value(response["processes"].clone())?;
    Ok((job, processes))
}

async fn owner_response<E: RemoteHostExecutor>(
    executor: &E,
    target: &SshTarget,
    windows: bool,
    install: &str,
    envelope: &OwnerPrecheckEnvelope,
    action: &str,
) -> Result<serde_json::Value> {
    let quote = if windows {
        crate::ssh_bootstrap::powershell_string
    } else {
        crate::ssh_bootstrap::shell_quote
    };
    let metadata = base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(envelope)?);
    let arguments = format!(
        "project control-owner-precheck --metadata-base64 {} --action {action}",
        quote(&metadata)
    );
    let script =
        crate::remote_owner_terminal_launch::owner_command_script(windows, install, &arguments);
    let output = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        executor.run(target, windows, &script),
    )
    .await
    .context("The owner precheck response timed out")??;
    if output.len() > 4_194_304 {
        bail!("The owner precheck response exceeds the limit");
    }
    Ok(serde_json::from_str(output.trim())?)
}

fn outcome(job: &OwnerAutomationPrecheck) -> Result<bool> {
    match job
        .outcome
        .as_ref()
        .context("The owner precheck result is incomplete")?
    {
        OwnerAutomationPrecheckOutcome::Passed => Ok(true),
        OwnerAutomationPrecheckOutcome::Rejected => Ok(false),
        OwnerAutomationPrecheckOutcome::Cancelled => bail!("Automation precheck was cancelled"),
        OwnerAutomationPrecheckOutcome::TimedOut => bail!("Automation precheck timed out"),
        OwnerAutomationPrecheckOutcome::Failed(reason) => {
            bail!("{}", redact_known_patterns(reason))
        }
    }
}

async fn owner_envelope(
    store: &RuntimeStore,
    intent: &AutomationPrecheckProcess,
) -> Result<OwnerPrecheckEnvelope> {
    let request = intent.remote_owner_request()?;
    let mut project = store
        .find_project(&intent.project_id)
        .await?
        .context("The precheck project is missing")?;
    let workspace = if let Some(scope) = &request.workspace {
        let workspace = store
            .find_workspace(&scope.workspace_id)
            .await?
            .context("The retained precheck workspace is missing")?;
        let checkout = store
            .find_workspace_checkout(&scope.workspace_id)
            .await?
            .context("The retained precheck checkout is missing")?;
        if workspace.instance_id != scope.instance_id
            || workspace.project_id != intent.project_id
            || workspace.host_id != intent.host_id
            || workspace.path != intent.path
            || workspace.kind != scope.kind
            || workspace.status != alera_core::runtime::WorkspaceStatus::Active
            || checkout.repository_path != scope.repository_path
        {
            bail!(
                "The retained precheck workspace ownership changed; no replacement task was sent"
            );
        }
        project.repo_path = match store
            .find_project_checkout(&intent.project_id, &intent.host_id)
            .await?
        {
            Some(checkout) => checkout.path,
            None => scope
                .repository_path
                .clone()
                .context("The linked repository origin is missing")?,
        };
        Some(workspace)
    } else {
        project.repo_path = intent.path.clone();
        None
    };
    Ok(OwnerPrecheckEnvelope {
        project,
        request,
        workspace,
    })
}

#[cfg(test)]
#[path = "automation_ssh_precheck_envelope_tests.rs"]
mod envelope_tests;

async fn linked_preview(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    host_id: &str,
    cwd: &str,
    platform: &str,
) -> Result<Option<OwnerPrecheckEnvelope>> {
    let Some(id) = definition.target.source_workspace_id() else {
        return Ok(None);
    };
    let task = store
        .find_workspace(id)
        .await?
        .context("The precheck source task is missing")?;
    if task.kind != alera_core::runtime::WorkspaceKind::Linked {
        return Ok(None);
    }
    if task.host_id != host_id || task.path != cwd {
        bail!("The precheck source location changed");
    }
    let checkout = store
        .find_workspace_checkout(id)
        .await?
        .context("The linked checkout binding is missing")?;
    let origin = checkout
        .repository_path
        .context("The linked repository origin must be verified before running its precheck")?;
    let preview = AutomationPrecheckProcess {
        id: uuid::Uuid::new_v4().to_string(),
        run_id: run.id.clone(),
        attempt_count: run.attempt_count,
        project_id: task.project_id,
        host_id: host_id.into(),
        path: cwd.into(),
        precheck: definition
            .precheck
            .clone()
            .context("The precheck command is missing")?,
        workspace: Some(alera_core::runtime::AutomationPrecheckWorkspace {
            workspace_id: task.id,
            instance_id: task.instance_id,
            kind: task.kind,
            repository_path: Some(origin),
        }),
        phase: WorkspaceProcessJobPhase::LaunchIntent,
        platform: platform.into(),
        boot_id: None,
        pid: None,
        start_marker: None,
        closure_boot_id: None,
    };
    Ok(Some(owner_envelope(store, &preview).await?))
}
