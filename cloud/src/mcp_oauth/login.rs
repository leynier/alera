use axum::{
    extract::{RawQuery, State},
    response::{IntoResponse, Redirect, Response},
};
use chrono::{DateTime, TimeDelta, Utc};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{
    accounts::load_account_summary,
    api_models::ProviderKind,
    auth::{
        identity::resolve_account,
        validation::{hash_secret, pkce_challenge, random_secret},
    },
    device_auth,
    oauth::{AuthorizationInput, ExchangeInput},
    state::AppState,
};

use super::{
    authorize::ClientRedirect, consent, forms::FormFields, pages::PageError,
    AUTHORIZATION_REQUEST_MINUTES,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LoginPurpose {
    Mcp,
    Device,
}

impl LoginPurpose {
    fn as_str(self) -> &'static str {
        match self {
            Self::Mcp => "mcp",
            Self::Device => "device",
        }
    }
}

#[derive(FromRow)]
struct WebLoginRow {
    purpose: String,
    target_id: Uuid,
    provider: String,
    code_verifier: String,
    nonce: Option<String>,
    expires_at: DateTime<Utc>,
    used_at: Option<DateTime<Utc>>,
}

#[derive(FromRow)]
struct PendingRequest {
    redirect_uri: String,
    state: Option<String>,
}

