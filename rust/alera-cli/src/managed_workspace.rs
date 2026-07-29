//! Lifecycle of an Alera-managed Git worktree workspace: validating a create
//! or remove request, resolving where the worktree lives, and driving `git`.
//!
//! Applying the project's `worktree.copy` rules and `worktree.setup` commands
//! lives in [`crate::worktree_setup`].

use std::path::{Path, PathBuf};

use alera_core::git::{self as core_git, GitErrorKind};
use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceCreationResult, WorkspaceKind,
    WorkspaceStatus, LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Context, Result};
use chrono::Utc;
use serde::Deserialize;
use uuid::Uuid;

use crate::worktree_setup::{prepare_deferred_worktree_setup, run_worktree_setup};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ManagedWorkspaceCreateRequest {
    #[serde(default)]
    pub id: Option<String>,
    pub project_id: String,
    #[serde(default)]
    pub name: Option<String>,
    pub branch: String,
    #[serde(default)]
    pub source_branch: Option<String>,
    #[serde(default)]
    pub reuse_existing_branch: bool,
    #[serde(default)]
    pub workspace_root: Option<String>,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub parent_workspace_id: Option<String>,
    /// Asks the host to prepare the worktree setup instead of running it, so
    /// the caller can show it in a terminal. Defaults to running it inline,
    /// which is what the `alera` CLI and the mobile gateway still want.
    #[serde(default)]
    pub defer_setup: bool,
    /// Directory the deferred setup script is written to. The host fills this
    /// in from its own state directory; a caller cannot choose it.
    #[serde(skip)]
    pub setup_script_directory: Option<PathBuf>,
}
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ManagedWorkspaceRemoveRequest {
    pub id: String,
    #[serde(default)]
    pub delete_branch: Option<bool>,
}
pub async fn create_managed_workspace(
    store: &RuntimeStore,
    request: ManagedWorkspaceCreateRequest,
) -> Result<WorkspaceCreationResult> {
    let project = store
        .find_project(&request.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", request.project_id))?;
    if project.kind != ProjectKind::GitRepository {
        bail!("Linked Workspaces Require a Git Repository Project");
    }
    let requested_id = match request.id.as_deref().map(str::trim) {
        Some("") => bail!("Workspace Id Is Required"),
        Some(id) => {
            if store.find_workspace(id).await?.is_some() {
                bail!("A workspace with id \"{id}\" already exists");
            }
            Some(id.to_string())
        }
        None => None,
    };
    if let Some(parent_workspace_id) = request.parent_workspace_id.as_deref() {
        if requested_id.as_deref() == Some(parent_workspace_id) {
            bail!("Workspace cannot be related to itself");
        }
        if store.find_workspace(parent_workspace_id).await?.is_none() {
            bail!("Parent workspace not found: {parent_workspace_id}");
        }
    }

    let branch = require_trimmed(&request.branch, "New Branch Name Is Required")?;
    let source_branch = request
        .source_branch
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    if !request.reuse_existing_branch && source_branch.is_none() {
        bail!("Source Branch Is Required");
    }

    if !core_git::is_valid_branch_name(&branch)? {
        bail!("Invalid branch name \"{branch}\"");
    }
    if request.reuse_existing_branch {
        ensure_target_branch_exists(&project, &branch)?;
    } else {
        let source = source_branch.as_deref().expect("checked above");
        ensure_source_branch_exists(&project, source)?;
        ensure_new_branch_does_not_exist(&project, &branch)?;
    }

    let workspaces = store.list_workspaces(&project.id).await?;
    if workspaces
        .iter()
        .any(|workspace| workspace.branch.as_deref() == Some(branch.as_str()))
    {
        bail!("A workspace for branch \"{branch}\" already exists");
    }

    let display_name = request
        .name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&branch)
        .to_string();
    let workspace_path = resolve_workspace_path(store, &project, &display_name, &request).await?;
    if workspaces
        .iter()
        .any(|workspace| path_equals(&workspace.path, &workspace_path))
    {
        bail!("A workspace already exists at \"{workspace_path}\"");
    }

    if !request.reuse_existing_branch {
        core_git::refresh_source_branch(
            &project.repo_path,
            source_branch.as_deref().expect("checked above"),
        )
        .context("git source branch refresh failed")?;
    }

    if let Some(parent) = Path::new(&workspace_path).parent() {
        std::fs::create_dir_all(parent)?;
    }
    core_git::create_worktree(
        &project.repo_path,
        &branch,
        &workspace_path,
        source_branch.as_deref().unwrap_or(""),
        request.reuse_existing_branch,
    )
    .context("git worktree add failed")?;

    let now = Utc::now();
    let workspace = Workspace {
        id: requested_id.unwrap_or_else(|| Uuid::new_v4().to_string()),
        instance_id: Uuid::new_v4().to_string(),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: project.id.clone(),
        name: display_name,
        branch: Some(branch),
        path: workspace_path,
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: if request.reuse_existing_branch {
            None
        } else {
            source_branch
        },
        reuses_existing_branch: request.reuse_existing_branch,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
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
    if request.defer_setup {
        let (setup_report, deferred_setup_command) = prepare_deferred_worktree_setup(
            store,
            &project,
            &workspace,
            request.setup_script_directory.as_deref(),
        )
        .await;
        return Ok(WorkspaceCreationResult {
            workspace,
            setup_report,
            deferred_setup_command,
        });
    }
    let setup_report = run_worktree_setup(store, &project, &workspace).await;
    Ok(WorkspaceCreationResult {
        workspace,
        setup_report,
        deferred_setup_command: None,
    })
}

pub async fn remove_managed_workspace(
    store: &RuntimeStore,
    request: ManagedWorkspaceRemoveRequest,
) -> Result<Workspace> {
    let workspace = store
        .find_workspace(&request.id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {}", request.id))?;
    if workspace.kind == WorkspaceKind::Main {
        bail!("The main workspace cannot be removed");
    }
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", workspace.project_id))?;
    match core_git::remove_worktree(&project.repo_path, &workspace.path, true) {
        Ok(()) => {}
        Err(error)
            if error.kind == GitErrorKind::WorktreeNotFound
                && filesystem_entry_is_missing(&workspace.path)? => {}
        Err(error) => return Err(error).context("git worktree remove failed"),
    }
    let should_delete_branch = request
        .delete_branch
        .unwrap_or(!workspace.reuses_existing_branch);
    if should_delete_branch {
        let branch = workspace
            .branch
            .as_deref()
            .filter(|branch| !branch.is_empty())
            .ok_or_else(|| anyhow!("Workspace Branch Is Required"))?;
        match core_git::delete_branch(&project.repo_path, branch, true) {
            Ok(()) => {}
            Err(error) if error.kind == GitErrorKind::BranchNotFound => {}
            Err(error) => {
                return Err(error).with_context(|| format!("git branch -D {branch} failed"));
            }
        }
    }
    store.remove_workspace(&workspace.id, true).await?;
    Ok(workspace)
}

fn filesystem_entry_is_missing(path: &str) -> Result<bool> {
    match std::fs::symlink_metadata(path) {
        Ok(_) => Ok(false),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(true),
        Err(error) => {
            Err(error).with_context(|| format!("Could not inspect workspace path \"{path}\""))
        }
    }
}

fn require_trimmed(value: &str, message: &str) -> Result<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        bail!("{message}");
    }
    Ok(trimmed.to_string())
}

