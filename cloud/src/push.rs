use std::{collections::BTreeMap, future::Future, time::Duration};

use axum::{extract::State, http::HeaderMap, Json};
use chrono::{TimeDelta, Utc};
use serde_json::Value;
use tokio::time::{timeout_at, Instant};
use uuid::Uuid;

use crate::{
    api_models::{
        ClientKind, PushCategory, RuntimeEventRequest, RuntimeEventResponse,
        RuntimeSubscriptionStatus,
    },
    auth::authenticate,
    error::ApiError,
    push_delivery::{
        deliver_target, delivery_send_deadline, run_bounded_deliveries, DeliveryContext,
        DeliveryTarget,
    },
    state::AppState,
};

// The runtime client waits 15 seconds; reserve time for SQL, audit writes and the response.
const PUSH_DELIVERY_BUDGET: Duration = Duration::from_secs(12);

#[derive(sqlx::FromRow)]
struct StoredRuntimeEvent {
    id: Uuid,
    category: String,
    event_type: String,
    title: String,
    body: String,
    data: Value,
}

pub async fn get_runtime_subscriptions(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<RuntimeSubscriptionStatus>, ApiError> {
    let auth = authenticate(&headers, &state, "push:send").await?;
    if auth.client_kind != ClientKind::Runtime {
        return Err(ApiError::forbidden(
            "runtime_session_required",
            "A runtime session is required.",
        ));
    }
    let active_subscriptions =
        active_subscription_count(&state, auth.account_id, &auth.client_id).await?;
    Ok(Json(RuntimeSubscriptionStatus {
        active_subscriptions,
    }))
}

pub async fn post_runtime_event(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RuntimeEventRequest>,
) -> Result<Json<RuntimeEventResponse>, ApiError> {
    let auth = authenticate(&headers, &state, "push:send").await?;
    let delivery_deadline = Instant::now() + PUSH_DELIVERY_BUDGET;
    validate_event(&request)?;
    if auth.client_kind != ClientKind::Runtime || auth.client_id != request.runtime_id {
        return Err(ApiError::forbidden(
            "runtime_event_not_owned",
            "The runtime event does not belong to this account session.",
        ));
    }
    let runtime_owned = within_delivery_budget(
        delivery_deadline,
        sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM runtimes WHERE id = $1 AND account_id = $2)",
        )
        .bind(&request.runtime_id)
        .bind(auth.account_id)
        .fetch_one(&state.pool),
    )
    .await?;
    if !runtime_owned {
        return Err(ApiError::forbidden(
            "runtime_event_not_owned",
            "The runtime does not belong to this account.",
        ));
    }
    if !state.config.push_delivery_enabled {
        return Err(ApiError::unavailable(
            "push_delivery_disabled",
            "Push delivery is temporarily disabled.",
        ));
    }
    let active_subscriptions = within_delivery_budget(
        delivery_deadline,
        active_subscription_count(&state, auth.account_id, &request.runtime_id),
    )
    .await?;
    let database_event_id = Uuid::now_v7();
    let inserted = within_delivery_budget(
        delivery_deadline,
        sqlx::query_scalar::<_, Uuid>(
            r#"
        INSERT INTO runtime_events (
            id, account_id, runtime_id, event_id, category, event_type,
            title, body, data, occurred_at, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        ON CONFLICT (runtime_id, event_id) DO NOTHING
        RETURNING id
        "#,
        )
        .bind(database_event_id)
        .bind(auth.account_id)
        .bind(&request.runtime_id)
        .bind(&request.event_id)
        .bind(request.category.as_str())
        .bind(&request.event_type)
        .bind(&request.title)
        .bind(&request.body)
        .bind(&request.data)
        .bind(request.occurred_at)
        .bind(Utc::now())
        .fetch_optional(&state.pool),
    )
    .await?;
    let (database_event_id, duplicate, category, event_type, title, body, event_data) =
        match inserted {
            Some(id) => (
                id,
                false,
                request.category,
                request.event_type.clone(),
                request.title.clone(),
                request.body.clone(),
                request.data.clone(),
            ),
            None => {
                let Some(existing) = within_delivery_budget(
                    delivery_deadline,
                    sqlx::query_as::<_, StoredRuntimeEvent>(
                        r#"
                    SELECT id, category, event_type, title, body, data
                    FROM runtime_events
                    WHERE account_id = $1 AND runtime_id = $2 AND event_id = $3
                    "#,
                    )
                    .bind(auth.account_id)
                    .bind(&request.runtime_id)
                    .bind(&request.event_id)
                    .fetch_optional(&state.pool),
                )
                .await?
                else {
                    return Ok(Json(RuntimeEventResponse {
                        accepted: true,
                        duplicate: true,
                        deliveries_queued: 0,
                        active_subscriptions,
                    }));
                };
                (
                    existing.id,
                    true,
                    stored_category(&existing.category)?,
                    existing.event_type,
                    existing.title,
                    existing.body,
                    existing.data,
                )
            }
        };

    let targets = within_delivery_budget(
        delivery_deadline,
        sqlx::query_as::<_, DeliveryTarget>(
            r#"
        SELECT s.mobile_device_id, t.token, s.attention, s.done, s.terminal_exit
        FROM push_subscriptions s
        JOIN fcm_tokens t
          ON t.account_id = s.account_id
         AND t.mobile_device_id = s.mobile_device_id
        JOIN mobile_devices d
          ON d.account_id = s.account_id
         AND d.id = s.mobile_device_id
        WHERE s.account_id = $1
          AND s.runtime_id = $2
          AND d.revoked_at IS NULL
        "#,
        )
        .bind(auth.account_id)
        .bind(&request.runtime_id)
        .fetch_all(&state.pool),
    )
    .await?;
    let data = message_data(
        auth.account_id,
        &request.runtime_id,
        &request.event_id,
        &event_type,
        category,
        &event_data,
    )?;
    let channel_id = match category {
        PushCategory::Attention => "alera_attention",
        PushCategory::Done | PushCategory::TerminalExit => "alera_activity",
    };
    let context = DeliveryContext {
        account_id: auth.account_id,
        event_id: database_event_id,
        title,
        body,
        data,
        channel_id: channel_id.to_owned(),
        deadline: delivery_deadline,
        send_deadline: delivery_send_deadline(delivery_deadline),
    };
    let tasks = targets
        .into_iter()
        .filter(|target| category_enabled(target, category))
        .map(|target| {
            let state = state.clone();
            let context = context.clone();
            async move { deliver_target(&state, context, target).await }
        })
        .collect();
    let mut deliveries_queued = 0_usize;
    let mut delivery_error = None;
    for result in run_bounded_deliveries(tasks).await {
        match result {
            Ok(queued) => deliveries_queued += usize::from(queued),
            Err(error) if delivery_error.is_none() => delivery_error = Some(error),
            Err(_) => {}
        }
    }
    if let Some(error) = delivery_error {
        return Err(error);
    }

    let active_subscriptions = within_delivery_budget(
        delivery_deadline,
        active_subscription_count(&state, auth.account_id, &request.runtime_id),
    )
    .await?;
    Ok(Json(RuntimeEventResponse {
        accepted: true,
        duplicate,
        deliveries_queued,
        active_subscriptions,
    }))
}

