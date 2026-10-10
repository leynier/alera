//! Signed webhook delivery: claim with a 45-second lease, recheck authorization, sign with
//! Standard Webhooks, send, and settle with the retry policy.

use std::time::Duration;

use chrono::{DateTime, TimeDelta, Utc};
use serde::Serialize;
use serde_json::{Map, Value};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{error::ApiError, state::AppState};

use super::{
    callback::CallbackError, catalog::TEST_EVENT_KIND, cursor, fanout::RETENTION,
    secrets::signing_key,
};

pub use super::wire::{event_body, signed_headers};

pub const LEASE: TimeDelta = TimeDelta::seconds(45);
pub const MAX_ATTEMPTS: i32 = 12;
const CLAIM_BATCH: i64 = 16;
const FIRST_RETRY: Duration = Duration::from_secs(5);
const MAX_RETRY: Duration = Duration::from_secs(15 * 60);

/// The wait after `attempts` failed attempts: 5 s doubling up to 15 minutes.
pub fn retry_delay(attempts: i32) -> Duration {
    let exponent = attempts.saturating_sub(1).clamp(0, 16) as u32;
    FIRST_RETRY
        .saturating_mul(2_u32.saturating_pow(exponent))
        .min(MAX_RETRY)
}

/// How one attempt settles.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    Delivered(u16),
    /// Transient: 5xx, 408, 425, 429, timeouts, and connection or DNS failures.
    Retry(String),
    /// Definitive: 413, redirects, other 4xx, and callbacks that can never be valid.
    Dead(String),
    /// `410 Gone`: the receiver ended the subscription.
    Gone,
}

