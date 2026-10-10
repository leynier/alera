use std::{sync::Arc, time::Duration};

use alera_cloud::{
    api_models::ClientKind,
    auth::{create_session, rotate_session, TokenService},
    migrations,
    signing::LocalEd25519Signer,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::Utc;
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn migrations_and_refresh_replay_contract() -> anyhow::Result<()> {
    let database_url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&database_url)
        .await?;
    migrations::run_required(&pool).await?;
    let blocker = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    let migration_lock_key = 0x41_6c_65_72_61_53_78_i64;
    sqlx::query("SELECT pg_advisory_lock($1)")
        .bind(migration_lock_key)
        .execute(&blocker)
        .await?;
    tokio::time::timeout(Duration::from_secs(1), migrations::run_required(&pool)).await??;
    sqlx::query("SELECT pg_advisory_unlock($1)")
        .bind(migration_lock_key)
        .execute(&blocker)
        .await?;
    blocker.close().await;
    migrations::run(&pool).await?;
    sqlx::query(
        "INSERT INTO _sqlx_migrations (version, description, success, checksum, execution_time) VALUES (24, 'future-schema', true, decode('00', 'hex'), 0)",
    )
    .execute(&pool)
    .await?;
    let unclassified = match migrations::run_required(&pool).await {
        Ok(()) => anyhow::bail!("unclassified migration must block startup"),
        Err(error) => error,
    };
    assert!(format!("{unclassified:#}").contains("not classified"));
    sqlx::query("DELETE FROM _sqlx_migrations WHERE version = 24")
        .execute(&pool)
        .await?;
    migrations::run_required(&pool).await?;

    // A canceled concurrent build leaves an invalid index without a SQLx row.
    // Recreate that state and verify the next online pass repairs it and records
    // the original migration checksum.
    let expected_checksum =
        sqlx::query_scalar::<_, Vec<u8>>("SELECT checksum FROM _sqlx_migrations WHERE version = 5")
            .fetch_one(&pool)
            .await?;
    sqlx::query("DELETE FROM _sqlx_migrations WHERE version = 5")
        .execute(&pool)
        .await?;
    sqlx::query("DROP INDEX CONCURRENTLY IF EXISTS public.auth_transactions_expiry_idx")
        .execute(&pool)
        .await?;
    // Autovacuum would analyze the million rows inserted below while holding
    // the lock that CREATE INDEX CONCURRENTLY needs, so the 100ms timeout could
    // fire before the build creates its invalid index.
    sqlx::query("ALTER TABLE auth_transactions SET (autovacuum_enabled = false)")
        .execute(&pool)
        .await?;
    sqlx::query(
        r#"
        INSERT INTO auth_transactions (
            id, state_hash, provider, purpose, account_id, refresh_family_id,
            redirect_uri, code_challenge, nonce, client_id, client_kind,
            device_name, created_at, expires_at, used_at
        )
        SELECT
            gen_random_uuid(), decode(repeat('ab', 32), 'hex'), 'migration-contract',
            'test', NULL, NULL, 'https://example.test/callback', 'challenge',
            NULL, 'client', 'runtime', 'migration test', now(),
            now() + interval '1 day', NULL
        FROM generate_series(1, 1000000)
        "#,
    )
    .execute(&pool)
    .await?;
    let blocker_pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;
    let mut snapshot = blocker_pool.acquire().await?;
    sqlx::query("BEGIN").execute(&mut *snapshot).await?;
    sqlx::query("SELECT count(*) FROM auth_transactions")
        .execute(&mut *snapshot)
        .await?;
    let mut index_builder = pool.acquire().await?;
    index_builder.close_on_drop();
    sqlx::query("SET statement_timeout = '100ms'")
        .execute(&mut *index_builder)
        .await?;
    let interrupted = sqlx::query(
        "CREATE INDEX CONCURRENTLY auth_transactions_expiry_idx ON public.auth_transactions (expires_at)",
    )
    .execute(&mut *index_builder)
    .await;
    assert!(
        interrupted.is_err(),
        "test must cancel the concurrent build"
    );
    drop(index_builder);
    sqlx::query("ROLLBACK").execute(&mut *snapshot).await?;
    drop(snapshot);
    blocker_pool.close().await;
    let invalid_state = sqlx::query_as::<_, (bool, bool)>(
        r#"
        SELECT i.indisvalid, i.indisready
        FROM pg_class c
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE c.relname = 'auth_transactions_expiry_idx'
        "#,
    )
    .fetch_optional(&pool)
    .await?;
    assert!(matches!(invalid_state, Some((false, _))));
    sqlx::query("ALTER TABLE auth_transactions RESET (autovacuum_enabled)")
        .execute(&pool)
        .await?;
    migrations::run_online(&pool).await?;
    let repaired_state = sqlx::query_as::<_, (bool, bool)>(
        r#"
        SELECT i.indisvalid, i.indisready
        FROM pg_class c
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE c.relname = 'auth_transactions_expiry_idx'
        "#,
    )
    .fetch_one(&pool)
    .await?;
    assert_eq!(repaired_state, (true, true));
    let (success, checksum) = sqlx::query_as::<_, (bool, Vec<u8>)>(
        "SELECT success, checksum FROM _sqlx_migrations WHERE version = 5",
    )
    .fetch_one(&pool)
    .await?;
    assert!(success);
    assert_eq!(checksum, expected_checksum);
    sqlx::query("DELETE FROM auth_transactions WHERE provider = 'migration-contract'")
        .execute(&pool)
        .await?;
    sqlx::query("UPDATE _sqlx_migrations SET success = false WHERE version = 5")
        .execute(&pool)
        .await?;
    migrations::run_required(&pool).await?;
    let dirty_online = match migrations::run_online(&pool).await {
        Ok(()) => anyhow::bail!("dirty online migration must require operator repair"),
        Err(error) => error,
    };
    assert!(format!("{dirty_online:#}").contains("dirty"));
    sqlx::query("UPDATE _sqlx_migrations SET success = true WHERE version = 5")
        .execute(&pool)
        .await?;
    migrations::run_online(&pool).await?;
    sqlx::query("UPDATE _sqlx_migrations SET success = false WHERE version = 1")
        .execute(&pool)
        .await?;
    let dirty_required = match migrations::run_required(&pool).await {
        Ok(()) => anyhow::bail!("dirty required migration must fail startup"),
        Err(error) => error,
    };
    assert!(format!("{dirty_required:#}").contains("partially applied"));
    sqlx::query("UPDATE _sqlx_migrations SET success = true WHERE version = 1")
        .execute(&pool)
        .await?;
    migrations::run_required(&pool).await?;

    let account_id = Uuid::now_v7();
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO accounts (
            id, primary_email, created_at, updated_at, last_seen_at
        ) VALUES ($1, $2, $3, $3, $3)
        "#,
    )
    .bind(account_id)
    .bind(format!("{account_id}@example.test"))
    .bind(now)
    .execute(&pool)
    .await?;
    let signer = LocalEd25519Signer::from_seed_b64url(
        "postgres-test".to_owned(),
        &URL_SAFE_NO_PAD.encode([17_u8; 32]),
    )?;
    let tokens = TokenService::new(
        Arc::new(signer),
        "https://issuer.test".to_owned(),
        "alera-cloud".to_owned(),
    );
    let initial = create_session(
        &pool,
        &tokens,
        account_id,
        "runtime-test",
        ClientKind::Runtime,
        "Runtime Test",
        now,
    )
    .await?;
    let rotated = rotate_session(&pool, &tokens, &initial.refresh_token).await?;
    let replay = rotate_session(&pool, &tokens, &initial.refresh_token).await;
    assert!(replay.is_err());
    let revoked_family = rotate_session(&pool, &tokens, &rotated.refresh_token).await;
    assert!(revoked_family.is_err());

    sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(account_id)
        .execute(&pool)
        .await?;
    pool.close().await;
    Ok(())
}
