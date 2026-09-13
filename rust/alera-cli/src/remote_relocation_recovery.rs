use alera_core::runtime::{
    RemoteWorkspaceRelocationRecovery, RuntimeStore, Workspace, WorkspaceRelocationRecovery,
    LOCAL_HOST_ID,
};
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RecoveryReport {
    kind: &'static str,
    workspace: Workspace,
    home_intents: Vec<RemoteWorkspaceRelocationRecovery>,
    owner: Option<OwnerRecovery>,
    owner_error: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct OwnerRecovery {
    version: u32,
    workspace: Workspace,
    platform: String,
    items: Vec<WorkspaceRelocationRecovery>,
}

pub(crate) async fn inspect<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: Workspace,
    limit: u32,
    executor: &E,
) -> Result<RecoveryReport> {
    if workspace.host_id == LOCAL_HOST_ID {
        bail!("SSH recovery requires a remote task");
    }
    let home_intents = store
        .list_remote_workspace_relocation_recovery(&workspace, limit)
        .await?;
    let (owner, owner_error) = match inspect_owner(store, &workspace, limit, executor).await {
        Ok(owner) => (Some(owner), None),
        Err(error) => (None, Some(format!("{error:#}"))),
    };
    Ok(RecoveryReport {
        kind: "remoteWorkspaceRelocationRecovery",
        workspace,
        home_intents,
        owner,
        owner_error,
    })
}

async fn inspect_owner<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    limit: u32,
    executor: &E,
) -> Result<OwnerRecovery> {
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let install = target
        .install_dir
        .as_deref()
        .context("The SSH owner installation is unknown")?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let quote = if windows {
        crate::ssh_bootstrap::powershell_string
    } else {
        crate::ssh_bootstrap::shell_quote
    };
    let arguments = format!("project inspect-owner-recovery --workspace-id {} --instance-id {} --project-id {} --limit {}", quote(&workspace.id), quote(&workspace.instance_id), quote(&workspace.project_id), limit.clamp(1, 100));
    let profile = hex::encode(Sha256::digest(workspace.project_id.as_bytes()));
    let script = crate::remote_owner_terminal_launch::owner_command_script(
        windows, install, &profile, &arguments,
    );
    let output = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        executor.run(&target, windows, &script),
    )
    .await
    .context("SSH owner recovery inspection timed out")??;
    if output.len() > 4_194_304 {
        bail!("Owner recovery response exceeds the inspection limit");
    }
    let owner: OwnerRecovery = serde_json::from_str(output.trim())?;
    if owner.version != 1
        || owner.workspace.id != workspace.id
        || owner.workspace.instance_id != workspace.instance_id
        || owner.workspace.project_id != workspace.project_id
        || owner.workspace.host_id != LOCAL_HOST_ID
        || !matches!(owner.platform.as_str(), "linux" | "macos" | "windows")
        || owner.items.iter().any(|item| {
            [&item.relocation.source, &item.relocation.destination]
                .iter()
                .any(|task| {
                    task.id != workspace.id
                        || task.instance_id != workspace.instance_id
                        || task.project_id != workspace.project_id
                        || task.host_id != LOCAL_HOST_ID
                })
        })
    {
        bail!("Owner recovery does not match the requested task and host");
    }
    Ok(owner)
}

pub(crate) fn print(report: &RecoveryReport, json_output: bool) {
    if json_output {
        crate::print_value(report, true, "");
        return;
    }
    println!("SSH Host: {}", report.workspace.host_id);
    for item in &report.home_intents {
        let phase = if item.home_committed {
            "Home updated"
        } else if item.owner_receipt.is_some() {
            "Owner completed; Home pending"
        } else if item.intent.owner_preparation.is_some() {
            "Prepared by owner"
        } else {
            "Awaiting owner preparation"
        };
        println!(
            "{}: {phase}\n  {} -> {}",
            item.intent.id,
            item.intent.source.path,
            item.intent
                .destination_path
                .as_deref()
                .unwrap_or("Destination not yet resolved")
        );
    }
    if let Some(owner) = &report.owner {
        println!("Owner Recovery ({})", owner.platform);
        crate::workspace_setup_command::print_recovery(&owner.items, false);
    }
    if let Some(error) = &report.owner_error {
        println!("Owner unavailable: {error}\nHome recovery records were retained.");
    }
}
