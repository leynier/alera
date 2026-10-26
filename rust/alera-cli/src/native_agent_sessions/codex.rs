//! Codex deletes a thread with `codex delete --force <uuid>`; the path scope
//! finds thread ids by exact `cwd` in Codex's newest `state_<n>.sqlite`.

use std::path::{Path, PathBuf};

use super::cleanup_context::CleanupContext;
use super::readonly_sqlite::{placeholders, ReadOnlyDatabase};
use super::session_id_rules::command_session_id;
use super::{AgentCleanupRequest, AgentOutcome, CleanupFailure};

const HOME_VARIABLE: &str = "CODEX_HOME";

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let mut discovered = Vec::new();
    let mut outcomes = Vec::new();
    if let Some(paths) = &request.discovery_paths {
        let codex_home = context.directory_or_home(HOME_VARIABLE, &[".codex"]);
        if codex_home.is_dir() {
            let result = match discover_thread_ids(&codex_home, paths).await {
                Ok(found) => {
                    discovered = found;
                    Ok(())
                }
                Err(failure) => Err(failure),
            };
            outcomes.push(AgentOutcome::path(result));
        }
    }
    let ids = request.ids_with(discovered);
    let env = context.storage_env(&[HOME_VARIABLE]);
    let mut deletions = Vec::new();
    for id in ids {
        let result = match uuid_session_id(&id) {
            Ok(id) => {
                context
                    .run_command("codex", &["delete", "--force", id], &env)
                    .await
            }
            Err(failure) => Err(failure),
        };
        deletions.push(AgentOutcome::new(id, result));
    }
    deletions.extend(outcomes);
    deletions
}

/// `--force` refuses anything but a UUID, and a session name could match a
/// different thread than the one Alera recorded.
fn uuid_session_id(id: &str) -> Result<&str, CleanupFailure> {
    let id = command_session_id(id)?;
    let is_hyphenated_uuid = id.len() == 36 && uuid::Uuid::try_parse(id).is_ok();
    if is_hyphenated_uuid {
        Ok(id)
    } else {
        Err(CleanupFailure::new(
            "not_uuid",
            "codex deletes without a prompt only by UUID",
        ))
    }
}

/// The highest-numbered `state_<n>.sqlite`, which is the one Codex writes.
fn newest_state_database(codex_home: &Path) -> Option<PathBuf> {
    std::fs::read_dir(codex_home)
        .ok()?
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            let version = name
                .strip_prefix("state_")?
                .strip_suffix(".sqlite")?
                .parse::<u64>()
                .ok()?;
            Some((version, entry.path()))
        })
        .max_by_key(|(version, _)| *version)
        .map(|(_, path)| path)
}

async fn discover_thread_ids(
    codex_home: &Path,
    paths: &[String],
) -> Result<Vec<String>, CleanupFailure> {
    let Some(database) = newest_state_database(codex_home) else {
        return Ok(Vec::new());
    };
    let mut database = ReadOnlyDatabase::open(&database).await?;
    let sql = format!(
        "SELECT id FROM threads WHERE cwd IN ({}) ORDER BY id",
        placeholders(paths.len())
    );
    let rows = database.text_rows(sql, paths, 1).await;
    database.close().await;
    Ok(rows?
        .into_iter()
        .filter_map(|row| row.into_iter().next().flatten())
        .collect())
}

#[cfg(test)]
#[path = "codex_tests.rs"]
mod tests;
