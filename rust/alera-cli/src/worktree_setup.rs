//! Runs a project's worktree setup: the `worktree.copy` rules, gitignored
//! matches from `.worktreeinclude`, and the `worktree.setup` commands from
//! `alera.toml` or the per-project UI override.
//!
//! Split out of `managed_workspace.rs`, which keeps the lifecycle of the
//! workspace itself: validating the request, creating and removing the Git
//! worktree, and resolving where it lives on disk.

use std::collections::HashSet;
use std::path::Path;

use alera_core::git as core_git;
use alera_core::runtime::{
    Project, ProjectConfig, RuntimeStore, Workspace, WorktreeCopyRule, WorktreeSetupReport,
    WorktreeSetupStepKind, WorktreeSetupStepReport,
};
use anyhow::{anyhow, Context, Result};

use crate::project_config_toml::parse_project_config_toml;
use crate::worktree_copy::copy_rule;
use crate::worktree_include::{
    expand_worktree_include, has_worktree_include, WORKTREE_INCLUDE_FILE,
};

use crate::worktree_setup_process::run_setup_command;
#[cfg(test)]
#[path = "worktree_setup_owner_tests.rs"]
mod owner_tests;
#[cfg(test)]
#[path = "worktree_setup_source_branch_tests.rs"]
mod source_branch_tests;

/// Resolves the project config and writes the script the "Setup" terminal will
/// run, instead of running the copies and commands here.
///
/// A config that fails to parse still comes back as the same failed `Config`
/// step the inline path reports, so the caller keeps surfacing it.
pub(crate) async fn prepare_deferred_worktree_setup(
    store: &RuntimeStore,
    project: &Project,
    workspace: &Workspace,
    script_directory: Option<&Path>,
) -> (WorktreeSetupReport, Option<String>) {
    if let Err(error) = validate_setup_owner(workspace) {
        return (config_error_report(&error.to_string()), None);
    }
    let config = match effective_project_config(store, project).await {
        Ok(config) => config,
        Err(error) => return (config_error_report(&error.to_string()), None),
    };
    if !setup_has_copy_or_command_actions(project, &config) {
        return (WorktreeSetupReport::empty(), None);
    }
    let Some(script_directory) = script_directory else {
        // Only the runtime host knows where to put the script, so anything
        // else falls back to running the setup rather than dropping it.
        return (
            run_setup_config(store, project, workspace, &config, true, None).await,
            None,
        );
    };
    let executable = match std::env::current_exe() {
        Ok(executable) => executable,
        Err(error) => {
            return (
                config_error_report(&format!("Could not resolve the Alera executable: {error}")),
                None,
            )
        }
    };
    match crate::worktree_setup_script::write_setup_script(
        script_directory,
        &executable,
        &workspace.id,
        &workspace.path,
        &config.worktree.setup,
        has_copy_actions(project, &config),
    ) {
        Ok(script) => (WorktreeSetupReport::empty(), Some(script.command)),
        Err(error) => (config_error_report(&error.to_string()), None),
    }
}

fn config_error_report(message: &str) -> WorktreeSetupReport {
    WorktreeSetupReport {
        steps: vec![WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Config,
            label: "alera.toml".to_string(),
            succeeded: false,
            message: Some(message.to_string()),
            exit_code: None,
            stdout_tail: None,
            stderr_tail: None,
        }],
    }
}

