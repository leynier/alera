use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    Json,
};
use chrono::{DateTime, TimeDelta, Utc};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use sqlx::{FromRow, PgPool, Row};
use uuid::Uuid;

use crate::{
    api_models::{
        AccountDetail, AccountSummary, AuthTransactionResponse, DeleteAccountRequest,
        IdentitySummary, LinkAccountRequest, MobileDeviceSummary, QuotaSummary, RuntimeSummary,
    },
    auth::{authenticate, create_link_transaction},
    error::ApiError,
    state::AppState,
};

#[derive(FromRow)]
struct IdentityRow {
    provider: String,
    email: String,
    email_verified: bool,
}

#[derive(FromRow)]
struct IdentityKeyRow {
    provider: String,
    provider_user_id: String,
}

#[derive(FromRow)]
struct RuntimeRow {
    id: String,
    name: String,
    last_seen_at: DateTime<Utc>,
}

#[derive(FromRow)]
struct MobileDeviceRow {
    id: String,
    name: String,
    last_seen_at: DateTime<Utc>,
}

pub async fn get_account(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<AccountDetail>, ApiError> {
    let auth = authenticate(&headers, &state, "account:read").await?;
    let account = load_account_summary(&state.pool, auth.account_id).await?;
    let runtimes = sqlx::query_as::<_, RuntimeRow>(
        "SELECT id, name, last_seen_at FROM runtimes WHERE account_id = $1 ORDER BY created_at",
    )
    .bind(auth.account_id)
    .fetch_all(&state.pool)
    .await?
    .into_iter()
    .map(|row| RuntimeSummary {
        id: row.id,
        name: row.name,
        last_seen_at: row.last_seen_at,
    })
    .collect();
    let mobile_devices = sqlx::query_as::<_, MobileDeviceRow>(
        r#"
        SELECT id, name, last_seen_at
        FROM mobile_devices
        WHERE account_id = $1 AND revoked_at IS NULL
        ORDER BY created_at
        "#,
    )
    .bind(auth.account_id)
    .fetch_all(&state.pool)
    .await?
    .into_iter()
    .map(|row| MobileDeviceSummary {
        id: row.id,
        name: row.name,
        last_seen_at: row.last_seen_at,
    })
    .collect();
    let daily_used = sqlx::query_scalar::<_, i32>(
        "SELECT count FROM push_quota_daily WHERE account_id = $1 AND day = CURRENT_DATE",
    )
    .bind(auth.account_id)
    .fetch_optional(&state.pool)
    .await?
    .unwrap_or_default();

    Ok(Json(AccountDetail {
        account,
        runtimes,
        mobile_devices,
        quota: QuotaSummary {
            daily_used,
            daily_limit: state.config.limits.push_daily,
            hourly_limit: state.config.limits.push_hourly,
            burst_limit: state.config.limits.push_burst,
        },
    }))
}

pub async fn link_account(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<LinkAccountRequest>,
) -> Result<Json<AuthTransactionResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "account:read").await?;
    Ok(Json(create_link_transaction(&state, &auth, request).await?))
}

pub async fn delete_account(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<DeleteAccountRequest>,
) -> Result<StatusCode, ApiError> {
    let auth = authenticate(&headers, &state, "account:read").await?;
    if request.confirmation != "DELETE" {
        return Err(ApiError::bad_request(
            "invalid_confirmation",
            "Account deletion requires the exact confirmation DELETE.",
        ));
    }
    if Utc::now() - auth.auth_time > TimeDelta::minutes(5) {
        return Err(ApiError::unauthorized(
            "recent_auth_required",
            "Sign in again before deleting the account.",
        ));
    }

    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let identities = sqlx::query_as::<_, IdentityKeyRow>(
        "SELECT provider, provider_user_id FROM account_identities WHERE account_id = $1",
    )
    .bind(auth.account_id)
    .fetch_all(&mut *transaction)
    .await?;
    for identity in identities {
        let subject_hash = identity_tombstone_hash(
            &state.config.tombstone_pepper,
            &identity.provider,
            &identity.provider_user_id,
        )?;
        sqlx::query(
            r#"
            INSERT INTO abuse_tombstones (
                id, subject_kind, subject_hash, reason, created_at, expires_at
            ) VALUES ($1, 'identity', $2, 'account_deleted', $3, $4)
            "#,
        )
        .bind(Uuid::now_v7())
        .bind(subject_hash)
        .bind(now)
        .bind(now + TimeDelta::days(90))
        .execute(&mut *transaction)
        .await?;
    }
    let result = sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(auth.account_id)
        .execute(&mut *transaction)
        .await?;
    if result.rows_affected() == 0 {
        return Err(ApiError::not_found(
            "account_not_found",
            "The Alera account no longer exists.",
        ));
    }
    transaction.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) fn identity_tombstone_hash(
    pepper: &str,
    provider: &str,
    provider_user_id: &str,
) -> Result<Vec<u8>, ApiError> {
    let mut mac = Hmac::<Sha256>::new_from_slice(pepper.as_bytes())
        .map_err(|error| ApiError::internal(anyhow::Error::msg(error.to_string())))?;
    mac.update(provider.as_bytes());
    mac.update(b":");
    mac.update(provider_user_id.as_bytes());
    Ok(mac.finalize().into_bytes().to_vec())
}

pub async fn load_account_summary(
    pool: &PgPool,
    account_id: Uuid,
) -> Result<AccountSummary, ApiError> {
    let row = sqlx::query(
        r#"
        SELECT primary_email
        FROM accounts
        WHERE id = $1 AND deleted_at IS NULL AND banned_at IS NULL
        "#,
    )
    .bind(account_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| {
        ApiError::unauthorized("account_unavailable", "The Alera account is unavailable.")
    })?;
    let identities = sqlx::query_as::<_, IdentityRow>(
        r#"
        SELECT provider, email, email_verified
        FROM account_identities
        WHERE account_id = $1
        ORDER BY linked_at
        "#,
    )
    .bind(account_id)
    .fetch_all(pool)
    .await?
    .into_iter()
    .map(|row| IdentitySummary {
        provider: row.provider,
        email: row.email,
        email_verified: row.email_verified,
    })
    .collect();
    Ok(AccountSummary {
        id: account_id,
        email: row.try_get("primary_email")?,
        identities,
    })
}