pub async fn start(State(state): State<AppState>, RawQuery(query): RawQuery) -> Response {
    match start_login(&state, query.as_deref()).await {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

async fn start_login(state: &AppState, query: Option<&str>) -> Result<Response, PageError> {
    let form = FormFields::parse_query(query);
    let read = |name: &str| {
        form.get(name)
            .map_err(|_| PageError::bad_request("A sign-in parameter is repeated."))
    };
    let provider: ProviderKind = read("provider")?
        .ok_or_else(|| PageError::bad_request("Choose an identity provider."))?
        .parse()?;
    let (purpose, raw_target) = match (read("request")?, read("device")?) {
        (Some(request), None) => (LoginPurpose::Mcp, request),
        (None, Some(device)) => (LoginPurpose::Device, device),
        _ => return Err(PageError::bad_request("The sign-in request is missing.")),
    };
    let target_id = Uuid::parse_str(raw_target).map_err(|_| PageError::expired())?;
    let now = Utc::now();
    let pending = match purpose {
        LoginPurpose::Mcp => {
            state.config.mcp.enabled
                && sqlx::query_scalar::<_, bool>(
                    r#"
                    SELECT EXISTS(
                        SELECT 1 FROM mcp_authorization_requests
                        WHERE id = $1 AND completed_at IS NULL AND expires_at > $2
                    )
                    "#,
                )
                .bind(target_id)
                .bind(now)
                .fetch_one(&state.pool)
                .await?
        }
        LoginPurpose::Device => device_auth::is_pending(state, target_id).await?,
    };
    if !pending {
        return Err(PageError::expired());
    }
    let raw_state = random_secret("aws_");
    let code_verifier = random_secret("");
    let nonce = (provider == ProviderKind::Google).then(|| random_secret("an_"));
    sqlx::query(
        r#"
        INSERT INTO web_logins (
            id, purpose, target_id, provider, state_hash, code_verifier, nonce,
            created_at, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        "#,
    )
    .bind(Uuid::now_v7())
    .bind(purpose.as_str())
    .bind(target_id)
    .bind(provider.as_str())
    .bind(hash_secret(&raw_state))
    .bind(&code_verifier)
    .bind(&nonce)
    .bind(now)
    .bind(now + TimeDelta::minutes(AUTHORIZATION_REQUEST_MINUTES))
    .execute(&state.pool)
    .await?;
    let redirect_uri = state.config.web_callback_url();
    let provider = state.web_oauth.get(provider).map_err(|error| {
        tracing::error!(error = %error, "web identity provider is not configured");
        PageError::bad_request("That identity provider is not available.")
    })?;
    let url = provider
        .authorization_url(AuthorizationInput {
            redirect_uri: &redirect_uri,
            state: &raw_state,
            code_challenge: &pkce_challenge(&code_verifier),
            nonce: nonce.as_deref(),
        })
        .map_err(|error| {
            tracing::error!(error = %error, "build provider authorization URL failed");
            PageError::bad_request("That identity provider is not available.")
        })?;
    Ok(Redirect::to(url.as_str()).into_response())
}

pub async fn callback(State(state): State<AppState>, RawQuery(query): RawQuery) -> Response {
    match finish_login(&state, query.as_deref()).await {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

/// The edge forwards the browser's query as a form body, so Cloud Run request
/// logs never record the provider code or state.
pub async fn callback_form(State(state): State<AppState>, body: String) -> Response {
    match finish_login(&state, Some(&body)).await {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

async fn finish_login(state: &AppState, query: Option<&str>) -> Result<Response, PageError> {
    let form = FormFields::parse_query(query);
    let read = |name: &str| {
        form.get(name)
            .map_err(|_| PageError::bad_request("A sign-in parameter is repeated."))
    };
    let raw_state = read("state")?.ok_or_else(PageError::expired)?;
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let login = sqlx::query_as::<_, WebLoginRow>(
        r#"
        SELECT purpose, target_id, provider, code_verifier, nonce, expires_at, used_at
        FROM web_logins
        WHERE state_hash = $1
        FOR UPDATE
        "#,
    )
    .bind(hash_secret(raw_state))
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(PageError::expired)?;
    if login.used_at.is_some() || login.expires_at <= now {
        return Err(PageError::expired());
    }
    sqlx::query("UPDATE web_logins SET used_at = $2 WHERE state_hash = $1")
        .bind(hash_secret(raw_state))
        .bind(now)
        .execute(&mut *transaction)
        .await?;
    transaction.commit().await?;
    let purpose = match login.purpose.as_str() {
        "mcp" => LoginPurpose::Mcp,
        _ => LoginPurpose::Device,
    };

    let Some(code) = read("code")? else {
        return provider_declined(state, purpose, login.target_id).await;
    };
    let provider = state
        .web_oauth
        .get(login.provider.parse()?)
        .map_err(|_| PageError::bad_request("That identity provider is not available."))?;
    let redirect_uri = state.config.web_callback_url();
    let identity = provider
        .exchange(ExchangeInput {
            code,
            code_verifier: &login.code_verifier,
            redirect_uri: &redirect_uri,
            expected_nonce: login.nonce.as_deref(),
        })
        .await
        .map_err(crate::error::ApiError::upstream)?;
    let mut transaction = state.pool.begin().await?;
    let account_id = resolve_account(state, &mut transaction, &identity, None).await?;
    transaction.commit().await?;
    let account = load_account_summary(&state.pool, account_id).await?;
    match purpose {
        LoginPurpose::Mcp => consent::begin(state, login.target_id, &account).await,
        LoginPurpose::Device => device_auth::begin_confirm(state, login.target_id, &account).await,
    }
}

/// The person canceled at the provider. An MCP client learns through `access_denied`.
async fn provider_declined(
    state: &AppState,
    purpose: LoginPurpose,
    target_id: Uuid,
) -> Result<Response, PageError> {
    if purpose == LoginPurpose::Mcp {
        let request = sqlx::query_as::<_, PendingRequest>(
            r#"
            UPDATE mcp_authorization_requests
            SET completed_at = $2
            WHERE id = $1 AND completed_at IS NULL
            RETURNING redirect_uri, state
            "#,
        )
        .bind(target_id)
        .bind(Utc::now())
        .fetch_optional(&state.pool)
        .await?;
        if let Some(request) = request {
            let redirect = ClientRedirect {
                redirect_uri: &request.redirect_uri,
                state: request.state.as_deref(),
                issuer: &state.config.issuer,
            };
            return Ok(redirect.error("access_denied", "Sign-in was canceled."));
        }
    }
    Err(PageError::bad_request(
        "Sign-in was canceled. Start again from the app that sent you here.",
    ))
}
