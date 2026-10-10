//! Runtime side: `POST /v1/runtime/domain-events` and `GET /v1/runtime/event-subscriptions`.

use std::collections::HashSet;

use axum::{extract::State, http::HeaderMap, Json};
use chrono::{TimeDelta, Utc};
use uuid::Uuid;

use crate::{
    api_models::ClientKind,
    auth::{authenticate_any, AuthContext},
    error::ApiError,
    state::AppState,
};

use super::{
    catalog::{self, DataViolation},
    models::{
        DomainEventBatch, DomainEventBatchResponse, DomainEventInput, EventSubscriptionCount,
        RejectedEvent,
    },
};

pub const MAX_BATCH_EVENTS: usize = 100;
/// Tokens issued before `events:send` existed carry `push:send`.
pub const RUNTIME_EVENT_SCOPES: [&str; 2] = ["events:send", "push:send"];

/// Authenticates the runtime itself and returns its session.
pub async fn authenticate_runtime(
    headers: &HeaderMap,
    state: &AppState,
) -> Result<AuthContext, ApiError> {
    let auth = authenticate_any(headers, state, &RUNTIME_EVENT_SCOPES).await?;
    if auth.client_kind != ClientKind::Runtime {
        return Err(ApiError::forbidden(
            "runtime_session_required",
            "A runtime session is required.",
        ));
    }
    Ok(auth)
}

pub async fn post_domain_events(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(batch): Json<DomainEventBatch>,
) -> Result<Json<DomainEventBatchResponse>, ApiError> {
    let auth = authenticate_runtime(&headers, &state).await?;
    if auth.client_id != batch.runtime_id {
        return Err(not_owned());
    }
    let (valid, rejected) = validate_batch(&batch)?;
    let owned = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM runtimes
            WHERE id = $1 AND account_id = $2 AND transferred_at IS NULL
        )
        "#,
    )
    .bind(&batch.runtime_id)
    .bind(auth.account_id)
    .fetch_one(&state.pool)
    .await?;
    if !owned {
        return Err(not_owned());
    }
    let mut seen = HashSet::new();
    let unique: Vec<&DomainEventInput> = valid
        .iter()
        .copied()
        .filter(|event| seen.insert(event.event_id.to_ascii_lowercase()))
        .collect();
    let repeated = valid.len() - unique.len();
    let accepted = insert_events(&state, &auth, &batch.runtime_id, &unique).await?;
    if accepted > 0 {
        super::fanout::fan_out_pending(&state).await?;
        state.events.wake.notify_one();
    }
    let active_subscriptions =
        active_subscription_count(&state, auth.account_id, &batch.runtime_id).await?;
    Ok(Json(DomainEventBatchResponse {
        accepted,
        duplicate: unique.len() - accepted + repeated,
        active_subscriptions,
        rejected,
    }))
}

