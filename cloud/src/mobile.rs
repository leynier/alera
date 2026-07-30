use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::{DateTime, TimeDelta, Utc};
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{
    api_models::{
        ClientKind, CreateEnrollmentRequest, EnrollmentResponse, MobileEnrollmentTokenResponse,
        PushTokenRequest, PushTokenResponse, RedeemEnrollmentRequest, SubscriptionResponse,
        UpsertSubscriptionRequest,
    },
    auth::{authenticate, create_session},
    error::ApiError,
    state::AppState,
};

#[derive(FromRow)]
struct EnrollmentRow {
    account_id: Uuid,
    runtime_id: String,
    device_id: String,
    expires_at: DateTime<Utc>,
    redeemed_at: Option<DateTime<Utc>>,
}

pub async fn create_enrollment(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateEnrollmentRequest>,
) -> Result<Json<EnrollmentResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "enrollment:write").await?;
    validate_id(&request.runtime_id, "runtimeId")?;
    validate_id(&request.device_id, "deviceId")?;
    validate_name(&request.device_name)?;
    if auth.client_kind != ClientKind::Runtime
        || auth.client_id != request.runtime_id
        || !runtime_belongs_to(&state, auth.account_id, &request.runtime_id).await?
    {
        return Err(ApiError::forbidden(
            "runtime_not_owned",
            "The runtime does not belong to this account session.",
        ));
    }

    let code = random_enrollment_code();
    let now = Utc::now();
    let expires_at = now + TimeDelta::minutes(5);
    sqlx::query(
        r#"
        INSERT INTO mobile_enrollments (
            id, code_hash, account_id, runtime_id, device_id, device_name,
            created_at, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(Uuid::now_v7())
    .bind(hash_secret(&code))
    .bind(auth.account_id)
    .bind(&request.runtime_id)
    .bind(&request.device_id)
    .bind(&request.device_name)
    .bind(now)
    .bind(expires_at)
    .execute(&state.pool)
    .await?;

    Ok(Json(EnrollmentResponse {
        code,
        expires_at,
        runtime_id: request.runtime_id,
        account_id: auth.account_id,
    }))
}

pub async fn redeem_enrollment(
    State(state): State<AppState>,
    Json(request): Json<RedeemEnrollmentRequest>,
) -> Result<Json<MobileEnrollmentTokenResponse>, ApiError> {
    validate_enrollment_code(&request.code)?;
    validate_id(&request.device_id, "deviceId")?;
    validate_name(&request.device_name)?;
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let enrollment = sqlx::query_as::<_, EnrollmentRow>(
        r#"
        SELECT account_id, runtime_id, device_id, expires_at, redeemed_at
        FROM mobile_enrollments
        WHERE code_hash = $1
        FOR UPDATE
        "#,
    )
    .bind(hash_secret(&request.code))
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(|| {
        ApiError::bad_request("invalid_enrollment", "The enrollment code is invalid.")
    })?;
    if enrollment.redeemed_at.is_some() {
        return Err(ApiError::bad_request(
            "enrollment_used",
            "The enrollment code was already used.",
        ));
    }
    if enrollment.expires_at <= now {
        return Err(ApiError::bad_request(
            "enrollment_expired",
            "The enrollment code expired.",
        ));
    }
    if enrollment.device_id != request.device_id {
        return Err(ApiError::forbidden(
            "enrollment_device_mismatch",
            "The enrollment belongs to a different mobile installation.",
        ));
    }
    let existing = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM mobile_devices
            WHERE account_id = $1 AND id = $2 AND revoked_at IS NULL
        )
        "#,
    )
    .bind(enrollment.account_id)
    .bind(&request.device_id)
    .fetch_one(&mut *transaction)
    .await?;
    if !existing {
        sqlx::query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE")
            .bind(enrollment.account_id)
            .fetch_one(&mut *transaction)
            .await?;
        let count = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM mobile_devices WHERE account_id = $1 AND revoked_at IS NULL",
        )
        .bind(enrollment.account_id)
        .fetch_one(&mut *transaction)
        .await?;
        if count >= state.config.limits.max_mobile_devices_per_account {
            return Err(ApiError::forbidden(
                "mobile_device_limit_reached",
                "This account has reached its mobile installation limit.",
            ));
        }
    }
    sqlx::query(
        r#"
        INSERT INTO mobile_devices (
            account_id, id, name, created_at, last_seen_at
        ) VALUES ($1, $2, $3, $4, $4)
        ON CONFLICT (account_id, id) DO UPDATE
        SET name = EXCLUDED.name, last_seen_at = EXCLUDED.last_seen_at, revoked_at = NULL
        "#,
    )
    .bind(enrollment.account_id)
    .bind(&request.device_id)
    .bind(&request.device_name)
    .bind(now)
    .execute(&mut *transaction)
    .await?;
    sqlx::query("UPDATE mobile_enrollments SET redeemed_at = $2 WHERE code_hash = $1")
        .bind(hash_secret(&request.code))
        .bind(now)
        .execute(&mut *transaction)
        .await?;
    transaction.commit().await?;

    let tokens = create_session(
        &state.pool,
        &state.tokens,
        enrollment.account_id,
        &request.device_id,
        ClientKind::Mobile,
        &request.device_name,
        now,
    )
    .await?;
    Ok(Json(MobileEnrollmentTokenResponse {
        runtime_id: enrollment.runtime_id,
        tokens,
    }))
}