async fn within_delivery_budget<T, E, F>(deadline: Instant, operation: F) -> Result<T, ApiError>
where
    F: Future<Output = Result<T, E>>,
    ApiError: From<E>,
{
    timeout_at(deadline, operation)
        .await
        .map_err(|_| {
            ApiError::unavailable(
                "push_delivery_deadline",
                "Push delivery exceeded the request budget.",
            )
        })?
        .map_err(ApiError::from)
}

pub(crate) async fn active_subscription_count(
    state: &AppState,
    account_id: Uuid,
    runtime_id: &str,
) -> Result<usize, ApiError> {
    let count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*)
        FROM push_subscriptions s
        JOIN fcm_tokens t
          ON t.account_id = s.account_id
         AND t.mobile_device_id = s.mobile_device_id
        JOIN mobile_devices d
          ON d.account_id = s.account_id
         AND d.id = s.mobile_device_id
        WHERE s.account_id = $1
          AND s.runtime_id = $2
          AND d.revoked_at IS NULL
          AND (s.attention OR s.done OR s.terminal_exit)
        "#,
    )
    .bind(account_id)
    .bind(runtime_id)
    .fetch_one(&state.pool)
    .await?;
    Ok(count.max(0) as usize)
}

fn category_enabled(target: &DeliveryTarget, category: PushCategory) -> bool {
    match category {
        PushCategory::Attention => target.attention,
        PushCategory::Done => target.done,
        PushCategory::TerminalExit => target.terminal_exit,
    }
}

fn stored_category(value: &str) -> Result<PushCategory, ApiError> {
    match value {
        "attention" => Ok(PushCategory::Attention),
        "done" => Ok(PushCategory::Done),
        "terminalExit" => Ok(PushCategory::TerminalExit),
        _ => Err(ApiError::internal(anyhow::anyhow!(
            "runtime event has unknown push category: {value}"
        ))),
    }
}

