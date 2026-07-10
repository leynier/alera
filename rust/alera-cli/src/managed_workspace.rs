use std::env;
use std::path::{Path, PathBuf};
use std::process::Stdio;

use alera_core::git as core_git;
use alera_core::runtime::{
    Project, ProjectConfig, ProjectKind, RuntimeStore, Workspace, WorkspaceCreationResult,
    WorkspaceKind, WorkspaceStatus, WorktreeCopyRule, WorktreeSetupReport, WorktreeSetupStepKind,
    WorktreeSetupStepReport, LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Context, Result};
use chrono::Utc;
use serde::Deserialize;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::time::{timeout, Duration};
use uuid::Uuid;

const SHELL_PATH_HYDRATION_DELIMITER: &str = "__ALERA_SHELL_PATH__";
const SHELL_PATH_HYDRATION_TIMEOUT: Duration = Duration::from_secs(5);
const SETUP_OUTPUT_TAIL_BYTES: usize = 16 * 1024;

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
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        child_count: 0,
    };
    let workspace = store.upsert_workspace(workspace).await?;
    let setup_report = run_worktree_setup(store, &project, &workspace).await;
    Ok(WorkspaceCreationResult {
        workspace,
        setup_report,
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
    core_git::remove_worktree(&project.repo_path, &workspace.path, true)
        .context("git worktree remove failed")?;
    let should_delete_branch = request
        .delete_branch
        .unwrap_or(!workspace.reuses_existing_branch);
    if should_delete_branch {
        let branch = workspace
            .branch
            .as_deref()
            .filter(|branch| !branch.is_empty())
            .ok_or_else(|| anyhow!("Workspace Branch Is Required"))?;
        core_git::delete_branch(&project.repo_path, branch, true)
            .with_context(|| format!("git branch -D {branch} failed"))?;
    }
    store.remove_workspace(&workspace.id, true).await?;
    Ok(workspace)
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

async fn run_worktree_setup(
    store: &RuntimeStore,
    project: &Project,
    workspace: &Workspace,
) -> WorktreeSetupReport {
    match effective_project_config(store, project).await {
        Ok(config) if config.is_empty() => WorktreeSetupReport::empty(),
        Ok(config) => run_setup_config(project, workspace, &config).await,
        Err(error) => WorktreeSetupReport {
            steps: vec![WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Config,
                label: "alera.toml".to_string(),
                succeeded: false,
                message: Some(error.to_string()),
                exit_code: None,
                stdout_tail: None,
                stderr_tail: None,
            }],
        },
    }
}

async fn effective_project_config(
    store: &RuntimeStore,
    project: &Project,
) -> Result<ProjectConfig> {
    if let Some(config) = store.find_project_config(&project.id).await? {
        return Ok(config);
    }
    let config_path = Path::new(&project.repo_path).join("alera.toml");
    if !config_path.exists() {
        return Ok(ProjectConfig::default());
    }
    let contents = std::fs::read_to_string(&config_path)
        .with_context(|| format!("Could not load {}", config_path.display()))?;
    parse_project_config_toml(&contents)
}

fn parse_project_config_toml(contents: &str) -> Result<ProjectConfig> {
    let value: toml::Value = contents.parse().context("Invalid alera.toml")?;
    let Some(root) = value.as_table() else {
        bail!("alera.toml must contain a table");
    };
    let git_hosting_provider = parse_git_hosting_provider(root.get("git_hosting_provider"))?;
    let Some(worktree) = root.get("worktree") else {
        return Ok(ProjectConfig {
            git_hosting_provider,
            ..ProjectConfig::default()
        });
    };
    let Some(worktree) = worktree.as_table() else {
        bail!("alera.toml [worktree] must be a table");
    };
    let copy = parse_copy_rules(worktree.get("copy"))?;
    let setup = parse_setup_commands(worktree.get("setup"))?;
    Ok(ProjectConfig {
        worktree: alera_core::runtime::WorktreeSetupConfig { copy, setup },
        git_hosting_provider,
    })
}

fn parse_git_hosting_provider(value: Option<&toml::Value>) -> Result<Option<String>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let Some(raw) = value.as_str() else {
        bail!("git_hosting_provider must be a string");
    };
    match raw.trim().to_lowercase().as_str() {
        "github" => Ok(Some("github".to_string())),
        "azuredevops" | "azure_devops" | "azure-devops" | "azure" => {
            Ok(Some("azureDevops".to_string()))
        }
        _ => bail!("git_hosting_provider must be one of: github, azureDevops"),
    }
}

