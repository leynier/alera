//! Create and remove Alera-managed Git worktrees on a bootstrapped SSH host.

use std::path::Path;

use alera_core::runtime::{
    Project, RuntimeStore, Workspace, WorkspaceCreationResult, WorkspaceKind, WorkspaceStatus,
    WorktreeSetupReport,
};
use anyhow::{anyhow, bail, Context, Result};
use chrono::Utc;
use uuid::Uuid;

use crate::managed_workspace::ManagedWorkspaceCreateRequest;
use crate::ssh_bootstrap::{powershell_string, remote_join, shell_quote};
use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, RemoteHostExecutor,
};

pub(crate) async fn create_remote_managed_workspace<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: ManagedWorkspaceCreateRequest,
    project: &Project,
    host_id: &str,
    executor: &E,
) -> Result<WorkspaceCreationResult> {
    let branch = request.branch.trim();
    let source_branch = request
        .source_branch
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let display_name = request
        .name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(branch);
    let target = require_bootstrapped_ssh_target(store, host_id).await?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let checkout = store
        .find_project_checkout(&project.id, host_id)
        .await?
        .ok_or_else(|| {
            anyhow!("Register a project checkout on this SSH host before creating a worktree")
        })?;
    let install_dir = target.install_dir.as_deref().ok_or_else(|| {
        anyhow!("Bootstrap the SSH sidecar again to record its installation directory")
    })?;
    let platform = if windows { "windows" } else { "posix" };
    let layout = remote_layout(project, display_name, &request)?;
    let probe = executor
        .run(
            &target,
            windows,
            &probe_roots_script(windows, layout.explicit_root.as_deref()),
        )
        .await
        .with_context(|| format!("failed probing host '{}'", target.alias))?;
    let (workspace_root, _) = parse_probe_roots(&probe).ok_or_else(|| {
        anyhow!(
            "host '{}' did not return workspace and temp directories",
            target.alias
        )
    })?;
    let worktree_path = match layout.explicit_path.as_deref() {
        Some(path) => path.to_string(),
        None => checkout_join(
            platform,
            &workspace_root,
            &[
                &format!("{}-{}", layout.project_slug, project.id),
                &layout.workspace_slug,
            ],
        ),
    };
    let repo_path = checkout.path;
    let script = create_worktree_script(
        windows,
        install_dir,
        &repo_path,
        &worktree_path,
        branch,
        source_branch.unwrap_or("HEAD"),
        request.reuse_existing_branch,
    );
    let stdout = executor
        .run(&target, windows, &script)
        .await
        .with_context(|| {
            format!(
                "failed creating the Git worktree on host '{}'. Verify checkout access and update the remote sidecar if create-checkout-worktree is unsupported. Check connectivity with `alera ssh-target status --id {}`.",
                target.alias, target.id
            )
        })?;
    let created: crate::project_checkout_worktree::CreatedCheckoutWorktree = serde_json::from_str(stdout.trim())
        .context("The remote sidecar did not return a supported worktree receipt; inspect the remote destination before retrying")?;
    if created.version != 1
        || created.repository_path != repo_path
        || created.branch != branch
        || created.path.is_empty()
    {
        bail!("The remote worktree receipt does not match this request; its files were retained");
    }
    let resolved_path = created.path;
    let now = Utc::now();
    let workspace = Workspace {
        id: request
            .id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string)
            .unwrap_or_else(|| Uuid::new_v4().to_string()),
        instance_id: Uuid::new_v4().to_string(),
        host_id: target.id.clone(),
        project_id: project.id.clone(),
        name: display_name.to_string(),
        branch: Some(branch.to_string()),
        path: resolved_path,
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: if request.reuse_existing_branch {
            None
        } else {
            source_branch.map(ToString::to_string)
        },
        reuses_existing_branch: request.reuse_existing_branch,
        is_pinned: false,
        is_archived: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    };
    let mut workspace = store
        .insert_workspace_with_repository(workspace, &repo_path)
        .await?;
    if let Some(parent_workspace_id) = request.parent_workspace_id.as_deref() {
        store
            .link_workspaces(parent_workspace_id, &workspace.id)
            .await?;
        workspace = store
            .find_workspace(&workspace.id)
            .await?
            .ok_or_else(|| anyhow!("Workspace disappeared after linking: {}", workspace.id))?;
    }
    Ok(WorkspaceCreationResult {
        workspace,
        setup_report: WorktreeSetupReport::empty(),
        deferred_setup_command: None,
    })
}

pub(crate) async fn remove_remote_managed_workspace<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    project: &Project,
    branch_to_delete: Option<&str>,
    executor: &E,
) -> Result<()> {
    run_remote_workspace_removal(store, workspace, project, branch_to_delete, executor, false).await
}

pub(crate) async fn validate_remote_workspace_removal<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    project: &Project,
    branch: Option<&str>,
    executor: &E,
) -> Result<()> {
    run_remote_workspace_removal(store, workspace, project, branch, executor, true).await
}

