use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceKind, LOCAL_HOST_ID};
use anyhow::{bail, Context, Result};
use base64::Engine;
use serde_json::Value;

use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};

#[derive(Debug, Clone)]
pub(crate) struct RemoteRetirementProof {
    source: Box<Workspace>,
}

impl RemoteRetirementProof {
    pub(crate) fn verify(&self, workspace: &Workspace) -> Result<()> {
        let source = &self.source;
        if source.id != workspace.id
            || source.instance_id != workspace.instance_id
            || source.project_id != workspace.project_id
            || source.host_id != workspace.host_id
            || source.path != workspace.path
            || workspace.kind != source.kind
        {
            bail!("Workspace identity or location changed after owner retirement");
        }
        Ok(())
    }
}

pub(crate) async fn retire<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    executor: &E,
) -> Result<RemoteRetirementProof> {
    retire_scoped(store, workspace, executor, None, false).await
}

pub(crate) async fn retire_linked<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    executor: &E,
    delete_branch: bool,
) -> Result<RemoteRetirementProof> {
    if workspace.kind != WorkspaceKind::Linked {
        bail!("Linked retirement requires a linked task");
    }
    retire_scoped(store, workspace, executor, None, delete_branch).await
}

pub(crate) async fn retire_automation<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    run: &alera_core::runtime::AutomationRun,
    executor: &E,
) -> Result<RemoteRetirementProof> {
    store
        .require_automation_shared_workspace_cleanup(run, workspace)
        .await?;
    let mut expected = workspace.clone();
    expected.host_id = LOCAL_HOST_ID.into();
    let mut tab_ids = Vec::new();
    if run.owned_tab {
        if let Some(id) = &run.tab_id {
            tab_ids.push(id.clone());
        }
    }
    if let Some(id) = &run.setup_tab_id {
        if !tab_ids.contains(id) {
            tab_ids.push(id.clone());
        }
    }
    let scope = alera_core::runtime::RemoteAutomationCleanup {
        run_id: run.id.clone(),
        workspace: expected,
        tab_ids,
    };
    retire_scoped(store, workspace, executor, Some(&scope), false).await
}

async fn retire_scoped<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    executor: &E,
    scope: Option<&alera_core::runtime::RemoteAutomationCleanup>,
    delete_branch: bool,
) -> Result<RemoteRetirementProof> {
    if workspace.host_id == LOCAL_HOST_ID {
        bail!("Remote retirement requires a task on an SSH host");
    }
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
    let mut arguments = format!(
        "project retire-owner-workspace --workspace-id {} --instance-id {} --close-sessions",
        quote(&workspace.id),
        quote(&workspace.instance_id)
    );
    if delete_branch {
        arguments.push_str(" --delete-branch");
    }
    if store
        .workspace_terminal_launch_attempted(&workspace.id, &workspace.instance_id)
        .await?
        == Some(false)
    {
        let mut project = store
            .find_project(&workspace.project_id)
            .await?
            .context("The remote workspace project is missing")?;
        let checkout = store
            .find_project_checkout(&project.id, &workspace.host_id)
            .await?
            .context("The remote project checkout is missing")?;
        if workspace.kind == WorkspaceKind::Main && checkout.path != workspace.path {
            bail!("The shared task no longer matches its registered SSH checkout");
        }
        project.repo_path = checkout.path;
        let mut registration = serde_json::json!({"project":project,"workspace":workspace});
        if workspace.kind == WorkspaceKind::Linked {
            let binding = store
                .find_workspace_checkout(&workspace.id)
                .await?
                .context("The linked checkout binding is missing")?;
            registration["repositoryPath"] = serde_json::json!(binding
                .repository_path
                .context("The linked repository origin is unverified")?);
        }
        let encoded =
            base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&registration)?);
        arguments.push_str(&format!(
            " --enroll-never-started-base64 {}",
            quote(&encoded)
        ));
    }
    if let Some(scope) = scope {
        let encoded = base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(scope)?);
        arguments.push_str(&format!(" --automation-cleanup-base64 {}", quote(&encoded)));
    }
    let script =
        crate::remote_owner_terminal_launch::owner_command_script(windows, install, &arguments);
    let output = tokio::time::timeout(std::time::Duration::from_secs(60), executor.run(&target, windows, &script)).await
        .context("The SSH retirement response timed out. Remote closure is unverified; retry to recover the owner receipt")??;
    let receipt: Value = serde_json::from_str(output.trim())
        .context("The SSH host did not return a retirement receipt")?;
    validate_receipt(workspace, &receipt)?;
    Ok(RemoteRetirementProof {
        source: Box::new(workspace.clone()),
    })
}

fn validate_receipt(workspace: &Workspace, receipt: &Value) -> Result<()> {
    let retired: Workspace = serde_json::from_value(receipt["workspace"].clone())?;
    if receipt["version"] != 1
        || receipt["processClosureVerified"] != true
        || retired.id != workspace.id
        || retired.instance_id != workspace.instance_id
        || retired.project_id != workspace.project_id
        || retired.path != workspace.path
        || retired.host_id != LOCAL_HOST_ID
        || retired.kind != workspace.kind
    {
        bail!("The SSH retirement receipt does not verify this task and checkout; Home records were preserved");
    }
    Ok(())
}

#[cfg(test)]
#[path = "remote_shared_retirement_tests.rs"]
mod tests;
