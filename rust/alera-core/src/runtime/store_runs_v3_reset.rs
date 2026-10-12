//! Moves a store onto orchestration schema v3 by starting runs from scratch.
//!
//! Runs and workflows from schema 1 or 2 are dropped rather than translated:
//! their lifecycles do not map onto the unified run. Agent profiles, launch
//! receipts, personal recipes, SSH targets and the external inbox survive.
//! The previous database is copied next to the store first.

use std::collections::BTreeSet;
use std::path::Path;

use anyhow::{bail, Result};
use sqlx::{Row, SqliteConnection};

use super::runs_v3_schema::{
    install_runs_v3_schema, ORCHESTRATION_SCHEMA_VERSION, ORCHESTRATION_SCHEMA_VERSION_KEY,
};
use super::RuntimeStore;

pub const RUNS_V3_BACKUP_FILE_NAME: &str = "runtime-pre-runs-v3.sqlite";
const RETIRED_APPROVAL_KEY_FILE: &str = "desktop-workflow-approval.key";
const PRESERVED_INBOX_TABLE: &str = "temp.runsV3PreservedInbox";

/// Columns of the v3 `orchestrationMessages` table an older row may carry.
const MESSAGE_COLUMNS: &[&str] = &[
    "id",
    "from_handle",
    "to_handle",
    "subject",
    "body",
    "type",
    "priority",
    "thread_id",
    "payload",
    "read",
    "sequence",
    "created_at",
    "delivered_at",
    "run_id",
    "workspace_id",
    "task_id",
    "dispatch_id",
    "state",
    "expires_at",
    "obsolete_at",
    "reply_to_id",
    "external_meta",
];

/// What the reset discarded, for the caller's log.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RunsV3Reset {
    pub dropped_runs: i64,
    pub preserved_inbox_messages: i64,
}

impl RuntimeStore {
    /// Brings the orchestration schema to v3. `backup_dir` is where the
    /// pre-reset copy goes; `None` skips the copy (an in-memory store).
    /// Only the runtime owner may reset: any other process (a CLI command, an
    /// agent's `alera` after the binary was replaced) fails closed, because
    /// the host that still runs may be using the tables the reset drops.
    pub(super) async fn migrate_orchestration_v3(
        &self,
        backup_dir: Option<&Path>,
        owns_runtime: bool,
    ) -> Result<Option<RunsV3Reset>> {
        let version = self.get_metadata(ORCHESTRATION_SCHEMA_VERSION_KEY).await?;
        let legacy = match version.as_deref() {
            Some(ORCHESTRATION_SCHEMA_VERSION) => false,
            Some("1") | Some("2") => true,
            None => self.has_pre_v3_orchestration_tables().await?,
            Some(other) => bail!(
                "unsupported orchestration schema version {other}; this runtime understands \
                 {ORCHESTRATION_SCHEMA_VERSION} and refuses to modify a newer store"
            ),
        };
        if legacy && !owns_runtime {
            bail!(
                "the runtime store predates orchestration schema v3 and only the Alera runtime \
                 can upgrade it; stop any running Alera runtime, start Alera, then retry"
            );
        }
        if legacy {
            if let Some(directory) = backup_dir {
                self.back_up_before_runs_v3(directory).await?;
            }
        }
        let mut tx = self.pool().begin().await?;
        let reset = if legacy {
            Some(drop_pre_v3_orchestration(&mut tx).await?)
        } else {
            None
        };
        install_runs_v3_schema(&mut tx).await?;
        let reset = match reset {
            Some(mut reset) => {
                reset.preserved_inbox_messages = restore_preserved_inbox(&mut tx).await?;
                Some(reset)
            }
            None => None,
        };
        sqlx::query(
            "INSERT INTO runtimeMetadata (key, value, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
        )
        .bind(ORCHESTRATION_SCHEMA_VERSION_KEY)
        .bind(ORCHESTRATION_SCHEMA_VERSION)
        .bind(super::store::format_timestamp(chrono::Utc::now()))
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        if let Some(reset) = reset {
            tracing::warn!(
                dropped_runs = reset.dropped_runs,
                preserved_inbox_messages = reset.preserved_inbox_messages,
                "orchestration store reset to schema v3; runs and workflows from the previous \
                 schema were discarded"
            );
            if let Some(directory) = backup_dir {
                // The signing key only authorised workflow decisions, which no
                // longer exist; a missing file is the expected case.
                let _ = std::fs::remove_file(directory.join(RETIRED_APPROVAL_KEY_FILE));
            }
        }
        Ok(reset)
    }

    async fn has_pre_v3_orchestration_tables(&self) -> Result<bool> {
        Ok(sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' \
             AND (name LIKE 'orchestration%' OR name LIKE 'workflow%'))",
        )
        .fetch_one(self.pool())
        .await?)
    }

    /// The drop is one transaction, so a store that is still pre-v3 holds
    /// everything: a backup left by an attempt that did not commit may be
    /// older than the store and is kept beside a fresh copy, never trusted as
    /// the only one.
    async fn back_up_before_runs_v3(&self, directory: &Path) -> Result<()> {
        let path = runs_v3_backup_path(directory);
        let Some(target) = path.to_str() else {
            bail!("runtime directory is not valid UTF-8; cannot back up the store");
        };
        sqlx::query("VACUUM INTO ?")
            .bind(target)
            .execute(self.pool())
            .await?;
        super::set_private_file_permissions(&path)?;
        Ok(())
    }
}

