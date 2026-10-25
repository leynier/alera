use std::path::Path;
use std::time::Duration;

use sqlx::sqlite::{SqliteConnectOptions, SqliteConnection};
use sqlx::{ConnectOptions, Connection, Row};

use super::CleanupFailure;

/// A third-party agent database opened read-only. Every failure is a
/// `discovery` failure: a schema change upstream must skip discovery, never
/// stop the deletion of the ids Alera already knows.
pub(super) struct ReadOnlyDatabase {
    connection: SqliteConnection,
}

impl ReadOnlyDatabase {
    pub async fn open(path: &Path) -> Result<Self, CleanupFailure> {
        let connection = SqliteConnectOptions::new()
            .filename(path)
            .read_only(true)
            .create_if_missing(false)
            .busy_timeout(Duration::from_secs(2))
            .connect()
            .await
            .map_err(discovery_failure)?;
        Ok(Self { connection })
    }

    pub async fn has_table(&mut self, name: &str) -> Result<bool, CleanupFailure> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
        )
        .bind(name)
        .fetch_one(&mut self.connection)
        .await
        .map_err(discovery_failure)?;
        Ok(count > 0)
    }

    /// Rows of `columns` text values; callers `CAST` anything that is not text.
    /// `sql` may only interpolate constant table names and `?` placeholders.
    pub async fn text_rows(
        &mut self,
        sql: String,
        binds: &[String],
        columns: usize,
    ) -> Result<Vec<Vec<Option<String>>>, CleanupFailure> {
        let mut query = sqlx::query(sqlx::AssertSqlSafe(sql));
        for value in binds {
            query = query.bind(value.as_str());
        }
        let rows = query
            .fetch_all(&mut self.connection)
            .await
            .map_err(discovery_failure)?;
        rows.iter()
            .map(|row| {
                (0..columns)
                    .map(|index| row.try_get::<Option<String>, _>(index))
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(discovery_failure)
            })
            .collect()
    }

    pub async fn close(self) {
        let _ = self.connection.close().await;
    }
}

/// `?, ?, ?` for an `IN` list of `count` values.
pub(super) fn placeholders(count: usize) -> String {
    vec!["?"; count.max(1)].join(", ")
}

fn discovery_failure(error: sqlx::Error) -> CleanupFailure {
    CleanupFailure::new(
        "discovery",
        format!("could not read agent database: {error}"),
    )
}
