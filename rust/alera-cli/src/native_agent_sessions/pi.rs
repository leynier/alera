//! Pi writes `<timestamp>_<id>.jsonl` files, by default into
//! `sessions/--<cwd with separators as dashes>--/`, or flat into
//! `PI_CODING_AGENT_SESSION_DIR` when that is set.
//!
//! That directory encoding is lossy (`/a-b` and `/a/b` share one), so the path
//! scope only removes files whose header line names the exact workspace path.

use std::path::{Path, PathBuf};

use super::cleanup_context::CleanupContext;
use super::storage_removal::{read_head, StorageRoot};
use super::{
    blocking, first_failure, normalize_workspace_path, AgentCleanupRequest, AgentOutcome,
    CleanupFailure,
};

const HEADER_LIMIT_BYTES: u64 = 64 * 1024;

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let sessions = sessions_dir(context);
    let mut outcomes = Vec::new();
    for id in request.registered_ids() {
        let (sessions, owned_id) = (sessions.clone(), id.to_string());
        let result = blocking(move || remove_session(&sessions, &owned_id)).await;
        outcomes.push(AgentOutcome::new(id, result));
    }
    if let Some(paths) = request.discovery_paths.clone() {
        let preserved = request.preserved.clone();
        let result =
            blocking(move || remove_workspace_sessions(&sessions, &paths, &preserved)).await;
        if let Some(result) = result.transpose() {
            outcomes.push(AgentOutcome::path(result));
        }
    }
    outcomes
}

fn sessions_dir(context: &CleanupContext) -> PathBuf {
    context
        .directory_variable("PI_CODING_AGENT_SESSION_DIR")
        .unwrap_or_else(|| {
            context
                .directory_or_home("PI_CODING_AGENT_DIR", &[".pi", "agent"])
                .join("sessions")
        })
}

/// Pi's `getDefaultSessionDirPath`: strip one leading separator, turn every
/// `/`, `\` and `:` into `-`, and wrap the result in `--`.
fn encoded_workspace_dir(workspace_path: &str) -> String {
    let trimmed = workspace_path
        .strip_prefix(['/', '\\'])
        .unwrap_or(workspace_path);
    format!("--{}--", trimmed.replace(['/', '\\', ':'], "-"))
}

fn session_files(
    root: &StorageRoot,
    directory: &Path,
    keep: impl Fn(&str) -> bool,
) -> Result<Vec<PathBuf>, CleanupFailure> {
    Ok(root
        .entry_names(directory, |name, path| {
            name.ends_with(".jsonl") && path.is_file() && keep(name)
        })?
        .into_iter()
        .map(|name| directory.join(name))
        .collect())
}

fn remove_session(sessions: &Path, id: &str) -> Result<(), CleanupFailure> {
    let Some(root) = StorageRoot::open(sessions)? else {
        return Ok(());
    };
    let suffix = format!("_{id}.jsonl");
    let mut files = session_files(&root, root.path(), |name| name.ends_with(&suffix))?;
    for workspace in root.child_directories()? {
        files.extend(session_files(&root, &workspace, |name| {
            name.ends_with(&suffix)
        })?);
    }
    first_failure(files.iter().map(|file| root.remove(file).map(drop)))
}

/// `None` when Pi has no session store on this machine.
fn remove_workspace_sessions(
    sessions: &Path,
    paths: &[String],
    preserved: &[String],
) -> Result<Option<()>, CleanupFailure> {
    let Some(root) = StorageRoot::open(sessions)? else {
        return Ok(None);
    };
    let mut results = Vec::new();
    let mut candidates = session_files(&root, root.path(), |_| true)?;
    let mut workspace_dirs = Vec::new();
    for path in paths {
        let directory = root.entry(&encoded_workspace_dir(path));
        if directory.is_dir() {
            candidates.extend(session_files(&root, &directory, |_| true)?);
            workspace_dirs.push(directory);
        }
    }
    for file in candidates {
        let Some(header) = session_header(&file) else {
            continue;
        };
        let keep = preserved.iter().any(|id| {
            header.id.as_deref() == Some(id.as_str()) || file_session_id(&file) == Some(id.as_str())
        });
        if paths.contains(&header.cwd) && !keep {
            results.push(root.remove(&file).map(drop));
        }
    }
    for directory in workspace_dirs {
        root.remove_if_empty(&directory);
    }
    first_failure(results).map(Some)
}

struct SessionHeader {
    cwd: String,
    id: Option<String>,
}

/// A session file's first line, `{"type":"session","id":...,"cwd":...}`.
fn session_header(file: &Path) -> Option<SessionHeader> {
    let head = read_head(file, HEADER_LIMIT_BYTES)?;
    let header: serde_json::Value = serde_json::from_str(head.lines().next()?).ok()?;
    if header.get("type")?.as_str()? != "session" {
        return None;
    }
    Some(SessionHeader {
        cwd: normalize_workspace_path(header.get("cwd")?.as_str()?),
        id: header
            .get("id")
            .and_then(|id| id.as_str())
            .map(str::to_string),
    })
}

/// The id in a `<timestamp>_<id>.jsonl` file name.
fn file_session_id(file: &Path) -> Option<&str> {
    file.file_name()?
        .to_str()?
        .strip_suffix(".jsonl")?
        .split_once('_')
        .map(|(_, id)| id)
}

#[cfg(test)]
#[path = "pi_tests.rs"]
mod tests;