fn parse_copy_rules(value: Option<&toml::Value>) -> Result<Vec<WorktreeCopyRule>> {
    let Some(value) = value else {
        return Ok(Vec::new());
    };
    let Some(items) = value.as_array() else {
        bail!("worktree.copy must be a list");
    };
    let mut rules = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        let Some(table) = item.as_table() else {
            bail!("worktree.copy[{index}] must be a table");
        };
        let from = required_string(table.get("from"), &format!("worktree.copy[{index}].from"))?;
        let to = optional_string(table.get("to"), &format!("worktree.copy[{index}].to"))?;
        let overwrite = table
            .get("overwrite")
            .map(|value| {
                value
                    .as_bool()
                    .ok_or_else(|| anyhow!("worktree.copy[{index}].overwrite must be a boolean"))
            })
            .transpose()?
            .unwrap_or(false);
        rules.push(WorktreeCopyRule {
            from: normalize_config_path(&from, &format!("worktree.copy[{index}].from"))?,
            to: to
                .map(|value| normalize_config_path(&value, &format!("worktree.copy[{index}].to")))
                .transpose()?,
            overwrite,
        });
    }
    Ok(rules)
}

fn parse_setup_commands(value: Option<&toml::Value>) -> Result<Vec<String>> {
    let Some(value) = value else {
        return Ok(Vec::new());
    };
    let Some(items) = value.as_array() else {
        bail!("worktree.setup must be a list");
    };
    let mut commands = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        commands.push(required_string(
            Some(item),
            &format!("worktree.setup[{index}]"),
        )?);
    }
    Ok(commands)
}

fn required_string(value: Option<&toml::Value>, label: &str) -> Result<String> {
    let Some(value) = value else {
        bail!("{label} must be a non-empty string");
    };
    let Some(value) = value.as_str() else {
        bail!("{label} must be a non-empty string");
    };
    let trimmed = value.trim();
    if trimmed.is_empty() {
        bail!("{label} must be a non-empty string");
    }
    Ok(trimmed.to_string())
}

fn optional_string(value: Option<&toml::Value>, label: &str) -> Result<Option<String>> {
    match value {
        Some(value) => required_string(Some(value), label).map(Some),
        None => Ok(None),
    }
}

fn normalize_config_path(value: &str, label: &str) -> Result<String> {
    let path = value.trim().replace('\\', "/");
    if path.is_empty() {
        bail!("{label} must be a non-empty string");
    }
    if path.starts_with('/') || path.contains(':') {
        bail!("{label} Must Be a Relative Path");
    }
    let mut parts = Vec::new();
    for part in path.split('/') {
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            bail!("{label} Must Stay Inside the Project");
        }
        parts.push(part);
    }
    if parts.is_empty() {
        bail!("{label} must be a non-empty string");
    }
    Ok(parts.join("/"))
}

async fn run_setup_config(
    project: &Project,
    workspace: &Workspace,
    config: &ProjectConfig,
) -> WorktreeSetupReport {
    let mut steps = Vec::new();
    for rule in &config.worktree.copy {
        let report = copy_rule(project, workspace, rule);
        let succeeded = report.succeeded;
        steps.push(report);
        if !succeeded {
            return WorktreeSetupReport { steps };
        }
    }
    let command_environment = if config.worktree.setup.is_empty() {
        Vec::new()
    } else {
        setup_command_environment().await
    };
    for command in &config.worktree.setup {
        let report = run_setup_command(&workspace.path, command, &command_environment).await;
        let succeeded = report.succeeded;
        steps.push(report);
        if !succeeded {
            return WorktreeSetupReport { steps };
        }
    }
    WorktreeSetupReport { steps }
}

fn copy_rule(
    project: &Project,
    workspace: &Workspace,
    rule: &WorktreeCopyRule,
) -> WorktreeSetupStepReport {
    let label = format!("{} -> {}", rule.from, rule.destination());
    match copy_rule_inner(project, workspace, rule) {
        Ok(()) => WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Copy,
            label,
            succeeded: true,
            message: None,
            exit_code: None,
            stdout_tail: None,
            stderr_tail: None,
        },
        Err(error) => WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Copy,
            label,
            succeeded: false,
            message: Some(error.to_string()),
            exit_code: None,
            stdout_tail: None,
            stderr_tail: None,
        },
    }
}

