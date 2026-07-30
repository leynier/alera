use axum::{extract::State, http::HeaderMap, Json};
use chrono::Utc;
use sqlx::Row;

use crate::{
    api_models::{ClientKind, TransferRuntimeRequest, TransferRuntimeResponse},
    auth::authenticate,
    error::ApiError,
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
