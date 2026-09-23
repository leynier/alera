use alera_core::runtime::{ProjectKind, RepositoryCheckout, RuntimeStore};
use anyhow::{anyhow, bail, Context, Result};
use serde::Deserialize;

use crate::project_checkout_inspection::{CheckoutInspection, INSPECTION_VERSION};
use crate::ssh_bootstrap::{powershell_string, shell_quote};
use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RegisterProjectCheckoutRequest {
    pub project_id: String,
    pub host_id: String,
    pub path: String,
    pub clone_url: Option<String>,
}

pub(crate) async fn register<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: RegisterProjectCheckoutRequest,
    executor: &E,
) -> Result<RepositoryCheckout> {
    let project = store
        .find_project(&request.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", request.project_id))?;
    let host_id = crate::ssh_remote::normalized_host_id(Some(&request.host_id));
    if host_id == alera_core::runtime::LOCAL_HOST_ID {
        bail!("Use project registration to select the local project folder");
    }
    if request.clone_url.is_some() {
        if project.kind != ProjectKind::GitRepository {
            bail!("Only Git projects can clone an SSH checkout");
        }
        if store
            .find_project_checkout(&project.id, &host_id)
            .await?
            .is_some()
        {
            bail!("This project already has a checkout on this host; no clone was started");
        }
    }
    let checkout = inspect_remote_with_clone(
        store,
        &host_id,
        &request.path,
        project.kind,
        request.clone_url.as_deref(),
        executor,
    )
    .await?;
    store
        .register_project_checkout(&project.id, &host_id, &checkout.path)
        .await
}

pub(crate) async fn inspect_remote<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    host_id: &str,
    path: &str,
    kind: ProjectKind,
    executor: &E,
) -> Result<CheckoutInspection> {
    inspect_remote_with_clone(store, host_id, path, kind, None, executor).await
}

async fn inspect_remote_with_clone<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    host_id: &str,
    path: &str,
    kind: ProjectKind,
    clone_url: Option<&str>,
    executor: &E,
) -> Result<CheckoutInspection> {
    if path.trim().is_empty() {
        bail!("A checkout path is required");
    }
    let target = require_bootstrapped_ssh_target(store, host_id).await?;
    let install_dir = target
        .install_dir
        .as_deref()
        .filter(|path| !path.trim().is_empty())
        .ok_or_else(|| {
            anyhow!("Bootstrap this SSH host again to record its sidecar installation directory")
        })?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let script = match clone_url {
        Some(url) if !url.trim().is_empty() => clone_script(windows, install_dir, path, url),
        Some(_) => bail!("A clone source is required"),
        None => inspection_script(windows, install_dir, path, kind),
    };
    let stdout = executor.run(&target, windows, &script).await
        .context("Could not inspect or clone the SSH checkout. Verify access, use a new destination when cloning, and update the remote sidecar if the checkout command is unsupported. No existing checkout was replaced; inspect the destination before retrying")?;
    let result: CheckoutInspection = serde_json::from_str(stdout.trim()).context(
        "The SSH sidecar did not return a supported checkout inspection; update the remote sidecar",
    )?;
    let absolute = if windows {
        result.path.starts_with("\\\\") || result.path.starts_with("//") || {
            let bytes = result.path.as_bytes();
            bytes.len() >= 3
                && bytes[0].is_ascii_alphabetic()
                && bytes[1] == b':'
                && matches!(bytes[2], b'/' | b'\\')
        }
    } else {
        result.path.starts_with('/')
    };
    if result.version != INSPECTION_VERSION
        || result.kind != kind
        || !absolute
        || (kind == ProjectKind::GitRepository
            && result.branch.as_deref().is_none_or(str::is_empty))
        || (kind == ProjectKind::Folder && result.branch.is_some())
    {
        bail!("The SSH checkout inspection is incompatible with this project; no checkout was registered");
    }
    Ok(result)
}

fn inspection_script(windows: bool, install_dir: &str, path: &str, kind: ProjectKind) -> String {
    let kind = match kind {
        ProjectKind::Folder => "folder",
        ProjectKind::GitRepository => "git-repository",
    };
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    checkout_command_script(
        windows,
        install_dir,
        &format!(
            "project inspect-checkout --path {} --kind {kind}",
            quote(path)
        ),
    )
}

fn clone_script(windows: bool, install_dir: &str, path: &str, url: &str) -> String {
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    checkout_command_script(
        windows,
        install_dir,
        &format!(
            "project clone-checkout-folder --path {} --url {}",
            quote(path),
            quote(url)
        ),
    )
}

pub(crate) fn checkout_command_script(windows: bool, install_dir: &str, arguments: &str) -> String {
    if windows {
        format!("$ErrorActionPreference = 'Stop'\n$install = [Environment]::ExpandEnvironmentVariables({})\n$current = (Get-Content -Raw -LiteralPath (Join-Path $install 'current.txt')).Trim()\n& (Join-Path $current 'alera.exe') {arguments}\nif ($LASTEXITCODE -ne 0) {{ throw 'Remote checkout operation failed' }}\n", powershell_string(install_dir))
    } else {
        format!("set -eu\ninstall={}\ncase \"$install\" in '~/'*) install=\"$HOME/${{install#\"~/\"}}\";; esac\nexec \"$install/current/alera\" {arguments}\n", shell_quote(install_dir))
    }
}

pub(crate) async fn ensure_linked_origin<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &alera_core::runtime::Workspace,
    target: &alera_core::runtime::SshTarget,
    windows: bool,
    install: &str,
    executor: &E,
) -> Result<()> {
    if workspace.kind != alera_core::runtime::WorkspaceKind::Linked {
        return Ok(());
    }
    if workspace.host_id != target.id {
        bail!("The linked checkout owner changed before inspection");
    }
    let checkout = store
        .find_workspace_checkout(&workspace.id)
        .await?
        .context("The linked checkout binding is missing")?;
    if checkout.repository_path.is_some() {
        return Ok(());
    }
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    let script = checkout_command_script(
        windows,
        install,
        &format!(
            "project inspect-linked-checkout --path {}",
            quote(&workspace.path)
        ),
    );
    let output = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        executor.run(target, windows, &script),
    )
    .await
    .context("Linked repository inspection timed out")??;
    if output.len() > 1_048_576 {
        bail!("Linked repository inspection exceeds the response limit");
    }
    let inspection: crate::project_checkout_inspection::LinkedCheckoutInspection =
        serde_json::from_str(output.trim())
            .context("Update the SSH runtime to inspect the legacy linked repository origin")?;
    let origin = &inspection.repository_path;
    let absolute = if windows {
        origin.starts_with("\\\\") || origin.starts_with("//") || {
            let bytes = origin.as_bytes();
            bytes.len() >= 3
                && bytes[0].is_ascii_alphabetic()
                && bytes[1] == b':'
                && matches!(bytes[2], b'/' | b'\\')
        }
    } else {
        origin.starts_with('/')
    };
    if inspection.version != 1
        || inspection.path != checkout.path
        || !absolute
        || origin == &inspection.path
        || inspection.branch.is_empty()
    {
        bail!("The native linked inspection does not match the retained checkout");
    }
    store
        .record_verified_linked_origin(workspace, &checkout, origin)
        .await
}

#[cfg(test)]
#[path = "remote_project_checkout_tests.rs"]
mod tests;
