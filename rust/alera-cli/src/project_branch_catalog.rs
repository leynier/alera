use alera_core::runtime::{ProjectKind, RuntimeStore, LOCAL_HOST_ID};
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProjectBranchCatalog {
    pub version: u32,
    pub path: String,
    pub branches: Vec<String>,
    pub local_branches: Vec<String>,
}

pub(crate) async fn inspect(path: String) -> Result<ProjectBranchCatalog> {
    tokio::task::spawn_blocking(move || {
        let path = std::fs::canonicalize(path)?
            .to_str()
            .ok_or_else(|| anyhow!("Checkout path is not valid UTF-8"))?
            .to_string();
        alera_core::git::project_checkout_branch(&path)?;
        let branches = alera_core::git::list_branches(&path)?;
        let mut local_branches = Vec::new();
        for branch in &branches {
            if alera_core::git::branch_exists(&path, branch)? {
                local_branches.push(branch.clone());
            }
        }
        Ok(ProjectBranchCatalog {
            version: 1,
            path,
            branches,
            local_branches,
        })
    })
    .await?
}

pub(crate) async fn list<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    project_id: &str,
    host_id: &str,
    executor: &E,
) -> Result<serde_json::Value> {
    let project = store
        .find_project(project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {project_id}"))?;
    if project.kind != ProjectKind::GitRepository {
        bail!("Branch selection requires a Git project");
    }
    let checkout = store
        .find_project_checkout(project_id, host_id)
        .await?
        .ok_or_else(|| {
            anyhow!("Register the project checkout on the selected host before loading branches")
        })?;
    let catalog = if host_id == LOCAL_HOST_ID {
        inspect(checkout.path.clone()).await?
    } else {
        let target = require_bootstrapped_ssh_target(store, host_id).await?;
        let windows = probe_or_unreachable(executor, &target).await?;
        let install = target
            .install_dir
            .as_deref()
            .filter(|path| !path.trim().is_empty())
            .ok_or_else(|| {
                anyhow!("Bootstrap this SSH host again to record its runtime installation")
            })?;
        let quote = if windows {
            crate::ssh_bootstrap::powershell_string
        } else {
            crate::ssh_bootstrap::shell_quote
        };
        let script = crate::remote_project_checkout::checkout_command_script(
            windows,
            install,
            &format!(
                "project inspect-checkout-branches --path {}",
                quote(&checkout.path)
            ),
        );
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(30),
            executor.run(&target, windows, &script),
        )
        .await
        .context("SSH branch inspection timed out")??;
        if output.len() > 4_194_304 {
            bail!("SSH branch inspection exceeds the response limit");
        }
        let result: ProjectBranchCatalog = serde_json::from_str(output.trim())
            .context("Update the SSH runtime to inspect branches on the selected checkout")?;
        if result.version != 1 || result.path != checkout.path {
            bail!("SSH branch inspection returned a different checkout or unsupported response");
        }
        result
    };
    let latest = store.find_project_checkout(project_id, host_id).await?;
    if latest.as_ref().map(|value| (&value.id, &value.path)) != Some((&checkout.id, &checkout.path))
    {
        bail!("The project checkout changed while branches were loading; try again");
    }
    Ok(serde_json::json!({
        "projectId": project_id, "hostId": host_id, "path": catalog.path,
        "branches": catalog.branches, "localBranches": catalog.local_branches,
    }))
}