/// The canonical backup name, or a numbered one when an earlier attempt
/// already left a copy there.
fn runs_v3_backup_path(directory: &Path) -> std::path::PathBuf {
    let canonical = directory.join(RUNS_V3_BACKUP_FILE_NAME);
    if !canonical.exists() {
        return canonical;
    }
    let stem = RUNS_V3_BACKUP_FILE_NAME.trim_end_matches(".sqlite");
    (1..)
        .map(|attempt| directory.join(format!("{stem}-{attempt}.sqlite")))
        .find(|path| !path.exists())
        .expect("an unbounded range yields a free name")
}

/// Drops every pre-v3 orchestration and workflow object except the external
/// inbox rows, which wait in a temporary table for the v3 schema.
async fn drop_pre_v3_orchestration(conn: &mut SqliteConnection) -> Result<RunsV3Reset> {
    // Parent tables go before their children; the check runs at commit, when
    // both are gone.
    sqlx::query("PRAGMA defer_foreign_keys = ON")
        .execute(&mut *conn)
        .await?;
    let tables = schema_names(
        conn,
        "SELECT name FROM sqlite_master WHERE type = 'table' \
         AND (name LIKE 'orchestration%' OR name LIKE 'workflow%')",
    )
    .await?;
    let dropped_runs = if tables.contains("orchestrationCoordinatorRuns") {
        sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationCoordinatorRuns")
            .fetch_one(&mut *conn)
            .await?
    } else {
        0
    };
    if tables.contains("orchestrationMessages") {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "CREATE TABLE {PRESERVED_INBOX_TABLE} AS SELECT * FROM orchestrationMessages \
             WHERE (substr(from_handle, 1, 4) = 'ext:' OR substr(to_handle, 1, 4) = 'ext:') \
             AND type NOT IN ('heartbeat', 'worker_done')"
        )))
        .execute(&mut *conn)
        .await?;
    }
    // Triggers go first: a protective trigger must not veto the drop, and one
    // on a surviving table must not keep pointing at a dropped one.
    let triggers = schema_names(
        conn,
        "SELECT name FROM sqlite_master WHERE type = 'trigger' \
         AND (name LIKE 'orchestration%' OR name LIKE 'workflow%' \
           OR tbl_name LIKE 'orchestration%' OR tbl_name LIKE 'workflow%' \
           OR sql LIKE '%orchestration%' OR sql LIKE '%workflow%')",
    )
    .await?;
    for trigger in &triggers {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DROP TRIGGER IF EXISTS \"{trigger}\""
        )))
        .execute(&mut *conn)
        .await?;
    }
    let views = schema_names(
        conn,
        "SELECT name FROM sqlite_master WHERE type = 'view' \
         AND (name LIKE 'orchestration%' OR name LIKE 'workflow%' \
           OR sql LIKE '%orchestration%' OR sql LIKE '%workflow%')",
    )
    .await?;
    for view in &views {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DROP VIEW IF EXISTS \"{view}\""
        )))
        .execute(&mut *conn)
        .await?;
    }
    for table in &tables {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DROP TABLE IF EXISTS \"{table}\""
        )))
        .execute(&mut *conn)
        .await?;
    }
    let has_old_recipes: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' \
         AND name = 'personalWorkflowRecipes')",
    )
    .fetch_one(&mut *conn)
    .await?;
    if has_old_recipes {
        sqlx::query("ALTER TABLE personalWorkflowRecipes RENAME TO personalRecipes")
            .execute(&mut *conn)
            .await?;
    }
    Ok(RunsV3Reset {
        dropped_runs,
        preserved_inbox_messages: 0,
    })
}

/// Copies the held inbox rows into the v3 table. Rows from schema 1 lack the
/// delivery state, so it is derived the way the v1 to v2 migration did.
async fn restore_preserved_inbox(conn: &mut SqliteConnection) -> Result<i64> {
    let held: BTreeSet<String> = sqlx::query("PRAGMA temp.table_info(runsV3PreservedInbox)")
        .fetch_all(&mut *conn)
        .await?
        .iter()
        .map(|row| row.try_get::<String, _>("name"))
        .collect::<std::result::Result<_, _>>()?;
    if held.is_empty() {
        return Ok(0);
    }
    let mut columns = Vec::new();
    let mut values = Vec::new();
    for column in MESSAGE_COLUMNS {
        let expression = match *column {
            "type" => "CASE WHEN type = 'decision_gate' AND substr(from_handle, 1, 4) = 'ext:' \
                       THEN 'question' ELSE type END"
                .to_string(),
            "state" if !held.contains("state") => "CASE WHEN read != 0 THEN 'read' \
                 WHEN delivered_at IS NOT NULL THEN 'delivered' ELSE 'queued' END"
                .to_string(),
            name if held.contains(name) => name.to_string(),
            _ => continue,
        };
        columns.push(*column);
        values.push(expression);
    }
    let restored = sqlx::query(sqlx::AssertSqlSafe(format!(
        "INSERT INTO orchestrationMessages ({}) SELECT {} FROM {PRESERVED_INBOX_TABLE} \
         ORDER BY sequence",
        columns.join(", "),
        values.join(", ")
    )))
    .execute(&mut *conn)
    .await?
    .rows_affected();
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP TABLE {PRESERVED_INBOX_TABLE}"
    )))
    .execute(&mut *conn)
    .await?;
    Ok(restored as i64)
}

async fn schema_names(conn: &mut SqliteConnection, sql: &'static str) -> Result<BTreeSet<String>> {
    sqlx::query(sql)
        .fetch_all(&mut *conn)
        .await?
        .iter()
        .map(|row| row.try_get::<String, _>("name").map_err(Into::into))
        .collect()
}