pub async fn put_push_token(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<PushTokenRequest>,
) -> Result<Json<PushTokenResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "push:register").await?;
    require_mobile_device(&state, auth.account_id, &auth.client_id).await?;
    validate_fcm_token(&request.token)?;
    let token_hash = hash_secret(&request.token);
    let tombstoned = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM abuse_tombstones
            WHERE subject_kind = 'fcm_token' AND subject_hash = $1 AND expires_at > $2
        )
        "#,
    )
    .bind(&token_hash)
    .bind(Utc::now())
    .fetch_one(&state.pool)
    .await?;
    if tombstoned {
        return Err(ApiError::conflict(
            "fcm_token_unregistered",
            "FCM previously reported this registration token as unregistered.",
        ));
    }
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO fcm_tokens (
            account_id, mobile_device_id, token, token_hash, platform,
            registered_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $6)
        ON CONFLICT (account_id, mobile_device_id) DO UPDATE
        SET token = EXCLUDED.token,
            token_hash = EXCLUDED.token_hash,
            platform = EXCLUDED.platform,
            updated_at = EXCLUDED.updated_at
        "#,
    )
    .bind(auth.account_id)
    .bind(&auth.client_id)
    .bind(&request.token)
    .bind(token_hash)
    .bind(request.platform.as_str())
    .bind(now)
    .execute(&state.pool)
    .await?;
    Ok(Json(PushTokenResponse { registered_at: now }))
}

pub async fn delete_push_token(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<StatusCode, ApiError> {
    let auth = authenticate(&headers, &state, "push:register").await?;
    sqlx::query("DELETE FROM fcm_tokens WHERE account_id = $1 AND mobile_device_id = $2")
        .bind(auth.account_id)
        .bind(&auth.client_id)
        .execute(&state.pool)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn put_subscription(
    State(state): State<AppState>,
    Path(runtime_id): Path<String>,
    headers: HeaderMap,
    Json(request): Json<UpsertSubscriptionRequest>,
) -> Result<Json<SubscriptionResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "subscription:write").await?;
    require_mobile_device(&state, auth.account_id, &auth.client_id).await?;
    if !runtime_belongs_to(&state, auth.account_id, &runtime_id).await? {
        return Err(ApiError::not_found(
            "runtime_not_found",
            "The runtime is not part of this account.",
        ));
    }
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO push_subscriptions (
            account_id, mobile_device_id, runtime_id,
            attention, done, terminal_exit, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
        ON CONFLICT (account_id, mobile_device_id, runtime_id) DO UPDATE
        SET attention = EXCLUDED.attention,
            done = EXCLUDED.done,
            terminal_exit = EXCLUDED.terminal_exit,
            updated_at = EXCLUDED.updated_at
        "#,
    )
    .bind(auth.account_id)
    .bind(&auth.client_id)
    .bind(&runtime_id)
    .bind(request.categories.attention)
    .bind(request.categories.done)
    .bind(request.categories.terminal_exit)
    .bind(now)
    .execute(&state.pool)
    .await?;
    Ok(Json(SubscriptionResponse {
        runtime_id,
        categories: request.categories,
        updated_at: now,
    }))
}

