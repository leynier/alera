//! Grok deletes with `grok sessions delete <id>`. Sessions live under
//! `sessions/<percent-encoded cwd>/<id>/`; the path scope decodes each
//! directory name and compares it exactly instead of re-encoding the path.

use std::path::Path;

use super::cleanup_context::CleanupContext;
use super::session_id_rules::command_session_id;
use super::storage_removal::StorageRoot;
use super::{blocking, AgentCleanupRequest, AgentOutcome, CleanupFailure};

const HOME_VARIABLE: &str = "GROK_HOME";

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let mut found = Vec::new();
    let mut path_outcome = None;
    if let Some(paths) = &request.discovery_paths {
        let sessions = context
            .directory_or_home(HOME_VARIABLE, &[".grok"])
            .join("sessions");
        let paths = paths.clone();
        let discovered = blocking(move || discover_session_ids(&sessions, &paths)).await;
        path_outcome = match discovered {
            Ok(None) => None,
            Ok(Some(ids)) => {
                found = ids;
                Some(AgentOutcome::path(Ok(())))
            }
            Err(failure) => Some(AgentOutcome::path(Err(failure))),
        };
    }
    let ids = request.ids_with(found);
    let env = context.storage_env(&[HOME_VARIABLE]);
    let mut outcomes = Vec::new();
    for id in ids {
        let result = match command_session_id(&id) {
            Ok(id) => {
                context
                    .run_command("grok", &["sessions", "delete", id], &env)
                    .await
            }
            Err(failure) => Err(failure),
        };
        outcomes.push(AgentOutcome::new(id, result));
    }
    outcomes.extend(path_outcome);
    outcomes
}

/// `None` when Grok has no session store on this machine.
fn discover_session_ids(
    sessions: &Path,
    paths: &[String],
) -> Result<Option<Vec<String>>, CleanupFailure> {
    let Some(root) = StorageRoot::open(sessions)? else {
        return Ok(None);
    };
    let mut ids = Vec::new();
    for workspace in root.child_directories()? {
        let decoded = workspace
            .file_name()
            .and_then(|name| name.to_str())
            .and_then(percent_decode);
        if !decoded.is_some_and(|decoded| paths.contains(&decoded)) {
            continue;
        }
        ids.extend(root.entry_names(&workspace, |_, path| path.is_dir())?);
    }
    Ok(Some(ids))
}

fn percent_decode(encoded: &str) -> Option<String> {
    let bytes = encoded.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            let hex = std::str::from_utf8(bytes.get(index + 1..index + 3)?).ok()?;
            decoded.push(u8::from_str_radix(hex, 16).ok()?);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8(decoded).ok()
}

#[cfg(test)]
#[path = "grok_tests.rs"]
mod tests;
