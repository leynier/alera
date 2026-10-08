use axum::{
    body::Bytes,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use sqlx::FromRow;
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::{
    api_models::ClientKind,
    auth::{
        sessions::{create_family, rotate_family, validate_refresh_token, FamilyKind},
        validation::{hash_secret, pkce_challenge, validate_code_verifier},
        McpAccessInput,
    },
    state::AppState,
};

use super::{forms::FormFields, grants::revoke_grant, no_store, with_cors, OAuthError};

#[derive(FromRow)]
struct CodeRow {
    grant_id: Uuid,
    account_id: Uuid,
    client_id: String,
    redirect_uri: String,
    code_challenge: String,
    expires_at: DateTime<Utc>,
    used_at: Option<DateTime<Utc>>,
    grant_revoked_at: Option<DateTime<Utc>>,
    account_active: bool,
    scopes: String,
    client_name: String,
    grant_created_at: DateTime<Utc>,
}

#[derive(FromRow)]
struct RefreshGrantRow {
    grant_id: Uuid,
    client_id: String,
}

pub async fn token(State(state): State<AppState>, body: Bytes) -> Response {
    match exchange(&state, &FormFields::parse(&body)).await {
        Ok(value) => no_store(with_cors(Json(value).into_response())),
        Err(error) => error.into_response(),
    }
}

fn field<'a>(form: &'a FormFields, name: &str) -> Result<Option<&'a str>, OAuthError> {
    form.get(name)
        .map_err(|_| OAuthError::invalid_request(format!("The {name} parameter is repeated.")))
}

fn required<'a>(form: &'a FormFields, name: &str) -> Result<&'a str, OAuthError> {
    field(form, name)?
        .ok_or_else(|| OAuthError::invalid_request(format!("The {name} parameter is required.")))
}

async fn exchange(state: &AppState, form: &FormFields) -> Result<Value, OAuthError> {
    if let Some(resource) = field(form, "resource")? {
        if resource != state.config.mcp.resource {
            return Err(OAuthError::bad_request(
                "invalid_target",
                "The requested resource is not served by this authorization server.",
            ));
        }
    }
    match required(form, "grant_type")? {
        "authorization_code" => authorization_code(state, form).await,
        "refresh_token" => refresh(state, form).await,
        _ => Err(OAuthError::bad_request(
            "unsupported_grant_type",
            "Only authorization_code and refresh_token are supported.",
        )),
    }
}

async fn authorization_code(state: &AppState, form: &FormFields) -> Result<Value, OAuthError> {
    let code = required(form, "code")?;
    let verifier = required(form, "code_verifier")?;
    let client_id = required(form, "client_id")?;
    let redirect_uri = field(form, "redirect_uri")?;
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let row = sqlx::query_as::<_, CodeRow>(
        r#"
        SELECT c.grant_id, c.account_id, c.client_id, c.redirect_uri, c.code_challenge,
               c.expires_at, c.used_at, g.revoked_at AS grant_revoked_at,
               (a.banned_at IS NULL AND a.deleted_at IS NULL) AS account_active,
               g.scopes, g.client_name, g.created_at AS grant_created_at
        FROM mcp_authorization_codes c
        JOIN mcp_grants g ON g.id = c.grant_id
        JOIN accounts a ON a.id = c.account_id
        WHERE c.code_hash = $1
        FOR UPDATE OF c
        "#,
    )
    .bind(hash_secret(code))
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(|| OAuthError::invalid_grant("The authorization code is invalid."))?;
    if row.used_at.is_some() {
        revoke_grant(
            &mut transaction,
            row.account_id,
            row.grant_id,
            "authorization_code_replay",
        )
        .await?;
        transaction.commit().await?;
        return Err(OAuthError::invalid_grant(
            "The authorization code was already used.",
        ));
    }
    // A failed redemption still consumes the code so a stolen code cannot be retried.
    sqlx::query("UPDATE mcp_authorization_codes SET used_at = $2 WHERE code_hash = $1")
        .bind(hash_secret(code))
        .bind(now)
        .execute(&mut *transaction)
        .await?;
    transaction.commit().await?;
    let challenge_matches = validate_code_verifier(verifier).is_ok()
        && bool::from(
            pkce_challenge(verifier)
                .as_bytes()
                .ct_eq(row.code_challenge.as_bytes()),
        );
    let failure = if row.expires_at <= now {
        Some("The authorization code expired.")
    } else if row.client_id != client_id {
        Some("The authorization code was issued to another client.")
    } else if redirect_uri.is_some_and(|uri| uri != row.redirect_uri) {
        Some("The redirect_uri does not match the authorization request.")
    } else if !challenge_matches {
        Some("The PKCE code verifier does not match.")
    } else if row.grant_revoked_at.is_some() || !row.account_active {
        Some("The authorization was revoked.")
    } else {
        None
    };
    if let Some(message) = failure {
        return Err(OAuthError::invalid_grant(message));
    }
    let (family_id, refresh_token) = create_family(
        &state.pool,
        row.account_id,
        &row.grant_id.to_string(),
        ClientKind::Mcp,
        &row.client_name,
        row.grant_created_at,
    )
    .await?;
    let access_token = state
        .tokens
        .issue_mcp(McpAccessInput {
            account_id: row.account_id,
            family_id,
            client_id: &row.client_id,
            grant_id: row.grant_id,
            scope: &row.scopes,
            authenticated_at: row.grant_created_at,
        })
        .await?;
    Ok(token_response(
        state,
        &access_token,
        &refresh_token,
        &row.scopes,
    ))
}