pub async fn get_event_subscriptions(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<EventSubscriptionCount>, ApiError> {
    let auth = authenticate_runtime(&headers, &state).await?;
    let active_subscriptions =
        active_subscription_count(&state, auth.account_id, &auth.client_id).await?;
    Ok(Json(EventSubscriptionCount {
        active_subscriptions,
    }))
}

async fn insert_events(
    state: &AppState,
    auth: &AuthContext,
    runtime_id: &str,
    events: &[&DomainEventInput],
) -> Result<usize, ApiError> {
    if events.is_empty() {
        return Ok(0);
    }
    let now = Utc::now();
    let mut ids = Vec::with_capacity(events.len());
    let mut event_ids = Vec::with_capacity(events.len());
    let mut seqs = Vec::with_capacity(events.len());
    let mut kinds = Vec::with_capacity(events.len());
    let mut workspaces = Vec::with_capacity(events.len());
    let mut projects = Vec::with_capacity(events.len());
    let mut data = Vec::with_capacity(events.len());
    let mut occurred = Vec::with_capacity(events.len());
    for event in events {
        let Some(kind) = catalog::kind(&event.kind) else {
            return Err(invalid("kind"));
        };
        ids.push(Uuid::now_v7());
        event_ids.push(event.event_id.to_ascii_lowercase());
        seqs.push(event.seq);
        kinds.push(event.kind.clone());
        let projected = catalog::project_data(kind, &event.data);
        // Kinds that list workspaceId in data also fill the envelope column filters use.
        let workspace = event.workspace_id.clone().or_else(|| {
            projected
                .get("workspaceId")
                .and_then(serde_json::Value::as_str)
                .filter(|value| valid_id(value))
                .map(ToOwned::to_owned)
        });
        workspaces.push(workspace);
        projects.push(event.project_id.clone());
        data.push(projected);
        occurred.push(event.occurred_at);
    }
    let inserted = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO domain_events (
            id, account_id, runtime_id, event_id, seq, kind, workspace_id, project_id,
            data, occurred_at, received_at
        )
        SELECT e.id, $1, $2, e.event_id, e.seq, e.kind, e.workspace_id, e.project_id,
               e.data, e.occurred_at, $3
        FROM UNNEST(
            $4::uuid[], $5::text[], $6::bigint[], $7::text[], $8::text[], $9::text[],
            $10::jsonb[], $11::timestamptz[]
        ) AS e(id, event_id, seq, kind, workspace_id, project_id, data, occurred_at)
        ON CONFLICT (runtime_id, event_id) DO NOTHING
        RETURNING id
        "#,
    )
    .bind(auth.account_id)
    .bind(runtime_id)
    .bind(now)
    .bind(&ids)
    .bind(&event_ids)
    .bind(&seqs)
    .bind(&kinds)
    .bind(&workspaces)
    .bind(&projects)
    .bind(&data)
    .bind(&occurred)
    .fetch_all(&state.pool)
    .await?;
    Ok(inserted.len())
}

/// Splits a batch into the events that pass the payload policy and the ones that do not.
/// Only a malformed batch as a whole (empty or oversized) fails the request: a runtime
/// retries a failed request with the same batch, so one bad event must not fail it.
fn validate_batch(
    batch: &DomainEventBatch,
) -> Result<(Vec<&DomainEventInput>, Vec<RejectedEvent>), ApiError> {
    if batch.events.is_empty() || batch.events.len() > MAX_BATCH_EVENTS {
        return Err(ApiError::bad_request(
            "invalid_event_batch",
            format!("A batch carries 1 to {MAX_BATCH_EVENTS} events."),
        ));
    }
    let latest = Utc::now() + TimeDelta::minutes(5);
    let mut valid = Vec::new();
    let mut rejected = Vec::new();
    for event in &batch.events {
        match validate_event(event, latest) {
            Ok(()) => valid.push(event),
            Err(error) => rejected.push(RejectedEvent {
                event_id: truncated(&event.event_id),
                code: error_code(&error),
            }),
        }
    }
    Ok((valid, rejected))
}

fn error_code(error: &ApiError) -> &'static str {
    match error {
        ApiError::Request { code, .. } => code,
        _ => "invalid_event",
    }
}

pub(crate) fn validate_event(
    event: &DomainEventInput,
    latest: chrono::DateTime<Utc>,
) -> Result<(), ApiError> {
    if Uuid::parse_str(&event.event_id).is_err() {
        return Err(invalid("eventId"));
    }
    if event.seq < 0 {
        return Err(invalid("seq"));
    }
    if catalog::kind(&event.kind).is_none() {
        return Err(ApiError::bad_request(
            "unknown_event_kind",
            format!("Unknown event kind {}.", truncated(&event.kind)),
        ));
    }
    for (value, field) in [
        (&event.workspace_id, "workspaceId"),
        (&event.project_id, "projectId"),
    ] {
        if let Some(value) = value {
            if !valid_id(value) {
                return Err(invalid(field));
            }
        }
    }
    if event.occurred_at > latest {
        return Err(ApiError::bad_request(
            "invalid_event_time",
            "The event timestamp is too far in the future.",
        ));
    }
    catalog::check_data(&event.data).map_err(|violation| match violation {
        DataViolation::SensitiveKey => ApiError::bad_request(
            "sensitive_event_data",
            "Events carry ids and states only; prompts, message text, commands, and output are refused.",
        ),
        DataViolation::TooManyKeys => ApiError::bad_request(
            "event_data_too_large",
            "Event data has too many fields.",
        ),
        _ => ApiError::bad_request(
            "invalid_event_data",
            "Event data must be a flat object of short scalar values.",
        ),
    })
}

