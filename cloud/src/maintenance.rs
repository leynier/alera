use std::time::Duration;

use chrono::{TimeDelta, Utc};
use sqlx::PgPool;

pub async fn run_once(pool: &PgPool) -> Result<(), sqlx::Error> {
    let now = Utc::now();
    let mut transaction = pool.begin().await?;
    sqlx::query("DELETE FROM auth_transactions WHERE expires_at < $1")
        .bind(now - TimeDelta::days(1))
        .execute(&mut *transaction)
        .await?;
    sqlx::query("DELETE FROM mobile_enrollments WHERE expires_at < $1")
        .bind(now - TimeDelta::days(1))
        .execute(&mut *transaction)
        .await?;
    sqlx::query(
        r#"
        DELETE FROM refresh_token_families
        WHERE absolute_expires_at < $1
           OR (revoked_at IS NOT NULL AND revoked_at < $1)
           OR (
               NOT EXISTS (
                   SELECT 1 FROM refresh_tokens t
                   WHERE t.family_id = refresh_token_families.id
                     AND t.inactivity_expires_at >= $2
               )
               AND last_used_at < $1
           )
        "#,
    )
    .bind(now - TimeDelta::days(30))
    .bind(now)
    .execute(&mut *transaction)
    .await?;
    sqlx::query("DELETE FROM runtime_events WHERE created_at < $1")
        .bind(now - TimeDelta::days(30))
        .execute(&mut *transaction)
        .await?;
    sqlx::query("DELETE FROM push_quota_hourly WHERE hour < $1")
        .bind(now - TimeDelta::days(7))
        .execute(&mut *transaction)
        .await?;
    sqlx::query("DELETE FROM push_quota_bursts WHERE window_start < $1")
        .bind(now - TimeDelta::days(7))
        .execute(&mut *transaction)
        .await?;
    sqlx::query("DELETE FROM push_quota_daily WHERE day < $1")
        .bind((now - TimeDelta::days(90)).date_naive())
        .execute(&mut *transaction)
        .await?;
    sqlx::query("DELETE FROM abuse_tombstones WHERE expires_at < $1")
        .bind(now)
        .execute(&mut *transaction)
        .await?;
    transaction.commit().await
}

pub fn spawn(pool: PgPool) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(6 * 60 * 60));
        interval.tick().await;
        loop {
            interval.tick().await;
            if let Err(error) = run_once(&pool).await {
                tracing::warn!(error = %error, "scheduled database cleanup failed");
            }
        }
    })
}