fn validate_event(request: &RuntimeEventRequest) -> Result<(), ApiError> {
    validate_text(&request.runtime_id, 128, "runtimeId")?;
    validate_text(&request.event_id, 160, "eventId")?;
    validate_text(&request.event_type, 80, "eventType")?;
    validate_text(&request.title, 160, "title")?;
    validate_text(&request.body, 600, "body")?;
    if request.occurred_at > Utc::now() + TimeDelta::minutes(5) {
        return Err(ApiError::bad_request(
            "invalid_event_time",
            "The event timestamp is too far in the future.",
        ));
    }
    let object = request.data.as_object().ok_or_else(|| {
        ApiError::bad_request("invalid_event_data", "Event data must be a JSON object.")
    })?;
    if object.len() > 20 {
        return Err(ApiError::bad_request(
            "event_data_too_large",
            "Event data has too many fields.",
        ));
    }
    for (key, value) in object {
        validate_text(key, 64, "data key")?;
        if sensitive_key(key) {
            return Err(ApiError::bad_request(
                "sensitive_event_data",
                "Prompts, commands, and terminal output cannot be sent through push.",
            ));
        }
        match value {
            Value::String(text) => validate_text(text, 1024, "data value")?,
            Value::Bool(_) | Value::Number(_) | Value::Null => {}
            Value::Array(_) | Value::Object(_) => {
                return Err(ApiError::bad_request(
                    "invalid_event_data",
                    "Event data values must be scalar.",
                ));
            }
        }
    }
    Ok(())
}

fn message_data(
    account_id: Uuid,
    runtime_id: &str,
    event_id: &str,
    event_type: &str,
    category: PushCategory,
    event_data: &Value,
) -> Result<BTreeMap<String, String>, ApiError> {
    let mut data = BTreeMap::new();
    if let Some(object) = event_data.as_object() {
        for (key, value) in object {
            let encoded = match value {
                Value::String(text) => text.clone(),
                Value::Null => String::new(),
                Value::Bool(value) => value.to_string(),
                Value::Number(value) => value.to_string(),
                Value::Array(_) | Value::Object(_) => {
                    return Err(ApiError::bad_request(
                        "invalid_event_data",
                        "Event data values must be scalar.",
                    ));
                }
            };
            data.insert(key.clone(), encoded);
        }
    }
    data.insert("accountId".to_owned(), account_id.to_string());
    data.insert("runtimeId".to_owned(), runtime_id.to_owned());
    data.insert("eventId".to_owned(), event_id.to_owned());
    data.insert("eventType".to_owned(), event_type.to_owned());
    data.insert("category".to_owned(), category.as_str().to_owned());
    Ok(data)
}

fn validate_text(value: &str, max: usize, field: &str) -> Result<(), ApiError> {
    if value.trim().is_empty() || value.len() > max || value.chars().any(char::is_control) {
        return Err(ApiError::bad_request(
            "invalid_event_field",
            format!("{field} is invalid."),
        ));
    }
    Ok(())
}

fn sensitive_key(key: &str) -> bool {
    let normalized = key.to_ascii_lowercase();
    ["prompt", "command", "output", "terminalbytes", "scrollback"]
        .iter()
        .any(|part| normalized.contains(part))
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use serde_json::json;
    use uuid::Uuid;

    use crate::api_models::{PushCategory, RuntimeEventRequest};

    use super::{message_data, validate_event};

    fn event(data: serde_json::Value) -> RuntimeEventRequest {
        RuntimeEventRequest {
            runtime_id: "runtime-1".to_owned(),
            event_id: "event-1".to_owned(),
            category: PushCategory::Attention,
            event_type: "agentWaiting".to_owned(),
            title: "Agent Waiting".to_owned(),
            body: "Workspace Alpha".to_owned(),
            data,
            occurred_at: Utc::now(),
        }
    }

    #[test]
    fn rejects_prompt_or_terminal_output_fields() {
        assert!(validate_event(&event(json!({"prompt": "secret"}))).is_err());
        assert!(validate_event(&event(json!({"terminalOutput": "secret"}))).is_err());
    }

    #[test]
    fn adds_trusted_routing_fields() {
        let account_id = Uuid::now_v7();
        let data = message_data(
            account_id,
            "runtime-1",
            "event-1",
            "agentWaiting",
            PushCategory::Attention,
            &json!({"workspaceId": "workspace-1"}),
        );
        assert!(data.is_ok());
        let data = match data {
            Ok(value) => value,
            Err(error) => panic!("unexpected data error: {error}"),
        };
        assert_eq!(
            data.get("accountId").map(String::as_str),
            Some(account_id.to_string().as_str())
        );
        assert_eq!(data.get("runtimeId").map(String::as_str), Some("runtime-1"));
        assert_eq!(
            data.get("workspaceId").map(String::as_str),
            Some("workspace-1")
        );
    }
}
