use std::path::Path;

use anyhow::Result;
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use sqlx::{Row, SqlitePool};

pub const HISTORY_DATABASE_FILE_NAME: &str = "terminal_history.sqlite";

const CREATE_CHECKPOINTS_TABLE_SQL: &str = "\
CREATE TABLE IF NOT EXISTS checkpoints (\n\
  sessionId TEXT PRIMARY KEY,\n\
  workspaceId TEXT NOT NULL,\n\
  tabId TEXT NOT NULL,\n\
  workingDirectory TEXT NOT NULL,\n\
  running INTEGER NOT NULL,\n\
  exitCode INTEGER,\n\
  endedAt TEXT,\n\
  outputStreamBytes INTEGER NOT NULL DEFAULT 0,\n\
  updatedAt TEXT NOT NULL\n\
);";

const CREATE_OUTPUT_CHUNKS_TABLE_SQL: &str = "\
CREATE TABLE IF NOT EXISTS outputChunks (\n\
  id INTEGER PRIMARY KEY AUTOINCREMENT,\n\
  sessionId TEXT NOT NULL,\n\
  sequence INTEGER NOT NULL,\n\
  createdAt TEXT NOT NULL,\n\
  data BLOB NOT NULL\n\
);";

const CREATE_OUTPUT_CHUNKS_SESSION_INDEX_SQL: &str = "\
CREATE INDEX IF NOT EXISTS outputChunksSessionIdSequenceIdx\n\
ON outputChunks(sessionId, sequence, id);";

#[derive(Debug, Clone, PartialEq)]
pub struct TerminalHostCheckpoint {
    pub session_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub working_directory: String,
    pub running: bool,
    pub exit_code: Option<i32>,
    pub ended_at: Option<DateTime<Utc>>,
    pub output_stream_bytes: u64,
    pub updated_at: DateTime<Utc>,
    pub buffer: Vec<u8>,
}

#[derive(Clone)]
pub struct TerminalHostHistoryStore {
    pool: SqlitePool,
}