fn ensure_source_branch_exists(project: &Project, branch: &str) -> Result<()> {
    let branches = core_git::list_branches(&project.repo_path)?;
    if !branches.iter().any(|candidate| candidate == branch) {
        bail!("Source branch \"{branch}\" does not exist");
    }
    Ok(())
}

fn ensure_new_branch_does_not_exist(project: &Project, branch: &str) -> Result<()> {
    if core_git::branch_exists(&project.repo_path, branch)? {
        bail!("Branch \"{branch}\" already exists");
    }
    Ok(())
}

fn ensure_target_branch_exists(project: &Project, branch: &str) -> Result<()> {
    if !core_git::branch_exists(&project.repo_path, branch)? {
        bail!("Branch \"{branch}\" does not exist");
    }
    Ok(())
}

async fn resolve_workspace_path(
    store: &RuntimeStore,
    project: &Project,
    display_name: &str,
    request: &ManagedWorkspaceCreateRequest,
) -> Result<String> {
    let explicit_path = request
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let explicit_root = request
        .workspace_root
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    if explicit_path.is_some() && explicit_root.is_some() {
        bail!("--path and --workspace-root cannot be used together");
    }
    if let Some(path) = explicit_path {
        return Ok(path.to_string());
    }
    let root = match explicit_root {
        Some(root) => root.to_string(),
        None => store
            .get_workspace_directory()
            .await?
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(default_workspace_root),
    };
    let project_slug = slugify(
        Path::new(&project.repo_path)
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or(&project.name),
    )?;
    let workspace_slug = slugify(display_name)?;
    Ok(PathBuf::from(root)
        .join(format!("{project_slug}-{}", project.id))
        .join(workspace_slug)
        .to_string_lossy()
        .to_string())
}

