use std::sync::Arc;

use alera_cloud::{
    api_models::ClientKind,
    auth::{create_session, rotate_session, TokenService},
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
    sqlx::migrate!("./migrations").run(&pool).await?;

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
