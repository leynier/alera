mod handlers;
mod sessions;
mod tokens;
mod transactions;
mod validation;

use axum::http::HeaderMap;
use chrono::{DateTime, Utc};
use sqlx::Row;
use uuid::Uuid;

use crate::{api_models::ClientKind, error::ApiError, state::AppState};

pub use handlers::{create_transaction, exchange, jwks, refresh, revoke};
pub use sessions::{create_session, revoke_family, rotate_session};
pub use tokens::{AccessClaims, TokenService};
pub use transactions::create_link_transaction;

#[derive(Clone, Debug)]
pub struct AuthContext {
    pub account_id: Uuid,
    pub client_id: String,
    pub client_kind: ClientKind,
    pub family_id: Uuid,
    pub auth_time: DateTime<Utc>,
    pub scopes: Vec<String>,
}

impl AuthContext {
    pub fn require_scope(&self, scope: &str) -> Result<(), ApiError> {
        if self.scopes.iter().any(|value| value == scope) {
            Ok(())
        } else {
            Err(ApiError::forbidden(
                "insufficient_scope",
                "The session is not allowed to perform this action.",
            ))
        }
    }
}

pub async fn authenticate(
    headers: &HeaderMap,
    state: &AppState,
    scope: &str,
) -> Result<AuthContext, ApiError> {
    let token = bearer_token(headers)?;
    let claims = state.tokens.verify(token)?;
    let account_id = Uuid::parse_str(&claims.sub).map_err(|_| {
        ApiError::unauthorized("invalid_token", "The access token subject is invalid.")
    })?;
    let family_id = Uuid::parse_str(&claims.sid).map_err(|_| {
        ApiError::unauthorized("invalid_token", "The access token session is invalid.")
    })?;
    let client_kind = claims.client_kind.parse()?;
    let row = sqlx::query(
        r#"
        SELECT a.banned_at, a.deleted_at, f.revoked_at
        FROM accounts a
        JOIN refresh_token_families f ON f.account_id = a.id
        WHERE a.id = $1 AND f.id = $2
        "#,
    )
    .bind(account_id)
    .bind(family_id)
    .fetch_optional(&state.pool)
    .await?;
    let row = row.ok_or_else(|| {
        ApiError::unauthorized("invalid_session", "The account session no longer exists.")
    })?;
    let banned_at: Option<DateTime<Utc>> = row.try_get("banned_at")?;
    let deleted_at: Option<DateTime<Utc>> = row.try_get("deleted_at")?;
    let revoked_at: Option<DateTime<Utc>> = row.try_get("revoked_at")?;
    if banned_at.is_some() {
        return Err(ApiError::forbidden(
            "account_banned",
            "This Alera account is disabled.",
        ));
    }
    if deleted_at.is_some() || revoked_at.is_some() {
        return Err(ApiError::unauthorized(
            "session_revoked",
            "The account session has been revoked.",
        ));
    }

    let context = AuthContext {
        account_id,
        client_id: claims.client_id,
        client_kind,
        family_id,
        auth_time: DateTime::from_timestamp(claims.auth_time, 0).ok_or_else(|| {
            ApiError::unauthorized("invalid_token", "The access token auth time is invalid.")
        })?,
        scopes: claims
            .scope
            .split_whitespace()
            .map(ToOwned::to_owned)
            .collect(),
    };
    context.require_scope(scope)?;
    Ok(context)
}

fn bearer_token(headers: &HeaderMap) -> Result<&str, ApiError> {
    let value = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| {
            ApiError::unauthorized("missing_bearer", "Authorization bearer token is required.")
        })?;
    value.strip_prefix("Bearer ").ok_or_else(|| {
        ApiError::unauthorized("invalid_bearer", "Authorization bearer token is invalid.")
    })
}
