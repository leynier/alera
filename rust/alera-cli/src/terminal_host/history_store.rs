use std::path::Path;

use alera_core::runtime::{
    harden_sqlite_files, open_private_runtime_file, prepare_private_runtime_directory,
};
use anyhow::Result;
use chrono::{DateTime, SecondsFormat, TimeZone, Utc};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use sqlx::{Row, SqlitePool};

pub const HISTORY_DATABASE_FILE_NAME: &str = "terminal_history.sqlite";
const HISTORY_STORE_MAX_CONNECTIONS: u32 = 2;

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
        prepare_private_runtime_directory(runtime_dir)?;
        let path = runtime_dir.join(HISTORY_DATABASE_FILE_NAME);
        open_private_runtime_file(&path)?;
        let options = SqliteConnectOptions::new()
            .filename(&path)
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal);
        // SQLite runs one worker thread per pooled connection. Output writes
        // are serialized by SQLite itself; a second connection lets a read or
        // trim proceed without retaining the default pool of ten threads.
        let pool = SqlitePoolOptions::new()
            .max_connections(HISTORY_STORE_MAX_CONNECTIONS)
            .connect_with(options)
            .await?;
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
        harden_sqlite_files(&path)?;
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
        // Find the cut in SQL rather than walking every row here. Retention is
        // by bytes, not rows, so a chatty session persisting a batch every
        // 100 ms accumulates six figures of rows, and this runs on the server
        // actor: on every checkpoint tick, every detach, and every configure.
        let row = sqlx::query(
            "SELECT id, sequence, byteLen, running FROM ( \
               SELECT id, sequence, length(data) AS byteLen, \
                      SUM(length(data)) OVER ( \
                        ORDER BY sequence DESC, id DESC \
                      ) AS running \
               FROM outputChunks WHERE sessionId = ? \
             ) WHERE running > ? ORDER BY sequence DESC, id DESC LIMIT 1",
        )
        .bind(session_id)
        .bind(i64::try_from(max_bytes).unwrap_or(i64::MAX))
        .fetch_optional(&self.pool)
        .await?;
        if let Some(row) = row {
            let id: i64 = row.try_get("id")?;
            let sequence: i64 = row.try_get("sequence")?;
            let byte_len: i64 = row.try_get("byteLen")?;
            let running: i64 = row.try_get("running")?;
            // Everything newer than this row, which is what stays whole.
            let kept = running.saturating_sub(byte_len).max(0) as usize;
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
        // Size the buffer in SQL. Summing the decoded blobs first allocated
        // every chunk twice, once to read a length and once to copy it.
        let total_len: i64 = sqlx::query(
            "SELECT COALESCE(SUM(length(data)), 0) AS total FROM outputChunks \
             WHERE sessionId = ?",
        )
        .bind(session_id)
        .fetch_one(&self.pool)
        .await?
        .try_get("total")?;
        let rows = sqlx::query(
            "SELECT data FROM outputChunks WHERE sessionId = ? ORDER BY sequence ASC, id ASC",
        )
        .bind(session_id)
        .fetch_all(&self.pool)
        .await?;
        let mut buffer = Vec::with_capacity(total_len.max(0) as usize);
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
mod tests;
