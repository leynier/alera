//! OpenAI MCP Events subscriptions, called by the edge with the MCP client's token.
//! Each subscription is bound to the grant that created it and stops when it is revoked.

use std::collections::BTreeMap;

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use chrono::{SecondsFormat, TimeDelta, Utc};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

use crate::{
    auth::{authenticate_mcp, validation::random_secret, McpAuthContext},
    error::ApiError,
    mcp_gateway::{reachable_runtimes, resolve_runtime},
    mcp_models::SCOPE_READ,
    state::AppState,
};

use super::{
    callback::CallbackError,
    catalog::{self, EventKind},
    cursor,
    delivery::signed_headers,
    fanout::{backfill, RETENTION},
    ingest::valid_id,
    models::{McpDelivery, McpSubscribeRequest, McpSubscribeResponse, McpUnsubscribeRequest},
    secrets::signing_key,
    webhooks::{check_callback, require_secrets},
};

const MIN_LIFETIME_SECONDS: i64 = 60;
const VERIFICATION_REUSE: TimeDelta = TimeDelta::minutes(5);
const ROTATION_WINDOW: TimeDelta = TimeDelta::minutes(5);

struct Subscription<'a> {
    kind: &'static EventKind,
    arguments: BTreeMap<String, String>,
    url: &'a str,
}

fn invalid(message: impl Into<String>) -> ApiError {
    ApiError::bad_request("invalid_event_subscription", message)
}

/// A callback that failed verification. The edge turns it into JSON-RPC `-32015`.
fn callback_error(reason: &str) -> ApiError {
    ApiError::Request {
        status: StatusCode::UNPROCESSABLE_ENTITY,
        code: "callback_endpoint_error",
        message: reason.to_owned(),
    }
}

async fn authorize(headers: &HeaderMap, state: &AppState) -> Result<McpAuthContext, ApiError> {
    if !state.config.events.mcp_events_enabled {
        return Err(ApiError::not_found(
            "mcp_events_disabled",
            "MCP Events are not enabled.",
        ));
    }
    let auth = authenticate_mcp(headers, state).await?;
    auth.require_scope(SCOPE_READ)?;
    Ok(auth)
}

fn parse<'a>(
    name: &str,
    arguments: &serde_json::Map<String, Value>,
    delivery: &'a McpDelivery,
) -> Result<Subscription<'a>, ApiError> {
    let kind = catalog::kind(name).ok_or_else(|| invalid(format!("Unknown event {name}.")))?;
    if delivery.mode != "webhook" {
        return Err(invalid("Only webhook delivery is supported."));
    }
    let mut parsed = BTreeMap::new();
    for (key, value) in arguments {
        let allowed =
            key == "runtime" || key == "workspaceId" || kind.filters.contains(&key.as_str());
        let value = value.as_str().filter(|value| valid_id(value));
        match (allowed, value) {
            (true, Some(value)) => {
                parsed.insert(key.clone(), value.to_owned());
            }
            _ => return Err(invalid(format!("Invalid argument {key} for {name}."))),
        }
    }
    Ok(Subscription {
        kind,
        arguments: parsed,
        url: &delivery.url,
    })
}

/// Deterministic id from the grant, callback URL, event name, and canonical arguments.
fn subscription_id(auth: &McpAuthContext, subscription: &Subscription<'_>) -> String {
    let canonical = json!([
        auth.account_id,
        auth.grant_id,
        subscription.url,
        subscription.kind.name,
        subscription.arguments,
    ]);
    format!(
        "sub_{}",
        hex::encode(Sha256::digest(canonical.to_string().as_bytes()))
    )
}

/// Sends the signed verification challenge and requires the receiver to echo it.
async fn verify(state: &AppState, url: &str, id: &str, key: &[u8]) -> Result<(), ApiError> {
    let challenge = random_secret("");
    let body = serde_json::to_vec(&json!({"type": "verification", "challenge": challenge}))
        .map_err(ApiError::internal)?;
    let message_id = format!("msg_verification_{}", &random_secret("")[..16]);
    let headers = signed_headers(
        &message_id,
        ("x-mcp-subscription-id", id),
        &[key.to_vec()],
        &body,
    );
    let reply = state
        .events
        .callbacks
        .post(url, &headers, body)
        .await
        .map_err(|error: CallbackError| callback_error(error.reason()))?;
    let echoed = serde_json::from_slice::<Value>(&reply.body)
        .ok()
        .and_then(|value| {
            value
                .get("challenge")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        });
    let matches =
        echoed.is_some_and(|echoed| bool::from(echoed.as_bytes().ct_eq(challenge.as_bytes())));
    if (200..300).contains(&reply.status) && matches {
        Ok(())
    } else {
        Err(callback_error("challenge_failed"))
    }
}

#[derive(sqlx::FromRow)]
struct Existing {
    secret_ciphertext: String,
    status: String,
    verified_at: Option<chrono::DateTime<Utc>>,
}

