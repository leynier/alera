use chrono::{DateTime, TimeDelta, Utc};
use sqlx::FromRow;
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::{
    api_models::{
        AuthTransactionResponse, ClientKind, CreateAuthTransactionRequest, ExchangeAuthRequest,
        LinkAccountRequest, ProviderKind, TokenEnvelope,
    },
    error::ApiError,
    oauth::{AuthorizationInput, ExchangeInput, ProviderIdentity},
    state::AppState,
};

use super::{
    create_session,
    identity::{ensure_client, resolve_account},
    revoke_family,
    validation::{
        hash_secret, pkce_challenge, random_secret, validate_code_challenge,
        validate_code_verifier, validate_identifier, validate_label, validate_loopback_redirect,
        validate_new_client_id, validate_short_secret,
    },
    AuthContext,
};

const TRANSACTION_MINUTES: i64 = 5;

#[derive(FromRow)]
struct AuthTransactionRow {
    state_hash: Vec<u8>,
    provider: String,
    purpose: String,
    account_id: Option<Uuid>,
    refresh_family_id: Option<Uuid>,
    redirect_uri: String,
    code_challenge: String,
    nonce: Option<String>,
    client_id: String,
    client_kind: String,
    device_name: String,
    expires_at: DateTime<Utc>,
    used_at: Option<DateTime<Utc>>,
}

pub async fn create_sign_in_transaction(
    state: &AppState,
    request: CreateAuthTransactionRequest,
) -> Result<AuthTransactionResponse, ApiError> {
    if !matches!(
        request.client_kind,
        ClientKind::Runtime | ClientKind::Mobile
    ) {
        return Err(ApiError::bad_request(
            "invalid_client_kind",
            "Interactive sign-in is not available to this client.",
        ));
    }
    validate_new_client_id(&request.client_id)?;
    create_transaction(
        state,
        TransactionSpec {
            provider: request.provider,
            redirect_uri: request.redirect_uri,
            code_challenge: request.code_challenge,
            client_id: request.client_id,
            client_kind: request.client_kind,
            device_name: request.device_name,
            purpose: "signIn",
            account_id: None,
            refresh_family_id: None,
        },
    )
    .await
}

pub async fn create_link_transaction(
    state: &AppState,
    auth: &AuthContext,
    request: LinkAccountRequest,
) -> Result<AuthTransactionResponse, ApiError> {
    if auth.client_kind != ClientKind::Runtime {
        return Err(ApiError::forbidden(
            "link_requires_runtime",
            "Identity providers can be linked only from an authenticated runtime.",
        ));
    }
    create_transaction(
        state,
        TransactionSpec {
            provider: request.provider,
            redirect_uri: request.redirect_uri,
            code_challenge: request.code_challenge,
            client_id: auth.client_id.clone(),
            client_kind: auth.client_kind,
            device_name: auth.client_id.clone(),
            purpose: "link",
            account_id: Some(auth.account_id),
            refresh_family_id: Some(auth.family_id),
        },
    )
    .await
}

pub async fn exchange_transaction(
    state: &AppState,
    request: ExchangeAuthRequest,
) -> Result<TokenEnvelope, ApiError> {
    validate_short_secret(&request.state, "invalid_state")?;
    validate_short_secret(&request.code, "invalid_authorization_code")?;
    validate_code_verifier(&request.code_verifier)?;
    let now = Utc::now();
    let mut database = state.pool.begin().await?;
    let transaction = sqlx::query_as::<_, AuthTransactionRow>(
        r#"
        SELECT state_hash, provider, purpose, account_id, refresh_family_id,
               redirect_uri, code_challenge, nonce, client_id, client_kind,
               device_name, expires_at, used_at
        FROM auth_transactions
        WHERE id = $1
        FOR UPDATE
        "#,
    )
    .bind(request.transaction_id)
    .fetch_optional(&mut *database)
    .await?
    .ok_or_else(|| {
        ApiError::bad_request(
            "invalid_auth_transaction",
            "The authorization transaction does not exist.",
        )
    })?;
    if transaction.used_at.is_some() {
        return Err(ApiError::bad_request(
            "auth_transaction_used",
            "The authorization transaction was already used.",
        ));
    }
    if transaction.expires_at <= now {
        return Err(ApiError::bad_request(
            "auth_transaction_expired",
            "The authorization transaction expired.",
        ));
    }
    let state_matches = bool::from(
        transaction
            .state_hash
            .as_slice()
            .ct_eq(hash_secret(&request.state).as_slice()),
    );
    let challenge_matches = bool::from(
        transaction
            .code_challenge
            .as_bytes()
            .ct_eq(pkce_challenge(&request.code_verifier).as_bytes()),
    );
    if !state_matches || !challenge_matches {
        return Err(ApiError::bad_request(
            "auth_transaction_mismatch",
            "The authorization transaction could not be verified.",
        ));
    }
    sqlx::query("UPDATE auth_transactions SET used_at = $2 WHERE id = $1")
        .bind(request.transaction_id)
        .bind(now)
        .execute(&mut *database)
        .await?;
    database.commit().await?;

    let provider_kind = transaction.provider.parse()?;
    let provider = state.oauth.get(provider_kind).map_err(ApiError::internal)?;
    let identity = provider
        .exchange(ExchangeInput {
            code: &request.code,
            code_verifier: &request.code_verifier,
            redirect_uri: &transaction.redirect_uri,
            expected_nonce: transaction.nonce.as_deref(),
        })
        .await
        .map_err(ApiError::upstream)?;
    let client_kind = transaction.client_kind.parse()?;
    let account_id =
        resolve_identity_and_runtime(state, &transaction, &identity, client_kind).await?;
    let envelope = create_session(
        &state.pool,
        &state.tokens,
        account_id,
        &transaction.client_id,
        client_kind,
        &transaction.device_name,
        now,
    )
    .await?;
    if let Some(previous_family) = transaction.refresh_family_id {
        revoke_family(&state.pool, previous_family, "identity_linked").await?;
    }
    Ok(envelope)
}

