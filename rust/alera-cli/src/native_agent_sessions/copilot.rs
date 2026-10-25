//! Copilot keeps each session in `session-state/<id>/`, with the cwd in its
//! `workspace.yaml` and an `inuse.<pid>.lock` while a CLI has it open.
//! `session-store.db` is a derived index Copilot rebuilds, so it is left alone.

use std::path::Path;

use super::cleanup_context::CleanupContext;
use super::storage_removal::{read_head, StorageRoot};
use super::{
    blocking, normalize_workspace_path, AgentCleanupRequest, AgentOutcome, CleanupFailure,
};

const WORKSPACE_FILE_LIMIT_BYTES: u64 = 64 * 1024;

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let state = context
        .directory_or_home("COPILOT_HOME", &[".copilot"])
        .join("session-state");
    let process_alive = context.process_alive;
    let ids = request
        .registered_ids()
        .map(str::to_string)
        .collect::<Vec<_>>();
    let paths = request.discovery_paths.clone();
    let preserved = request.preserved.clone();
    blocking(move || {
        Ok(clean_sessions(
            &state,
            &ids,
            paths.as_deref(),
            &preserved,
            process_alive,
        ))
    })
    .await
    .unwrap_or_else(|failure| vec![AgentOutcome::path(Err(failure))])
}

fn clean_sessions(
    state: &Path,
    ids: &[String],
    paths: Option<&[String]>,
    preserved: &[String],
    process_alive: fn(u32) -> bool,
) -> Vec<AgentOutcome> {
    let root = match StorageRoot::open(state) {
        Ok(Some(root)) => root,
        Ok(None) => return ids.iter().map(|id| AgentOutcome::new(id, Ok(()))).collect(),
        Err(failure) => return vec![AgentOutcome::path(Err(failure))],
    };
    let mut targets = ids.to_vec();
    let mut outcomes = Vec::new();
    if let Some(paths) = paths {
        match root.child_directories() {
            Ok(directories) => {
                for directory in directories {
                    let matches = workspace_cwd(&directory).is_some_and(|cwd| paths.contains(&cwd));
                    let id = directory_name(&directory);
                    if matches && !preserved.contains(&id) && !targets.contains(&id) {
                        targets.push(id);
                    }
                }
                outcomes.push(AgentOutcome::path(Ok(())));
            }
            Err(failure) => outcomes.push(AgentOutcome::path(Err(failure))),
        }
    }
    let mut removals = targets
        .into_iter()
        .map(|id| {
            let result = remove_session(&root, &id, process_alive);
            AgentOutcome::new(id, result)
        })
        .collect::<Vec<_>>();
    removals.extend(outcomes);
    removals
}

fn remove_session(
    root: &StorageRoot,
    id: &str,
    process_alive: fn(u32) -> bool,
) -> Result<(), CleanupFailure> {
    let directory = root.entry(id);
    let held = root.entry_names(&directory, |name, _| {
        lock_pid(name).is_some_and(process_alive)
    })?;
    if !held.is_empty() {
        return Err(CleanupFailure::in_use());
    }
    root.remove(&directory).map(drop)
}

/// The pid in an `inuse.<pid>.lock` file name.
fn lock_pid(name: &str) -> Option<u32> {
    name.strip_prefix("inuse.")?
        .strip_suffix(".lock")?
        .parse()
        .ok()
}

fn directory_name(directory: &Path) -> String {
    directory
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// The top-level `cwd:` of `workspace.yaml`, unquoted.
fn workspace_cwd(directory: &Path) -> Option<String> {
    let text = read_head(
        &directory.join("workspace.yaml"),
        WORKSPACE_FILE_LIMIT_BYTES,
    )?;
    let value = text
        .lines()
        .find_map(|line| line.strip_prefix("cwd:"))?
        .trim();
    Some(normalize_workspace_path(&unquote_yaml_scalar(value)?))
}

fn unquote_yaml_scalar(value: &str) -> Option<String> {
    if let Some(inner) = value
        .strip_prefix('\'')
        .and_then(|rest| rest.strip_suffix('\''))
    {
        return Some(inner.replace("''", "'"));
    }
    if let Some(inner) = value
        .strip_prefix('"')
        .and_then(|rest| rest.strip_suffix('"'))
    {
        let mut unescaped = String::with_capacity(inner.len());
        let mut chars = inner.chars();
        while let Some(ch) = chars.next() {
            if ch == '\\' {
                unescaped.push(chars.next()?);
            } else {
                unescaped.push(ch);
            }
        }
        return Some(unescaped);
    }
    (!value.is_empty()).then(|| value.to_string())
}

#[cfg(test)]
#[path = "copilot_tests.rs"]
mod tests;