pub async fn subscribe(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<McpSubscribeRequest>,
) -> Result<Json<McpSubscribeResponse>, ApiError> {
    let auth = authorize(&headers, &state).await?;
    let subscription = parse(&request.name, &request.arguments, &request.delivery)?;
    let secret = request.delivery.secret.as_deref().unwrap_or_default();
    let key = signing_key(secret)
        .ok_or_else(|| invalid("delivery.secret must be whsec_ base64 of 24 to 64 bytes."))?;
    let secrets = require_secrets(&state)?;
    let now = Utc::now();
    let (runtime_ids, all_runtimes) = match subscription.arguments.get("runtime") {
        Some(runtime) => {
            let runtimes = reachable_runtimes(&state, &auth).await?;
            let chosen = resolve_runtime(&runtimes, Some(runtime), now)?;
            (vec![chosen.id.clone()], false)
        }
        None => (Vec::new(), true),
    };
    let filter: serde_json::Map<String, Value> = subscription
        .arguments
        .iter()
        .filter(|(key, _)| key.as_str() != "runtime")
        .map(|(key, value)| (key.clone(), Value::from(value.as_str())))
        .collect();
    let (anchor, truncated) = match request.cursor.as_deref() {
        Some(text) => {
            let since =
                cursor::decode(text, now).ok_or_else(|| invalid("The cursor is invalid."))?;
            let floor = now - RETENTION;
            (since.max(floor), since < floor)
        }
        None => (now, false),
    };
    check_callback(&state, subscription.url)
        .await
        .map_err(|error| callback_error(error.reason()))?;
    let id = subscription_id(&auth, &subscription);
    let existing = sqlx::query_as::<_, Existing>(
        "SELECT secret_ciphertext, status, verified_at FROM event_subscriptions WHERE id = $1 AND account_id = $2",
    )
    .bind(&id)
    .bind(auth.account_id)
    .fetch_optional(&state.pool)
    .await?;
    let previous_secret = existing
        .as_ref()
        .and_then(|row| secrets.decrypt(&row.secret_ciphertext, &id).ok());
    let secret_changed = existing.is_some() && previous_secret.as_deref() != Some(secret);
    let reuse_verification = existing.as_ref().is_some_and(|row| {
        row.status == "active"
            && !secret_changed
            && row
                .verified_at
                .is_some_and(|at| at > now - VERIFICATION_REUSE)
    });
    if !reuse_verification {
        verify(&state, subscription.url, &id, &key).await?;
    }
    let lifetime = request
        .ttl_ms
        .map(|ms| ms / 1000)
        .unwrap_or(RETENTION.num_seconds())
        .clamp(MIN_LIFETIME_SECONDS, RETENTION.num_seconds());
    let refresh_before = now + TimeDelta::seconds(lifetime);
    let ciphertext = secrets.encrypt(secret, &id).map_err(ApiError::internal)?;
    sqlx::query(
        r#"
        INSERT INTO event_subscriptions (
            id, account_id, target_kind, callback_url, secret_ciphertext, kinds, runtime_ids,
            all_runtimes, status, refresh_before, owner_grant_id, filter, verified_at,
            created_at, updated_at
        ) VALUES ($1, $2, 'mcp_events', $3, $4, $5, $6, $7, 'active', $8, $9, $10, $11, $12, $12)
        ON CONFLICT (id) DO UPDATE SET
            previous_secret_ciphertext = CASE WHEN $13
                THEN event_subscriptions.secret_ciphertext
                ELSE event_subscriptions.previous_secret_ciphertext END,
            previous_secret_until = CASE WHEN $13
                THEN $14 ELSE event_subscriptions.previous_secret_until END,
            secret_ciphertext = EXCLUDED.secret_ciphertext,
            runtime_ids = EXCLUDED.runtime_ids,
            all_runtimes = EXCLUDED.all_runtimes,
            filter = EXCLUDED.filter,
            status = 'active',
            refresh_before = EXCLUDED.refresh_before,
            verified_at = COALESCE(EXCLUDED.verified_at, event_subscriptions.verified_at),
            last_error = NULL,
            updated_at = EXCLUDED.updated_at
        "#,
    )
    .bind(&id)
    .bind(auth.account_id)
    .bind(subscription.url)
    .bind(&ciphertext)
    .bind(vec![subscription.kind.name.to_owned()])
    .bind(&runtime_ids)
    .bind(all_runtimes)
    .bind(refresh_before)
    .bind(auth.grant_id)
    .bind(Value::Object(filter))
    .bind((!reuse_verification).then_some(now))
    .bind(now)
    .bind(secret_changed)
    .bind(now + ROTATION_WINDOW)
    .execute(&state.pool)
    .await?;
    if request.cursor.is_some() {
        backfill(&state, &id, anchor).await?;
        state.events.wake.notify_one();
    }
    Ok(Json(McpSubscribeResponse {
        id,
        refresh_before: refresh_before.to_rfc3339_opts(SecondsFormat::Secs, true),
        cursor: cursor::encode(anchor),
        truncated,
    }))
}

/// Idempotent: unknown or already removed subscriptions also answer `204`.
pub async fn unsubscribe(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<McpUnsubscribeRequest>,
) -> Result<StatusCode, ApiError> {
    let auth = authorize(&headers, &state).await?;
    let subscription = parse(&request.name, &request.arguments, &request.delivery)?;
    let id = subscription_id(&auth, &subscription);
    delete_owned(&state, &auth, &id).await
}

pub async fn delete_subscription(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    let auth = authorize(&headers, &state).await?;
    delete_owned(&state, &auth, &id).await
}

async fn delete_owned(
    state: &AppState,
    auth: &McpAuthContext,
    id: &str,
) -> Result<StatusCode, ApiError> {
    sqlx::query(
        "DELETE FROM event_subscriptions WHERE id = $1 AND account_id = $2 AND owner_grant_id = $3",
    )
    .bind(id)
    .bind(auth.account_id)
    .bind(auth.grant_id)
    .execute(&state.pool)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}
