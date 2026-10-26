//! OpenCode v1 and v2 both delete with `opencode session delete <id>`, which
//! also removes child sessions. The path scope reads top-level session ids by
//! exact `directory` from `session` (v1) and `session_v2` (v2).

use std::path::Path;

use super::cleanup_context::CleanupContext;
use super::readonly_sqlite::{placeholders, ReadOnlyDatabase};
use super::session_id_rules::command_session_id;
use super::{AgentCleanupRequest, AgentOutcome, CleanupFailure};

const DATA_HOME_VARIABLE: &str = "XDG_DATA_HOME";
const SESSION_TABLES: [&str; 2] = ["session", "session_v2"];

pub(super) async fn clean(
    context: &CleanupContext,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    let mut discovered = Vec::new();
    let mut path_outcome = None;
    if let Some(paths) = &request.discovery_paths {
        let database = context
            .directory_or_home(DATA_HOME_VARIABLE, &[".local", "share"])
            .join("opencode")
            .join("opencode.db");
        if database.is_file() {
            let (found, result) = discover_session_ids(&database, paths).await;
            discovered = found;
            path_outcome = Some(AgentOutcome::path(result));
        }
    }
    let ids = request.ids_with(discovered);
    let env = context.storage_env(&[DATA_HOME_VARIABLE]);
    let mut outcomes = Vec::new();
    for id in ids {
        let result = match command_session_id(&id) {
            Ok(id) => {
                context
                    .run_command("opencode", &["session", "delete", id], &env)
                    .await
            }
            Err(failure) => Err(failure),
        };
        outcomes.push(AgentOutcome::new(id, result));
    }
    outcomes.extend(path_outcome);
    outcomes
}

/// Ids from every table that could be read; a table whose schema changed
/// upstream is reported without discarding what the other one found.
async fn discover_session_ids(
    database: &Path,
    paths: &[String],
) -> (Vec<String>, Result<(), CleanupFailure>) {
    let mut database = match ReadOnlyDatabase::open(database).await {
        Ok(database) => database,
        Err(failure) => return (Vec::new(), Err(failure)),
    };
    let mut ids = Vec::new();
    let mut result = Ok(());
    for table in SESSION_TABLES {
        match read_top_level_sessions(&mut database, table, paths).await {
            Ok(found) => {
                for id in found {
                    if !ids.contains(&id) {
                        ids.push(id);
                    }
                }
            }
            Err(failure) => result = result.and(Err(failure)),
        }
    }
    database.close().await;
    (ids, result)
}

async fn read_top_level_sessions(
    database: &mut ReadOnlyDatabase,
    table: &str,
    paths: &[String],
) -> Result<Vec<String>, CleanupFailure> {
    if !database.has_table(table).await? {
        return Ok(Vec::new());
    }
    let sql = format!(
        "SELECT id FROM {table} WHERE directory IN ({}) \
         AND (parent_id IS NULL OR parent_id = '') ORDER BY id",
        placeholders(paths.len())
    );
    Ok(database
        .text_rows(sql, paths, 1)
        .await?
        .into_iter()
        .filter_map(|row| row.into_iter().next().flatten())
        .collect())
}

#[cfg(test)]
#[path = "opencode_tests.rs"]
mod tests;