fn default_workspace_root() -> String {
    let home = std::env::var("HOME")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| {
            std::env::var("USERPROFILE")
                .ok()
                .filter(|value| !value.is_empty())
        })
        .unwrap_or_else(|| ".".to_string());
    PathBuf::from(home)
        .join(".alera")
        .join("workspaces")
        .to_string_lossy()
        .to_string()
}

fn slugify(input: &str) -> Result<String> {
    let mut output = String::new();
    let mut last_dash = false;
    for ch in input.trim().to_lowercase().chars() {
        let next = if ch.is_ascii_alphanumeric() {
            last_dash = false;
            Some(ch)
        } else if ch.is_whitespace() || ch == '_' || ch == '/' || ch == '-' {
            if last_dash {
                None
            } else {
                last_dash = true;
                Some('-')
            }
        } else if last_dash {
            None
        } else {
            last_dash = true;
            Some('-')
        };
        if let Some(next) = next {
            output.push(next);
        }
    }
    let trimmed = output.trim_matches('-').to_string();
    if trimmed.is_empty() {
        bail!("Workspace name must contain a letter or digit");
    }
    Ok(trimmed)
}

fn path_equals(left: &str, right: &str) -> bool {
    let left = canonical_path(left);
    let right = canonical_path(right);
    left == right
}

