use std::time::Duration;

use anyhow::Context;
use sqlx::{pool::PoolConnection, PgPool, Postgres};
use tokio::time::{timeout_at, Instant};

// A non-blocking polling lock avoids the SQLx advisory-lock wait/deadlock
// interaction with CREATE INDEX CONCURRENTLY during simultaneous startups.
const MIGRATION_LOCK_KEY: i64 = 0x41_6c_65_72_61_53_78;
const REQUIRED_MIGRATION_DEADLINE: Duration = Duration::from_secs(30);
const MIGRATION_LOCK_DEADLINE: Duration = Duration::from_secs(30);
const ONLINE_MIGRATION_STEP_DEADLINE: Duration = Duration::from_secs(15 * 60);
const LATEST_MIGRATION_VERSION: i64 = 22;
const REQUIRED_SCHEMA_MIGRATION_VERSIONS: &[i64] = &[1, 2, 3, 4, 21, 22];
const ONLINE_MIGRATION_VERSIONS: &[i64] =
    &[5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
const ONLINE_INDEXES: &[(&str, &str)] = &[
    (
        "auth_transactions_expiry_idx",
        "auth_transactions (expires_at)",
    ),
    (
        "auth_transactions_account_idx",
        "auth_transactions (account_id)",
    ),
    (
        "auth_transactions_refresh_family_idx",
        "auth_transactions (refresh_family_id)",
    ),
    (
        "mobile_enrollments_expiry_idx",
        "mobile_enrollments (expires_at)",
    ),
    (
        "mobile_enrollments_account_idx",
        "mobile_enrollments (account_id)",
    ),
    (
        "mobile_enrollments_runtime_idx",
        "mobile_enrollments (runtime_id)",
    ),
    ("refresh_tokens_family_idx", "refresh_tokens (family_id)"),
    (
        "runtime_events_created_at_idx",
        "runtime_events (created_at)",
    ),
    ("runtime_events_account_idx", "runtime_events (account_id)"),
    (
        "delivery_attempts_account_idx",
        "delivery_attempts (account_id)",
    ),
    (
        "push_subscriptions_account_runtime_idx",
        "push_subscriptions (account_id, runtime_id, mobile_device_id)",
    ),
    (
        "push_subscriptions_runtime_idx",
        "push_subscriptions (runtime_id)",
    ),
    ("push_quota_hourly_hour_idx", "push_quota_hourly (hour)"),
    (
        "push_quota_bursts_window_start_idx",
        "push_quota_bursts (window_start)",
    ),
    ("push_quota_daily_day_idx", "push_quota_daily (day)"),
    (
        "abuse_tombstones_expires_at_idx",
        "abuse_tombstones (expires_at)",
    ),
];

pub async fn run(pool: &PgPool) -> anyhow::Result<()> {
    run_required(pool).await?;
    run_online(pool).await
}

pub async fn run_required(pool: &PgPool) -> anyhow::Result<()> {
    let mut connection = pool
        .acquire()
        .await
        .context("acquire required migration connection")?;
    connection.close_on_drop();
    let migrator = sqlx::migrate!("./migrations");
    validate_migration_plan(&migrator)?;
    if required_migrations_ready(&mut connection).await? {
        verify_required_migrations(&mut connection, &migrator).await?;
        return Ok(());
    }

    acquire_lock(&mut connection, Instant::now() + MIGRATION_LOCK_DEADLINE).await?;
    let mut required_migrator = sqlx::migrate::Migrator::with_migrations(
        migrator
            .iter()
            .filter(|migration| REQUIRED_SCHEMA_MIGRATION_VERSIONS.contains(&migration.version))
            .cloned()
            .collect(),
    );
    required_migrator.set_locking(false);
    required_migrator.set_ignore_missing(true);
    let mut migration_result = match timeout_at(
        Instant::now() + REQUIRED_MIGRATION_DEADLINE,
        required_migrator.run_direct(Some(LATEST_MIGRATION_VERSION), &mut *connection, false),
    )
    .await
    {
        Ok(result) => result.context("apply required PostgreSQL migrations"),
        Err(_) => Err(anyhow::anyhow!(
            "required PostgreSQL migration deadline exceeded"
        )),
    };
    if migration_result.is_ok() {
        migration_result = verify_required_migrations(&mut connection, &migrator).await;
    }
    let unlock_result = release_lock_bounded(&mut connection).await;
    if let Err(error) = migration_result {
        let _ = unlock_result;
        return Err(error);
    }
    unlock_result.context("release required migration lock")?;
    Ok(())
}

pub async fn run_online(pool: &PgPool) -> anyhow::Result<()> {
    let mut connection = pool
        .acquire()
        .await
        .context("acquire online migration connection")?;
    connection.close_on_drop();
    let mut required_migrator = sqlx::migrate!("./migrations");
    required_migrator.set_locking(false);
    validate_migration_plan(&required_migrator)?;
    verify_required_migrations(&mut connection, &required_migrator).await?;
    acquire_lock(&mut connection, Instant::now() + MIGRATION_LOCK_DEADLINE).await?;
    let migration_result = apply_online_migrations(&mut connection).await;
    let unlock_result = release_lock_bounded(&mut connection).await;

    if let Err(error) = migration_result {
        let _ = unlock_result;
        return Err(error).context("apply online PostgreSQL migrations");
    }
    unlock_result.context("release online migration lock")?;
    Ok(())
}

pub fn spawn_online(pool: PgPool) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        if let Err(error) = run_online(&pool).await {
            tracing::warn!(
                error = %error,
                "background online PostgreSQL migrations did not finish; retry on the next startup or guarded operator phase"
            );
        }
    })
}

