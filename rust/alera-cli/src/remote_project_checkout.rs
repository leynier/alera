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
    /// Empty together with `clone_name` when the host picks the destination.
    #[serde(default)]
    pub path: String,
    pub clone_url: Option<String>,
    /// Directory name for a clone into the host's default projects folder,
    /// used instead of `path`. Only the host knows its home directory.
    #[serde(default)]
    pub clone_name: Option<String>,
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
        request.clone_name.as_deref(),
        executor,
    )
    .await?;
    store
        .register_project_checkout(&project.id, &host_id, &checkout.path)
        .await
}

/// A project whose only folder is on another host: nothing is checked out on
/// this device, `repoPath` is the path on that host, and the project checkout
/// row is what says so. With `clone_url` and no `path` the host clones into
/// its default projects folder first.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RegisterRemoteProjectRequest {
    pub host_id: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub kind: Option<ProjectKind>,
    #[serde(default)]
    pub clone_url: Option<String>,
}

pub(crate) async fn register_remote_project<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: RegisterRemoteProjectRequest,
    executor: &E,
) -> Result<serde_json::Value> {
    let host_id = crate::ssh_remote::normalized_host_id(Some(&request.host_id));
    if host_id == alera_core::runtime::LOCAL_HOST_ID {
        bail!("Use project registration for a folder on this device");
    }
    let kind = request.kind.unwrap_or(ProjectKind::GitRepository);
    let clone_url = request
        .clone_url
        .as_deref()
        .map(str::trim)
        .filter(|url| !url.is_empty());
    if clone_url.is_some() && kind != ProjectKind::GitRepository {
        bail!("Only Git projects can be cloned");
    }
    let clone_name = clone_url.map(clone_name_from_url);
    let checkout = inspect_remote_with_clone(
        store,
        &host_id,
        &request.path,
        kind,
        clone_url,
        clone_name.as_deref(),
        executor,
    )
    .await?;
    for project in store.list_projects().await? {
        if project.repo_path == checkout.path
            && store
                .find_project_checkout(&project.id, &host_id)
                .await?
                .is_some()
        {
            bail!(
                "This folder is already the project \"{}\" on that host",
                project.name
            );
        }
    }
    let name = request
        .name
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| {
            checkout
                .path
                .trim_end_matches(['/', '\\'])
                .rsplit(['/', '\\'])
                .next()
                .filter(|segment| !segment.is_empty())
                .unwrap_or("Project")
                .to_string()
        });
    let now = chrono::Utc::now();
    let project = store
        .upsert_project(alera_core::runtime::Project {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            repo_path: checkout.path.clone(),
            created_at: now,
            updated_at: now,
            kind,
        })
        .await?;
    let registered = store
        .register_project_checkout(&project.id, &host_id, &checkout.path)
        .await?;
    Ok(serde_json::json!({ "project": project, "checkout": registered }))
}

/// `git@github.com:owner/repo.git` and `https://host/owner/repo/` both name
/// the directory `repo`.
fn clone_name_from_url(url: &str) -> String {
    let last = url
        .trim_end_matches('/')
        .rsplit(['/', ':'])
        .next()
        .unwrap_or_default();
    let name = last.strip_suffix(".git").unwrap_or(last);
    let cleaned: String = name
        .chars()
        .map(|character| {
            if character.is_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '-'
            }
        })
        .collect();
    let cleaned = cleaned.trim_matches(['-', '.']).to_string();
    if cleaned.is_empty() {
        "project".to_string()
    } else {
        cleaned
    }
}

pub(crate) async fn inspect_remote<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    host_id: &str,
    path: &str,
    kind: ProjectKind,
    executor: &E,
) -> Result<CheckoutInspection> {
    inspect_remote_with_clone(store, host_id, path, kind, None, None, executor).await
}

async fn inspect_remote_with_clone<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    host_id: &str,
    path: &str,
    kind: ProjectKind,
    clone_url: Option<&str>,
    clone_name: Option<&str>,
    executor: &E,
) -> Result<CheckoutInspection> {
    let clone_name = clone_name.map(str::trim).filter(|name| !name.is_empty());
    if path.trim().is_empty() && (clone_url.is_none() || clone_name.is_none()) {
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
        Some(url) if !url.trim().is_empty() => match clone_name {
            Some(name) if path.trim().is_empty() => {
                clone_by_name_script(windows, install_dir, name, url)
            }
            _ => clone_script(windows, install_dir, path, url),
        },
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

fn clone_by_name_script(windows: bool, install_dir: &str, name: &str, url: &str) -> String {
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    checkout_command_script(
        windows,
        install_dir,
        &format!(
            "project clone-checkout-folder --name {} --url {}",
            quote(name),
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
        || !crate::windows_path_form::same_path(&inspection.path, &checkout.path)
        || !absolute
        || crate::windows_path_form::same_path(origin, &inspection.path)
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
