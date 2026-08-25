//! Applies copy actions into a new linked workspace: explicit `worktree.copy`
//! rules and gitignored matches from `.worktreeinclude`.
//!
//! Every path is validated rather than trusted: symlinks are refused, and both
//! the source and the destination must stay inside their own root. Split out of
//! `worktree_setup.rs` so this validation stays in one place - the deferred
//! setup script calls back into it through `alera workspace setup
//! --copies-only` instead of rewriting it in shell.

use std::path::{Path, PathBuf};

use alera_core::runtime::{
    Project, Workspace, WorktreeCopyRule, WorktreeSetupStepKind, WorktreeSetupStepReport,
};
use anyhow::{anyhow, bail, Context, Result};

pub(crate) fn copy_rule(
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

#[cfg(all(test, unix))]
mod tests {
    use super::prepare_target;

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
}