async fn required_migrations_ready(
    connection: &mut PoolConnection<Postgres>,
) -> anyhow::Result<bool> {
    let table_exists = sqlx::query_scalar::<_, Option<String>>(
        "SELECT to_regclass('public._sqlx_migrations')::text",
    )
    .fetch_one(&mut **connection)
    .await
    .context("check required migration table")?
    .is_some();
    if !table_exists {
        return Ok(false);
    }
    let applied_required = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM _sqlx_migrations WHERE version = ANY($1) AND success",
    )
    .bind(REQUIRED_SCHEMA_MIGRATION_VERSIONS)
    .fetch_one(&mut **connection)
    .await
    .context("check required migration state")?;
    Ok(applied_required == REQUIRED_SCHEMA_MIGRATION_VERSIONS.len() as i64)
}

async fn verify_required_migrations(
    connection: &mut PoolConnection<Postgres>,
    migrator: &sqlx::migrate::Migrator,
) -> anyhow::Result<()> {
    if !required_migrations_ready(connection).await? {
        anyhow::bail!("required PostgreSQL migrations are not ready");
    }
    ensure_no_unclassified_database_migrations(connection).await?;
    validate_required_migrations(connection, migrator).await
}

async fn ensure_no_unclassified_database_migrations(
    connection: &mut PoolConnection<Postgres>,
) -> anyhow::Result<()> {
    let version = sqlx::query_scalar::<_, i64>(
        "SELECT version FROM _sqlx_migrations WHERE version < 1 OR version > $1 ORDER BY version LIMIT 1",
    )
    .bind(LATEST_MIGRATION_VERSION)
    .fetch_optional(&mut **connection)
    .await
    .context("check unclassified PostgreSQL migrations")?;
    if let Some(version) = version {
        anyhow::bail!(
            "PostgreSQL migration {version} is not classified for startup or the online index phase"
        );
    }
    Ok(())
}

