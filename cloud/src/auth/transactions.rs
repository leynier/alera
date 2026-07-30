use chrono::{DateTime, TimeDelta, Utc};
use sqlx::{FromRow, Postgres, Transaction};
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::{
    accounts::identity_tombstone_hash,
    api_models::{
        AuthTransactionResponse, ClientKind, CreateAuthTransactionRequest, ExchangeAuthRequest,
        LinkAccountRequest, ProviderKind, TokenEnvelope,
    },
    error::ApiError,
    oauth::{AuthorizationInput, ExchangeInput, ProviderIdentity},
    state::AppState,
};

use super::{
    create_session, revoke_family,
    validation::{
        hash_secret, pkce_challenge, random_secret, validate_code_challenge,
        validate_code_verifier, validate_identifier, validate_label, validate_loopback_redirect,
        validate_short_secret,
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
    if request.client_kind != ClientKind::Runtime {
        return Err(ApiError::bad_request(
            "invalid_client_kind",
            "Interactive sign-in is available only to runtimes.",
        ));
    }
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
    let mut transaction = state.pool.begin().await?;
    let existing_account = sqlx::query_scalar::<_, Uuid>(
        "SELECT account_id FROM account_identities WHERE provider = $1 AND provider_user_id = $2",
    )
    .bind(identity.provider.as_str())
    .bind(&identity.provider_user_id)
    .fetch_optional(&mut *transaction)
    .await?;
    let account_id = if auth.purpose == "link" {
        let target = auth.account_id.ok_or_else(|| {
            ApiError::bad_request("invalid_link", "The link transaction has no account.")
        })?;
        if existing_account.is_some_and(|value| value != target) {
            return Err(ApiError::conflict(
                "identity_already_linked",
                "That provider identity belongs to another Alera account.",
            ));
        }
        target
    } else if let Some(existing) = existing_account {
        existing
    } else {
        reject_tombstoned_identity(state, &mut transaction, identity).await?;
        find_verified_email_account(&mut transaction, identity)
            .await?
            .unwrap_or_else(Uuid::now_v7)
    };

    if existing_account.is_none() {
        ensure_account(&mut transaction, account_id, identity).await?;
        sqlx::query(
            r#"
            INSERT INTO account_identities (
                provider, provider_user_id, account_id, email, email_verified, linked_at
            ) VALUES ($1, $2, $3, $4, $5, $6)
            "#,
        )
        .bind(identity.provider.as_str())
        .bind(&identity.provider_user_id)
        .bind(account_id)
        .bind(&identity.email)
        .bind(identity.email_verified)
        .bind(Utc::now())
        .execute(&mut *transaction)
        .await?;
    } else {
        sqlx::query(
            r#"
            UPDATE account_identities
            SET email = $3, email_verified = $4
            WHERE provider = $1 AND provider_user_id = $2
            "#,
        )
        .bind(identity.provider.as_str())
        .bind(&identity.provider_user_id)
        .bind(&identity.email)
        .bind(identity.email_verified)
        .execute(&mut *transaction)
        .await?;
        sqlx::query("UPDATE accounts SET last_seen_at = $2, updated_at = $2 WHERE id = $1")
            .bind(account_id)
            .bind(Utc::now())
            .execute(&mut *transaction)
            .await?;
    }
    ensure_runtime(
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

async fn find_verified_email_account(
    transaction: &mut Transaction<'_, Postgres>,
    identity: &ProviderIdentity,
) -> Result<Option<Uuid>, ApiError> {
    if !identity.email_verified {
        return Ok(None);
    }
    let candidates = sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT DISTINCT account_id
        FROM account_identities
        WHERE email_verified AND LOWER(email) = LOWER($1)
        LIMIT 2
        "#,
    )
    .bind(&identity.email)
    .fetch_all(&mut **transaction)
    .await?;
    Ok((candidates.len() == 1).then(|| candidates[0]))
}

async fn ensure_account(
    transaction: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    identity: &ProviderIdentity,
) -> Result<(), ApiError> {
    let now = Utc::now();
    sqlx::query(
        r#"
        INSERT INTO accounts (
            id, primary_email, created_at, updated_at, last_seen_at
        ) VALUES ($1, $2, $3, $3, $3)
        ON CONFLICT (id) DO UPDATE
        SET last_seen_at = EXCLUDED.last_seen_at, updated_at = EXCLUDED.updated_at
        "#,
    )
    .bind(account_id)
    .bind(&identity.email)
    .bind(now)
    .execute(&mut **transaction)
    .await?;
    Ok(())
}

async fn ensure_runtime(
    state: &AppState,
    transaction: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    runtime_id: &str,
    name: &str,
    client_kind: ClientKind,
) -> Result<(), ApiError> {
    if client_kind != ClientKind::Runtime {
        return Err(ApiError::bad_request(
            "invalid_client_kind",
            "OAuth sessions must belong to a runtime.",
        ));
    }
    let existing =
        sqlx::query_scalar::<_, Uuid>("SELECT account_id FROM runtimes WHERE id = $1 FOR UPDATE")
            .bind(runtime_id)
            .fetch_optional(&mut **transaction)
            .await?;
    if existing.is_some_and(|value| value != account_id) {
        return Err(ApiError::conflict(
            "runtime_owned_by_another_account",
            "This runtime is already assigned to another Alera account.",
        ));
    }
    if existing.is_none() {
        sqlx::query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE")
            .bind(account_id)
            .fetch_one(&mut **transaction)
            .await?;
        let count =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM runtimes WHERE account_id = $1")
                .bind(account_id)
                .fetch_one(&mut **transaction)
                .await?;
        if count >= state.config.limits.max_runtimes_per_account {
            return Err(ApiError::forbidden(
                "runtime_limit_reached",
                "This account has reached its runtime limit.",
            ));
        }
    }
    sqlx::query(
        r#"
        INSERT INTO runtimes (id, account_id, name, created_at, last_seen_at)
        VALUES ($1, $2, $3, $4, $4)
        ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name, last_seen_at = EXCLUDED.last_seen_at
        "#,
    )
    .bind(runtime_id)
    .bind(account_id)
    .bind(name)
    .bind(Utc::now())
    .execute(&mut **transaction)
    .await?;
    Ok(())
}

async fn reject_tombstoned_identity(
    state: &AppState,
    transaction: &mut Transaction<'_, Postgres>,
    identity: &ProviderIdentity,
) -> Result<(), ApiError> {
    let subject_hash = identity_tombstone_hash(
        &state.config.tombstone_pepper,
        identity.provider.as_str(),
        &identity.provider_user_id,
    )?;
    let tombstoned = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM abuse_tombstones
            WHERE subject_kind = 'identity' AND subject_hash = $1 AND expires_at > $2
        )
        "#,
    )
    .bind(subject_hash)
    .bind(Utc::now())
    .fetch_one(&mut **transaction)
    .await?;
    if tombstoned {
        return Err(ApiError::forbidden(
            "identity_cooling_down",
            "This identity recently deleted an Alera account and cannot create another yet.",
        ));
    }
    Ok(())
}
