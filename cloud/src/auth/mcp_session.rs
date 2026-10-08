use axum::http::HeaderMap;
use chrono::{DateTime, Utc};
use sqlx::Row;
use uuid::Uuid;

use crate::{error::ApiError, mcp_models::scope_list, state::AppState};

use super::bearer_token;

#[derive(Clone, Debug)]
pub struct McpAuthContext {
    pub account_id: Uuid,
    pub family_id: Uuid,
    pub grant_id: Uuid,
    pub client_id: String,
    pub client_name: String,
    pub all_runtimes: bool,
    pub scopes: Vec<String>,
}

impl McpAuthContext {
    pub fn has_scope(&self, scope: &str) -> bool {
        self.scopes.iter().any(|value| value == scope)
    }

    pub fn require_scope(&self, scope: &str) -> Result<(), ApiError> {
        if self.has_scope(scope) {
            Ok(())
        } else {
            Err(ApiError::forbidden(
                "insufficient_scope",
                format!("The MCP grant does not include the {scope} scope."),
            ))
        }
    }
}

/// Authenticates an MCP client access token and checks its grant and session are still live.
pub async fn authenticate_mcp(
    headers: &HeaderMap,
    state: &AppState,
) -> Result<McpAuthContext, ApiError> {
    let token = bearer_token(headers)?;
    let claims = state.tokens.verify_mcp(token)?;
    let invalid = || ApiError::unauthorized("invalid_token", "The access token is invalid.");
    let account_id = Uuid::parse_str(&claims.sub).map_err(|_| invalid())?;
    let family_id = Uuid::parse_str(&claims.sid).map_err(|_| invalid())?;
    let grant_id = claims
        .gid
        .as_deref()
        .and_then(|value| Uuid::parse_str(value).ok())
        .ok_or_else(invalid)?;
    let row = sqlx::query(
        r#"
        SELECT a.banned_at, a.deleted_at, f.revoked_at AS family_revoked_at,
               g.revoked_at AS grant_revoked_at, g.client_id, g.client_name,
               g.all_runtimes, g.scopes
        FROM accounts a
        JOIN refresh_token_families f
          ON f.account_id = a.id AND f.client_kind = 'mcp'
        JOIN mcp_grants g
          ON g.account_id = a.id AND f.client_id = g.id::text
        WHERE a.id = $1 AND f.id = $2 AND g.id = $3
        "#,
    )
    .bind(account_id)
    .bind(family_id)
    .bind(grant_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| {
        ApiError::unauthorized("invalid_session", "The MCP authorization no longer exists.")
    })?;
    let banned_at: Option<DateTime<Utc>> = row.try_get("banned_at")?;
    let deleted_at: Option<DateTime<Utc>> = row.try_get("deleted_at")?;
    let family_revoked_at: Option<DateTime<Utc>> = row.try_get("family_revoked_at")?;
    let grant_revoked_at: Option<DateTime<Utc>> = row.try_get("grant_revoked_at")?;
    if banned_at.is_some() {
        return Err(ApiError::forbidden(
            "account_banned",
            "This Alera account is disabled.",
        ));
    }
    if deleted_at.is_some() || family_revoked_at.is_some() || grant_revoked_at.is_some() {
        return Err(ApiError::unauthorized(
            "session_revoked",
            "The MCP authorization has been revoked.",
        ));
    }
    let client_id: String = row.try_get("client_id")?;
    if client_id != claims.client_id {
        return Err(invalid());
    }
    let granted: String = row.try_get("scopes")?;
    let granted = scope_list(&granted);
    let scopes = scope_list(&claims.scope)
        .into_iter()
        .filter(|scope| granted.contains(scope))
        .collect();
    Ok(McpAuthContext {
        account_id,
        family_id,
        grant_id,
        client_id,
        client_name: row.try_get("client_name")?,
        all_runtimes: row.try_get("all_runtimes")?,
        scopes,
    })
}
