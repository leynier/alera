use alera_core::runtime::{RuntimeStore, LOCAL_HOST_ID};
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::remote_sidecar_command::{parse_last_json_line, sidecar_command, SidecarProfile};
use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};
use crate::ssh_remote_command::RemoteCommandBudget;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProjectFileCatalog {
    pub version: u32,
    pub path: String,
    pub files: Vec<String>,
}

pub(crate) async fn inspect(path: String) -> Result<ProjectFileCatalog> {
    tokio::task::spawn_blocking(move || {
        let path = std::fs::canonicalize(path)?
            .to_str()
            .ok_or_else(|| anyhow!("Checkout path is not valid UTF-8"))?
            .to_string();
        let files = alera_core::workspace_files::collect_workspace_quick_open_paths(path.clone())?;
        Ok(ProjectFileCatalog {
            version: 1,
            path,
            files,
        })
    })
    .await?
}

pub(crate) async fn list<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    project_id: &str,
    host_id: &str,
    executor: &E,
) -> Result<alera_core::workspace_files::WorkspaceQuickOpenSession> {
    let checkout = store
        .find_project_checkout(project_id, host_id)
        .await?
        .ok_or_else(|| {
            anyhow!("Register the project checkout on the selected host before searching files")
        })?;
    let catalog = if host_id == LOCAL_HOST_ID {
        inspect(checkout.path.clone()).await?
    } else {
        let target = require_bootstrapped_ssh_target(store, host_id).await?;
        let shell = probe_or_unreachable(executor, &target).await?;
        let install = target
            .install_dir
            .as_deref()
            .filter(|path| !path.trim().is_empty())
            .ok_or_else(|| {
                anyhow!("Bootstrap this SSH host again to record its runtime installation")
            })?;
        let script = sidecar_command(
            shell,
            install,
            &format!(
                "project inspect-checkout-files --path {}",
                shell.quote(&checkout.path)
            ),
            SidecarProfile::Bare,
        );
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            executor.run(&target, shell, &script, RemoteCommandBudget::Transfer),
        )
        .await
        .context("SSH file indexing timed out")??;
        if output.len() > 16_777_216 {
            bail!("SSH file indexing exceeds the response limit");
        }
        let result: ProjectFileCatalog = parse_last_json_line(&output)
            .context("Update the SSH runtime to index files on the selected checkout")?;
        if result.version != 1 || result.path != checkout.path {
            bail!("SSH file indexing returned a different checkout or unsupported response");
        }
        result
    };
    let latest = store.find_project_checkout(project_id, host_id).await?;
    if latest.as_ref().map(|value| (&value.id, &value.path)) != Some((&checkout.id, &checkout.path))
    {
        bail!("The project checkout changed while files were indexing; try again");
    }
    tokio::task::spawn_blocking(move || {
        alera_core::workspace_files::import_workspace_quick_open_paths(catalog.files)
            .map_err(Into::into)
    })
    .await?
}
