//! Runs a project's worktree setup: the `worktree.copy` rules, gitignored
//! matches from `.worktreeinclude`, and the `worktree.setup` commands from
//! `alera.toml` or the per-project UI override.
//!
//! Split out of `managed_workspace.rs`, which keeps the lifecycle of the
//! workspace itself: validating the request, creating and removing the Git
//! worktree, and resolving where it lives on disk.

use std::collections::HashSet;
use std::path::Path;
use std::process::Stdio;

use alera_core::child_process::windowless_async_command;
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
use tokio::io::AsyncReadExt;

const SETUP_OUTPUT_TAIL_BYTES: usize = 16 * 1024;

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
        return (run_setup_config(project, workspace, &config).await, None);
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
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", workspace.project_id))?;
    let config = match effective_project_config(store, &project).await {
        Ok(config) => config,
        Err(error) => return Ok(config_error_report(&error.to_string())),
    };
    let mut steps = apply_copy_actions(&project, &workspace, &config, false);
    if copies_only {
        return Ok(WorktreeSetupReport { steps });
    }
    let command_environment = if config.worktree.setup.is_empty() {
        Vec::new()
    } else {
        crate::login_shell_environment::setup_command_environment().await
    };
    for command in &config.worktree.setup {
        steps.push(run_setup_command(&workspace.path, command, &command_environment).await);
    }
    Ok(WorktreeSetupReport { steps })
}

pub(crate) async fn run_worktree_setup(
    store: &RuntimeStore,
    project: &Project,
    workspace: &Workspace,
) -> WorktreeSetupReport {
    match effective_project_config(store, project).await {
        Ok(config) if !setup_has_copy_or_command_actions(project, &config) => {
            WorktreeSetupReport::empty()
        }
        Ok(config) => run_setup_config(project, workspace, &config).await,
        Err(error) => config_error_report(&error.to_string()),
    }
}

fn has_copy_actions(project: &Project, config: &ProjectConfig) -> bool {
    !config.worktree.copy.is_empty() || has_worktree_include(Path::new(&project.repo_path))
}

fn setup_has_copy_or_command_actions(project: &Project, config: &ProjectConfig) -> bool {
    has_copy_actions(project, config) || !config.worktree.setup.is_empty()
}

fn apply_copy_actions(
    project: &Project,
    workspace: &Workspace,
    config: &ProjectConfig,
    stop_on_failure: bool,
) -> Vec<WorktreeSetupStepReport> {
    let mut steps = Vec::new();
    let include_rules = match expand_worktree_include(Path::new(&project.repo_path)) {
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
        &mut steps,
    ) {
        return steps;
    }
    let extra: Vec<WorktreeCopyRule> = include_rules
        .into_iter()
        .filter(|rule| !explicit_from.contains(rule.from.as_str()))
        .collect();
    append_copy_rules(project, workspace, &extra, stop_on_failure, &mut steps);
    steps
}

fn append_copy_rules(
    project: &Project,
    workspace: &Workspace,
    rules: &[WorktreeCopyRule],
    stop_on_failure: bool,
    steps: &mut Vec<WorktreeSetupStepReport>,
) -> bool {
    for rule in rules {
        let report = copy_rule(project, workspace, rule);
        let succeeded = report.succeeded;
        steps.push(report);
        if stop_on_failure && !succeeded {
            return true;
        }
    }
    false
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

async fn run_setup_config(
    project: &Project,
    workspace: &Workspace,
    config: &ProjectConfig,
) -> WorktreeSetupReport {
    let mut steps = apply_copy_actions(project, workspace, config, true);
    if steps.iter().any(|step| !step.succeeded) {
        return WorktreeSetupReport { steps };
    }
    let command_environment = if config.worktree.setup.is_empty() {
        Vec::new()
    } else {
        crate::login_shell_environment::setup_command_environment().await
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

async fn run_setup_command(
    workspace_path: &str,
    command: &str,
    environment: &[(String, String)],
) -> WorktreeSetupStepReport {
    let (executable, args) = shell_invocation(command);
    let mut child = match windowless_async_command(executable)
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
    use super::text_tail;

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
}
