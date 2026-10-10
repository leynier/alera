//! Fan-out: one `event_deliveries` row per new event and matching subscription.

use chrono::{DateTime, TimeDelta, Utc};

use crate::{error::ApiError, state::AppState};

use super::delivery::SUBSCRIPTION_EXPIRED;

/// Events and their deliveries live for 24 hours after the cloud receives them.
pub const RETENTION: TimeDelta = TimeDelta::hours(24);
const FAN_OUT_BATCH: i64 = 500;

/// Matches event `m` to subscription `s`. `$1` is now, `$2` the MCP Events switch.
/// MCP Events subscriptions also need MCP Control on the event's runtime (not `off`) and
/// a live grant that still reaches it. Webhooks belong to the account owner and do not
/// depend on MCP Control.
const MATCH: &str = r#"
    s.account_id = m.account_id
    AND s.status = 'active'
    AND (s.refresh_before IS NULL OR s.refresh_before > $1)
    AND m.kind = ANY(s.kinds)
    AND (s.all_runtimes OR m.runtime_id = ANY(s.runtime_ids))
    AND NOT EXISTS (
        SELECT 1 FROM jsonb_each_text(s.filter) f
        WHERE f.value IS DISTINCT FROM (
            CASE f.key
                WHEN 'workspaceId' THEN m.workspace_id
                WHEN 'projectId' THEN m.project_id
                ELSE m.data ->> f.key
            END
        )
    )
    AND (
        s.target_kind = 'webhook'
        OR ($2 AND EXISTS (
            SELECT 1 FROM runtimes r
            WHERE r.id = m.runtime_id AND r.mcp_access <> 'off'
        ) AND EXISTS (
            SELECT 1 FROM mcp_grants g
            WHERE g.id = s.owner_grant_id
              AND g.revoked_at IS NULL
              AND (g.all_runtimes OR EXISTS (
                  SELECT 1 FROM mcp_grant_runtimes gr
                  WHERE gr.grant_id = g.id AND gr.runtime_id = m.runtime_id
              ))
        ))
    )
"#;

/// Fans out events that have not been fanned out yet. Concurrent workers skip each
/// other's rows. Returns the number of deliveries created.
pub async fn fan_out_pending(state: &AppState) -> Result<u64, ApiError> {
    let now = Utc::now();
    let created = sqlx::query_scalar::<_, i64>(sqlx::AssertSqlSafe(format!(
        r#"
        WITH claimed AS (
            SELECT id FROM domain_events
            WHERE fanned_out_at IS NULL
            ORDER BY received_at
            LIMIT $3
            FOR UPDATE SKIP LOCKED
        ),
        marked AS (
            UPDATE domain_events e SET fanned_out_at = $1
            FROM claimed c WHERE e.id = c.id
            RETURNING e.*
        ),
        inserted AS (
            INSERT INTO event_deliveries (
                id, subscription_id, event_id, status, attempts, next_attempt_at, created_at
            )
            SELECT gen_random_uuid(), s.id, m.id, 'pending', 0, $1, $1
            FROM marked m
            JOIN event_subscriptions s ON {MATCH}
            WHERE m.received_at > $4
            ON CONFLICT (subscription_id, event_id) DO NOTHING
            RETURNING 1
        )
        SELECT COUNT(*) FROM inserted
        "#
    )))
    .bind(now)
    .bind(state.config.events.mcp_events_enabled)
    .bind(FAN_OUT_BATCH)
    .bind(now - RETENTION)
    .fetch_one(&state.pool)
    .await?;
    Ok(created.max(0) as u64)
}

/// Queues every retained event since `since` for one subscription (MCP Events replay).
/// Deliveries that already exist are kept, so acknowledged events are not sent again,
/// except those stopped because the subscription expired: the refresh queues them again
/// with a fresh retry budget. Deliveries stopped for other reasons (revoked grant,
/// MCP Control off, `410 Gone`) stay stopped.
pub async fn backfill(
    state: &AppState,
    subscription_id: &str,
    since: DateTime<Utc>,
) -> Result<u64, ApiError> {
    let now = Utc::now();
    let since = since.max(now - RETENTION);
    let created = sqlx::query(sqlx::AssertSqlSafe(format!(
        r#"
        INSERT INTO event_deliveries (
            id, subscription_id, event_id, status, attempts, next_attempt_at, created_at
        )
        SELECT gen_random_uuid(), s.id, m.id, 'pending', 0, $1, $1
        FROM domain_events m
        JOIN event_subscriptions s ON s.id = $3 AND {MATCH}
        WHERE m.received_at >= $4
        ON CONFLICT (subscription_id, event_id) DO UPDATE SET
            status = 'pending', attempts = 0, next_attempt_at = $1, lease_until = NULL,
            last_status = NULL, last_error = NULL
        WHERE event_deliveries.status = 'stopped' AND event_deliveries.last_error = $5
        "#
    )))
    .bind(now)
    .bind(state.config.events.mcp_events_enabled)
    .bind(subscription_id)
    .bind(since)
    .bind(SUBSCRIPTION_EXPIRED)
    .execute(&state.pool)
    .await?
    .rows_affected();
    Ok(created)
}