fn validate_migration_plan(migrator: &sqlx::migrate::Migrator) -> anyhow::Result<()> {
    if ONLINE_MIGRATION_VERSIONS.len() != ONLINE_INDEXES.len() {
        anyhow::bail!("online PostgreSQL migration and index allowlists are out of sync");
    }
    for &version in REQUIRED_SCHEMA_MIGRATION_VERSIONS {
        if !migrator.version_exists(version) {
            anyhow::bail!("required PostgreSQL migration {version} is missing from source");
        }
    }
    for &version in ONLINE_MIGRATION_VERSIONS {
        if !migrator.version_exists(version) {
            anyhow::bail!("online PostgreSQL migration {version} is missing from source");
        }
    }
    if let Some(version) = migrator
        .iter()
        .map(|migration| migration.version)
        .find(|version| {
            !REQUIRED_SCHEMA_MIGRATION_VERSIONS.contains(version)
                && !ONLINE_MIGRATION_VERSIONS.contains(version)
        })
    {
        anyhow::bail!(
            "PostgreSQL migration {version} is not classified for startup or the online index phase"
        );
    }
    Ok(())
}

async fn validate_required_migrations(
    connection: &mut PoolConnection<Postgres>,
    migrator: &sqlx::migrate::Migrator,
) -> anyhow::Result<()> {
    let rows = sqlx::query_as::<_, (i64, Vec<u8>, bool)>(
        "SELECT version, checksum, success FROM _sqlx_migrations WHERE version = ANY($1) ORDER BY version",
    )
    .bind(REQUIRED_SCHEMA_MIGRATION_VERSIONS)
    .fetch_all(&mut **connection)
    .await
    .context("read required migration checksums")?;
    if rows.len() != REQUIRED_SCHEMA_MIGRATION_VERSIONS.len() {
        anyhow::bail!("required PostgreSQL migrations are incomplete");
    }
    for (version, checksum, success) in rows {
        if !success {
            anyhow::bail!("required PostgreSQL migration {version} is dirty");
        }
        let migration = migrator
            .iter()
            .find(|migration| migration.version == version)
            .ok_or_else(|| {
                anyhow::anyhow!("required migration {version} is missing from source")
            })?;
        if migration.checksum.as_ref() != checksum.as_slice() {
            anyhow::bail!("required PostgreSQL migration {version} checksum mismatch");
        }
    }
    Ok(())
}

async fn apply_online_migrations(connection: &mut PoolConnection<Postgres>) -> anyhow::Result<()> {
    let mut migrator = sqlx::migrate!("./migrations");
    migrator.set_locking(false);
    let online_versions = migrator
        .iter()
        .filter(|migration| ONLINE_MIGRATION_VERSIONS.contains(&migration.version))
        .map(|migration| migration.version)
        .collect::<Vec<_>>();
    ensure_no_failed_online_migrations(connection).await?;
    let online_migrations_applied = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS (SELECT 1 FROM _sqlx_migrations WHERE version = ANY($1) AND success)",
    )
    .bind(&online_versions)
    .fetch_one(&mut **connection)
    .await
    .context("check online migration state")?;
    repair_invalid_indexes(connection, online_migrations_applied).await?;

    for version in online_versions {
        timeout_at(
            Instant::now() + ONLINE_MIGRATION_STEP_DEADLINE,
            migrator.run_direct(Some(version), &mut **connection, false),
        )
        .await
        .map_err(|_| {
            anyhow::anyhow!("online PostgreSQL migration {version} exceeded its per-index deadline")
        })?
        .with_context(|| format!("apply online PostgreSQL migration {version}"))?;
    }
    Ok(())
}

async fn ensure_no_failed_online_migrations(
    connection: &mut PoolConnection<Postgres>,
) -> anyhow::Result<()> {
    let dirty_version = timeout_at(
        Instant::now() + ONLINE_MIGRATION_STEP_DEADLINE,
        sqlx::query_scalar::<_, i64>(
            "SELECT version FROM _sqlx_migrations WHERE version = ANY($1) AND success = false ORDER BY version",
        )
        .bind(ONLINE_MIGRATION_VERSIONS)
        .fetch_optional(&mut **connection),
    )
    .await
    .map_err(|_| anyhow::anyhow!("check failed online migrations timed out"))?
    .context("check failed online migrations")?;
    if let Some(version) = dirty_version {
        anyhow::bail!(
            "online PostgreSQL migration {version} is dirty; repair it in a guarded operator phase"
        );
    }
    Ok(())
}