fn canonical_path(path: &str) -> String {
    let target = Path::new(path);
    if let Ok(resolved) = std::fs::canonicalize(target) {
        return resolved.to_string_lossy().trim_end_matches('/').to_string();
    }
    if let (Some(parent), Some(name)) = (target.parent(), target.file_name()) {
        if let Ok(resolved_parent) = std::fs::canonicalize(parent) {
            return resolved_parent
                .join(name)
                .to_string_lossy()
                .trim_end_matches('/')
                .to_string();
        }
    }
    path.trim_end_matches('/').to_string()
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::process::Command as StdCommand;

    use alera_core::runtime::{
        Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
        WorktreeSetupStepKind, LOCAL_HOST_ID,
    };
    use chrono::Utc;

    use super::{create_managed_workspace, slugify, ManagedWorkspaceCreateRequest};

    #[test]
    fn slugify_matches_workspace_path_segments() {
        assert_eq!(slugify("Feature/Coverage").unwrap(), "feature-coverage");
        assert_eq!(slugify("  Fix UI  State  ").unwrap(), "fix-ui-state");
        assert!(slugify("///").is_err());
    }

    #[tokio::test]
    async fn create_managed_workspace_rejects_existing_id_before_worktree_create() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);

        let store = RuntimeStore::open(&dir.path().join("runtime"))
            .await
            .unwrap();
        let now = Utc::now();
        store
            .upsert_project(Project {
                id: "project-1".to_string(),
                name: "Project".to_string(),
                repo_path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
            .upsert_workspace(Workspace {
                id: "workspace-1".to_string(),
                instance_id: "instance-1".to_string(),
                host_id: LOCAL_HOST_ID.to_string(),
                project_id: "project-1".to_string(),
                name: "Main".to_string(),
                branch: Some("main".to_string()),
                path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Main,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: false,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                child_count: 0,
            })
            .await
            .unwrap();

        let worktree_path = dir.path().join("workspaces").join("feature-collide");
        let result = create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("workspace-1".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/collide".to_string()),
                branch: "feature/collide".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: None,
                defer_setup: false,
                setup_script_directory: None,
            },
        )
        .await;

        let error = result.unwrap_err().to_string();
        assert!(error.contains("workspace-1"));
        assert!(!worktree_path.exists());
        let existing = store.find_workspace("workspace-1").await.unwrap().unwrap();
        assert_eq!(existing.kind, WorkspaceKind::Main);
        assert_eq!(existing.path, repo.to_string_lossy());
    }

    #[tokio::test]
    async fn create_managed_workspace_rejects_missing_parent_before_worktree_create() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        let store = RuntimeStore::open(&dir.path().join("runtime"))
            .await
            .unwrap();
        let now = Utc::now();
        store
            .upsert_project(Project {
                id: "project-1".to_string(),
                name: "Project".to_string(),
                repo_path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        let worktree_path = dir.path().join("workspaces").join("feature-child");

        let result = create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("workspace-child".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/child".to_string()),
                branch: "feature/child".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: Some("missing-parent".to_string()),
                defer_setup: false,
                setup_script_directory: None,
            },
        )
        .await;

        assert!(result.unwrap_err().to_string().contains("missing-parent"));
        assert!(!worktree_path.exists());
        assert!(store
            .find_workspace("workspace-child")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn create_managed_workspace_returns_the_linked_parent() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        let store = RuntimeStore::open(&dir.path().join("runtime"))
            .await
            .unwrap();
        let now = Utc::now();
        store
            .upsert_project(Project {
                id: "project-1".to_string(),
                name: "Project".to_string(),
                repo_path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
            .upsert_workspace(Workspace {
                id: "parent".to_string(),
                instance_id: "parent-instance".to_string(),
                host_id: LOCAL_HOST_ID.to_string(),
                project_id: "project-1".to_string(),
                name: "Parent".to_string(),
                branch: Some("main".to_string()),
                path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Main,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: false,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                child_count: 0,
            })
            .await
            .unwrap();
        let worktree_path = dir.path().join("workspaces").join("feature-child");

        let result = create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("child".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/child".to_string()),
                branch: "feature/child".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: Some("parent".to_string()),
                defer_setup: false,
                setup_script_directory: None,
            },
        )
        .await
        .unwrap();

        assert_eq!(
            result.workspace.parent_workspace_id.as_deref(),
            Some("parent")
        );
    }

    #[tokio::test]
    async fn deferred_setup_writes_a_script_instead_of_running_the_commands() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        std::fs::write(repo.join(".env"), "TOKEN=1\n").unwrap();
        std::fs::write(
            repo.join("alera.toml"),
            "[worktree]\ncopy = [{ from = \".env\" }]\nsetup = [\"pnpm install\", \"pnpm build\"]\n",
        )
        .unwrap();
        let store = seed_project(dir.path(), &repo).await;
        let scripts = dir.path().join("scripts");
        let worktree_path = dir.path().join("workspaces").join("feature-deferred");

        let result = create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("workspace-deferred".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/deferred".to_string()),
                branch: "feature/deferred".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: None,
                defer_setup: true,
                setup_script_directory: Some(scripts.clone()),
            },
        )
        .await
        .unwrap();

        // Nothing ran: no copy landed and the report carries no steps, so the
        // create dialog has nothing to wait on.
        assert!(result.setup_report.steps.is_empty());
        assert!(!worktree_path.join(".env").exists());

        let command = result.deferred_setup_command.expect("deferred command");
        let script = crate::worktree_setup_script::setup_script_path(
            &scripts,
            "workspace-deferred",
            cfg!(windows),
        );
        assert!(script.exists(), "{}", script.display());
        assert!(command.contains(&script.display().to_string()), "{command}");
        let contents = std::fs::read_to_string(&script).unwrap();
        assert!(contents.contains("pnpm install"), "{contents}");
        assert!(contents.contains("pnpm build"), "{contents}");
        assert!(contents.contains("--copies-only"), "{contents}");
        assert!(!contents.contains("&&"), "{contents}");
    }

    #[tokio::test]
    async fn deferred_setup_stays_quiet_when_the_project_configures_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        let store = seed_project(dir.path(), &repo).await;
        let scripts = dir.path().join("scripts");
        let worktree_path = dir.path().join("workspaces").join("feature-plain");

        let result = create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("workspace-plain".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/plain".to_string()),
                branch: "feature/plain".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: None,
                defer_setup: true,
                setup_script_directory: Some(scripts.clone()),
            },
        )
        .await
        .unwrap();

        assert_eq!(result.deferred_setup_command, None);
        assert!(result.setup_report.steps.is_empty());
        assert!(!scripts.exists());
    }

    #[tokio::test]
    async fn deferred_setup_reports_an_invalid_config_like_the_inline_path() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        std::fs::write(repo.join("alera.toml"), "[worktree]\nsetup = 3\n").unwrap();
        let store = seed_project(dir.path(), &repo).await;
        let worktree_path = dir.path().join("workspaces").join("feature-broken");

        let result = create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("workspace-broken".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/broken".to_string()),
                branch: "feature/broken".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: None,
                defer_setup: true,
                setup_script_directory: Some(dir.path().join("scripts")),
            },
        )
        .await
        .unwrap();

        assert_eq!(result.deferred_setup_command, None);
        let step = result.setup_report.steps.first().expect("config step");
        assert_eq!(step.kind, WorktreeSetupStepKind::Config);
        assert!(!step.succeeded);
    }

    #[tokio::test]
    async fn setup_copies_only_applies_the_copy_rules_and_keeps_going_after_a_failure() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir(&repo).unwrap();
        init_git_repo(&repo);
        std::fs::write(repo.join(".env"), "TOKEN=1\n").unwrap();
        std::fs::write(
            repo.join("alera.toml"),
            "[worktree]\ncopy = [{ from = \"missing.env\" }, { from = \".env\" }]\nsetup = [\"exit 7\"]\n",
        )
        .unwrap();
        let store = seed_project(dir.path(), &repo).await;
        let worktree_path = dir.path().join("workspaces").join("feature-copies");
        create_managed_workspace(
            &store,
            ManagedWorkspaceCreateRequest {
                id: Some("workspace-copies".to_string()),
                project_id: "project-1".to_string(),
                name: Some("feature/copies".to_string()),
                branch: "feature/copies".to_string(),
                source_branch: Some("main".to_string()),
                reuse_existing_branch: false,
                workspace_root: None,
                path: Some(worktree_path.to_string_lossy().into_owned()),
                parent_workspace_id: None,
                defer_setup: true,
                setup_script_directory: Some(dir.path().join("scripts")),
            },
        )
        .await
        .unwrap();

        let report = crate::worktree_setup::run_workspace_setup(&store, "workspace-copies", true)
            .await
            .unwrap();

        // The first rule fails and the second still runs, matching what the
        // script does with the commands.
        assert_eq!(report.steps.len(), 2);
        assert!(!report.steps[0].succeeded);
        assert!(report.steps[1].succeeded);
        assert!(report
            .steps
            .iter()
            .all(|step| step.kind == WorktreeSetupStepKind::Copy));
        assert!(worktree_path.join(".env").exists());
    }

    async fn seed_project(root: &Path, repo: &Path) -> RuntimeStore {
        let store = RuntimeStore::open(&root.join("runtime")).await.unwrap();
        let now = Utc::now();
        store
            .upsert_project(Project {
                id: "project-1".to_string(),
                name: "Project".to_string(),
                repo_path: repo.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
    }

    fn init_git_repo(repo: &Path) {
        run_git(repo, &["init"]);
        run_git(repo, &["config", "user.email", "test@example.com"]);
        run_git(repo, &["config", "user.name", "Test"]);
        std::fs::write(repo.join("README.md"), "hello\n").unwrap();
        run_git(repo, &["add", "README.md"]);
        run_git(repo, &["commit", "-m", "initial"]);
        run_git(repo, &["branch", "-M", "main"]);
    }

    // Test fixture: it runs from a console, so the console-window suppression in
    // `alera_core::child_process` does not apply.
    #[allow(clippy::disallowed_methods)]
    fn run_git(repo: &Path, args: &[&str]) {
        let output = StdCommand::new("git")
            .args(args)
            .current_dir(repo)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "git {} failed\nstdout:\n{}\nstderr:\n{}",
            args.join(" "),
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
