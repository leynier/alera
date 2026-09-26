use alera_core::runtime::{
    RemoteWorkspaceRelocationIntent, RuntimeStore, Workspace, WorkspaceRelocation, LOCAL_HOST_ID,
};
use anyhow::{bail, Context, Result};
use base64::Engine;
use serde_json::{json, Value};

use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};

pub(crate) async fn execute<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    mut pending: RemoteWorkspaceRelocationIntent,
    executor: &E,
    verify: impl Fn() -> Result<()>,
) -> Result<Value> {
    verify()?;
    if pending.owner_preparation.is_none()
        && store
            .find_remote_workspace_relocation_receipt(&pending.id)
            .await?
            .is_none()
    {
        let response = request_owner(store, &pending, executor, true).await?;
        let preparation = parse_response(&pending, &response, true)?;
        pending = store
            .record_remote_workspace_relocation_preparation(&pending.id, &preparation)
            .await?;
    }
    verify()?;
    let response = request_owner(store, &pending, executor, false).await?;
    let receipt = parse_response(&pending, &response, false)?;
    if let Some(previous) = store
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await?
    {
        if serde_json::to_value(previous)? != serde_json::to_value(&receipt)? {
            bail!("The owner completion changed; preserve the retained recovery evidence");
        }
    } else {
        store
            .record_remote_workspace_relocation_receipt(&pending.id, &receipt)
            .await?;
    }
    verify()?;
    let workspace = store
        .commit_remote_workspace_relocation(&pending.id)
        .await?;
    let mut result = response["result"].clone();
    result["workspace"] = serde_json::to_value(workspace)?;
    result["relocationId"] = json!(pending.id);
    Ok(result)
}

async fn request_owner<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    pending: &RemoteWorkspaceRelocationIntent,
    executor: &E,
    prepare: bool,
) -> Result<Value> {
    let workspace = &pending.source;
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let install = target
        .install_dir
        .as_deref()
        .filter(|path| !path.is_empty())
        .context("Bootstrap the SSH host again to record its installation directory")?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let quote = if windows {
        crate::ssh_bootstrap::powershell_string
    } else {
        crate::ssh_bootstrap::shell_quote
    };
    let mut owner = workspace.clone();
    owner.host_id = LOCAL_HOST_ID.into();
    let mut intent = pending.intent.clone();
    if !prepare && !intent.to_project_checkout {
        intent.destination_path = Some(
            pending
                .destination_path
                .clone()
                .context("The owner destination has not been prepared")?,
        );
    }
    let encoded = base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&json!({
        "workspace":owner,"intent":intent,"relocationId":pending.id,
        "workspaceRoot":if prepare { pending.workspace_root.clone() } else { None },
        "setupConfig":if prepare { pending.setup_config.clone() } else { None },
    }))?);
    let mut arguments = format!(
        "project relocate-owner-workspace --request-base64 {}",
        quote(&encoded)
    );
    if prepare {
        arguments.push_str(" --prepare-only");
    }
    if store
        .workspace_terminal_launch_attempted(&workspace.id, &workspace.instance_id)
        .await?
        == Some(false)
    {
        let mut project = store
            .find_project(&workspace.project_id)
            .await?
            .context("The remote project is missing")?;
        project.repo_path = pending.project_checkout_path.clone();
        let checkout = store
            .find_workspace_checkout(&workspace.id)
            .await?
            .context("The remote checkout binding is missing")?;
        let metadata =
            base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&json!({
                "project":project,"workspace":workspace,"repositoryPath":checkout.repository_path,
            }))?);
        arguments.push_str(&format!(
            " --enroll-never-started-base64 {}",
            quote(&metadata)
        ));
    }
    let script =
        crate::remote_owner_terminal_launch::owner_command_script(windows, install, &arguments);
    let output = tokio::time::timeout(std::time::Duration::from_secs(60), executor.run(&target, windows, &script)).await
        .context("The SSH relocation response timed out. Retain both locations and retry the same relocation ID to recover the owner journal")??;
    if output.len() > 2_097_152 {
        bail!("The owner relocation response is too large; Home location was preserved");
    }
    serde_json::from_str(output.trim())
        .context("The SSH owner did not return a relocation response")
}

fn parse_response(
    pending: &RemoteWorkspaceRelocationIntent,
    response: &Value,
    prepare: bool,
) -> Result<WorkspaceRelocation> {
    if response["version"] != 1 || (response["prepared"] == true) != prepare {
        bail!("The SSH owner returned an incompatible relocation response");
    }
    let journal: WorkspaceRelocation = serde_json::from_value(response["relocation"].clone())?;
    let workspace: Workspace = serde_json::from_value(response["workspace"].clone())?;
    let expected = &pending.source;
    if journal.id != pending.id
        || workspace.id != expected.id
        || workspace.instance_id != expected.instance_id
        || workspace.project_id != expected.project_id
        || workspace.host_id != LOCAL_HOST_ID
    {
        bail!("The owner relocation response belongs to another task instance");
    }
    if !prepare {
        let result_workspace: Workspace =
            serde_json::from_value(response["result"]["workspace"].clone())?;
        if serde_json::to_value(&workspace)? != serde_json::to_value(&result_workspace)?
            || workspace.path != journal.destination.path
            || workspace.kind != journal.destination.kind
        {
            bail!("The owner result does not match its completed relocation");
        }
    }
    Ok(journal)
}

#[cfg(test)]
#[path = "remote_workspace_relocation_tests.rs"]
pub(crate) mod tests;