fn copy_rule_inner(
    project: &Project,
    workspace: &Workspace,
    rule: &WorktreeCopyRule,
) -> Result<()> {
    let project_root = std::fs::canonicalize(&project.repo_path)?;
    let workspace_root = std::fs::canonicalize(&workspace.path)?;
    let source_path = join_config_path(&project_root, &rule.from);
    let target_path = join_config_path(&workspace_root, rule.destination());
    reject_symlink(&source_path, "Source is a symlink")?;
    let source_metadata = std::fs::metadata(&source_path).context("Source does not exist")?;
    let source_canonical = std::fs::canonicalize(&source_path)?;
    if !is_within_or_equal(&project_root, &source_canonical) {
        bail!("Source escapes the project root");
    }
    prepare_target(&target_path, &workspace_root, rule.overwrite)?;
    if source_metadata.is_dir() {
        copy_directory(&source_path, &target_path, &workspace_root)?;
    } else if source_metadata.is_file() {
        std::fs::copy(&source_path, &target_path)?;
    } else {
        bail!("Unsupported source type");
    }
    Ok(())
}

fn join_config_path(root: &Path, relative: &str) -> PathBuf {
    relative
        .split('/')
        .fold(root.to_path_buf(), |path, part| path.join(part))
}

fn reject_symlink(path: &Path, message: &str) -> Result<()> {
    if std::fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_symlink())
        .unwrap_or(false)
    {
        bail!("{message}");
    }
    Ok(())
}

fn prepare_target(target_path: &Path, workspace_root: &Path, overwrite: bool) -> Result<()> {
    validate_destination_parent(target_path, workspace_root)?;
    if let Some(parent) = target_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    validate_destination_parent(target_path, workspace_root)?;
    let target_metadata = match std::fs::symlink_metadata(target_path) {
        Ok(metadata) => Some(metadata),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => return Err(error.into()),
    };
    let Some(target_metadata) = target_metadata else {
        return Ok(());
    };
    if !overwrite {
        bail!("Destination already exists");
    }
    if target_metadata.is_dir() {
        std::fs::remove_dir_all(target_path)?;
    } else {
        std::fs::remove_file(target_path)?;
    }
    Ok(())
}

fn copy_directory(source_path: &Path, target_path: &Path, workspace_root: &Path) -> Result<()> {
    std::fs::create_dir_all(target_path)?;
    let target_canonical = std::fs::canonicalize(target_path)?;
    if !is_within_or_equal(workspace_root, &target_canonical) {
        bail!("Destination escapes the workspace root");
    }
    for entry in std::fs::read_dir(source_path)? {
        let entry = entry?;
        let child_source = entry.path();
        reject_symlink(&child_source, "Directory contains a symlink")?;
        let child_target = target_path.join(entry.file_name());
        let metadata = entry.metadata()?;
        if metadata.is_dir() {
            copy_directory(&child_source, &child_target, workspace_root)?;
        } else if metadata.is_file() {
            std::fs::copy(&child_source, &child_target)?;
        } else {
            bail!("Directory contains an unsupported entry");
        }
    }
    Ok(())
}

fn validate_destination_parent(target_path: &Path, workspace_root: &Path) -> Result<()> {
    let mut current = target_path
        .parent()
        .ok_or_else(|| anyhow!("Destination escapes the workspace root"))?
        .to_path_buf();
    loop {
        if current.exists() {
            reject_symlink(&current, "Destination contains a symlink")?;
            if !current.is_dir() {
                bail!("Destination parent is not a directory");
            }
            let canonical = std::fs::canonicalize(&current)?;
            if !is_within_or_equal(workspace_root, &canonical) {
                bail!("Destination escapes the workspace root");
            }
        }
        if current == workspace_root {
            return Ok(());
        }
        let Some(parent) = current.parent() else {
            bail!("Destination escapes the workspace root");
        };
        if parent == current {
            bail!("Destination escapes the workspace root");
        }
        current = parent.to_path_buf();
    }
}

fn is_within_or_equal(parent: &Path, child: &Path) -> bool {
    child == parent || child.starts_with(parent)
}