pub(crate) fn valid_id(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 128 && !value.chars().any(char::is_control)
}

fn truncated(value: &str) -> String {
    value.chars().take(64).collect()
}

fn invalid(field: &str) -> ApiError {
    ApiError::bad_request("invalid_event_field", format!("{field} is invalid."))
}

fn not_owned() -> ApiError {
    ApiError::forbidden(
        "runtime_event_not_owned",
        "The runtime events do not belong to this account session.",
    )
}

/// Active webhooks and MCP Events subscriptions that would receive this runtime's events.
/// MCP Events subscriptions count only while MCP Control on the runtime is not `off`.
pub async fn active_subscription_count(
    state: &AppState,
    account_id: Uuid,
    runtime_id: &str,
) -> Result<usize, ApiError> {
    let count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*)
        FROM event_subscriptions s
        WHERE s.account_id = $1
          AND s.status = 'active'
          AND (s.refresh_before IS NULL OR s.refresh_before > $3)
          AND (s.all_runtimes OR $2 = ANY(s.runtime_ids))
          AND (
              s.target_kind = 'webhook'
              OR ($4 AND EXISTS (
                  SELECT 1 FROM runtimes r WHERE r.id = $2 AND r.mcp_access <> 'off'
              ) AND EXISTS (
                  SELECT 1 FROM mcp_grants g
                  WHERE g.id = s.owner_grant_id
                    AND g.revoked_at IS NULL
                    AND (g.all_runtimes OR EXISTS (
                        SELECT 1 FROM mcp_grant_runtimes gr
                        WHERE gr.grant_id = g.id AND gr.runtime_id = $2
                    ))
              ))
          )
        "#,
    )
    .bind(account_id)
    .bind(runtime_id)
    .bind(Utc::now())
    .bind(state.config.events.mcp_events_enabled)
    .fetch_one(&state.pool)
    .await?;
    Ok(count.max(0) as usize)
}

#[cfg(test)]
mod tests {
    use chrono::{TimeDelta, Utc};
    use serde_json::json;

    use super::{validate_event, DomainEventInput};

    fn event(kind: &str, data: serde_json::Value) -> DomainEventInput {
        DomainEventInput {
            event_id: "0190f1f2-7a1b-7c3d-8e4f-1234567890ab".to_owned(),
            seq: 4,
            kind: kind.to_owned(),
            workspace_id: Some("workspace-1".to_owned()),
            project_id: None,
            data,
            occurred_at: Utc::now(),
        }
    }

    fn code(result: Result<(), crate::error::ApiError>) -> &'static str {
        match result {
            Ok(()) => "ok",
            Err(crate::error::ApiError::Request { code, .. }) => code,
            Err(_) => "other",
        }
    }

    #[test]
    fn validates_the_event_envelope_and_payload_policy() {
        let latest = Utc::now() + TimeDelta::minutes(5);
        assert_eq!(
            code(validate_event(
                &event("inbox.reply", json!({"threadId": "t"})),
                latest
            )),
            "ok"
        );
        assert_eq!(
            code(validate_event(&event("alera.test", json!({})), latest)),
            "unknown_event_kind"
        );
        assert_eq!(
            code(validate_event(
                &event("inbox.reply", json!({"replyText": "hi"})),
                latest
            )),
            "sensitive_event_data"
        );
        let mut bad_id = event("agent.status", json!({}));
        bad_id.event_id = "not-a-uuid".to_owned();
        assert_eq!(code(validate_event(&bad_id, latest)), "invalid_event_field");
        let mut negative = event("agent.status", json!({}));
        negative.seq = -1;
        assert_eq!(
            code(validate_event(&negative, latest)),
            "invalid_event_field"
        );
        let mut future = event("agent.status", json!({}));
        future.occurred_at = Utc::now() + TimeDelta::hours(1);
        assert_eq!(code(validate_event(&future, latest)), "invalid_event_time");
        let mut workspace = event("agent.status", json!({}));
        workspace.workspace_id = Some("w".repeat(129));
        assert_eq!(
            code(validate_event(&workspace, latest)),
            "invalid_event_field"
        );
    }
}
