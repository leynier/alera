use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::state::AppState;

pub(crate) async fn remove_unregistered_token(
    state: &AppState,
    account_id: Uuid,
    device_id: &str,
    token: &str,
) -> Result<(), sqlx::Error> {
    let now = chrono::Utc::now();
    let mut transaction = state.pool.begin().await?;
    sqlx::query(
        "DELETE FROM fcm_tokens WHERE account_id = $1 AND mobile_device_id = $2 AND token = $3",
    )
    .bind(account_id)
    .bind(device_id)
    .bind(token)
    .execute(&mut *transaction)
    .await?;
    sqlx::query(
        r#"
        INSERT INTO abuse_tombstones (
            id, subject_kind, subject_hash, reason, created_at, expires_at
        ) VALUES ($1, 'fcm_token', $2, 'unregistered', $3, $4)
        "#,
    )
    .bind(Uuid::now_v7())
    .bind(Sha256::digest(token.as_bytes()).to_vec())
    .bind(now)
    .bind(now + chrono::TimeDelta::days(30))
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await
}