async fn run_setup_command(
    workspace_path: &str,
    command: &str,
    environment: &[(String, String)],
) -> WorktreeSetupStepReport {
    let (executable, args) = shell_invocation(command);
    let mut child = match Command::new(executable)
        .args(args)
        .current_dir(workspace_path)
        .envs(environment.iter().map(|(key, value)| (key, value)))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => {
            return WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Command,
                label: command.to_string(),
                succeeded: false,
                message: Some(error.to_string()),
                exit_code: None,
                stdout_tail: None,
                stderr_tail: None,
            };
        }
    };
    let stdout_tail = child
        .stdout
        .take()
        .map(|stdout| tokio::spawn(read_bounded_tail(stdout)));
    let stderr_tail = child
        .stderr
        .take()
        .map(|stderr| tokio::spawn(read_bounded_tail(stderr)));
    match child.wait().await {
        Ok(status) => {
            let code = status.code().unwrap_or(-1) as i64;
            WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Command,
                label: command.to_string(),
                succeeded: status.success(),
                message: if status.success() {
                    None
                } else {
                    Some(format!("Command exited with code {code}"))
                },
                exit_code: Some(code),
                stdout_tail: await_tail(stdout_tail).await,
                stderr_tail: await_tail(stderr_tail).await,
            }
        }
        Err(error) => WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Command,
            label: command.to_string(),
            succeeded: false,
            message: Some(error.to_string()),
            exit_code: None,
            stdout_tail: None,
            stderr_tail: None,
        },
    }
}

async fn await_tail(handle: Option<tokio::task::JoinHandle<Option<String>>>) -> Option<String> {
    match handle {
        Some(handle) => handle.await.ok().flatten(),
        None => None,
    }
}

async fn read_bounded_tail<R>(mut reader: R) -> Option<String>
where
    R: tokio::io::AsyncRead + Unpin + Send + 'static,
{
    let mut tail = BoundedOutputTail::default();
    let mut buffer = [0_u8; 8192];
    loop {
        match reader.read(&mut buffer).await {
            Ok(0) => break,
            Ok(count) => tail.push(&buffer[..count]),
            Err(_) => break,
        }
    }
    tail.value()
}

#[derive(Default)]
struct BoundedOutputTail {
    bytes: Vec<u8>,
}

impl BoundedOutputTail {
    fn push(&mut self, chunk: &[u8]) {
        self.bytes.extend_from_slice(chunk);
        if self.bytes.len() > SETUP_OUTPUT_TAIL_BYTES {
            let excess = self.bytes.len() - SETUP_OUTPUT_TAIL_BYTES;
            self.bytes.drain(0..excess);
        }
    }

    fn value(self) -> Option<String> {
        text_tail(&self.bytes)
    }
}

async fn setup_command_environment() -> Vec<(String, String)> {
    let mut environment = env::vars().collect::<Vec<_>>();
    if cfg!(windows) {
        return environment;
    }
    let Some(shell) = pick_user_shell() else {
        return environment;
    };
    if let Some(segments) = hydrate_shell_path(&shell).await {
        merge_path_segments(&mut environment, &segments);
    }
    environment
}

fn pick_user_shell() -> Option<String> {
    let shell = env::var("SHELL").ok().map(|value| value.trim().to_string());
    if let Some(shell) = shell.filter(|value| !value.is_empty()) {
        return Some(shell);
    }
    if cfg!(target_os = "macos") {
        Some("/bin/zsh".to_string())
    } else {
        Some("/bin/bash".to_string())
    }
}

async fn hydrate_shell_path(shell: &str) -> Option<Vec<String>> {
    let command = format!(
        "printf '%s' '{delimiter}'; printf '%s' \"$PATH\"; printf '%s' '{delimiter}'",
        delimiter = SHELL_PATH_HYDRATION_DELIMITER,
    );
    let mut process = Command::new(shell);
    process.args(["-ilc", &command]);
    let output = match timeout(SHELL_PATH_HYDRATION_TIMEOUT, process.output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(_)) | Err(_) => return None,
    };
    let segments = parse_hydrated_shell_path(&output.stdout);
    if segments.is_empty() {
        None
    } else {
        Some(segments)
    }
}

fn parse_hydrated_shell_path(stdout: &[u8]) -> Vec<String> {
    let cleaned = String::from_utf8_lossy(stdout);
    let Some(first) = cleaned.find(SHELL_PATH_HYDRATION_DELIMITER) else {
        return Vec::new();
    };
    let start = first + SHELL_PATH_HYDRATION_DELIMITER.len();
    let Some(second) = cleaned[start..].find(SHELL_PATH_HYDRATION_DELIMITER) else {
        return Vec::new();
    };
    cleaned[start..start + second]
        .trim()
        .split(':')
        .filter(|segment| !segment.is_empty())
        .map(ToString::to_string)
        .collect()
}

