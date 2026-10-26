//! Antigravity has no delete command. A conversation is `conversations/<id>.db`
//! (with its WAL files), `brain/<id>/` and `annotations/<id>.pbtxt`; its
//! workspace and busy flag are in the `conversation_summaries.db` index, read
//! here without writing, so a removed conversation's index row stays behind.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use super::cleanup_context::CleanupContext;
use super::readonly_sqlite::ReadOnlyDatabase;
use super::session_id_rules::is_storage_entry_name;
use super::storage_removal::StorageRoot;
use super::{
    blocking, first_failure, normalize_workspace_path, AgentCleanupRequest, AgentOutcome,
    CleanupFailure,
};

struct ConversationSummary {
    workspace_paths: Vec<String>,
    busy: bool,
}

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let storage = context.home.join(".gemini").join("antigravity-cli");
    if !storage.is_dir() {
        return request
            .registered_ids()
            .map(|id| AgentOutcome::new(id, Ok(())))
            .collect();
    }
    let summaries = read_summaries(&storage.join("conversation_summaries.db")).await;
    let mut discovered = Vec::new();
    let mut path_outcome = None;
    if let Some(paths) = &request.discovery_paths {
        path_outcome = Some(AgentOutcome::path(match &summaries {
            Ok(summaries) => {
                for (id, summary) in summaries {
                    let matches = !summary.workspace_paths.is_empty()
                        && summary
                            .workspace_paths
                            .iter()
                            .all(|path| paths.contains(path));
                    if matches && is_storage_entry_name(id) {
                        discovered.push(id.clone());
                    }
                }
                Ok(())
            }
            Err(failure) => Err(failure.clone()),
        }));
    }
    let ids = request.ids_with(discovered);
    let busy = summaries
        .map(|summaries| {
            summaries
                .into_iter()
                .filter(|(_, summary)| summary.busy)
                .map(|(id, _)| id)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let mut outcomes = Vec::new();
    for id in ids {
        let result = if busy.contains(&id) {
            Err(CleanupFailure::in_use())
        } else {
            let (storage, owned_id) = (storage.clone(), id.clone());
            blocking(move || remove_conversation(&storage, &owned_id)).await
        };
        outcomes.push(AgentOutcome::new(id, result));
    }
    outcomes.extend(path_outcome);
    outcomes
}

fn remove_conversation(storage: &Path, id: &str) -> Result<(), CleanupFailure> {
    let mut results = Vec::new();
    if let Some(conversations) = StorageRoot::open(&storage.join("conversations"))? {
        for suffix in [".db", ".db-wal", ".db-shm"] {
            let file = conversations.entry(&format!("{id}{suffix}"));
            results.push(conversations.remove(&file).map(drop));
        }
    }
    if let Some(brain) = StorageRoot::open(&storage.join("brain"))? {
        results.push(brain.remove(&brain.entry(id)).map(drop));
    }
    if let Some(annotations) = StorageRoot::open(&storage.join("annotations"))? {
        let file = annotations.entry(&format!("{id}.pbtxt"));
        results.push(annotations.remove(&file).map(drop));
    }
    first_failure(results)
}

/// Every summary row; a missing index means there is nothing to discover.
async fn read_summaries(
    database: &Path,
) -> Result<BTreeMap<String, ConversationSummary>, CleanupFailure> {
    if !database.is_file() {
        return Ok(BTreeMap::new());
    }
    let mut database = ReadOnlyDatabase::open(database).await?;
    let rows = database
        .text_rows(
            "SELECT conversation_id, workspace_uris, \
             CASE WHEN not_fully_idle IN (0, '0', 'false', 'FALSE') THEN '0' ELSE '1' END \
             FROM conversation_summaries"
                .to_string(),
            &[],
            3,
        )
        .await;
    database.close().await;
    let mut summaries = BTreeMap::new();
    for row in rows? {
        let [Some(id), uris, busy] = <[Option<String>; 3]>::try_from(row).unwrap_or_default()
        else {
            continue;
        };
        summaries.insert(
            id,
            ConversationSummary {
                workspace_paths: workspace_paths(uris.as_deref().unwrap_or_default()),
                busy: busy.as_deref() == Some("1"),
            },
        );
    }
    Ok(summaries)
}

/// `workspace_uris` is a JSON array of `file://` URIs; anything else yields
/// no paths, which never matches.
fn workspace_paths(uris: &str) -> Vec<String> {
    let Ok(uris) = serde_json::from_str::<Vec<String>>(uris) else {
        return Vec::new();
    };
    let paths = uris
        .iter()
        .map(|uri| file_uri_path(uri))
        .collect::<Option<Vec<_>>>();
    paths.unwrap_or_default()
}

fn file_uri_path(uri: &str) -> Option<String> {
    let path: PathBuf = url::Url::parse(uri).ok()?.to_file_path().ok()?;
    Some(normalize_workspace_path(&path.to_string_lossy()))
}

#[cfg(test)]
#[path = "agy_tests.rs"]
mod tests;
