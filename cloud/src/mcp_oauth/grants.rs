use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use chrono::{DateTime, TimeDelta, Utc};
use sqlx::{FromRow, PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::{
    auth::{
        authenticate,
        validation::{hash_secret, random_secret},
    },
    error::ApiError,
    mcp_models::{scope_list, McpGrantList, McpGrantSummary},
    state::AppState,
};

use super::authorize::redirect_host;

pub const AUTHORIZATION_CODE_MINUTES: i64 = 5;

pub struct GrantSpec<'a> {
    pub account_id: Uuid,
    pub client_id: &'a str,
    pub client_name: &'a str,
    pub redirect_uri: &'a str,
    pub code_challenge: &'a str,
    pub resource: Option<&'a str>,
    pub scopes: &'a str,
    pub all_runtimes: bool,
    pub runtime_ids: &'a [String],
}

#[derive(FromRow)]
struct GrantRow {
    id: Uuid,
    client_id: String,
    client_name: String,
    redirect_uri: String,
    scopes: String,
    all_runtimes: bool,
    runtime_ids: Vec<String>,
    created_at: DateTime<Utc>,
    last_used_at: Option<DateTime<Utc>>,
}

/// Records an approved grant and returns a single-use authorization code for it.
pub async fn create_grant_with_code(
    transaction: &mut Transaction<'_, Postgres>,
    spec: GrantSpec<'_>,
) -> Result<String, sqlx::Error> {
    let now = Utc::now();
    let grant_id = Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO mcp_grants (
            id, account_id, client_id, client_name, redirect_uri, scopes,
            all_runtimes, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        "#,
    )
    .bind(grant_id)
    .bind(spec.account_id)
    .bind(spec.client_id)
    .bind(spec.client_name)
    .bind(spec.redirect_uri)
    .bind(spec.scopes)
    .bind(spec.all_runtimes)
    .bind(now)
    .execute(&mut **transaction)
    .await?;
    if !spec.runtime_ids.is_empty() {
        sqlx::query(
            r#"
            INSERT INTO mcp_grant_runtimes (grant_id, runtime_id)
            SELECT $1, UNNEST($2::text[])
            "#,
        )
        .bind(grant_id)
        .bind(spec.runtime_ids)
        .execute(&mut **transaction)
        .await?;
    }
    let code = random_secret("amc_");
    sqlx::query(
        r#"
        INSERT INTO mcp_authorization_codes (
            code_hash, grant_id, account_id, client_id, redirect_uri, code_challenge,
            resource, created_at, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        "#,
    )
    .bind(hash_secret(&code))
    .bind(grant_id)
    .bind(spec.account_id)
    .bind(spec.client_id)
    .bind(spec.redirect_uri)
    .bind(spec.code_challenge)
    .bind(spec.resource)
    .bind(now)
    .bind(now + TimeDelta::minutes(AUTHORIZATION_CODE_MINUTES))
    .execute(&mut **transaction)
    .await?;
    sqlx::query("UPDATE mcp_clients SET last_used_at = $2 WHERE id = $1")
        .bind(spec.client_id)
        .bind(now)
        .execute(&mut **transaction)
        .await?;
    Ok(code)
}

/// Revokes a grant and every refresh family issued for it. Returns false when the
/// account owns no such grant.
pub async fn revoke_grant(
    connection: &mut PgConnection,
    account_id: Uuid,
    grant_id: Uuid,
    reason: &str,
) -> Result<bool, sqlx::Error> {
    let now = Utc::now();
    let found = sqlx::query(
        r#"
        UPDATE mcp_grants
        SET revoked_at = COALESCE(revoked_at, $3), revoke_reason = COALESCE(revoke_reason, $4)
        WHERE id = $1 AND account_id = $2
        "#,
    )
    .bind(grant_id)
    .bind(account_id)
    .bind(now)
    .bind(reason)
    .execute(&mut *connection)
    .await?
    .rows_affected()
        > 0;
    sqlx::query(
        r#"
        UPDATE refresh_token_families
        SET revoked_at = COALESCE(revoked_at, $3), revoke_reason = COALESCE(revoke_reason, $4)
        WHERE account_id = $1 AND client_kind = 'mcp' AND client_id = $2
        "#,
    )
    .bind(account_id)
    .bind(grant_id.to_string())
    .bind(now)
    .bind(reason)
    .execute(&mut *connection)
    .await?;
    Ok(found)
}

pub async fn list(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<McpGrantList>, ApiError> {
    let auth = authenticate(&headers, &state, "account:read").await?;
    let rows = sqlx::query_as::<_, GrantRow>(
        r#"
        SELECT g.id, g.client_id, g.client_name, g.redirect_uri, g.scopes, g.all_runtimes,
               COALESCE(
                   ARRAY_AGG(gr.runtime_id ORDER BY gr.runtime_id)
                       FILTER (WHERE gr.runtime_id IS NOT NULL),
                   ARRAY[]::text[]
               ) AS runtime_ids,
               g.created_at, g.last_used_at
        FROM mcp_grants g
        LEFT JOIN mcp_grant_runtimes gr ON gr.grant_id = g.id
        WHERE g.account_id = $1 AND g.revoked_at IS NULL
        GROUP BY g.id
        ORDER BY g.created_at DESC
        "#,
    )
    .bind(auth.account_id)
    .fetch_all(&state.pool)
    .await?;
    let grants = rows
        .into_iter()
        .map(|row| McpGrantSummary {
            id: row.id,
            client_id: row.client_id,
            client_name: row.client_name,
            redirect_host: redirect_host(&row.redirect_uri),
            scopes: scope_list(&row.scopes),
            all_runtimes: row.all_runtimes,
            runtime_ids: row.runtime_ids,
            created_at: row.created_at,
            last_used_at: row.last_used_at,
        })
        .collect();
    Ok(Json(McpGrantList { grants }))
}

pub async fn revoke(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(grant_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    let auth = authenticate(&headers, &state, "account:read").await?;
    let not_found = || ApiError::not_found("grant_not_found", "The MCP grant does not exist.");
    let grant_id = Uuid::parse_str(&grant_id).map_err(|_| not_found())?;
    let mut transaction = state.pool.begin().await?;
    let found = revoke_grant(&mut transaction, auth.account_id, grant_id, "user_revoked").await?;
    if !found {
        return Err(not_found());
    }
    transaction.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}
