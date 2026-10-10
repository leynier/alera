//! Generic webhooks, managed by a signed-in runtime on behalf of its account.

use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use chrono::{DateTime, Utc};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{error::ApiError, state::AppState};

use super::{
    callback::CallbackError,
    catalog::{self, TEST_EVENT_KIND},
    ingest::{authenticate_runtime, valid_id},
    models::{CreateWebhookRequest, CreatedWebhook, TestDelivery, WebhookList, WebhookSummary},
    secrets::{generate_secret, SecretBox},
};

pub const MAX_WEBHOOKS_PER_ACCOUNT: i64 = 20;
const MAX_RUNTIME_IDS: usize = 20;

#[derive(FromRow)]
struct WebhookRow {
    id: String,
    callback_url: String,
    kinds: Vec<String>,
    runtime_ids: Vec<String>,
    all_runtimes: bool,
    status: String,
    created_at: DateTime<Utc>,
    last_delivery_at: Option<DateTime<Utc>>,
    last_error: Option<String>,
}

impl From<WebhookRow> for WebhookSummary {
    fn from(row: WebhookRow) -> Self {
        Self {
            id: row.id,
            url: row.callback_url,
            kinds: row.kinds,
            runtime_ids: row.runtime_ids,
            all_runtimes: row.all_runtimes,
            status: row.status,
            created_at: row.created_at,
            last_delivery_at: row.last_delivery_at,
            last_error: row.last_error,
        }
    }
}

const WEBHOOK_COLUMNS: &str = "id, callback_url, kinds, runtime_ids, all_runtimes, status, created_at, last_delivery_at, last_error";

/// The secret box, or `503` when the cloud has no webhook encryption key.
pub fn require_secrets(state: &AppState) -> Result<Arc<SecretBox>, ApiError> {
    state.events.secrets.clone().ok_or_else(|| {
        ApiError::unavailable(
            "webhooks_not_configured",
            "Webhooks are not configured on this Alera cloud (ALERA_WEBHOOK_SECRET_KEY is missing).",
        )
    })
}

/// Checks the URL and its DNS answers before anything is stored.
pub async fn check_callback(state: &AppState, url: &str) -> Result<(), CallbackError> {
    let parsed = state.events.callbacks.validate_url(url)?;
    state
        .events
        .callbacks
        .destination(&parsed)
        .await
        .map(|_| ())
}

pub async fn list_webhooks(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<WebhookList>, ApiError> {
    let auth = authenticate_runtime(&headers, &state).await?;
    let rows = sqlx::query_as::<_, WebhookRow>(sqlx::AssertSqlSafe(format!(
        "SELECT {WEBHOOK_COLUMNS} FROM event_subscriptions WHERE account_id = $1 AND target_kind = 'webhook' ORDER BY created_at, id"
    )))
    .bind(auth.account_id)
    .fetch_all(&state.pool)
    .await?;
    Ok(Json(WebhookList {
        webhooks: rows.into_iter().map(WebhookSummary::from).collect(),
    }))
}

pub async fn create_webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateWebhookRequest>,
) -> Result<Json<CreatedWebhook>, ApiError> {
    let auth = authenticate_runtime(&headers, &state).await?;
    let secrets = require_secrets(&state)?;
    let kinds = validate_kinds(&request.kinds)?;
    let runtime_ids = if request.all_runtimes {
        Vec::new()
    } else {
        let mut ids = request
            .runtime_ids
            .clone()
            .unwrap_or_else(|| vec![auth.client_id.clone()]);
        ids.sort();
        ids.dedup();
        if ids.is_empty() || ids.len() > MAX_RUNTIME_IDS || !ids.iter().all(|id| valid_id(id)) {
            return Err(ApiError::bad_request(
                "invalid_webhook_runtimes",
                "Name 1 to 20 runtimes, or set allRuntimes.",
            ));
        }
        let owned = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM runtimes WHERE account_id = $1 AND transferred_at IS NULL AND id = ANY($2)",
        )
        .bind(auth.account_id)
        .bind(&ids)
        .fetch_one(&state.pool)
        .await?;
        if owned != ids.len() as i64 {
            return Err(ApiError::not_found(
                "runtime_not_found",
                "A webhook runtime does not belong to this account.",
            ));
        }
        ids
    };
    check_callback(&state, &request.url)
        .await
        .map_err(|error| {
            ApiError::bad_request(
                "invalid_webhook_url",
                format!(
                    "Webhook URLs must use HTTPS on port 443 and resolve to public addresses ({}).",
                    error.reason()
                ),
            )
        })?;
    let count = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM event_subscriptions WHERE account_id = $1 AND target_kind = 'webhook'",
    )
    .bind(auth.account_id)
    .fetch_one(&state.pool)
    .await?;
    if count >= MAX_WEBHOOKS_PER_ACCOUNT {
        return Err(ApiError::conflict(
            "webhook_limit_reached",
            format!("An account can have at most {MAX_WEBHOOKS_PER_ACCOUNT} webhooks."),
        ));
    }
    let id = Uuid::now_v7().to_string();
    let secret = generate_secret();
    let ciphertext = secrets.encrypt(&secret, &id).map_err(ApiError::internal)?;
    let now = Utc::now();
    let row = sqlx::query_as::<_, WebhookRow>(sqlx::AssertSqlSafe(format!(
        r#"
        INSERT INTO event_subscriptions (
            id, account_id, target_kind, callback_url, secret_ciphertext, kinds, runtime_ids,
            all_runtimes, status, filter, created_by_runtime_id, created_at, updated_at
        ) VALUES ($1, $2, 'webhook', $3, $4, $5, $6, $7, 'active', '{{}}'::jsonb, $8, $9, $9)
        RETURNING {WEBHOOK_COLUMNS}
        "#
    )))
    .bind(&id)
    .bind(auth.account_id)
    .bind(&request.url)
    .bind(&ciphertext)
    .bind(&kinds)
    .bind(&runtime_ids)
    .bind(request.all_runtimes)
    .bind(&auth.client_id)
    .bind(now)
    .fetch_one(&state.pool)
    .await?;
    Ok(Json(CreatedWebhook {
        webhook: row.into(),
        secret,
    }))
}