async fn refresh(state: &AppState, form: &FormFields) -> Result<Value, OAuthError> {
    let refresh_token = required(form, "refresh_token")?;
    let invalid = || OAuthError::invalid_grant("The refresh token is invalid.");
    validate_refresh_token(refresh_token).map_err(|_| invalid())?;
    let grant = sqlx::query_as::<_, RefreshGrantRow>(
        r#"
        SELECT g.id AS grant_id, g.client_id
        FROM refresh_tokens t
        JOIN refresh_token_families f ON f.id = t.family_id AND f.client_kind = 'mcp'
        JOIN mcp_grants g ON g.id::text = f.client_id AND g.account_id = f.account_id
        WHERE t.token_hash = $1
        "#,
    )
    .bind(hash_secret(refresh_token))
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(invalid)?;
    if field(form, "client_id")?.is_some_and(|client_id| client_id != grant.client_id) {
        return Err(OAuthError::invalid_grant(
            "The refresh token was issued to another client.",
        ));
    }
    let rotated = rotate_family(&state.pool, refresh_token, FamilyKind::Mcp)
        .await
        .map_err(|_| invalid())?;
    let live = sqlx::query_as::<_, (String, DateTime<Utc>)>(
        r#"
        SELECT g.scopes, g.created_at
        FROM mcp_grants g
        JOIN accounts a ON a.id = g.account_id
        WHERE g.id = $1 AND g.account_id = $2 AND g.revoked_at IS NULL
          AND a.banned_at IS NULL AND a.deleted_at IS NULL
        "#,
    )
    .bind(grant.grant_id)
    .bind(rotated.account_id)
    .fetch_optional(&state.pool)
    .await?;
    let Some((scopes, authenticated_at)) = live else {
        let mut connection = state.pool.acquire().await?;
        revoke_grant(
            &mut connection,
            rotated.account_id,
            grant.grant_id,
            "grant_revoked",
        )
        .await?;
        return Err(OAuthError::invalid_grant("The authorization was revoked."));
    };
    let access_token = state
        .tokens
        .issue_mcp(McpAccessInput {
            account_id: rotated.account_id,
            family_id: rotated.family_id,
            client_id: &grant.client_id,
            grant_id: grant.grant_id,
            scope: &scopes,
            authenticated_at,
        })
        .await?;
    Ok(token_response(
        state,
        &access_token,
        &rotated.refresh_token,
        &scopes,
    ))
}

fn token_response(state: &AppState, access_token: &str, refresh_token: &str, scope: &str) -> Value {
    json!({
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_in": state.tokens.expires_in_seconds(),
        "refresh_token": refresh_token,
        "scope": scope,
    })
}

/// RFC 7009 revocation. It always answers 200 so callers learn nothing about tokens.
pub async fn revoke(State(state): State<AppState>, body: Bytes) -> Response {
    let form = FormFields::parse(&body);
    if let Ok(Some(token)) = form.get("token") {
        if let Err(error) = revoke_token(&state, token).await {
            tracing::warn!(error = %error, "MCP token revocation failed");
        }
    }
    no_store(with_cors(StatusCode::OK.into_response()))
}

async fn revoke_token(state: &AppState, token: &str) -> Result<(), sqlx::Error> {
    let family = if validate_refresh_token(token).is_ok() {
        sqlx::query_as::<_, (Uuid, String)>(
            r#"
            SELECT f.account_id, f.client_id
            FROM refresh_tokens t
            JOIN refresh_token_families f ON f.id = t.family_id
            WHERE t.token_hash = $1 AND f.client_kind = 'mcp'
            "#,
        )
        .bind(hash_secret(token))
        .fetch_optional(&state.pool)
        .await?
    } else {
        state
            .tokens
            .verify_mcp(token)
            .ok()
            .and_then(|claims| Some((Uuid::parse_str(&claims.sub).ok()?, claims.gid?)))
    };
    let Some((account_id, grant_id)) = family else {
        return Ok(());
    };
    let Ok(grant_id) = Uuid::parse_str(&grant_id) else {
        return Ok(());
    };
    let mut connection = state.pool.acquire().await?;
    revoke_grant(&mut connection, account_id, grant_id, "client_revoked").await?;
    Ok(())
}