async fn run_remote_workspace_removal<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    project: &Project,
    branch_to_delete: Option<&str>,
    executor: &E,
    preflight_only: bool,
) -> Result<()> {
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let repo_path = match store
        .find_workspace_checkout(&workspace.id)
        .await?
        .and_then(|checkout| checkout.repository_path)
    {
        Some(repository_path) => repository_path,
        None => {
            // Legacy worktrees retain their bare repository origin when a main checkout is registered.
            let platform = if windows { "windows" } else { "posix" };
            let probe = executor
                .run(&target, windows, &probe_roots_script(windows, None))
                .await
                .with_context(|| format!("failed probing host '{}'", target.alias))?;
            let (workspace_root, _) = parse_probe_roots(&probe).ok_or_else(|| {
                anyhow!(
                    "host '{}' did not return workspace and temp directories",
                    target.alias
                )
            })?;
            let project_slug = crate::managed_workspace_slug::slugify(
                Path::new(&project.repo_path)
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or(&project.name),
            )?;
            checkout_join(
                platform,
                &workspace_root,
                &[&format!("{}-{}.git", project_slug, project.id)],
            )
        }
    };
    let script_builder = if preflight_only {
        crate::remote_managed_workspace_remove_script::validate_worktree_removal_script
    } else {
        crate::remote_managed_workspace_remove_script::remove_worktree_script
    };
    let script = script_builder(windows, &repo_path, &workspace.path, branch_to_delete);
    executor
        .run(&target, windows, &script)
        .await
        .with_context(|| {
            format!(
                "failed removing the Git worktree on host '{}'. Confirm the host is reachable with `alera ssh-target status --id {}`.",
                target.alias, target.id
            )
        })?;
    Ok(())
}

fn checkout_join(platform: &str, root: &str, parts: &[&str]) -> String {
    let path = remote_join(platform, root, parts);
    // SFTP's /C:/ form is not an absolute path for the native Windows sidecar.
    let bytes = path.as_bytes();
    if platform == "windows"
        && bytes.len() >= 3
        && bytes[0] == b'/'
        && bytes[1].is_ascii_alphabetic()
        && bytes[2] == b':'
    {
        path[1..].to_string()
    } else {
        path
    }
}

struct RemoteLayout {
    explicit_path: Option<String>,
    explicit_root: Option<String>,
    project_slug: String,
    workspace_slug: String,
}

fn remote_layout(
    project: &Project,
    display_name: &str,
    request: &ManagedWorkspaceCreateRequest,
) -> Result<RemoteLayout> {
    let explicit_path = request
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    let explicit_root = request
        .workspace_root
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    if explicit_path.is_some() && explicit_root.is_some() {
        bail!("--path and --workspace-root cannot be used together");
    }
    Ok(RemoteLayout {
        explicit_path,
        explicit_root,
        project_slug: crate::managed_workspace_slug::slugify(
            Path::new(&project.repo_path)
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or(&project.name),
        )?,
        workspace_slug: crate::managed_workspace_slug::slugify(display_name)?,
    })
}

fn probe_roots_script(windows: bool, explicit_root: Option<&str>) -> String {
    if windows {
        let root = match explicit_root {
            Some(root) => format!(
                "$root = [Environment]::ExpandEnvironmentVariables({})",
                powershell_string(root)
            ),
            None => "$root = Join-Path $env:USERPROFILE '.alera\\workspaces'".to_string(),
        };
        format!(
            "$ErrorActionPreference = 'Stop'\n{root}\nNew-Item -ItemType Directory -Force -Path $root | Out-Null\n$temp = $env:TEMP\nif ([string]::IsNullOrWhiteSpace($temp)) {{ $temp = $env:TMP }}\nNew-Item -ItemType Directory -Force -Path $temp | Out-Null\nWrite-Output $root\nWrite-Output $temp\n"
        )
    } else {
        let root = match explicit_root {
            Some(root) => format!("ROOT={}", shell_quote(root)),
            None => "ROOT=\"${HOME}/.alera/workspaces\"".to_string(),
        };
        format!(
            "set -eu\n{root}\nmkdir -p \"$ROOT\"\nTMPDIR_VALUE=\"${{TMPDIR:-/tmp}}\"\nmkdir -p \"$TMPDIR_VALUE\"\nprintf '%s\\n' \"$ROOT\"\nprintf '%s\\n' \"$TMPDIR_VALUE\"\n"
        )
    }
}

fn parse_probe_roots(stdout: &str) -> Option<(String, String)> {
    let mut lines = stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty());
    let root = lines.next()?.to_string();
    let temp = lines.next()?.to_string();
    Some((root, temp))
}

#[cfg(test)]
fn last_nonempty_line(stdout: &str) -> Option<String> {
    stdout
        .lines()
        .map(str::trim)
        .rev()
        .find(|line| !line.is_empty())
        .map(ToString::to_string)
}

fn create_worktree_script(
    windows: bool,
    install_dir: &str,
    repo_path: &str,
    worktree_path: &str,
    branch: &str,
    source_branch: &str,
    reuse_existing_branch: bool,
) -> String {
    let quote = if windows {
        powershell_string
    } else {
        shell_quote
    };
    let reuse = if reuse_existing_branch {
        " --reuse-existing-branch"
    } else {
        ""
    };
    let arguments = format!(
        "project create-checkout-worktree --repository {} --path {} --branch {} --source {}{reuse}",
        quote(repo_path),
        quote(worktree_path),
        quote(branch),
        quote(source_branch)
    );
    if windows {
        format!("$ErrorActionPreference = 'Stop'\n$install = [Environment]::ExpandEnvironmentVariables({})\n$current = (Get-Content -Raw -LiteralPath (Join-Path $install 'current.txt')).Trim()\n& (Join-Path $current 'alera.exe') {arguments}\nif ($LASTEXITCODE -ne 0) {{ throw 'Remote worktree creation failed' }}\n", quote(install_dir))
    } else {
        format!("set -eu\ninstall={}\ncase \"$install\" in '~/'*) install=\"$HOME/${{install#\"~/\"}}\";; esac\nexec \"$install/current/alera\" {arguments}\n", quote(install_dir))
    }
}

#[cfg(test)]
#[path = "remote_managed_workspace_tests.rs"]
mod tests;
