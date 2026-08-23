use axum::{extract::State, http::HeaderMap, Json};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use chrono::{Duration, Utc};
use sqlx::Row;

use crate::{
    api_models::{
        ClientKind, RegisterRelayIdentityRequest, RelayGrantRequest, RelayGrantResponse,
        RelayIdentityResponse, RuntimeDiscoveryResponse, RuntimeRelaySummary,
    },
    auth::{authenticate, RelayGrantInput},
    error::ApiError,
    state::AppState,
};

const GRANT_SECONDS: i64 = 120;
const ACTIVE_RUNTIME_SECONDS: i64 = 180;

pub async fn register_identity(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RegisterRelayIdentityRequest>,
) -> Result<Json<RelayIdentityResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "relay:identity").await?;
    if request.key_version <= 0 || request.key_version > 1_000_000 {
        return Err(ApiError::bad_request(
            "invalid_relay_key_version",
            "The relay identity key version is invalid.",
        ));
    }
    let public_key = URL_SAFE_NO_PAD.decode(&request.public_key).map_err(|_| {
        ApiError::bad_request(
            "invalid_relay_public_key",
            "The relay identity public key is invalid.",
        )
    })?;
    if public_key.len() != 32 {
        return Err(ApiError::bad_request(
            "invalid_relay_public_key",
            "The relay identity public key must contain 32 bytes.",
        ));
    }
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let existing = sqlx::query(
        "SELECT public_key, key_version FROM relay_identities WHERE account_id = $1 AND client_kind = $2 AND client_id = $3 FOR UPDATE",
    )
    .bind(auth.account_id)
    .bind(auth.client_kind.as_str())
    .bind(&auth.client_id)
    .fetch_optional(&mut *transaction)
    .await?;
    if let Some(row) = existing {
        let current_version: i32 = row.try_get("key_version")?;
        let current_key: Vec<u8> = row.try_get("public_key")?;
        if request.key_version < current_version
            || (request.key_version == current_version && current_key != public_key)
        {
            return Err(ApiError::conflict(
                "relay_key_rotation_conflict",
                "The relay identity key version is older than the registered key.",
            ));
        }
    }
    sqlx::query(
        r#"
        INSERT INTO relay_identities (
            account_id, client_kind, client_id, public_key, key_version,
            created_at, updated_at, revoked_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $6, NULL)
        ON CONFLICT (account_id, client_kind, client_id) DO UPDATE
        SET public_key = EXCLUDED.public_key,
            key_version = EXCLUDED.key_version,
            updated_at = EXCLUDED.updated_at,
            revoked_at = NULL
        "#,
    )
    .bind(auth.account_id)
    .bind(auth.client_kind.as_str())
    .bind(&auth.client_id)
    .bind(&public_key)
    .bind(request.key_version)
    .bind(now)
    .execute(&mut *transaction)
    .await?;
    if auth.client_kind == ClientKind::Runtime {
        sqlx::query("UPDATE runtimes SET last_seen_at = $2 WHERE id = $1 AND account_id = $3")
            .bind(&auth.client_id)
            .bind(now)
            .bind(auth.account_id)
            .execute(&mut *transaction)
            .await?;
    } else {
        sqlx::query(
            "UPDATE mobile_devices SET last_seen_at = $3 WHERE account_id = $1 AND id = $2",
        )
        .bind(auth.account_id)
        .bind(&auth.client_id)
        .bind(now)
        .execute(&mut *transaction)
        .await?;
    }
    transaction.commit().await?;
    Ok(Json(RelayIdentityResponse {
        client_id: auth.client_id,
        client_kind: auth.client_kind.as_str().to_owned(),
        public_key: request.public_key,
        key_version: request.key_version,
    }))
}

pub async fn discover_runtimes(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<RuntimeDiscoveryResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "runtime:discover").await?;
    if auth.client_kind != ClientKind::Mobile {
        return Err(ApiError::forbidden(
            "mobile_client_required",
            "Runtime discovery is available only to mobile clients.",
        ));
    }
    let cutoff = Utc::now() - Duration::seconds(ACTIVE_RUNTIME_SECONDS);
    let rows = sqlx::query(
        r#"
        SELECT r.id, r.name, r.last_seen_at, i.public_key, i.key_version
        FROM runtimes r
        JOIN relay_identities i
          ON i.account_id = r.account_id
         AND i.client_kind = 'runtime'
         AND i.client_id = r.id
         AND i.revoked_at IS NULL
        WHERE r.account_id = $1
          AND r.last_seen_at > $2
          AND r.transferred_at IS NULL
        ORDER BY r.name, r.id
        "#,
    )
    .bind(auth.account_id)
    .bind(cutoff)
    .fetch_all(&state.pool)
    .await?;
    let mut runtimes = Vec::with_capacity(rows.len());
    for row in rows {
        let public_key: Vec<u8> = row.try_get("public_key")?;
        runtimes.push(RuntimeRelaySummary {
            id: row.try_get("id")?,
            name: row.try_get("name")?,
            last_seen_at: row.try_get("last_seen_at")?,
            relay_public_key: URL_SAFE_NO_PAD.encode(public_key),
            relay_key_version: row.try_get("key_version")?,
        });
    }
    Ok(Json(RuntimeDiscoveryResponse { runtimes }))
}