fn merge_path_segments(environment: &mut Vec<(String, String)>, shell_segments: &[String]) {
    let existing = environment
        .iter()
        .position(|(key, _)| key == "PATH")
        .and_then(|index| {
            environment
                .get(index)
                .map(|(_, value)| (index, value.clone()))
        });
    let existing_segments = existing
        .as_ref()
        .map(|(_, path)| split_path_segments(path))
        .unwrap_or_default();
    let mut merged = Vec::<String>::new();
    for segment in shell_segments.iter().chain(existing_segments.iter()) {
        if !segment.is_empty() && !merged.iter().any(|value| value == segment) {
            merged.push(segment.clone());
        }
    }
    if merged.is_empty() {
        return;
    }
    let value = merged.join(":");
    if let Some((index, _)) = existing {
        environment[index].1 = value;
    } else {
        environment.push(("PATH".to_string(), value));
    }
}

fn split_path_segments(value: &str) -> Vec<String> {
    value
        .split(':')
        .filter(|segment| !segment.is_empty())
        .map(ToString::to_string)
        .collect()
}

fn shell_invocation(command: &str) -> (&'static str, Vec<String>) {
    if cfg!(windows) {
        (
            "cmd.exe",
            vec![
                "/d".to_string(),
                "/s".to_string(),
                "/c".to_string(),
                command.to_string(),
            ],
        )
    } else {
        ("/bin/sh", vec!["-c".to_string(), command.to_string()])
    }
}

fn text_tail(bytes: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(bytes).trim().to_string();
    if text.is_empty() {
        return None;
    }
    const MAX_CHARS: usize = 4000;
    if text.chars().count() <= MAX_CHARS {
        return Some(text);
    }
    let mut chars = text.chars().rev().take(MAX_CHARS).collect::<Vec<_>>();
    chars.reverse();
    Some(chars.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::process::Command as StdCommand;

    use alera_core::runtime::{
        Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
        LOCAL_HOST_ID,
    };
    use chrono::Utc;

    use super::{
        create_managed_workspace, merge_path_segments, parse_hydrated_shell_path, prepare_target,
        slugify, text_tail, ManagedWorkspaceCreateRequest,
    };

    #[test]
    fn slugify_matches_workspace_path_segments() {
        assert_eq!(slugify("Feature/Coverage").unwrap(), "feature-coverage");
        assert_eq!(slugify("  Fix UI  State  ").unwrap(), "fix-ui-state");
        assert!(slugify("///").is_err());
    }

    #[test]
    fn text_tail_keeps_unicode_boundaries() {
        let input = format!("{}{}", "a".repeat(4001), "ñ");
        let tail = text_tail(input.as_bytes()).unwrap();

        assert!(tail.starts_with('a'));
        assert!(tail.ends_with('ñ'));
        assert_eq!(tail.chars().count(), 4000);
    }

    #[test]
    fn text_tail_trims_empty_output() {
        assert_eq!(text_tail(b" \n\t "), None);
    }

    #[test]
    fn parse_hydrated_shell_path_extracts_marked_segments() {
        let stdout = b"noise__ALERA_SHELL_PATH__/shell/bin:/usr/bin__ALERA_SHELL_PATH__";

        assert_eq!(
            parse_hydrated_shell_path(stdout),
            vec!["/shell/bin".to_string(), "/usr/bin".to_string()]
        );
    }

    #[test]
    fn merge_path_segments_prepends_shell_path_without_duplicates() {
        let mut environment = vec![("PATH".to_string(), "/usr/bin:/bin".to_string())];

        merge_path_segments(
            &mut environment,
            &["/custom/bin".to_string(), "/usr/bin".to_string()],
        );

        assert_eq!(environment[0].1, "/custom/bin:/usr/bin:/bin");
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

    #[cfg(unix)]
    #[test]
    fn prepare_target_treats_dangling_symlink_as_existing() {
        let dir = tempfile::tempdir().unwrap();
        let raw_workspace_root = dir.path().join("workspace");
        std::fs::create_dir(&raw_workspace_root).unwrap();
        let workspace_root = std::fs::canonicalize(&raw_workspace_root).unwrap();
        let target = workspace_root.join("copied.env");
        let outside = dir.path().join("outside.env");
        std::os::unix::fs::symlink(&outside, &target).unwrap();

        let error = prepare_target(&target, &workspace_root, false)
            .unwrap_err()
            .to_string();

        assert!(error.contains("Destination already exists"));
        assert!(!outside.exists());
        prepare_target(&target, &workspace_root, true).unwrap();
        assert!(std::fs::symlink_metadata(&target).is_err());
        assert!(!outside.exists());
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
