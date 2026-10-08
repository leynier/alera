use axum::{extract::State, http::HeaderMap, Json};
use chrono::Utc;
use sqlx::Row;

use crate::{
    api_models::{ClientKind, TransferRuntimeRequest, TransferRuntimeResponse},
    auth::authenticate,
    error::ApiError,
    mcp_models::{RenameRuntimeRequest, RenameRuntimeResponse, RuntimeCapabilitiesRequest},
    state::AppState,
};

pub async fn transfer_runtime(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<TransferRuntimeRequest>,
) -> Result<Json<TransferRuntimeResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "runtime:write").await?;
    if auth.client_kind != ClientKind::Runtime
        || auth.client_id != request.runtime_id
        || request.confirmation != request.runtime_id
    {
        return Err(ApiError::forbidden(
            "runtime_transfer_not_confirmed",
            "The runtime transfer was not explicitly confirmed by its owner.",
        ));
    }
    if request.target_account_id == auth.account_id {
        return Err(ApiError::bad_request(
            "runtime_transfer_same_account",
            "The runtime already belongs to the target account.",
        ));
    }

    let mut transaction = state.pool.begin().await?;
    let current_owner = sqlx::query("SELECT account_id FROM runtimes WHERE id = $1 FOR UPDATE")
        .bind(&request.runtime_id)
        .fetch_optional(&mut *transaction)
        .await?
        .ok_or_else(|| ApiError::not_found("runtime_not_found", "The runtime does not exist."))?;
    let current_owner: uuid::Uuid = current_owner.try_get("account_id")?;
    if current_owner != auth.account_id {
        return Err(ApiError::forbidden(
            "runtime_not_owned",
            "The runtime belongs to another account.",
        ));
    }
    let target_exists = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM accounts
            WHERE id = $1 AND banned_at IS NULL AND deleted_at IS NULL
        )
        "#,
    )
    .bind(request.target_account_id)
    .fetch_one(&mut *transaction)
    .await?;
    if !target_exists {
        return Err(ApiError::not_found(
            "target_account_not_found",
            "The target account is unavailable.",
        ));
    }
    sqlx::query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE")
        .bind(request.target_account_id)
        .fetch_one(&mut *transaction)
        .await?;
    let target_count =
        sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM runtimes WHERE account_id = $1")
            .bind(request.target_account_id)
            .fetch_one(&mut *transaction)
            .await?;
    if target_count >= state.config.limits.max_runtimes_per_account {
        return Err(ApiError::forbidden(
            "runtime_limit_reached",
            "The target account has reached its runtime limit.",
        ));
    }

    sqlx::query("DELETE FROM mobile_enrollments WHERE runtime_id = $1")
        .bind(&request.runtime_id)
        .execute(&mut *transaction)
        .await?;
    sqlx::query("DELETE FROM push_subscriptions WHERE runtime_id = $1")
        .bind(&request.runtime_id)
        .execute(&mut *transaction)
        .await?;
    sqlx::query(
        r#"
        UPDATE refresh_token_families
        SET revoked_at = COALESCE(revoked_at, $3),
            revoke_reason = COALESCE(revoke_reason, 'runtime_transferred')
        WHERE account_id = $1 AND client_kind = 'runtime' AND client_id = $2
        "#,
    )
    .bind(auth.account_id)
    .bind(&request.runtime_id)
    .bind(Utc::now())
    .execute(&mut *transaction)
    .await?;
    sqlx::query(
        "UPDATE runtimes SET account_id = $2, transferred_at = $3, last_seen_at = $3 WHERE id = $1",
    )
    .bind(&request.runtime_id)
    .bind(request.target_account_id)
    .bind(Utc::now())
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await?;

    Ok(Json(TransferRuntimeResponse {
        runtime_id: request.runtime_id,
        previous_account_id: auth.account_id,
        account_id: request.target_account_id,
        reauthentication_required: true,
    }))
}

const MAX_RUNTIME_NAME_CHARS: usize = 64;

