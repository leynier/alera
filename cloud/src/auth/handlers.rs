use axum::{extract::State, http::StatusCode, Json};

use crate::{
    api_models::{
        AuthTransactionResponse, CreateAuthTransactionRequest, ExchangeAuthRequest, RefreshRequest,
        TokenEnvelope,
    },
    error::ApiError,
    signing::JsonWebKeySet,
    state::AppState,
};

use super::{
    rotate_session,
    sessions::revoke_by_refresh_token,
    transactions::{create_sign_in_transaction, exchange_transaction},
};

pub async fn create_transaction(
    State(state): State<AppState>,
    Json(request): Json<CreateAuthTransactionRequest>,
) -> Result<Json<AuthTransactionResponse>, ApiError> {
    Ok(Json(create_sign_in_transaction(&state, request).await?))
}

pub async fn exchange(
    State(state): State<AppState>,
    Json(request): Json<ExchangeAuthRequest>,
) -> Result<Json<TokenEnvelope>, ApiError> {
    Ok(Json(exchange_transaction(&state, request).await?))
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(request): Json<RefreshRequest>,
) -> Result<Json<TokenEnvelope>, ApiError> {
    Ok(Json(
        rotate_session(&state.pool, &state.tokens, &request.refresh_token).await?,
    ))
}

pub async fn revoke(
    State(state): State<AppState>,
    Json(request): Json<RefreshRequest>,
) -> Result<StatusCode, ApiError> {
    revoke_by_refresh_token(&state.pool, &request.refresh_token, "client_revoked").await?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn jwks(State(state): State<AppState>) -> Json<JsonWebKeySet> {
    Json(state.tokens.jwks())
}
