use std::path::Path;

use anyhow::Result;
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use sea_orm::sea_query::OnConflict;
use sea_orm::{
    ColumnTrait, ConnectionTrait, DatabaseConnection, EntityTrait, QueryFilter, Set,
    SqlxSqliteConnector, Statement,
};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};

use crate::terminal_host::checkpoint_entity::{ActiveModel, Column, Entity as Checkpoints, Model};

pub const HISTORY_DATABASE_FILE_NAME: &str = "terminal_history.sqlite";

/// Schema for the checkpoints table. Keep this stable so existing terminal
/// history databases remain readable.
const CREATE_TABLE_SQL: &str = "\
CREATE TABLE IF NOT EXISTS checkpoints (\n\
  sessionId TEXT PRIMARY KEY,\n\
  workspaceId TEXT NOT NULL,\n\
  tabId TEXT NOT NULL,\n\
  workingDirectory TEXT NOT NULL,\n\
  running INTEGER NOT NULL,\n\
  exitCode INTEGER,\n\
  endedAt TEXT,\n\
  updatedAt TEXT NOT NULL,\n\
  buffer BLOB NOT NULL\n\
);";

/// A persisted terminal session snapshot.
#[derive(Debug, Clone, PartialEq)]
pub struct TerminalHostCheckpoint {
    pub session_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub working_directory: String,
    pub running: bool,
    pub exit_code: Option<i32>,
    pub ended_at: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
    pub buffer: Vec<u8>,
}

impl TerminalHostCheckpoint {
    fn from_model(model: Model) -> Self {
        TerminalHostCheckpoint {
            session_id: model.session_id,
            workspace_id: model.workspace_id,
            tab_id: model.tab_id,
            working_directory: model.working_directory,
            running: model.running == 1,
            exit_code: model.exit_code,
            ended_at: parse_timestamp(model.ended_at.as_deref()),
            updated_at: parse_timestamp(Some(model.updated_at.as_str()))
                .unwrap_or_else(|| Utc.timestamp_opt(0, 0).single().expect("epoch is valid")),
            buffer: model.buffer,
        }
    }

    fn into_active_model(self) -> ActiveModel {
        ActiveModel {
            session_id: Set(self.session_id),
            workspace_id: Set(self.workspace_id),
            tab_id: Set(self.tab_id),
            working_directory: Set(self.working_directory),
            running: Set(if self.running { 1 } else { 0 }),
            exit_code: Set(self.exit_code),
            ended_at: Set(self.ended_at.map(format_timestamp)),
            updated_at: Set(format_timestamp(self.updated_at)),
            buffer: Set(self.buffer),
        }
    }
}

/// SQLite-backed checkpoint store. Cloneable so PTY sessions and the server can
/// share the same connection pool (SeaORM wraps an `Arc` pool internally).
#[derive(Clone)]
pub struct TerminalHostHistoryStore {
    db: DatabaseConnection,
}

impl TerminalHostHistoryStore {
    /// Open (creating if needed) the history database under `runtime_dir`,
    /// applying the host pragmas and ensuring the schema exists.
    pub async fn open(runtime_dir: &Path) -> Result<Self> {
        if !runtime_dir.exists() {
            std::fs::create_dir_all(runtime_dir)?;
        }
        let path = runtime_dir.join(HISTORY_DATABASE_FILE_NAME);
        let options = SqliteConnectOptions::new()
            .filename(&path)
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal);
        let pool = SqlitePoolOptions::new().connect_with(options).await?;
        let db = SqlxSqliteConnector::from_sqlx_sqlite_pool(pool);
        db.execute(Statement::from_string(
            db.get_database_backend(),
            CREATE_TABLE_SQL.to_string(),
        ))
        .await?;
        Ok(TerminalHostHistoryStore { db })
    }

    pub async fn read(&self, session_id: &str) -> Result<Option<TerminalHostCheckpoint>> {
        let model = Checkpoints::find_by_id(session_id.to_string())
            .one(&self.db)
            .await?;
        Ok(model.map(TerminalHostCheckpoint::from_model))
    }

    /// Insert or replace a checkpoint.
    pub async fn upsert(&self, checkpoint: TerminalHostCheckpoint) -> Result<()> {
        Checkpoints::insert(checkpoint.into_active_model())
            .on_conflict(
                OnConflict::column(Column::SessionId)
                    .update_columns([
                        Column::WorkspaceId,
                        Column::TabId,
                        Column::WorkingDirectory,
                        Column::Running,
                        Column::ExitCode,
                        Column::EndedAt,
                        Column::UpdatedAt,
                        Column::Buffer,
                    ])
                    .to_owned(),
            )
            .exec(&self.db)
            .await?;
        Ok(())
    }

    pub async fn delete(&self, session_id: &str) -> Result<()> {
        Checkpoints::delete_many()
            .filter(Column::SessionId.eq(session_id))
            .exec(&self.db)
            .await?;
        Ok(())
    }
}