pub fn normalize_runtime_name(value: &str) -> Result<String, ApiError> {
    let name = value.trim();
    let length = name.chars().count();
    // Sign-in sends the same name as a label, which is capped at 160 bytes.
    if length == 0
        || length > MAX_RUNTIME_NAME_CHARS
        || name.len() > 160
        || name.chars().any(char::is_control)
    {
        return Err(ApiError::bad_request(
            "invalid_runtime_name",
            "Runtime names must contain 1 to 64 characters.",
        ));
    }
    Ok(name.to_owned())
}

pub async fn rename_runtime(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RenameRuntimeRequest>,
) -> Result<Json<RenameRuntimeResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "runtime:write").await?;
    if auth.client_kind != ClientKind::Runtime {
        return Err(ApiError::forbidden(
            "runtime_session_required",
            "Only the runtime itself can change its name.",
        ));
    }
    let name = normalize_runtime_name(&request.name)?;
    let mut transaction = state.pool.begin().await?;
    // Locking the account row serializes renames so two runtimes cannot claim one name.
    sqlx::query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE")
        .bind(auth.account_id)
        .fetch_optional(&mut *transaction)
        .await?;
    let taken = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM runtimes
            WHERE account_id = $1 AND id <> $2 AND transferred_at IS NULL
              AND LOWER(name) = LOWER($3)
        )
        "#,
    )
    .bind(auth.account_id)
    .bind(&auth.client_id)
    .bind(&name)
    .fetch_one(&mut *transaction)
    .await?;
    if taken {
        return Err(ApiError::conflict(
            "runtime_name_taken",
            "Another runtime on this account already uses that name.",
        ));
    }
    let updated = sqlx::query("UPDATE runtimes SET name = $3 WHERE id = $1 AND account_id = $2")
        .bind(&auth.client_id)
        .bind(auth.account_id)
        .bind(&name)
        .execute(&mut *transaction)
        .await?
        .rows_affected();
    if updated == 0 {
        return Err(ApiError::not_found(
            "runtime_not_found",
            "The runtime is not registered to this account.",
        ));
    }
    transaction.commit().await?;
    Ok(Json(RenameRuntimeResponse {
        id: auth.client_id,
        name,
    }))
}

/// Records MCP Control and Remote Access when they change. A runtime that
/// turns both off stops requesting relay grants, so without this report the
/// cloud would keep listing the last level it saw.
pub async fn report_capabilities(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RuntimeCapabilitiesRequest>,
) -> Result<axum::http::StatusCode, ApiError> {
    let auth = authenticate(&headers, &state, "runtime:write").await?;
    if auth.client_kind != ClientKind::Runtime {
        return Err(ApiError::forbidden(
            "runtime_session_required",
            "Only the runtime itself can report its capabilities.",
        ));
    }
    let updated = sqlx::query(
        r#"
        UPDATE runtimes
        SET mcp_access = $3, mobile_access_enabled = $4
        WHERE id = $1 AND account_id = $2 AND transferred_at IS NULL
        "#,
    )
    .bind(&auth.client_id)
    .bind(auth.account_id)
    .bind(request.mcp_access.as_str())
    .bind(request.mobile_access)
    .execute(&state.pool)
    .await?
    .rows_affected();
    if updated == 0 {
        return Err(ApiError::not_found(
            "runtime_not_found",
            "The runtime is not registered to this account.",
        ));
    }
    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::normalize_runtime_name;

    #[test]
    fn runtime_names_are_trimmed_and_bounded() {
        assert_eq!(
            normalize_runtime_name("  Work Laptop ").ok().as_deref(),
            Some("Work Laptop")
        );
        assert!(normalize_runtime_name("   ").is_err());
        assert!(normalize_runtime_name(&"n".repeat(65)).is_err());
        assert!(normalize_runtime_name(&"ñ".repeat(64)).is_ok());
        assert!(normalize_runtime_name(&"\u{4f60}".repeat(54)).is_err());
        assert!(normalize_runtime_name("bad\nname").is_err());
    }
}
