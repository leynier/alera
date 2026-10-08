mod web;

use axum::{extract::State, Json};
use chrono::{DateTime, TimeDelta, Utc};
use rand::{rand_core::UnwrapErr, rngs::SysRng, Rng};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{
    api_models::{ClientKind, TokenEnvelope},
    auth::{
        create_session,
        validation::{hash_secret, random_secret, validate_label, validate_new_client_id},
    },
    error::ApiError,
    mcp_models::{
        DeviceAuthorizationResponse, DeviceTokenRequest, StartDeviceAuthorizationRequest,
    },
    state::AppState,
};

pub use web::{begin_confirm, page, page_form, submit_confirm};

pub const DEVICE_CODE_SECONDS: i64 = 600;
pub const POLL_INTERVAL_SECONDS: i64 = 5;
const USER_CODE_ALPHABET: &[u8; 32] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const USER_CODE_LENGTH: usize = 8;

#[derive(FromRow)]
struct DeviceRow {
    client_id: String,
    device_name: String,
    account_id: Option<Uuid>,
    status: String,
    poll_interval_seconds: i32,
    approved_at: Option<DateTime<Utc>>,
    last_polled_at: Option<DateTime<Utc>>,
    expires_at: DateTime<Utc>,
}

pub async fn start(
    State(state): State<AppState>,
    Json(request): Json<StartDeviceAuthorizationRequest>,
) -> Result<Json<DeviceAuthorizationResponse>, ApiError> {
    if request.client_kind != ClientKind::Runtime {
        return Err(ApiError::bad_request(
            "invalid_client_kind",
            "Device sign-in is available only to runtimes.",
        ));
    }
    validate_new_client_id(&request.client_id)?;
    validate_label(&request.device_name, "deviceName")?;
    // The request is unauthenticated and runtime ids are not secret, so a
    // runtime that still holds a session cannot be signed in again from here:
    // an approved code would hand its identity to whoever started the flow.
    let signed_in = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM refresh_token_families f
            JOIN refresh_tokens t ON t.family_id = f.id
            WHERE f.client_kind = 'runtime' AND f.client_id = $1
              AND f.revoked_at IS NULL AND f.absolute_expires_at > $2
              AND t.used_at IS NULL AND t.revoked_at IS NULL
              AND t.inactivity_expires_at > $2
        )
        "#,
    )
    .bind(&request.client_id)
    .bind(Utc::now())
    .fetch_one(&state.pool)
    .await?;
    if signed_in {
        return Err(ApiError::conflict(
            "runtime_already_signed_in",
            "This runtime is already signed in. Sign it out first, then try again.",
        ));
    }
    let device_code = random_secret("adc_");
    let now = Utc::now();
    let mut attempts = 0;
    let user_code = loop {
        attempts += 1;
        let user_code = generate_user_code();
        let inserted = sqlx::query(
            r#"
            INSERT INTO device_authorizations (
                id, device_code_hash, user_code, client_id, device_name, status,
                poll_interval_seconds, created_at, expires_at
            ) VALUES ($1, $2, $3, $4, $5, 'pending', $6, $7, $8)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(hash_secret(&device_code))
        .bind(&user_code)
        .bind(&request.client_id)
        .bind(request.device_name.trim())
        .bind(POLL_INTERVAL_SECONDS as i32)
        .bind(now)
        .bind(now + TimeDelta::seconds(DEVICE_CODE_SECONDS))
        .execute(&state.pool)
        .await;
        match inserted {
            Ok(_) => break user_code,
            Err(sqlx::Error::Database(error)) if error.is_unique_violation() && attempts < 3 => {}
            Err(error) => return Err(error.into()),
        }
    };
    let display = format_user_code(&user_code);
    let verification_uri = state.config.public_url("/device");
    Ok(Json(DeviceAuthorizationResponse {
        device_code,
        verification_uri_complete: format!("{verification_uri}?user_code={display}"),
        verification_uri,
        user_code: display,
        expires_in: DEVICE_CODE_SECONDS,
        interval: POLL_INTERVAL_SECONDS,
    }))
}

