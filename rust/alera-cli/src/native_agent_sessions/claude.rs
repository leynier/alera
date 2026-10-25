//! Claude Code keeps one transcript per session under `projects/<cwd>/`, plus
//! per-session side directories. The path scope is `claude purge`, Claude's
//! own command for "everything about this project" (see `claude_purge`).

use std::path::{Path, PathBuf};

use super::cleanup_context::CleanupContext;
use super::storage_removal::StorageRoot;
use super::{
    blocking, claude_purge, first_failure, AgentCleanupRequest, AgentOutcome, CleanupFailure,
};

pub(super) const CONFIG_DIR_VARIABLE: &str = "CLAUDE_CONFIG_DIR";

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let mut outcomes = Vec::new();
    for session in &request.sessions {
        let result = match config_dir(context, session.ccs_profile.as_deref()) {
            Some(dir) => {
                let id = session.id.clone();
                blocking(move || remove_session_files(&dir, &id)).await
            }
            None => Err(CleanupFailure::new(
                "missing_ccs_profile",
                "CCS profile directory not found",
            )),
        };
        outcomes.push(AgentOutcome::new(session.id.clone(), result));
    }
    if let Some(paths) = &request.discovery_paths {
        outcomes.extend(
            claude_purge::purge_workspace(context, paths, &request.preserved)
                .await
                .map(AgentOutcome::path),
        );
    }
    outcomes
}

pub(super) fn default_config_dir(context: &CleanupContext) -> PathBuf {
    context.directory_or_home(CONFIG_DIR_VARIABLE, &[".claude"])
}

pub(super) fn ccs_instances_dir(context: &CleanupContext) -> PathBuf {
    context
        .directory_or_home("CCS_DIR", &[".ccs"])
        .join("instances")
}

fn config_dir(context: &CleanupContext, ccs_profile: Option<&str>) -> Option<PathBuf> {
    match ccs_profile {
        None => Some(default_config_dir(context)),
        Some(profile) => {
            let dir = ccs_instances_dir(context).join(profile);
            dir.is_dir().then_some(dir)
        }
    }
}

/// A missing directory means nothing was stored there, which is success.
pub(super) fn remove_session_files(config_dir: &Path, id: &str) -> Result<(), CleanupFailure> {
    let mut results = Vec::new();
    if let Some(projects) = StorageRoot::open(&config_dir.join("projects"))? {
        for project in projects.child_directories()? {
            results.push(
                projects
                    .remove(&project.join(format!("{id}.jsonl")))
                    .map(drop),
            );
            results.push(projects.remove(&project.join(id)).map(drop));
        }
    }
    for side_directory in ["file-history", "session-env", "tasks"] {
        if let Some(root) = StorageRoot::open(&config_dir.join(side_directory))? {
            results.push(root.remove(&root.entry(id)).map(drop));
        }
    }
    if let Some(debug) = StorageRoot::open(&config_dir.join("debug"))? {
        results.push(debug.remove(&debug.entry(&format!("{id}.txt"))).map(drop));
    }
    if let Some(todos) = StorageRoot::open(&config_dir.join("todos"))? {
        let prefix = format!("{id}-");
        let names = todos.entry_names(todos.path(), |name, _| {
            name.starts_with(&prefix) && name.ends_with(".json")
        })?;
        for name in names {
            results.push(todos.remove(&todos.entry(&name)).map(drop));
        }
    }
    first_failure(results)
}

#[cfg(test)]
#[path = "claude_tests.rs"]
mod tests;