struct TransactionSpec {
    provider: ProviderKind,
    redirect_uri: String,
    code_challenge: String,
    client_id: String,
    client_kind: ClientKind,
    device_name: String,
    purpose: &'static str,
    account_id: Option<Uuid>,
    refresh_family_id: Option<Uuid>,
}

async fn create_transaction(
    state: &AppState,
    spec: TransactionSpec,
) -> Result<AuthTransactionResponse, ApiError> {
    validate_loopback_redirect(&spec.redirect_uri)?;
    validate_code_challenge(&spec.code_challenge)?;
    validate_identifier(&spec.client_id, "clientId")?;
    validate_label(&spec.device_name, "deviceName")?;
    let id = Uuid::now_v7();
    let raw_state = random_secret("ast_");
    let nonce = (spec.provider == ProviderKind::Google).then(|| random_secret("an_"));
    let now = Utc::now();
    let expires_at = now + TimeDelta::minutes(TRANSACTION_MINUTES);
    sqlx::query(
        r#"
        INSERT INTO auth_transactions (
            id, state_hash, provider, purpose, account_id, refresh_family_id,
            redirect_uri, code_challenge, nonce, client_id, client_kind,
            device_name, created_at, expires_at
        ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14
        )
        "#,
    )
    .bind(id)
    .bind(hash_secret(&raw_state))
    .bind(spec.provider.as_str())
    .bind(spec.purpose)
    .bind(spec.account_id)
    .bind(spec.refresh_family_id)
    .bind(&spec.redirect_uri)
    .bind(&spec.code_challenge)
    .bind(&nonce)
    .bind(&spec.client_id)
    .bind(spec.client_kind.as_str())
    .bind(&spec.device_name)
    .bind(now)
    .bind(expires_at)
    .execute(&state.pool)
    .await?;
    let provider = state.oauth.get(spec.provider).map_err(ApiError::internal)?;
    let authorization_url = provider
        .authorization_url(AuthorizationInput {
            redirect_uri: &spec.redirect_uri,
            state: &raw_state,
            code_challenge: &spec.code_challenge,
            nonce: nonce.as_deref(),
        })
        .map_err(ApiError::internal)?;
    Ok(AuthTransactionResponse {
        transaction_id: id,
        state: raw_state,
        authorization_url: authorization_url.to_string(),
        expires_at,
    })
}

async fn resolve_identity_and_runtime(
    state: &AppState,
    auth: &AuthTransactionRow,
    identity: &ProviderIdentity,
    client_kind: ClientKind,
) -> Result<Uuid, ApiError> {
    let link_target = if auth.purpose == "link" {
        Some(auth.account_id.ok_or_else(|| {
            ApiError::bad_request("invalid_link", "The link transaction has no account.")
        })?)
    } else {
        None
    };
    let mut transaction = state.pool.begin().await?;
    let account_id = resolve_account(state, &mut transaction, identity, link_target).await?;
    ensure_client(
        state,
        &mut transaction,
        account_id,
        &auth.client_id,
        &auth.device_name,
        client_kind,
    )
    .await?;
    transaction.commit().await?;
    Ok(account_id)
}
