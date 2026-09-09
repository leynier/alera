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
use crate::remote_managed_workspace_git::write_git_bundle;
use crate::ssh_bootstrap::{powershell_string, remote_join, shell_quote};
use crate::ssh_remote::{
    probe_or_unreachable, require_bootstrapped_ssh_target, sftp_bundle_path, RemoteHostExecutor,
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
    let (workspace_root, staging_dir) = parse_probe_roots(&probe).ok_or_else(|| {
        anyhow!(
            "host '{}' did not return workspace and temp directories",
            target.alias
        )
    })?;
    let worktree_path = match layout.explicit_path.as_deref() {
        Some(path) => path.to_string(),
        None => remote_join(
            platform,
            &workspace_root,
            &[
                &format!("{}-{}", layout.project_slug, project.id),
                &layout.workspace_slug,
            ],
        ),
    };
    let repo_path = remote_join(
        platform,
        &workspace_root,
        &[&format!("{}-{}.git", layout.project_slug, project.id)],
    );
    let bundle_name = format!("alera-ws-{}.bundle", Uuid::new_v4());
    let remote_bundle = sftp_bundle_path(windows, &staging_dir, &bundle_name);
    let local_bundle = write_git_bundle(&project.repo_path).await?;
    executor
        .upload(&target, &local_bundle.path, &remote_bundle)
        .await
        .with_context(|| {
            format!(
                "failed to upload the git bundle to host '{}'. Confirm the host is reachable with `alera ssh-target status --id {}`.",
                target.alias, target.id
            )
        })?;
    let script = create_worktree_script(
        windows,
        &repo_path,
        &worktree_path,
        &remote_bundle,
        branch,
        source_branch.unwrap_or(""),
        request.reuse_existing_branch,
    );
    let stdout = executor
        .run(&target, windows, &script)
        .await
        .with_context(|| {
            format!(
                "failed creating the Git worktree on host '{}'. Confirm Git is installed there and retry `alera ssh-target status --id {}`.",
                target.alias, target.id
            )
        })?;
    let resolved_path = last_nonempty_line(&stdout).unwrap_or(worktree_path);
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
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    };
    let mut workspace = store.upsert_workspace(workspace).await?;
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
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let windows = probe_or_unreachable(executor, &target).await?;
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
    let repo_path = remote_join(
        platform,
        &workspace_root,
        &[&format!("{}-{}.git", project_slug, project.id)],
    );
    let script = remove_worktree_script(windows, &repo_path, &workspace.path, branch_to_delete);
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
    repo_path: &str,
    worktree_path: &str,
    bundle_path: &str,
    branch: &str,
    source_branch: &str,
    reuse_existing_branch: bool,
) -> String {
    if windows {
        windows_create_script(
            repo_path,
            worktree_path,
            bundle_path,
            branch,
            source_branch,
            reuse_existing_branch,
        )
    } else {
        posix_create_script(
            repo_path,
            worktree_path,
            bundle_path,
            branch,
            source_branch,
            reuse_existing_branch,
        )
    }
}

fn posix_create_script(
    repo_path: &str,
    worktree_path: &str,
    bundle_path: &str,
    branch: &str,
    source_branch: &str,
    reuse_existing_branch: bool,
) -> String {
    let reuse = if reuse_existing_branch { "1" } else { "0" };
    format!(
        r#"set -eu
export GIT_TERMINAL_PROMPT=0
if ! command -v git >/dev/null 2>&1; then
  echo 'git is not installed on this host. Install Git and retry.' >&2
  exit 1
fi
REPO={repo}
WORKTREE={worktree}
BUNDLE={bundle}
BRANCH={branch}
SOURCE={source}
REUSE={reuse}
mkdir -p "$(dirname "$REPO")"
if [ ! -d "$REPO" ]; then
  git clone --bare "$BUNDLE" "$REPO"
else
  git -C "$REPO" fetch "$BUNDLE" '+refs/heads/*:refs/heads/*'
fi
if [ "$REUSE" = "1" ]; then
  git -C "$REPO" rev-parse --verify "refs/heads/$BRANCH" >/dev/null
else
  if git -C "$REPO" rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
    echo "branch already exists on the remote clone: $BRANCH" >&2
    exit 1
  fi
  git -C "$REPO" branch "$BRANCH" "$SOURCE"
fi
if [ -e "$WORKTREE" ]; then
  echo "workspace path already exists: $WORKTREE" >&2
  exit 1
fi
mkdir -p "$(dirname "$WORKTREE")"
git -C "$REPO" worktree add "$WORKTREE" "$BRANCH"
rm -f "$BUNDLE"
cd "$WORKTREE"
pwd
"#,
        repo = shell_quote(repo_path),
        worktree = shell_quote(worktree_path),
        bundle = shell_quote(bundle_path),
        branch = shell_quote(branch),
        source = shell_quote(source_branch),
        reuse = reuse,
    )
}

