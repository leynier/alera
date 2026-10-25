//! fx keeps each session in `~/.fx/sessions/<id>/`, holding an OS file lock
//! on its empty `session.lock` while a process runs it, and remembers the
//! last session per workspace in `~/.fx/continue/<sha256(workspace path)>`.

use std::fs::{File, TryLockError};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use super::cleanup_context::CleanupContext;
use super::storage_removal::{read_head, StorageRoot};
use super::{
    blocking, first_failure, normalize_workspace_path, AgentCleanupRequest, AgentOutcome,
    CleanupFailure,
};

const SESSION_FILE_LIMIT_BYTES: u64 = 256 * 1024;

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let fx_home = context.home.join(".fx");
    let ids = request
        .registered_ids()
        .map(str::to_string)
        .collect::<Vec<_>>();
    let workspace_path = request.workspace_path.clone();
    let paths = request.discovery_paths.clone();
    let preserved = request.preserved.clone();
    blocking(move || {
        Ok(clean_sessions(
            &fx_home,
            &ids,
            &workspace_path,
            paths.as_deref(),
            &preserved,
        ))
    })
    .await
    .unwrap_or_else(|failure| vec![AgentOutcome::path(Err(failure))])
}

fn clean_sessions(
    fx_home: &Path,
    ids: &[String],
    workspace_path: &str,
    paths: Option<&[String]>,
    preserved: &[String],
) -> Vec<AgentOutcome> {
    let root = match StorageRoot::open(&fx_home.join("sessions")) {
        Ok(Some(root)) => root,
        Ok(None) => return ids.iter().map(|id| AgentOutcome::new(id, Ok(()))).collect(),
        Err(failure) => return vec![AgentOutcome::path(Err(failure))],
    };
    let mut targets = ids.to_vec();
    let mut path_results = Vec::new();
    if let Some(paths) = paths {
        match root.child_directories() {
            Ok(directories) => {
                for directory in directories {
                    let id = directory
                        .file_name()
                        .map(|name| name.to_string_lossy().into_owned())
                        .unwrap_or_default();
                    let matches =
                        session_workspace(&directory).is_some_and(|root| paths.contains(&root));
                    if matches && !preserved.contains(&id) && !targets.contains(&id) {
                        targets.push(id);
                    }
                }
            }
            Err(failure) => path_results.push(Err(failure)),
        }
    }
    let mut outcomes = Vec::new();
    let mut removed = Vec::new();
    for id in targets {
        let result = remove_session(&root, &id);
        if result.is_ok() {
            removed.push(id.clone());
        }
        outcomes.push(AgentOutcome::new(id, result));
    }
    let pointer_paths = paths.map_or_else(|| vec![workspace_path.to_string()], <[String]>::to_vec);
    path_results.push(remove_continue_pointers(fx_home, &pointer_paths, &removed));
    let path_result = first_failure(path_results);
    if paths.is_some() || path_result.is_err() {
        outcomes.push(AgentOutcome::path(path_result));
    }
    outcomes
}

fn remove_session(root: &StorageRoot, id: &str) -> Result<(), CleanupFailure> {
    let directory = root.entry(id);
    if session_is_locked(&directory.join("session.lock"))? {
        return Err(CleanupFailure::in_use());
    }
    root.remove(&directory).map(drop)
}

/// fx takes an exclusive `flock`/`LockFileEx` lock, which is what
/// [`File::try_lock`] probes; the lock is released again when `file` drops.
fn session_is_locked(lock: &Path) -> Result<bool, CleanupFailure> {
    let file = match File::open(lock) {
        Ok(file) => file,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(CleanupFailure::filesystem(error, lock)),
    };
    match file.try_lock() {
        Ok(()) => Ok(false),
        Err(TryLockError::WouldBlock) => Ok(true),
        Err(TryLockError::Error(error)) => Err(CleanupFailure::filesystem(error, lock)),
    }
}

fn session_workspace(directory: &Path) -> Option<String> {
    let text = read_head(&directory.join("session.json"), SESSION_FILE_LIMIT_BYTES)?;
    let session: serde_json::Value = serde_json::from_str(&text).ok()?;
    Some(normalize_workspace_path(
        session.get("workspace_root")?.as_str()?,
    ))
}

/// A pointer is removed only while it still names a session removed here.
fn remove_continue_pointers(
    fx_home: &Path,
    paths: &[String],
    removed: &[String],
) -> Result<(), CleanupFailure> {
    let Some(root) = StorageRoot::open(&fx_home.join("continue"))? else {
        return Ok(());
    };
    let mut results = Vec::new();
    for path in paths {
        let pointer: PathBuf = root.entry(&hex::encode(Sha256::digest(path.as_bytes())));
        let points_at_removed = read_head(&pointer, 1024)
            .is_some_and(|target| removed.iter().any(|id| id == target.trim()));
        if points_at_removed {
            results.push(root.remove(&pointer).map(drop));
        }
    }
    first_failure(results)
}

#[cfg(test)]
#[path = "fx_tests.rs"]
mod tests;