pub async fn token(
    State(state): State<AppState>,
    Json(request): Json<DeviceTokenRequest>,
) -> Result<Json<TokenEnvelope>, ApiError> {
    let invalid = || ApiError::bad_request("invalid_device_code", "The device code is invalid.");
    if !request.device_code.starts_with("adc_") || request.device_code.len() > 128 {
        return Err(invalid());
    }
    let device_code_hash = hash_secret(&request.device_code);
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let row = sqlx::query_as::<_, DeviceRow>(
        r#"
        SELECT client_id, device_name, account_id, status, poll_interval_seconds,
               approved_at, last_polled_at, expires_at
        FROM device_authorizations
        WHERE device_code_hash = $1
        FOR UPDATE
        "#,
    )
    .bind(&device_code_hash)
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(invalid)?;
    let minimum_gap = TimeDelta::seconds(i64::from(row.poll_interval_seconds) - 1);
    let too_fast = row
        .last_polled_at
        .is_some_and(|polled| now - polled < minimum_gap);
    let expired = row.expires_at <= now;
    let next_status = match (row.status.as_str(), row.account_id) {
        ("approved", Some(_)) if !expired => "consumed",
        (status, _) => status,
    };
    // A pending poll keeps the consent token: the confirmation page may be open
    // while the runtime polls, and clearing it would expire that form.
    sqlx::query(
        r#"
        UPDATE device_authorizations
        SET last_polled_at = $2, status = $3,
            consent_token_hash = CASE WHEN $3 = 'pending' THEN consent_token_hash ELSE NULL END
        WHERE device_code_hash = $1
        "#,
    )
    .bind(&device_code_hash)
    .bind(now)
    .bind(next_status)
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await?;
    let error = |code: &'static str, message: &str| Err(ApiError::bad_request(code, message));
    match (row.status.as_str(), row.account_id) {
        ("denied", _) => error("access_denied", "The sign-in request was denied."),
        ("consumed", _) => error("expired_token", "The device code was already used."),
        _ if expired => error("expired_token", "The device code expired."),
        ("approved", Some(account_id)) => {
            let envelope = create_session(
                &state.pool,
                &state.tokens,
                account_id,
                &row.client_id,
                ClientKind::Runtime,
                &row.device_name,
                row.approved_at.unwrap_or(now),
            )
            .await?;
            Ok(Json(envelope))
        }
        _ if too_fast => error("slow_down", "Poll the token endpoint less often."),
        _ => error(
            "authorization_pending",
            "The sign-in has not been approved yet.",
        ),
    }
}

pub async fn is_pending(state: &AppState, id: Uuid) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM device_authorizations
            WHERE id = $1 AND status = 'pending' AND expires_at > $2
        )
        "#,
    )
    .bind(id)
    .bind(Utc::now())
    .fetch_one(&state.pool)
    .await
}

pub fn generate_user_code() -> String {
    let mut bytes = [0_u8; USER_CODE_LENGTH];
    UnwrapErr(SysRng).fill_bytes(&mut bytes);
    bytes
        .iter()
        .map(|byte| char::from(USER_CODE_ALPHABET[usize::from(byte & 31)]))
        .collect()
}

/// Accepts a typed user code in any case, with or without the dash and spaces.
pub fn normalize_user_code(input: &str) -> Option<String> {
    let normalized: String = input
        .chars()
        .filter(|character| *character != '-' && !character.is_whitespace())
        .map(|character| character.to_ascii_uppercase())
        .collect();
    let valid = normalized.len() == USER_CODE_LENGTH
        && normalized
            .bytes()
            .all(|byte| USER_CODE_ALPHABET.contains(&byte));
    valid.then_some(normalized)
}

pub fn format_user_code(code: &str) -> String {
    let (first, second) = code.split_at(code.len().min(4));
    format!("{first}-{second}")
}

#[cfg(test)]
mod tests {
    use super::{format_user_code, generate_user_code, normalize_user_code};

    #[test]
    fn user_codes_use_an_unambiguous_alphabet() {
        for _ in 0..50 {
            let code = generate_user_code();
            assert_eq!(code.len(), 8);
            assert!(!code.contains(['0', '1', 'I', 'O']));
            assert_eq!(normalize_user_code(&code).as_deref(), Some(code.as_str()));
        }
    }

    #[test]
    fn user_codes_compare_ignoring_case_and_dash() {
        assert_eq!(format_user_code("ABCDEFGH"), "ABCD-EFGH");
        assert_eq!(
            normalize_user_code("abcd-efgh").as_deref(),
            Some("ABCDEFGH")
        );
        assert_eq!(
            normalize_user_code(" ABCD EFGH ").as_deref(),
            Some("ABCDEFGH")
        );
        assert!(normalize_user_code("ABCD-EFG").is_none());
        assert!(normalize_user_code("ABCD-EFG0").is_none());
        assert!(normalize_user_code("ABCD-EFGHJ").is_none());
    }
}