pub async fn delete_webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    let auth = authenticate_runtime(&headers, &state).await?;
    let deleted = sqlx::query(
        "DELETE FROM event_subscriptions WHERE id = $1 AND account_id = $2 AND target_kind = 'webhook'",
    )
    .bind(&id)
    .bind(auth.account_id)
    .execute(&state.pool)
    .await?
    .rows_affected();
    if deleted == 0 {
        return Err(webhook_not_found());
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Queues a signed `alera.test` delivery to the webhook.
pub async fn test_webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<Json<TestDelivery>, ApiError> {
    let auth = authenticate_runtime(&headers, &state).await?;
    require_secrets(&state)?;
    let status = sqlx::query_scalar::<_, String>(
        "SELECT status FROM event_subscriptions WHERE id = $1 AND account_id = $2 AND target_kind = 'webhook'",
    )
    .bind(&id)
    .bind(auth.account_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(webhook_not_found)?;
    if status != "active" {
        return Err(ApiError::conflict(
            "webhook_inactive",
            format!("The webhook is {status}; create it again to resume deliveries."),
        ));
    }
    let now = Utc::now();
    let event_id = Uuid::now_v7();
    let delivery_id = Uuid::now_v7();
    let mut transaction = state.pool.begin().await?;
    sqlx::query(
        r#"
        INSERT INTO domain_events (
            id, account_id, runtime_id, event_id, seq, kind, data, occurred_at, received_at,
            fanned_out_at
        ) VALUES ($1, $2, $3, $4, 0, $5, '{}'::jsonb, $6, $6, $6)
        "#,
    )
    .bind(event_id)
    .bind(auth.account_id)
    .bind(&auth.client_id)
    .bind(event_id.to_string())
    .bind(TEST_EVENT_KIND)
    .bind(now)
    .execute(&mut *transaction)
    .await?;
    sqlx::query(
        r#"
        INSERT INTO event_deliveries (
            id, subscription_id, event_id, status, attempts, next_attempt_at, created_at
        ) VALUES ($1, $2, $3, 'pending', 0, $4, $4)
        "#,
    )
    .bind(delivery_id)
    .bind(&id)
    .bind(event_id)
    .bind(now)
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await?;
    state.events.wake.notify_one();
    Ok(Json(TestDelivery { delivery_id }))
}

fn validate_kinds(kinds: &[String]) -> Result<Vec<String>, ApiError> {
    let mut kinds = kinds.to_vec();
    kinds.sort();
    kinds.dedup();
    if kinds.is_empty() || !kinds.iter().all(|kind| catalog::kind(kind).is_some()) {
        return Err(ApiError::bad_request(
            "invalid_webhook_kinds",
            format!(
                "Name one or more event kinds: {}.",
                catalog::EVENT_KINDS
                    .iter()
                    .map(|kind| kind.name)
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        ));
    }
    Ok(kinds)
}

fn webhook_not_found() -> ApiError {
    ApiError::not_found("webhook_not_found", "The webhook does not exist.")
}