/// Applies a project's worktree setup to an existing workspace.
///
/// With `copies_only` this runs just the copy actions (explicit `worktree.copy`
/// rules plus `.worktreeinclude` matches), which is what the deferred setup
/// script invokes so the validation in `copy_rule_inner` stays in Rust
/// instead of being rewritten in shell. Unlike the inline path the copies do
/// not stop at the first failure, because the script keeps going too and the
/// user reads the outcome in the terminal.
pub(crate) async fn run_workspace_setup(
    store: &RuntimeStore,
    workspace_id: &str,
    copies_only: bool,
) -> Result<WorktreeSetupReport> {
    if store.workflow_workspace_owned(workspace_id).await? {
        anyhow::bail!("Workflow setup belongs to its attempt and cannot be replayed");
    }
    let workspace = store
        .find_workspace(workspace_id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {workspace_id}"))?;
    validate_setup_owner(&workspace)?;
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", workspace.project_id))?;
    crate::managed_workspace::workflow::ownership::ensure_unowned(store, &workspace, &project)
        .await?;
    let config = match effective_project_config(store, &project).await {
        Ok(config) => config,
        Err(error) => return Ok(config_error_report(&error.to_string())),
    };
    let mut steps = apply_copy_actions(store, &project, &workspace, &config, false, true).await;
    if copies_only {
        return Ok(WorktreeSetupReport { steps });
    }
    let command_environment = if config.worktree.setup.is_empty() {
        Vec::new()
    } else {
        crate::login_shell_environment::setup_command_environment().await
    };
    for command in &config.worktree.setup {
        steps.push(run_setup_command(&workspace.path, command, &command_environment, None).await);
    }
    Ok(WorktreeSetupReport { steps })
}

pub(crate) async fn run_worktree_setup(
    store: &RuntimeStore,
    project: &Project,
    workspace: &Workspace,
) -> WorktreeSetupReport {
    if let Err(error) = validate_setup_owner(workspace) {
        return config_error_report(&error.to_string());
    }
    match effective_project_config(store, project).await {
        Ok(config) if !setup_has_copy_or_command_actions(project, &config) => {
            WorktreeSetupReport::empty()
        }
        Ok(config) => run_setup_config(store, project, workspace, &config, true, None).await,
        Err(error) => config_error_report(&error.to_string()),
    }
}

fn has_copy_actions(project: &Project, config: &ProjectConfig) -> bool {
    !config.worktree.copy.is_empty() || has_worktree_include(Path::new(&project.repo_path))
}

fn validate_setup_owner(workspace: &Workspace) -> Result<()> {
    if workspace.kind != alera_core::runtime::WorkspaceKind::Linked {
        anyhow::bail!(
            "Worktree setup only applies to linked worktrees, not shared project folders"
        );
    }
    if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
        anyhow::bail!(
            "Worktree setup must execute on the owning SSH runtime; no local setup was started"
        );
    }
    Ok(())
}

fn setup_has_copy_or_command_actions(project: &Project, config: &ProjectConfig) -> bool {
    has_copy_actions(project, config) || !config.worktree.setup.is_empty()
}

async fn apply_copy_actions(
    store: &RuntimeStore,
    project: &Project,
    workspace: &Workspace,
    config: &ProjectConfig,
    stop_on_failure: bool,
    resolve_includes: bool,
) -> Vec<WorktreeSetupStepReport> {
    let protect_local_data = match store.workspace_location_was_relocated(workspace).await {
        Ok(value) => value,
        Err(error) => return config_error_report(&error.to_string()).steps,
    };
    let project = project.clone();
    let workspace = workspace.clone();
    let config = config.clone();
    match tokio::task::spawn_blocking(move || {
        apply_copy_actions_inner(
            &project,
            &workspace,
            &config,
            stop_on_failure,
            protect_local_data,
            resolve_includes,
        )
    })
    .await
    {
        Ok(steps) => steps,
        Err(error) => config_error_report(&error.to_string()).steps,
    }
}

fn apply_copy_actions_inner(
    project: &Project,
    workspace: &Workspace,
    config: &ProjectConfig,
    stop_on_failure: bool,
    protect_local_data: bool,
    resolve_includes: bool,
) -> Vec<WorktreeSetupStepReport> {
    let mut steps = Vec::new();
    let include_rules = match if resolve_includes {
        expand_worktree_include(Path::new(&project.repo_path))
    } else {
        Ok(Vec::new())
    } {
        Ok(rules) => rules,
        Err(error) => {
            steps.push(WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Config,
                label: WORKTREE_INCLUDE_FILE.to_string(),
                succeeded: false,
                message: Some(error.to_string()),
                exit_code: None,
                stdout_tail: None,
                stderr_tail: None,
            });
            if stop_on_failure {
                return steps;
            }
            Vec::new()
        }
    };
    let explicit_from: HashSet<&str> = config
        .worktree
        .copy
        .iter()
        .map(|rule| rule.from.as_str())
        .collect();
    if append_copy_rules(
        project,
        workspace,
        &config.worktree.copy,
        stop_on_failure,
        protect_local_data,
        &mut steps,
    ) {
        return steps;
    }
    let extra: Vec<WorktreeCopyRule> = include_rules
        .into_iter()
        .filter(|rule| !explicit_from.contains(rule.from.as_str()))
        .collect();
    append_copy_rules(
        project,
        workspace,
        &extra,
        stop_on_failure,
        protect_local_data,
        &mut steps,
    );
    steps
}

