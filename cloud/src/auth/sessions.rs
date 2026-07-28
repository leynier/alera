use chrono::{DateTime, TimeDelta, Utc};
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

use crate::{
    accounts::load_account_summary,
    api_models::{ClientKind, ClientSummary, TokenEnvelope},
    error::ApiError,
};

use super::TokenService;

const INACTIVITY_DAYS: i64 = 30;
const ABSOLUTE_DAYS: i64 = 365;

#[derive(FromRow)]
struct SessionRow {
    token_id: Uuid,
    family_id: Uuid,
    account_id: Uuid,
    client_id: String,
    client_kind: String,
    authenticated_at: DateTime<Utc>,
    absolute_expires_at: DateTime<Utc>,
    family_revoked_at: Option<DateTime<Utc>>,
    inactivity_expires_at: DateTime<Utc>,
    used_at: Option<DateTime<Utc>>,
    token_revoked_at: Option<DateTime<Utc>>,
}

struct SessionDescriptor<'a> {
    account_id: Uuid,
    family_id: Uuid,
    client_id: &'a str,
    client_kind: ClientKind,
    authenticated_at: DateTime<Utc>,
}

pub async fn create_session(
    pool: &PgPool,
    tokens: &TokenService,
    account_id: Uuid,
    client_id: &str,
    client_kind: ClientKind,
    label: &str,
    authenticated_at: DateTime<Utc>,
) -> Result<TokenEnvelope, ApiError> {
    let now = Utc::now();
    let family_id = Uuid::now_v7();
    let token_id = Uuid::now_v7();
    let refresh_token = random_refresh_token();
    let token_hash = hash_secret(&refresh_token);
    let absolute_expires_at = now + TimeDelta::days(ABSOLUTE_DAYS);
    let inactivity_expires_at = now + TimeDelta::days(INACTIVITY_DAYS);
    let mut transaction = pool.begin().await?;
    sqlx::query(
        r#"
        INSERT INTO refresh_token_families (
            id, account_id, client_id, client_kind, label, authenticated_at,
            created_at, last_used_at, absolute_expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8)
        "#,
    )
    .bind(family_id)
    .bind(account_id)
    .bind(client_id)
    .bind(client_kind.as_str())
    .bind(label)
    .bind(authenticated_at)
    .bind(now)
    .bind(absolute_expires_at)
    .execute(&mut *transaction)
    .await?;
    sqlx::query(
        r#"
        INSERT INTO refresh_tokens (
            id, family_id, token_hash, issued_at, inactivity_expires_at
        ) VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(token_id)
    .bind(family_id)
    .bind(token_hash)
    .bind(now)
    .bind(inactivity_expires_at)
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await?;

    envelope(
        pool,
        tokens,
        SessionDescriptor {
            account_id,
            family_id,
            client_id,
            client_kind,
            authenticated_at,
        },
        refresh_token,
    )
    .await
}

pub async fn rotate_session(
    pool: &PgPool,
    tokens: &TokenService,
    refresh_token: &str,
) -> Result<TokenEnvelope, ApiError> {
    validate_refresh_token(refresh_token)?;
    let token_hash = hash_secret(refresh_token);
    let now = Utc::now();
    let mut transaction = pool.begin().await?;
    let row = sqlx::query_as::<_, SessionRow>(
        r#"
        SELECT
            t.id AS token_id,
            t.family_id,
            f.account_id,
            f.client_id,
            f.client_kind,
            f.authenticated_at,
            f.absolute_expires_at,
            f.revoked_at AS family_revoked_at,
            t.inactivity_expires_at,
            t.used_at,
            t.revoked_at AS token_revoked_at
        FROM refresh_tokens t
        JOIN refresh_token_families f ON f.id = t.family_id
        WHERE t.token_hash = $1
        FOR UPDATE
        "#,
    )
    .bind(token_hash)
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(|| {
        ApiError::unauthorized("invalid_refresh_token", "The refresh token is invalid.")
    })?;

    let replayed = row.used_at.is_some();
    let expired = row.inactivity_expires_at <= now || row.absolute_expires_at <= now;
    if replayed || expired || row.family_revoked_at.is_some() || row.token_revoked_at.is_some() {
        if replayed && row.family_revoked_at.is_none() {
            sqlx::query(
                "UPDATE refresh_token_families SET revoked_at = $2, revoke_reason = $3 WHERE id = $1",
            )
            .bind(row.family_id)
            .bind(now)
            .bind("refresh_token_replay")
            .execute(&mut *transaction)
            .await?;
        }
        transaction.commit().await?;
        let (code, message) = if replayed {
            (
                "refresh_token_reuse",
                "Refresh token reuse revoked the entire session.",
            )
        } else {
            ("refresh_token_expired", "The account session has expired.")
        };
        return Err(ApiError::unauthorized(code, message));
    }

    let new_token_id = Uuid::now_v7();
    let new_refresh_token = random_refresh_token();
    let inactivity_expires_at =
        (now + TimeDelta::days(INACTIVITY_DAYS)).min(row.absolute_expires_at);
    sqlx::query(
        r#"
        INSERT INTO refresh_tokens (
            id, family_id, token_hash, issued_at, inactivity_expires_at
        ) VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(new_token_id)
    .bind(row.family_id)
    .bind(hash_secret(&new_refresh_token))
    .bind(now)
    .bind(inactivity_expires_at)
    .execute(&mut *transaction)
    .await?;
    sqlx::query("UPDATE refresh_tokens SET used_at = $2, replaced_by_id = $3 WHERE id = $1")
        .bind(row.token_id)
        .bind(now)
        .bind(new_token_id)
        .execute(&mut *transaction)
        .await?;
    sqlx::query("UPDATE refresh_token_families SET last_used_at = $2 WHERE id = $1")
        .bind(row.family_id)
        .bind(now)
        .execute(&mut *transaction)
        .await?;
    transaction.commit().await?;
    let client_kind = row.client_kind.parse()?;
    envelope(
        pool,
        tokens,
        SessionDescriptor {
            account_id: row.account_id,
            family_id: row.family_id,
            client_id: &row.client_id,
            client_kind,
            authenticated_at: row.authenticated_at,
        },
        new_refresh_token,
    )
    .await
}

pub async fn revoke_by_refresh_token(
    pool: &PgPool,
    refresh_token: &str,
    reason: &str,
) -> Result<(), ApiError> {
    validate_refresh_token(refresh_token)?;
    sqlx::query(
        r#"
        UPDATE refresh_token_families f
        SET revoked_at = COALESCE(f.revoked_at, $2), revoke_reason = COALESCE(f.revoke_reason, $3)
        FROM refresh_tokens t
        WHERE t.family_id = f.id AND t.token_hash = $1
        "#,
    )
    .bind(hash_secret(refresh_token))
    .bind(Utc::now())
    .bind(reason)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn revoke_family(pool: &PgPool, family_id: Uuid, reason: &str) -> Result<(), ApiError> {
    sqlx::query(
        r#"
        UPDATE refresh_token_families
        SET revoked_at = COALESCE(revoked_at, $2), revoke_reason = COALESCE(revoke_reason, $3)
        WHERE id = $1
        "#,
    )
    .bind(family_id)
    .bind(Utc::now())
    .bind(reason)
    .execute(pool)
    .await?;
    Ok(())
}

async fn envelope(
    pool: &PgPool,
    tokens: &TokenService,
    session: SessionDescriptor<'_>,
    refresh_token: String,
) -> Result<TokenEnvelope, ApiError> {
    let account = load_account_summary(pool, session.account_id).await?;
    let access_token = tokens
        .issue(
            session.account_id,
            session.family_id,
            session.client_id,
            session.client_kind,
            session.authenticated_at,
        )
        .await?;
    Ok(TokenEnvelope {
        access_token,
        refresh_token,
        token_type: "Bearer",
        expires_in: tokens.expires_in_seconds(),
        account,
        client: ClientSummary {
            id: session.client_id.to_owned(),
            kind: session.client_kind.as_str().to_owned(),
        },
    })
}

pub fn hash_secret(value: &str) -> Vec<u8> {
    Sha256::digest(value.as_bytes()).to_vec()
}

fn random_refresh_token() -> String {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};

    let mut bytes = [0_u8; 32];
    OsRng.fill_bytes(&mut bytes);
    format!("art_{}", URL_SAFE_NO_PAD.encode(bytes))
}

fn validate_refresh_token(value: &str) -> Result<(), ApiError> {
    if value.len() < 40 || value.len() > 128 || !value.starts_with("art_") {
        return Err(ApiError::unauthorized(
            "invalid_refresh_token",
            "The refresh token is invalid.",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{hash_secret, random_refresh_token, validate_refresh_token};

    #[test]
    fn refresh_tokens_are_prefixed_random_values() {
        let first = random_refresh_token();
        let second = random_refresh_token();
        assert_ne!(first, second);
        assert!(validate_refresh_token(&first).is_ok());
        assert_ne!(hash_secret(&first), hash_secret(&second));
    }

    #[test]
    fn malformed_refresh_tokens_are_rejected() {
        assert!(validate_refresh_token("short").is_err());
        assert!(validate_refresh_token(&format!("wrong_{}", "a".repeat(50))).is_err());
    }
}