pub async fn create_grant(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RelayGrantRequest>,
) -> Result<Json<RelayGrantResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "relay:grant").await?;
    if request.runtime_id.trim().is_empty() || request.runtime_id.len() > 128 {
        return Err(ApiError::bad_request(
            "invalid_runtime_id",
            "The runtime ID is invalid.",
        ));
    }
    let runtime = sqlx::query(
        r#"
        SELECT r.id, i.public_key AS runtime_key, i.key_version AS runtime_key_version
        FROM runtimes r
        JOIN relay_identities i
          ON i.account_id = r.account_id
         AND i.client_kind = 'runtime'
         AND i.client_id = r.id
         AND i.revoked_at IS NULL
        WHERE r.id = $1 AND r.account_id = $2 AND r.transferred_at IS NULL
        "#,
    )
    .bind(&request.runtime_id)
    .bind(auth.account_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| {
        ApiError::not_found(
            "runtime_unavailable",
            "The runtime is offline or has not enabled relay access.",
        )
    })?;
    if auth.client_kind == ClientKind::Runtime && auth.client_id != request.runtime_id {
        return Err(ApiError::forbidden(
            "runtime_not_owned",
            "The session cannot request a grant for another runtime.",
        ));
    }
    let client = sqlx::query(
        "SELECT public_key, key_version FROM relay_identities WHERE account_id = $1 AND client_kind = $2 AND client_id = $3 AND revoked_at IS NULL",
    )
    .bind(auth.account_id)
    .bind(auth.client_kind.as_str())
    .bind(&auth.client_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(|| {
        ApiError::forbidden(
            "relay_identity_required",
            "Register a relay identity before requesting a connection grant.",
        )
    })?;
    if auth.client_kind == ClientKind::Mobile {
        let registered = sqlx::query(
            "SELECT 1 FROM mobile_devices WHERE account_id = $1 AND id = $2 AND revoked_at IS NULL",
        )
        .bind(auth.account_id)
        .bind(&auth.client_id)
        .fetch_optional(&state.pool)
        .await?
        .is_some();
        if !registered {
            return Err(ApiError::forbidden(
                "mobile_device_required",
                "The mobile device is not registered for this account.",
            ));
        }
    }
    let client_key: Vec<u8> = client.try_get("public_key")?;
    let client_key_version: i32 = client.try_get("key_version")?;
    let runtime_key: Vec<u8> = runtime.try_get("runtime_key")?;
    let client_public_key = URL_SAFE_NO_PAD.encode(&client_key);
    let runtime_public_key = URL_SAFE_NO_PAD.encode(&runtime_key);
    let role = auth.client_kind.as_str();
    let grant = state
        .tokens
        .issue_relay_grant(RelayGrantInput {
            account_id: auth.account_id,
            runtime_id: &request.runtime_id,
            client_id: &auth.client_id,
            role,
            key_version: client_key_version,
            client_public_key: &client_public_key,
            runtime_public_key: &runtime_public_key,
        })
        .await?;
    if auth.client_kind == ClientKind::Runtime {
        sqlx::query("UPDATE runtimes SET last_seen_at = $2 WHERE id = $1 AND account_id = $3")
            .bind(&request.runtime_id)
            .bind(Utc::now())
            .bind(auth.account_id)
            .execute(&state.pool)
            .await?;
    }
    Ok(Json(RelayGrantResponse {
        grant,
        relay_url: format!("{}/{}", state.config.relay_base_url, request.runtime_id),
        expires_in: GRANT_SECONDS,
        account_id: auth.account_id,
        runtime_id: request.runtime_id,
        client_id: auth.client_id,
        client_kind: role.to_owned(),
        client_key_version,
        client_public_key: URL_SAFE_NO_PAD.encode(client_key),
        runtime_public_key: (auth.client_kind == ClientKind::Mobile)
            .then(|| URL_SAFE_NO_PAD.encode(runtime_key)),
    }))
}

#[cfg(test)]
mod tests {
    #[test]
    fn active_window_is_longer_than_a_normal_poll() {
        const { assert!(super::ACTIVE_RUNTIME_SECONDS >= 120) };
    }
}