/// Format a UTC instant the way Dart's `DateTime.toIso8601String()` does for UTC
/// values (millisecond precision, trailing `Z`).
fn format_timestamp(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(SecondsFormat::Millis, true)
}

/// Tolerant parse matching Dart's `DateTime.tryParse`: an absent or unparseable
/// value yields `None`.
fn parse_timestamp(value: Option<&str>) -> Option<DateTime<Utc>> {
    let value = value?;
    if value.is_empty() {
        return None;
    }
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(session_id: &str) -> TerminalHostCheckpoint {
        TerminalHostCheckpoint {
            session_id: session_id.to_string(),
            workspace_id: "ws".to_string(),
            tab_id: "tab".to_string(),
            working_directory: "/tmp/project".to_string(),
            running: true,
            exit_code: None,
            ended_at: None,
            updated_at: Utc.timestamp_opt(1_700_000_000, 123_000_000).unwrap(),
            buffer: vec![0, 159, 146, 150, b'h', b'i'],
        }
    }

    #[tokio::test]
    async fn upsert_then_read_round_trips() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();

        assert!(store.read("missing").await.unwrap().is_none());

        let checkpoint = sample("s1");
        store.upsert(checkpoint.clone()).await.unwrap();
        let read = store.read("s1").await.unwrap().unwrap();
        assert_eq!(read, checkpoint);
    }

    #[tokio::test]
    async fn upsert_replaces_existing_row() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();

        store.upsert(sample("s1")).await.unwrap();
        let mut exited = sample("s1");
        exited.running = false;
        exited.exit_code = Some(0);
        exited.ended_at = Some(Utc.timestamp_opt(1_700_000_100, 0).unwrap());
        store.upsert(exited.clone()).await.unwrap();

        let read = store.read("s1").await.unwrap().unwrap();
        assert_eq!(read, exited);
        assert!(!read.running);
        assert_eq!(read.exit_code, Some(0));
    }

    #[tokio::test]
    async fn delete_removes_row() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();
        store.delete("s1").await.unwrap();
        assert!(store.read("s1").await.unwrap().is_none());
        // Deleting a missing row is a no-op.
        store.delete("s1").await.unwrap();
    }

    #[tokio::test]
    async fn on_disk_format_matches_dart_expectations() {
        // Verifies the raw column encoding: running as an INTEGER 1,
        // timestamps as ISO8601 text ending in Z, buffer as a BLOB.
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        let mut checkpoint = sample("s1");
        checkpoint.ended_at = Some(Utc.timestamp_opt(1_700_000_100, 0).unwrap());
        store.upsert(checkpoint).await.unwrap();

        let backend = store.db.get_database_backend();
        let row = store
            .db
            .query_one(Statement::from_string(
                backend,
                "SELECT running, updatedAt, endedAt, typeof(buffer) AS buffer_type, \
                 length(buffer) AS buffer_len FROM checkpoints WHERE sessionId = 's1';"
                    .to_string(),
            ))
            .await
            .unwrap()
            .unwrap();

        let running: i32 = row.try_get("", "running").unwrap();
        let updated_at: String = row.try_get("", "updatedAt").unwrap();
        let ended_at: String = row.try_get("", "endedAt").unwrap();
        let buffer_type: String = row.try_get("", "buffer_type").unwrap();
        let buffer_len: i32 = row.try_get("", "buffer_len").unwrap();

        assert_eq!(running, 1);
        assert!(updated_at.ends_with('Z'), "got {updated_at}");
        assert!(ended_at.ends_with('Z'), "got {ended_at}");
        assert_eq!(buffer_type, "blob");
        assert_eq!(buffer_len, 6);
    }
}