fn windows_create_script(
    repo_path: &str,
    worktree_path: &str,
    bundle_path: &str,
    branch: &str,
    source_branch: &str,
    reuse_existing_branch: bool,
) -> String {
    let reuse = if reuse_existing_branch {
        "$true"
    } else {
        "$false"
    };
    format!(
        r#"$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {{
  throw 'git is not installed on this host. Install Git and retry.'
}}
$repo = {repo}
$worktree = {worktree}
$bundle = {bundle}
$branch = {branch}
$source = {source}
$reuse = {reuse}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $repo) | Out-Null
if (-not (Test-Path -LiteralPath $repo)) {{
  git clone --bare $bundle $repo
  if ($LASTEXITCODE -ne 0) {{ throw 'git clone failed' }}
}} else {{
  git -C $repo fetch $bundle '+refs/heads/*:refs/heads/*'
  if ($LASTEXITCODE -ne 0) {{ throw 'git fetch failed' }}
}}
if ($reuse) {{
  git -C $repo rev-parse --verify "refs/heads/$branch"
  if ($LASTEXITCODE -ne 0) {{ throw "branch does not exist on the remote clone: $branch" }}
}} else {{
  git -C $repo rev-parse --verify "refs/heads/$branch" 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {{ throw "branch already exists on the remote clone: $branch" }}
  git -C $repo branch $branch $source
  if ($LASTEXITCODE -ne 0) {{ throw 'git branch failed' }}
}}
if (Test-Path -LiteralPath $worktree) {{
  throw "workspace path already exists: $worktree"
}}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $worktree) | Out-Null
git -C $repo worktree add $worktree $branch
if ($LASTEXITCODE -ne 0) {{ throw 'git worktree add failed' }}
Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue
Write-Output (Get-Item -LiteralPath $worktree).FullName
"#,
        repo = powershell_string(repo_path),
        worktree = powershell_string(worktree_path),
        bundle = powershell_string(bundle_path),
        branch = powershell_string(branch),
        source = powershell_string(source_branch),
        reuse = reuse,
    )
}

fn remove_worktree_script(
    windows: bool,
    repo_path: &str,
    worktree_path: &str,
    branch_to_delete: Option<&str>,
) -> String {
    if windows {
        let expected = branch_to_delete.unwrap_or("");
        let branch = branch_to_delete
            .map(|branch| {
                format!(
                    "git -C $repo branch -D {}\nif ($LASTEXITCODE -ne 0) {{ }}\n",
                    powershell_string(branch)
                )
            })
            .unwrap_or_default();
        format!(
            r#"$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
$repo = {repo}
$worktree = {worktree}
$expected = {expected}
if (Test-Path -LiteralPath $worktree) {{
  if (-not [string]::IsNullOrWhiteSpace($expected)) {{
    $live = (git -C $worktree rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {{ throw "failed reading live branch for worktree: $worktree" }}
    if ($live -ne $expected) {{
      throw "Workspace branch does not match registered worktree: expected $expected, found $live"
    }}
  }}
}}
if (Test-Path -LiteralPath $repo) {{
  git -C $repo worktree remove --force $worktree
  {branch}
}}
if (Test-Path -LiteralPath $worktree) {{
  Remove-Item -LiteralPath $worktree -Recurse -Force
}}
"#,
            repo = powershell_string(repo_path),
            worktree = powershell_string(worktree_path),
            expected = powershell_string(expected),
            branch = branch,
        )
    } else {
        let expected = branch_to_delete.unwrap_or("");
        let branch = branch_to_delete
            .map(|branch| {
                format!(
                    "git -C \"$REPO\" branch -D {} >/dev/null 2>&1 || true\n",
                    shell_quote(branch)
                )
            })
            .unwrap_or_default();
        format!(
            r#"set -eu
export GIT_TERMINAL_PROMPT=0
REPO={repo}
WORKTREE={worktree}
EXPECTED={expected}
if [ -e "$WORKTREE" ]; then
  if [ -n "$EXPECTED" ]; then
    LIVE=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)
    if [ "$LIVE" != "$EXPECTED" ]; then
      printf 'Workspace branch does not match registered worktree: expected %s, found %s\n' "$EXPECTED" "$LIVE" >&2
      exit 1
    fi
  fi
fi
if [ -d "$REPO" ]; then
  git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  {branch}
fi
rm -rf "$WORKTREE"
"#,
            repo = shell_quote(repo_path),
            worktree = shell_quote(worktree_path),
            expected = shell_quote(expected),
            branch = branch,
        )
    }
}

#[cfg(test)]
#[path = "remote_managed_workspace_tests.rs"]
mod tests;