async fn release_lock_bounded(connection: &mut PoolConnection<Postgres>) -> anyhow::Result<()> {
    timeout_at(
        Instant::now() + MIGRATION_LOCK_DEADLINE,
        release_lock(connection),
    )
    .await
    .map_err(|_| anyhow::anyhow!("PostgreSQL migration unlock deadline exceeded"))?
}

async fn acquire_lock(
    connection: &mut PoolConnection<Postgres>,
    deadline: Instant,
) -> anyhow::Result<()> {
    loop {
        let acquired = match timeout_at(
            deadline,
            sqlx::query_scalar::<_, bool>("SELECT pg_try_advisory_lock($1)")
                .bind(MIGRATION_LOCK_KEY)
                .fetch_one(&mut **connection),
        )
        .await
        {
            Ok(result) => result.context("check migration lock")?,
            Err(_) => anyhow::bail!("PostgreSQL migration lock deadline exceeded"),
        };
        if acquired {
            return Ok(());
        }
        match timeout_at(deadline, tokio::time::sleep(Duration::from_millis(100))).await {
            Ok(()) => {}
            Err(_) => anyhow::bail!("PostgreSQL migration lock deadline exceeded"),
        }
    }
}

async fn release_lock(connection: &mut PoolConnection<Postgres>) -> anyhow::Result<()> {
    let released = sqlx::query_scalar::<_, bool>("SELECT pg_advisory_unlock($1)")
        .bind(MIGRATION_LOCK_KEY)
        .fetch_one(&mut **connection)
        .await
        .context("release migration lock query")?;
    if !released {
        anyhow::bail!("migration lock was not held by this connection");
    }
    Ok(())
}

async fn repair_invalid_indexes(
    connection: &mut PoolConnection<Postgres>,
    online_migrations_applied: bool,
) -> anyhow::Result<()> {
    let indexes = ONLINE_INDEXES
        .iter()
        .map(|(index, definition)| ((*index).to_owned(), (*definition).to_owned()))
        .collect::<Vec<_>>();
    for (index, definition) in indexes {
        let state = timeout_at(
            Instant::now() + ONLINE_MIGRATION_STEP_DEADLINE,
            sqlx::query_as::<_, (bool, bool)>(
                r#"
            SELECT i.indisvalid, i.indisready
            FROM pg_class c
            JOIN pg_index i ON i.indexrelid = c.oid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = $1
            "#,
            )
            .bind(&index)
            .fetch_optional(&mut **connection),
        )
        .await
        .map_err(|_| anyhow::anyhow!("check online index {index} timed out"))?
        .with_context(|| format!("check online index {index}"))?;
        let invalid = state.is_some_and(|(valid, ready)| !valid || !ready);
        if invalid {
            timeout_at(
                Instant::now() + ONLINE_MIGRATION_STEP_DEADLINE,
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "DROP INDEX CONCURRENTLY IF EXISTS public.\"{index}\""
                )))
                .execute(&mut **connection),
            )
            .await
            .map_err(|_| anyhow::anyhow!("drop invalid online index {index} timed out"))?
            .with_context(|| format!("drop invalid online index {index}"))?;
        }
        if online_migrations_applied && (invalid || state.is_none()) {
            timeout_at(
                Instant::now() + ONLINE_MIGRATION_STEP_DEADLINE,
                sqlx::query(sqlx::AssertSqlSafe(format!(
                    "CREATE INDEX CONCURRENTLY IF NOT EXISTS \"{index}\" ON public.{definition}"
                )))
                .execute(&mut **connection),
            )
            .await
            .map_err(|_| anyhow::anyhow!("recreate online index {index} timed out"))?
            .with_context(|| format!("recreate invalid online index {index}"))?;
        }
    }
    Ok(())
}
