//! Cursor keeps each chat at `chats/<md5(cwd)>/<id>/`, so a workspace's
//! whole history is the one directory named after its path's MD5.

use std::path::{Path, PathBuf};

use md5::{Digest, Md5};

use super::cleanup_context::CleanupContext;
use super::storage_removal::StorageRoot;
use super::{blocking, first_failure, AgentCleanupRequest, AgentOutcome, CleanupFailure};

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let chats = context
        .directory_or_home("CURSOR_DATA_DIR", &[".cursor"])
        .join("chats");
    let mut outcomes = Vec::new();
    for id in request.registered_ids() {
        let (chats, owned_id) = (chats.clone(), id.to_string());
        let result = blocking(move || remove_chat(&chats, &owned_id)).await;
        outcomes.push(AgentOutcome::new(id, result));
    }
    if let Some(paths) = request.discovery_paths.clone() {
        let preserved = request.preserved.clone();
        let result = blocking(move || remove_workspace_chats(&chats, &paths, &preserved)).await;
        if let Some(result) = result.transpose() {
            outcomes.push(AgentOutcome::path(result));
        }
    }
    outcomes
}

fn remove_chat(chats: &Path, id: &str) -> Result<(), CleanupFailure> {
    let Some(root) = StorageRoot::open(chats)? else {
        return Ok(());
    };
    let results = root
        .child_directories()?
        .into_iter()
        .map(|workspace| root.remove(&workspace.join(id)).map(drop))
        .collect::<Vec<_>>();
    first_failure(results)
}

/// `None` when Cursor has no chat store on this machine. A workspace
/// directory holding a preserved chat loses only its other chats.
fn remove_workspace_chats(
    chats: &Path,
    paths: &[String],
    preserved: &[String],
) -> Result<Option<()>, CleanupFailure> {
    let Some(root) = StorageRoot::open(chats)? else {
        return Ok(None);
    };
    let mut results = Vec::new();
    for path in paths {
        let directory = workspace_chats_dir(&root, path);
        if !preserved.iter().any(|id| directory.join(id).exists()) {
            results.push(root.remove(&directory).map(drop));
            continue;
        }
        let chats =
            root.entry_names(&directory, |name, _| !preserved.iter().any(|id| id == name))?;
        for chat in chats {
            results.push(root.remove(&directory.join(chat)).map(drop));
        }
    }
    first_failure(results).map(Some)
}

fn workspace_chats_dir(root: &StorageRoot, workspace_path: &str) -> PathBuf {
    root.entry(&hex::encode(Md5::digest(workspace_path.as_bytes())))
}

#[cfg(test)]
#[path = "cursor_tests.rs"]
mod tests;