fn append_copy_rules(
    project: &Project,
    workspace: &Workspace,
    rules: &[WorktreeCopyRule],
    stop_on_failure: bool,
    protect_local_data: bool,
    steps: &mut Vec<WorktreeSetupStepReport>,
) -> bool {
    for rule in rules {
        let report = copy_rule(project, workspace, rule, protect_local_data);
        let succeeded = report.succeeded;
        steps.push(report);
        if stop_on_failure && !succeeded {
            return true;
        }
    }
    false
}

pub(crate) fn preferred_source_branch_candidates(preferred: &str) -> Vec<String> {
    let trimmed = preferred.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    if let Some(local) = trimmed.strip_prefix("origin/") {
        if local.is_empty() {
            return vec![trimmed.to_string()];
        }
        return vec![trimmed.to_string(), local.to_string()];
    }
    vec![trimmed.to_string(), format!("origin/{trimmed}")]
}

pub(crate) fn resolve_configured_source_branch(
    branches: &[String],
    preferred: &str,
) -> Option<String> {
    preferred_source_branch_candidates(preferred)
        .into_iter()
        .find(|candidate| branches.iter().any(|branch| branch == candidate))
}

pub(crate) async fn preferred_source_branch(
    store: &RuntimeStore,
    project: &Project,
) -> Option<String> {
    let config = effective_project_config(store, project).await.ok()?;
    let preferred = config.new_workspace.source_branch.trim();
    if preferred.is_empty() {
        return None;
    }
    match core_git::list_branches(&project.repo_path) {
        Ok(branches) => Some(
            resolve_configured_source_branch(&branches, preferred)
                .unwrap_or_else(|| preferred.to_string()),
        ),
        Err(_) => Some(preferred.to_string()),
    }
}

pub(crate) async fn effective_project_config(
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

pub(crate) async fn run_setup_config(
    store: &RuntimeStore,
    project: &Project,
    workspace: &Workspace,
    config: &ProjectConfig,
    resolve_includes: bool,
    receipt: Option<&alera_core::runtime::RelocationSetupReceipt>,
) -> WorktreeSetupReport {
    if let Err(error) = validate_setup_owner(workspace) {
        return config_error_report(&error.to_string());
    }
    if let Some(report) = cancellation_report(store, receipt).await {
        return WorktreeSetupReport {
            steps: vec![report],
        };
    }
    let mut steps =
        apply_copy_actions(store, project, workspace, config, true, resolve_includes).await;
    if steps.iter().any(|step| !step.succeeded) {
        return WorktreeSetupReport { steps };
    }
    if let Some(report) = cancellation_report(store, receipt).await {
        steps.push(report);
        return WorktreeSetupReport { steps };
    }
    let command_environment = if config.worktree.setup.is_empty() {
        Vec::new()
    } else {
        crate::login_shell_environment::setup_command_environment().await
    };
    for (index, command) in config.worktree.setup.iter().enumerate() {
        if let Some(report) = cancellation_report(store, receipt).await {
            steps.push(report);
            return WorktreeSetupReport { steps };
        }
        let journal = receipt.map(
            |receipt| crate::relocation_setup_process::SetupProcessJournal {
                store,
                receipt,
                command_index: index as u32,
            },
        );
        let report =
            run_setup_command(&workspace.path, command, &command_environment, journal).await;
        let succeeded = report.succeeded;
        steps.push(report);
        if let Some(report) = cancellation_report(store, receipt).await {
            steps.push(report);
            return WorktreeSetupReport { steps };
        }
        if !succeeded {
            return WorktreeSetupReport { steps };
        }
    }
    WorktreeSetupReport { steps }
}

async fn cancellation_report(
    store: &RuntimeStore,
    receipt: Option<&alera_core::runtime::RelocationSetupReceipt>,
) -> Option<WorktreeSetupStepReport> {
    let receipt = receipt?;
    let message = match store.setup_cancellation_requested(receipt).await {
        Ok(false) => return None,
        Ok(true) => {
            "Cancellation was requested; no further setup commands will be started".to_owned()
        }
        Err(error) => format!("Could not verify setup cancellation: {error}"),
    };
    Some(WorktreeSetupStepReport {
        kind: WorktreeSetupStepKind::Config,
        label: "Setup Cancellation".into(),
        succeeded: false,
        message: Some(message),
        exit_code: None,
        stdout_tail: None,
        stderr_tail: None,
    })
}
