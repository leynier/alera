use chrono::Utc;
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{
    accounts::identity_tombstone_hash, api_models::ClientKind, error::ApiError,
    oauth::ProviderIdentity, state::AppState,
};

/// Resolves a provider identity to an Alera account, creating or linking it when allowed.
///
/// `link_target` attaches the identity to that account; otherwise an existing identity,
/// a single verified-email match, or a new account is used, and deleted identities that are
/// still cooling down are refused.
pub(crate) async fn resolve_account(
    state: &AppState,
    transaction: &mut Transaction<'_, Postgres>,
    identity: &ProviderIdentity,
    link_target: Option<Uuid>,
) -> Result<Uuid, ApiError> {
    let existing_account = sqlx::query_scalar::<_, Uuid>(
        "SELECT account_id FROM account_identities WHERE provider = $1 AND provider_user_id = $2",
    )
    .bind(identity.provider.as_str())
    .bind(&identity.provider_user_id)
    .fetch_optional(&mut **transaction)
    .await?;
    let account_id = if let Some(target) = link_target {
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
        reject_tombstoned_identity(state, transaction, identity).await?;
        find_verified_email_account(transaction, identity)
            .await?
            .unwrap_or_else(Uuid::now_v7)
    };

    if existing_account.is_none() {
        ensure_account(transaction, account_id, identity).await?;
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
        .execute(&mut **transaction)
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
        .execute(&mut **transaction)
        .await?;
        sqlx::query("UPDATE accounts SET last_seen_at = $2, updated_at = $2 WHERE id = $1")
            .bind(account_id)
            .bind(Utc::now())
            .execute(&mut **transaction)
            .await?;
    }
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

pub(crate) async fn ensure_client(
    state: &AppState,
    transaction: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    runtime_id: &str,
    name: &str,
    client_kind: ClientKind,
) -> Result<(), ApiError> {
    if client_kind == ClientKind::Mobile {
        sqlx::query(
            r#"
            INSERT INTO mobile_devices (
                account_id, id, name, created_at, last_seen_at
            ) VALUES ($1, $2, $3, $4, $4)
            ON CONFLICT (account_id, id) DO UPDATE
            SET name = EXCLUDED.name, last_seen_at = EXCLUDED.last_seen_at,
                revoked_at = NULL
            "#,
        )
        .bind(account_id)
        .bind(runtime_id)
        .bind(name)
        .bind(Utc::now())
        .execute(&mut **transaction)
        .await?;
        return Ok(());
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
