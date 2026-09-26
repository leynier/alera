use crate::remote_owner_setup::OwnerSetupAction;
use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};
use alera_core::runtime::{
    RelocationSetupReceipt, RuntimeStore, Workspace, WorktreeSetupReport, LOCAL_HOST_ID,
};
use anyhow::{bail, Context, Result};
use serde_json::Value;

pub(crate) struct SetupRequest {
    pub workspace_id: String,
    pub relocation_id: String,
    pub attempt_id: Option<String>,
    pub action: OwnerSetupAction,
}

impl SetupRequest {
    pub(crate) fn operation(&self) -> &'static str {
        match self.action {
            OwnerSetupAction::Run => "workspace.runSetup",
            OwnerSetupAction::Cancel => "workspace.cancelRelocationSetup",
            OwnerSetupAction::Recover => "workspace.recoverRelocationSetup",
        }
    }
}

pub(crate) async fn execute<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: SetupRequest,
    executor: &E,
) -> Result<Value> {
    uuid::Uuid::parse_str(&request.relocation_id).context("Relocation ID must be a UUID")?;
    if let Some(attempt) = &request.attempt_id {
        uuid::Uuid::parse_str(attempt).context("Setup attempt must be a UUID")?;
    }
    if !matches!(request.action, OwnerSetupAction::Run) && request.attempt_id.is_none() {
        bail!("An exact setup attempt is required");
    }
    let workspace = store
        .find_workspace(&request.workspace_id)
        .await?
        .context("Workspace no longer exists")?;
    let intent = store
        .find_remote_workspace_relocation_intent(&request.relocation_id)
        .await?
        .context("Home has no retained intent for this SSH relocation")?;
    if workspace.host_id == LOCAL_HOST_ID
        || intent.source.id != workspace.id
        || intent.source.instance_id != workspace.instance_id
        || intent.source.project_id != workspace.project_id
        || intent.source.host_id != workspace.host_id
        || intent.intent.to_project_checkout
    {
        bail!("Setup does not belong to this SSH task and relocation");
    }
    let prepared = intent
        .owner_preparation
        .as_ref()
        .context("Inspect and prepare the owner relocation before controlling setup")?;
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let install = target
        .install_dir
        .as_deref()
        .context("The owner installation directory is unknown")?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let quote = if windows {
        crate::ssh_bootstrap::powershell_string
    } else {
        crate::ssh_bootstrap::shell_quote
    };
    let action = match request.action {
        OwnerSetupAction::Run => "run",
        OwnerSetupAction::Cancel => "cancel",
        OwnerSetupAction::Recover => "recover",
    };
    let mut arguments = format!("project control-owner-setup --workspace-id {} --instance-id {} --project-id {} --relocation-id {} --action {action}", quote(&workspace.id), quote(&workspace.instance_id), quote(&workspace.project_id), quote(&request.relocation_id));
    if let Some(attempt) = &request.attempt_id {
        arguments.push_str(&format!(" --attempt-id {}", quote(attempt)));
    }
    let script =
        crate::remote_owner_terminal_launch::owner_command_script(windows, install, &arguments);
    let output = tokio::time::timeout(std::time::Duration::from_secs(60), executor.run(&target, windows, &script)).await
        .context("The SSH setup response timed out. Inspect owner recovery with the same relocation and attempt IDs; process closure is unverified")??;
    if output.len() > 4_194_304 {
        bail!("Owner setup response exceeds the limit; inspect recovery");
    }
    let response: Value = serde_json::from_str(output.trim())?;
    let owner: Workspace = serde_json::from_value(response["workspace"].clone())?;
    let setup: RelocationSetupReceipt = serde_json::from_value(response["setup"].clone())?;
    if response["version"] != 1
        || response["action"] != action
        || response["relocationId"] != request.relocation_id
        || owner.id != workspace.id
        || owner.instance_id != workspace.instance_id
        || owner.project_id != workspace.project_id
        || owner.host_id != LOCAL_HOST_ID
        || owner.path != prepared.destination.path
        || owner.kind != prepared.destination.kind
        || setup.relocation_id != request.relocation_id
        || request
            .attempt_id
            .as_ref()
            .is_some_and(|attempt| setup.attempt_id.as_ref() != Some(attempt))
    {
        bail!(
            "The owner setup response does not verify the requested task, relocation and attempt"
        );
    }
    let result = response["result"].clone();
    match request.action {
        OwnerSetupAction::Cancel => {
            if result["cancellationRequested"] != true || result["processesClosed"] != false {
                bail!("The owner did not acknowledge the cancellation request");
            }
        }
        OwnerSetupAction::Run | OwnerSetupAction::Recover => {
            let report: WorktreeSetupReport = serde_json::from_value(result.clone())?;
            if setup.report.as_ref() != Some(&report) {
                bail!("The owner setup report is not backed by its retained receipt");
            }
        }
    }
    Ok(result)
}

#[cfg(test)]
#[path = "remote_relocation_setup_tests.rs"]
mod tests;