impl TerminalHostHistoryStore {
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
        destroy_legacy_checkpoint_schema(&pool).await?;
        destroy_unsequenced_output_chunks_schema(&pool).await?;
        sqlx::query(CREATE_CHECKPOINTS_TABLE_SQL)
            .execute(&pool)
            .await?;
        ensure_output_stream_bytes_column(&pool).await?;
        sqlx::query(CREATE_OUTPUT_CHUNKS_TABLE_SQL)
            .execute(&pool)
            .await?;
        sqlx::query(CREATE_OUTPUT_CHUNKS_SESSION_INDEX_SQL)
            .execute(&pool)
            .await?;
        Ok(TerminalHostHistoryStore { pool })
    }

    pub async fn read(
        &self,
        session_id: &str,
        max_bytes: usize,
    ) -> Result<Option<TerminalHostCheckpoint>> {
        self.trim_session(session_id, max_bytes).await?;
        let row = sqlx::query(
            "SELECT sessionId, workspaceId, tabId, workingDirectory, running, exitCode, \
             endedAt, outputStreamBytes, updatedAt FROM checkpoints WHERE sessionId = ?",
        )
        .bind(session_id)
        .fetch_optional(&self.pool)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let buffer = self.read_buffer(session_id).await?;
        let ended_at: Option<String> = row.try_get("endedAt")?;
        let updated_at: String = row.try_get("updatedAt")?;
        Ok(Some(TerminalHostCheckpoint {
            session_id: row.try_get("sessionId")?,
            workspace_id: row.try_get("workspaceId")?,
            tab_id: row.try_get("tabId")?,
            working_directory: row.try_get("workingDirectory")?,
            running: row.try_get::<i64, _>("running")? == 1,
            exit_code: row.try_get("exitCode")?,
            ended_at: parse_timestamp(ended_at.as_deref()),
            output_stream_bytes: row.try_get::<i64, _>("outputStreamBytes")?.max(0) as u64,
            updated_at: parse_timestamp(Some(updated_at.as_str()))
                .unwrap_or_else(|| Utc.timestamp_opt(0, 0).single().expect("epoch is valid")),
            buffer,
        }))
    }

    pub async fn upsert(&self, checkpoint: TerminalHostCheckpoint) -> Result<()> {
        sqlx::query(
            "INSERT INTO checkpoints \
             (sessionId, workspaceId, tabId, workingDirectory, running, exitCode, endedAt, outputStreamBytes, updatedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(sessionId) DO UPDATE SET \
             workspaceId = excluded.workspaceId, \
             tabId = excluded.tabId, \
             workingDirectory = excluded.workingDirectory, \
             running = excluded.running, \
             exitCode = excluded.exitCode, \
             endedAt = excluded.endedAt, \
             outputStreamBytes = excluded.outputStreamBytes, \
             updatedAt = excluded.updatedAt",
        )
        .bind(checkpoint.session_id)
        .bind(checkpoint.workspace_id)
        .bind(checkpoint.tab_id)
        .bind(checkpoint.working_directory)
        .bind(if checkpoint.running { 1_i64 } else { 0_i64 })
        .bind(checkpoint.exit_code.map(i64::from))
        .bind(checkpoint.ended_at.map(format_timestamp))
        .bind(i64::try_from(checkpoint.output_stream_bytes).unwrap_or(i64::MAX))
        .bind(format_timestamp(checkpoint.updated_at))
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn append_output(&self, session_id: &str, sequence: i64, data: &[u8]) -> Result<()> {
        if data.is_empty() {
            return Ok(());
        }
        sqlx::query(
            "INSERT INTO outputChunks (sessionId, sequence, createdAt, data) \
             SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM checkpoints WHERE sessionId = ?)",
        )
        .bind(session_id)
        .bind(sequence)
        .bind(format_timestamp(Utc::now()))
        .bind(data)
        .bind(session_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn next_output_sequence(&self, session_id: &str) -> Result<i64> {
        let row = sqlx::query(
            "SELECT COALESCE(MAX(sequence), -1) AS maxSequence \
             FROM outputChunks WHERE sessionId = ?",
        )
        .bind(session_id)
        .fetch_one(&self.pool)
        .await?;
        let max_sequence: i64 = row.try_get("maxSequence")?;
        Ok(max_sequence.saturating_add(1))
    }

    pub async fn trim_session(&self, session_id: &str, max_bytes: usize) -> Result<()> {
        let rows = sqlx::query(
            "SELECT id, sequence, length(data) AS byteLen FROM outputChunks \
             WHERE sessionId = ? ORDER BY sequence DESC, id DESC",
        )
        .bind(session_id)
        .fetch_all(&self.pool)
        .await?;
        let mut kept = 0usize;
        for row in rows {
            let id: i64 = row.try_get("id")?;
            let sequence: i64 = row.try_get("sequence")?;
            let byte_len: i64 = row.try_get("byteLen")?;
            let byte_len = byte_len.max(0) as usize;
            if kept.saturating_add(byte_len) <= max_bytes {
                kept = kept.saturating_add(byte_len);
                continue;
            }
            let remaining = max_bytes.saturating_sub(kept);
            if remaining > 0 {
                let data: Vec<u8> = sqlx::query("SELECT data FROM outputChunks WHERE id = ?")
                    .bind(id)
                    .fetch_one(&self.pool)
                    .await?
                    .try_get("data")?;
                let tail_start = data.len().saturating_sub(remaining);
                let tail = data[tail_start..].to_vec();
                sqlx::query("UPDATE outputChunks SET data = ? WHERE id = ?")
                    .bind(tail)
                    .bind(id)
                    .execute(&self.pool)
                    .await?;
                sqlx::query(
                    "DELETE FROM outputChunks \
                     WHERE sessionId = ? AND (sequence < ? OR (sequence = ? AND id < ?))",
                )
                .bind(session_id)
                .bind(sequence)
                .bind(sequence)
                .bind(id)
                .execute(&self.pool)
                .await?;
            } else {
                sqlx::query(
                    "DELETE FROM outputChunks \
                     WHERE sessionId = ? AND (sequence < ? OR (sequence = ? AND id <= ?))",
                )
                .bind(session_id)
                .bind(sequence)
                .bind(sequence)
                .bind(id)
                .execute(&self.pool)
                .await?;
            }
            break;
        }
        Ok(())
    }

    pub async fn delete(&self, session_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM outputChunks WHERE sessionId = ?")
            .bind(session_id)
            .execute(&self.pool)
            .await?;
        sqlx::query("DELETE FROM checkpoints WHERE sessionId = ?")
            .bind(session_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn read_buffer(&self, session_id: &str) -> Result<Vec<u8>> {
        let rows = sqlx::query(
            "SELECT data FROM outputChunks WHERE sessionId = ? ORDER BY sequence ASC, id ASC",
        )
        .bind(session_id)
        .fetch_all(&self.pool)
        .await?;
        let total_len = rows
            .iter()
            .filter_map(|row| row.try_get::<Vec<u8>, _>("data").ok())
            .map(|data| data.len())
            .sum();
        let mut buffer = Vec::with_capacity(total_len);
        for row in rows {
            let data: Vec<u8> = row.try_get("data")?;
            buffer.extend_from_slice(&data);
        }
        Ok(buffer)
    }
}

async fn destroy_legacy_checkpoint_schema(pool: &SqlitePool) -> Result<()> {
    let rows = sqlx::query("PRAGMA table_info(checkpoints)")
        .fetch_all(pool)
        .await?;
    let has_legacy_buffer = rows.iter().any(|row| {
        row.try_get::<String, _>("name")
            .is_ok_and(|name| name == "buffer")
    });
    if has_legacy_buffer {
        sqlx::query("DROP TABLE IF EXISTS checkpoints")
            .execute(pool)
            .await?;
        sqlx::query("DROP TABLE IF EXISTS outputChunks")
            .execute(pool)
            .await?;
    }
    Ok(())
}

async fn destroy_unsequenced_output_chunks_schema(pool: &SqlitePool) -> Result<()> {
    let rows = sqlx::query("PRAGMA table_info(outputChunks)")
        .fetch_all(pool)
        .await?;
    if rows.is_empty() {
        return Ok(());
    }
    let has_sequence = rows.iter().any(|row| {
        row.try_get::<String, _>("name")
            .is_ok_and(|name| name == "sequence")
    });
    if !has_sequence {
        sqlx::query("DROP TABLE IF EXISTS outputChunks")
            .execute(pool)
            .await?;
    }
    Ok(())
}

async fn ensure_output_stream_bytes_column(pool: &SqlitePool) -> Result<()> {
    let rows = sqlx::query("PRAGMA table_info(checkpoints)")
        .fetch_all(pool)
        .await?;
    let has_column = rows.iter().any(|row| {
        row.try_get::<String, _>("name")
            .is_ok_and(|name| name == "outputStreamBytes")
    });
    if !has_column {
        sqlx::query(
            "ALTER TABLE checkpoints ADD COLUMN outputStreamBytes INTEGER NOT NULL DEFAULT 0",
        )
        .execute(pool)
        .await?;
    }
    Ok(())
}

fn format_timestamp(value: DateTime<Utc>) -> String {
    value.to_rfc3339_opts(SecondsFormat::Millis, true)
}

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
            output_stream_bytes: 42,
            updated_at: Utc.timestamp_opt(1_700_000_000, 123_000_000).unwrap(),
            buffer: Vec::new(),
        }
    }

    #[tokio::test]
    async fn upsert_append_then_read_round_trips_incremental_chunks() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();

        assert!(store.read("missing", 1024).await.unwrap().is_none());

        let checkpoint = sample("s1");
        store.upsert(checkpoint.clone()).await.unwrap();
        store.append_output("s1", 0, b"hello ").await.unwrap();
        store.append_output("s1", 1, b"world").await.unwrap();

        let read = store.read("s1", 1024).await.unwrap().unwrap();
        assert_eq!(read.session_id, checkpoint.session_id);
        assert_eq!(read.workspace_id, checkpoint.workspace_id);
        assert_eq!(read.output_stream_bytes, checkpoint.output_stream_bytes);
        assert_eq!(read.buffer, b"hello world");
    }

    #[tokio::test]
    async fn read_orders_chunks_by_sequence_not_insert_order() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();

        store.append_output("s1", 1, b"world").await.unwrap();
        store.append_output("s1", 0, b"hello ").await.unwrap();

        let read = store.read("s1", 1024).await.unwrap().unwrap();
        assert_eq!(read.buffer, b"hello world");
    }

    #[tokio::test]
    async fn next_output_sequence_advances_persisted_history() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();

        assert_eq!(store.next_output_sequence("s1").await.unwrap(), 0);
        store.append_output("s1", 0, b"first").await.unwrap();
        store.append_output("s1", 1, b"second").await.unwrap();

        assert_eq!(store.next_output_sequence("s1").await.unwrap(), 2);
    }

    #[tokio::test]
    async fn append_output_trims_oldest_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();

        store.append_output("s1", 0, b"abc").await.unwrap();
        store.append_output("s1", 1, b"de").await.unwrap();
        store.append_output("s1", 2, b"fg").await.unwrap();

        let read = store.read("s1", 5).await.unwrap().unwrap();
        assert_eq!(read.buffer, b"cdefg");
    }

    #[tokio::test]
    async fn append_output_keeps_tail_of_single_oversized_chunk() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();

        store.append_output("s1", 0, b"abcdefg").await.unwrap();

        let read = store.read("s1", 3).await.unwrap().unwrap();
        assert_eq!(read.buffer, b"efg");
    }

    #[tokio::test]
    async fn shrinking_session_limit_trims_existing_chunks() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();
        store.append_output("s1", 0, b"abcdefgh").await.unwrap();

        store.trim_session("s1", 3).await.unwrap();

        let read = store.read("s1", 3).await.unwrap().unwrap();
        assert_eq!(read.buffer, b"fgh");
    }

    #[tokio::test]
    async fn delete_removes_metadata_and_chunks() {
        let dir = tempfile::tempdir().unwrap();
        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();
        store.upsert(sample("s1")).await.unwrap();
        store.append_output("s1", 0, b"hello").await.unwrap();

        store.delete("s1").await.unwrap();

        assert!(store.read("s1", 1024).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn legacy_buffer_checkpoint_schema_is_destroyed() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(HISTORY_DATABASE_FILE_NAME);
        let options = SqliteConnectOptions::new()
            .filename(&path)
            .create_if_missing(true);
        let pool = SqlitePoolOptions::new()
            .connect_with(options)
            .await
            .unwrap();
        sqlx::query("CREATE TABLE checkpoints (sessionId TEXT PRIMARY KEY, buffer BLOB NOT NULL)")
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("INSERT INTO checkpoints (sessionId, buffer) VALUES ('old', x'4142')")
            .execute(&pool)
            .await
            .unwrap();
        drop(pool);

        let store = TerminalHostHistoryStore::open(dir.path()).await.unwrap();

        assert!(store.read("old", 1024).await.unwrap().is_none());
        let columns = sqlx::query("PRAGMA table_info(checkpoints)")
            .fetch_all(&store.pool)
            .await
            .unwrap();
        assert!(!columns
            .iter()
            .any(|row| row.try_get::<String, _>("name").unwrap() == "buffer"));
    }
}