pub fn classify(result: &Result<u16, CallbackError>) -> Outcome {
    match result {
        Ok(status) if (200..300).contains(status) => Outcome::Delivered(*status),
        Ok(410) => Outcome::Gone,
        Ok(status @ (408 | 425 | 429)) => Outcome::Retry(format!("http_{status}")),
        Ok(status) if *status >= 500 => Outcome::Retry(format!("http_{status}")),
        Ok(status) => Outcome::Dead(format!("http_{status}")),
        Err(error) if error.is_permanent() => Outcome::Dead(error.reason().to_owned()),
        Err(error) => Outcome::Retry(error.reason().to_owned()),
    }
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PassSummary {
    pub fanned_out: u64,
    pub claimed: usize,
    pub delivered: usize,
}

#[derive(FromRow)]
struct Claimed {
    id: Uuid,
    attempts: i32,
    subscription_id: String,
    target_kind: String,
    callback_url: String,
    secret_ciphertext: String,
    previous_secret_ciphertext: Option<String>,
    previous_secret_until: Option<DateTime<Utc>>,
    status: String,
    refresh_before: Option<DateTime<Utc>>,
    authorized: bool,
    /// False for an MCP Events delivery whose runtime has MCP Control off.
    runtime_allowed: bool,
    event_id: String,
    kind: String,
    runtime_id: String,
    workspace_id: Option<String>,
    project_id: Option<String>,
    seq: i64,
    data: Value,
    occurred_at: DateTime<Utc>,
    received_at: DateTime<Utc>,
    cursor_anchor: Option<DateTime<Utc>>,
}

/// One worker pass: fan out new events, then claim and send due deliveries.
pub async fn run_pass(state: &AppState) -> Result<PassSummary, ApiError> {
    let mut summary = PassSummary {
        fanned_out: super::fanout::fan_out_pending(state).await?,
        ..PassSummary::default()
    };
    if state.events.secrets.is_none() {
        return Ok(summary);
    }
    let claimed = claim(state).await?;
    summary.claimed = claimed.len();
    let mut tasks = tokio::task::JoinSet::new();
    for delivery in claimed {
        let state = state.clone();
        tasks.spawn(async move { deliver(&state, delivery).await });
    }
    while let Some(result) = tasks.join_next().await {
        match result {
            Ok(Ok(true)) => summary.delivered += 1,
            Ok(Ok(false)) => {}
            Ok(Err(error)) => tracing::warn!(error = %error, "event delivery failed"),
            Err(error) => tracing::warn!(error = %error, "event delivery task failed"),
        }
    }
    Ok(summary)
}

async fn claim(state: &AppState) -> Result<Vec<Claimed>, ApiError> {
    let now = Utc::now();
    let ids = sqlx::query_scalar::<_, Uuid>(
        r#"
        WITH due AS (
            SELECT id FROM event_deliveries
            WHERE status IN ('pending', 'sending') AND next_attempt_at <= $1
            ORDER BY next_attempt_at
            LIMIT $2
            FOR UPDATE SKIP LOCKED
        )
        UPDATE event_deliveries d
        SET status = 'sending', attempts = d.attempts + 1, lease_until = $3, next_attempt_at = $3
        FROM due WHERE d.id = due.id
        RETURNING d.id
        "#,
    )
    .bind(now)
    .bind(CLAIM_BATCH)
    .bind(now + LEASE)
    .fetch_all(&state.pool)
    .await?;
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    Ok(sqlx::query_as::<_, Claimed>(
        r#"
        SELECT d.id, d.attempts, s.id AS subscription_id, s.target_kind, s.callback_url,
               s.secret_ciphertext, s.previous_secret_ciphertext, s.previous_secret_until,
               s.status, s.refresh_before,
               (s.target_kind = 'webhook' OR EXISTS (
                   SELECT 1 FROM runtimes r
                   WHERE r.id = e.runtime_id AND r.mcp_access <> 'off'
               )) AS runtime_allowed,
               (s.target_kind = 'webhook' OR ($2 AND EXISTS (
                   SELECT 1 FROM mcp_grants g
                   WHERE g.id = s.owner_grant_id AND g.revoked_at IS NULL
                     AND (g.all_runtimes OR EXISTS (
                         SELECT 1 FROM mcp_grant_runtimes gr
                         WHERE gr.grant_id = g.id AND gr.runtime_id = e.runtime_id
                     ))
               ))) AS authorized,
               e.event_id, e.kind, e.runtime_id, e.workspace_id, e.project_id, e.seq, e.data,
               e.occurred_at, e.received_at,
               (SELECT MIN(e2.received_at)
                FROM event_deliveries d2 JOIN domain_events e2 ON e2.id = d2.event_id
                WHERE d2.subscription_id = s.id AND d2.status IN ('pending', 'sending')
               ) AS cursor_anchor
        FROM event_deliveries d
        JOIN event_subscriptions s ON s.id = d.subscription_id
        JOIN domain_events e ON e.id = d.event_id
        WHERE d.id = ANY($1)
        "#,
    )
    .bind(&ids)
    .bind(state.config.events.mcp_events_enabled)
    .fetch_all(&state.pool)
    .await?)
}

/// The decrypted signing keys: the current one, plus the previous one while it rotates out.
fn signing_keys(state: &AppState, delivery: &Claimed, now: DateTime<Utc>) -> Option<Vec<Vec<u8>>> {
    let secrets = state.events.secrets.as_ref()?;
    let id = &delivery.subscription_id;
    let mut keys = vec![signing_key(
        &secrets.decrypt(&delivery.secret_ciphertext, id).ok()?,
    )?];
    if let (Some(previous), Some(until)) = (
        &delivery.previous_secret_ciphertext,
        delivery.previous_secret_until,
    ) {
        if until > now {
            if let Some(key) = secrets
                .decrypt(previous, id)
                .ok()
                .and_then(|secret| signing_key(&secret))
            {
                keys.push(key);
            }
        }
    }
    Some(keys)
}

async fn deliver(state: &AppState, delivery: Claimed) -> Result<bool, ApiError> {
    let now = Utc::now();
    if delivery.received_at + RETENTION <= now {
        settle(state, &delivery, Outcome::Dead("expired".to_owned())).await?;
        return Ok(false);
    }
    let stop = if delivery.status != "active" {
        Some(None)
    } else if delivery.refresh_before.is_some_and(|at| at <= now) {
        Some(Some("expired"))
    } else if !delivery.authorized {
        Some(Some("revoked"))
    } else {
        None
    };
    if stop.is_none() && !delivery.runtime_allowed {
        // MCP Control is off on this runtime: drop the event, keep the subscription,
        // which may cover other runtimes or resume when MCP Control comes back on.
        finish(
            state,
            &delivery,
            "stopped",
            None,
            Some("runtime_mcp_disabled"),
            None,
        )
        .await?;
        return Ok(false);
    }
    if let Some(new_status) = stop {
        if let Some(new_status) = new_status {
            stop_subscription(state, &delivery.subscription_id, new_status, None).await?;
        }
        finish(
            state,
            &delivery,
            "stopped",
            None,
            Some("subscription_inactive"),
            None,
        )
        .await?;
        return Ok(false);
    }
    let Some(keys) = signing_keys(state, &delivery, now) else {
        settle(
            state,
            &delivery,
            Outcome::Dead("secret_unavailable".to_owned()),
        )
        .await?;
        return Ok(false);
    };
    let anchor = delivery.cursor_anchor.unwrap_or(delivery.received_at);
    let data = if delivery.kind == TEST_EVENT_KIND {
        Value::Object(Map::new())
    } else {
        delivery.data.clone()
    };
    let body = event_body(
        &delivery.event_id,
        &delivery.kind,
        delivery.occurred_at,
        (
            &delivery.runtime_id,
            delivery.workspace_id.as_deref(),
            delivery.project_id.as_deref(),
            delivery.seq,
        ),
        &data,
        &cursor::encode(anchor),
    );
    let body = serde_json::to_vec(&body).map_err(ApiError::internal)?;
    let header = if delivery.target_kind == "mcp_events" {
        "x-mcp-subscription-id"
    } else {
        "x-alera-webhook-id"
    };
    let headers = signed_headers(
        &delivery.event_id,
        (header, &delivery.subscription_id),
        &keys,
        &body,
    );
    let result = state
        .events
        .callbacks
        .post(&delivery.callback_url, &headers, body)
        .await
        .map(|reply| reply.status);
    let outcome = classify(&result);
    let delivered = matches!(outcome, Outcome::Delivered(_));
    settle(state, &delivery, outcome).await?;
    Ok(delivered)
}

async fn settle(state: &AppState, delivery: &Claimed, outcome: Outcome) -> Result<(), ApiError> {
    let now = Utc::now();
    match outcome {
        Outcome::Delivered(status) => {
            finish(
                state,
                delivery,
                "delivered",
                Some(i32::from(status)),
                None,
                None,
            )
            .await?;
            sqlx::query(
                "UPDATE event_subscriptions SET last_delivery_at = $2, last_error = NULL, updated_at = $2 WHERE id = $1",
            )
            .bind(&delivery.subscription_id)
            .bind(now)
            .execute(&state.pool)
            .await?;
        }
        Outcome::Gone => {
            stop_subscription(
                state,
                &delivery.subscription_id,
                "stopped",
                Some("http_410"),
            )
            .await?;
            finish(
                state,
                delivery,
                "stopped",
                Some(410),
                Some("http_410"),
                None,
            )
            .await?;
        }
        Outcome::Dead(reason) => {
            record_error(state, &delivery.subscription_id, &reason).await?;
            finish(
                state,
                delivery,
                "dead",
                status_of(&reason),
                Some(&reason),
                None,
            )
            .await?;
        }
        Outcome::Retry(reason) => {
            record_error(state, &delivery.subscription_id, &reason).await?;
            let delay = TimeDelta::from_std(retry_delay(delivery.attempts)).unwrap_or(LEASE);
            let next = now + delay;
            if delivery.attempts >= MAX_ATTEMPTS || next >= delivery.received_at + RETENTION {
                finish(
                    state,
                    delivery,
                    "dead",
                    status_of(&reason),
                    Some(&reason),
                    None,
                )
                .await?;
            } else {
                finish(
                    state,
                    delivery,
                    "pending",
                    status_of(&reason),
                    Some(&reason),
                    Some(next),
                )
                .await?;
            }
        }
    }
    Ok(())
}

fn status_of(reason: &str) -> Option<i32> {
    reason
        .strip_prefix("http_")
        .and_then(|code| code.parse().ok())
}

/// Settles the claim only if this worker still holds it (same attempt, still sending).
async fn finish(
    state: &AppState,
    delivery: &Claimed,
    status: &str,
    http_status: Option<i32>,
    error: Option<&str>,
    next_attempt_at: Option<DateTime<Utc>>,
) -> Result<(), ApiError> {
    let now = Utc::now();
    sqlx::query(
        r#"
        UPDATE event_deliveries
        SET status = $3, last_status = COALESCE($4, last_status), last_error = $5,
            next_attempt_at = COALESCE($6, next_attempt_at), lease_until = NULL,
            delivered_at = CASE WHEN $3 = 'delivered' THEN $7 ELSE delivered_at END
        WHERE id = $1 AND attempts = $2 AND status = 'sending'
        "#,
    )
    .bind(delivery.id)
    .bind(delivery.attempts)
    .bind(status)
    .bind(http_status)
    .bind(error)
    .bind(next_attempt_at)
    .bind(now)
    .execute(&state.pool)
    .await?;
    Ok(())
}

async fn record_error(
    state: &AppState,
    subscription_id: &str,
    reason: &str,
) -> Result<(), ApiError> {
    sqlx::query("UPDATE event_subscriptions SET last_error = $2, updated_at = $3 WHERE id = $1")
        .bind(subscription_id)
        .bind(reason)
        .bind(Utc::now())
        .execute(&state.pool)
        .await?;
    Ok(())
}

/// Ends a subscription and drops the deliveries still waiting for it.
pub async fn stop_subscription(
    state: &AppState,
    subscription_id: &str,
    status: &str,
    error: Option<&str>,
) -> Result<(), ApiError> {
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    sqlx::query(
        "UPDATE event_subscriptions SET status = $2, last_error = COALESCE($3, last_error), updated_at = $4 WHERE id = $1 AND status = 'active'",
    )
    .bind(subscription_id)
    .bind(status)
    .bind(error)
    .bind(now)
    .execute(&mut *transaction)
    .await?;
    sqlx::query(
        "UPDATE event_deliveries SET status = 'stopped', lease_until = NULL WHERE subscription_id = $1 AND status = 'pending'",
    )
    .bind(subscription_id)
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await?;
    Ok(())
}

#[cfg(test)]
#[path = "delivery_tests.rs"]
mod tests;