pub async fn delete_subscription(
    State(state): State<AppState>,
    Path(runtime_id): Path<String>,
    headers: HeaderMap,
) -> Result<StatusCode, ApiError> {
    let auth = authenticate(&headers, &state, "subscription:write").await?;
    sqlx::query(
        r#"
        DELETE FROM push_subscriptions
        WHERE account_id = $1 AND mobile_device_id = $2 AND runtime_id = $3
        "#,
    )
    .bind(auth.account_id)
    .bind(&auth.client_id)
    .bind(runtime_id)
    .execute(&state.pool)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn runtime_belongs_to(
    state: &AppState,
    account_id: Uuid,
    runtime_id: &str,
) -> Result<bool, ApiError> {
    Ok(sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM runtimes WHERE id = $1 AND account_id = $2)",
    )
    .bind(runtime_id)
    .bind(account_id)
    .fetch_one(&state.pool)
    .await?)
}

async fn require_mobile_device(
    state: &AppState,
    account_id: Uuid,
    device_id: &str,
) -> Result<(), ApiError> {
    let exists = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM mobile_devices
            WHERE account_id = $1 AND id = $2 AND revoked_at IS NULL
        )
        "#,
    )
    .bind(account_id)
    .bind(device_id)
    .fetch_one(&state.pool)
    .await?;
    if !exists {
        return Err(ApiError::unauthorized(
            "mobile_device_revoked",
            "The mobile installation is no longer active.",
        ));
    }
    Ok(())
}

fn validate_id(value: &str, field: &str) -> Result<(), ApiError> {
    if value.is_empty() || value.len() > 128 || value.chars().any(char::is_control) {
        return Err(ApiError::bad_request(
            "invalid_identifier",
            format!("{field} is invalid."),
        ));
    }
    Ok(())
}

fn validate_name(value: &str) -> Result<(), ApiError> {
    if value.trim().is_empty() || value.len() > 160 || value.chars().any(char::is_control) {
        return Err(ApiError::bad_request(
            "invalid_device_name",
            "deviceName is invalid.",
        ));
    }
    Ok(())
}

fn validate_fcm_token(value: &str) -> Result<(), ApiError> {
    if value.len() < 20 || value.len() > 4096 || value.chars().any(char::is_whitespace) {
        return Err(ApiError::bad_request(
            "invalid_fcm_token",
            "The FCM registration token is invalid.",
        ));
    }
    Ok(())
}

fn validate_enrollment_code(value: &str) -> Result<(), ApiError> {
    if value.len() < 40 || value.len() > 128 || !value.starts_with("ame_") {
        return Err(ApiError::bad_request(
            "invalid_enrollment",
            "The enrollment code is invalid.",
        ));
    }
    Ok(())
}

fn random_enrollment_code() -> String {
    let mut bytes = [0_u8; 32];
    OsRng.fill_bytes(&mut bytes);
    format!("ame_{}", URL_SAFE_NO_PAD.encode(bytes))
}

fn hash_secret(value: &str) -> Vec<u8> {
    Sha256::digest(value.as_bytes()).to_vec()
}

#[cfg(test)]
mod tests {
    use super::{random_enrollment_code, validate_enrollment_code, validate_fcm_token};

    #[test]
    fn enrollment_codes_have_valid_shape() {
        let code = random_enrollment_code();
        assert!(validate_enrollment_code(&code).is_ok());
    }

    #[test]
    fn rejects_short_or_whitespace_fcm_tokens() {
        assert!(validate_fcm_token("short").is_err());
        assert!(validate_fcm_token(&format!("{} token", "x".repeat(30))).is_err());
        assert!(validate_fcm_token(&"x".repeat(100)).is_ok());
    }
}
