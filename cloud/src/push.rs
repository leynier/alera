use std::collections::BTreeMap;

use axum::{extract::State, http::HeaderMap, Json};
use chrono::{TimeDelta, Utc};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{
    api_models::{
        ClientKind, PushCategory, RuntimeEventRequest, RuntimeEventResponse,
        RuntimeSubscriptionStatus,
    },
    auth::authenticate,
    error::ApiError,
    fcm::{send_with_retry, FcmError, FcmMessage},
    quota::reserve_push_delivery,
    state::AppState,
};

#[derive(FromRow)]
struct DeliveryTarget {
    mobile_device_id: String,
    token: String,
    attention: bool,
    done: bool,
    terminal_exit: bool,
}

struct DeliveryAttempt<'a> {
    event_id: Uuid,
    account_id: Uuid,
    mobile_device_id: &'a str,
    attempt: i32,
    status: &'a str,
    provider_message_id: Option<&'a str>,
    error_code: Option<&'a str>,
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
    validate_event(&request)?;
    if auth.client_kind != ClientKind::Runtime || auth.client_id != request.runtime_id {
        return Err(ApiError::forbidden(
            "runtime_event_not_owned",
            "The runtime event does not belong to this account session.",
        ));
    }
    let runtime_owned = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM runtimes WHERE id = $1 AND account_id = $2)",
    )
    .bind(&request.runtime_id)
    .bind(auth.account_id)
    .fetch_one(&state.pool)
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
    let active_subscriptions =
        active_subscription_count(&state, auth.account_id, &request.runtime_id).await?;

    let database_event_id = Uuid::now_v7();
    let inserted = sqlx::query_scalar::<_, Uuid>(
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
    .fetch_optional(&state.pool)
    .await?;
    if inserted.is_none() {
        return Ok(Json(RuntimeEventResponse {
            accepted: true,
            duplicate: true,
            deliveries_queued: 0,
            active_subscriptions,
        }));
    }

    let targets = sqlx::query_as::<_, DeliveryTarget>(
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
    .fetch_all(&state.pool)
    .await?;
    let data = message_data(auth.account_id, &request)?;
    let channel_id = match request.category {
        PushCategory::Attention => "alera_attention",
        PushCategory::Done | PushCategory::TerminalExit => "alera_activity",
    };
    let mut deliveries_queued = 0_usize;
    for target in targets
        .into_iter()
        .filter(|target| category_enabled(target, request.category))
    {
        let quota = reserve_push_delivery(&state.pool, auth.account_id, &state.config.limits).await;
        if let Err(error) = quota {
            record_attempt(
                &state,
                DeliveryAttempt {
                    event_id: database_event_id,
                    account_id: auth.account_id,
                    mobile_device_id: &target.mobile_device_id,
                    attempt: 1,
                    status: "quotaRejected",
                    provider_message_id: None,
                    error_code: Some("quota_exceeded"),
                },
            )
            .await?;
            tracing::info!(
                account_id = %auth.account_id,
                event_id = %request.event_id,
                error = %error,
                "push delivery skipped by quota"
            );
            continue;
        }
        deliveries_queued += 1;
        let (attempt, result) = send_with_retry(
            state.fcm.as_ref(),
            FcmMessage {
                token: target.token.clone(),
                title: request.title.clone(),
                body: request.body.clone(),
                data: data.clone(),
                channel_id: channel_id.to_owned(),
            },
        )
        .await;
        match result {
            Ok(receipt) => {
                record_attempt(
                    &state,
                    DeliveryAttempt {
                        event_id: database_event_id,
                        account_id: auth.account_id,
                        mobile_device_id: &target.mobile_device_id,
                        attempt,
                        status: "delivered",
                        provider_message_id: Some(&receipt.message_id),
                        error_code: None,
                    },
                )
                .await?;
            }
            Err(error) => {
                record_attempt(
                    &state,
                    DeliveryAttempt {
                        event_id: database_event_id,
                        account_id: auth.account_id,
                        mobile_device_id: &target.mobile_device_id,
                        attempt,
                        status: "failed",
                        provider_message_id: None,
                        error_code: Some(error.code()),
                    },
                )
                .await?;
                if matches!(error, FcmError::Unregistered) {
                    remove_unregistered_token(
                        &state,
                        auth.account_id,
                        &target.mobile_device_id,
                        &target.token,
                    )
                    .await?;
                }
                tracing::warn!(
                    account_id = %auth.account_id,
                    event_id = %request.event_id,
                    device_id = %target.mobile_device_id,
                    error_code = error.code(),
                    "FCM delivery failed"
                );
            }
        }
    }

    let active_subscriptions =
        active_subscription_count(&state, auth.account_id, &request.runtime_id).await?;
    Ok(Json(RuntimeEventResponse {
        accepted: true,
        duplicate: false,
        deliveries_queued,
        active_subscriptions,
    }))
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
    request: &RuntimeEventRequest,
) -> Result<BTreeMap<String, String>, ApiError> {
    let mut data = BTreeMap::new();
    if let Some(object) = request.data.as_object() {
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
    data.insert("runtimeId".to_owned(), request.runtime_id.clone());
    data.insert("eventId".to_owned(), request.event_id.clone());
    data.insert("eventType".to_owned(), request.event_type.clone());
    data.insert("category".to_owned(), request.category.as_str().to_owned());
    Ok(data)
}

async fn record_attempt(state: &AppState, attempt: DeliveryAttempt<'_>) -> Result<(), ApiError> {
    sqlx::query(
        r#"
        INSERT INTO delivery_attempts (
            id, event_id, account_id, mobile_device_id, attempt, status,
            provider_message_id, error_code, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (event_id, mobile_device_id, attempt) DO NOTHING
        "#,
    )
    .bind(Uuid::now_v7())
    .bind(attempt.event_id)
    .bind(attempt.account_id)
    .bind(attempt.mobile_device_id)
    .bind(attempt.attempt)
    .bind(attempt.status)
    .bind(attempt.provider_message_id)
    .bind(attempt.error_code)
    .bind(Utc::now())
    .execute(&state.pool)
    .await?;
    Ok(())
}

async fn remove_unregistered_token(
    state: &AppState,
    account_id: Uuid,
    device_id: &str,
    token: &str,
) -> Result<(), ApiError> {
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    sqlx::query("DELETE FROM fcm_tokens WHERE account_id = $1 AND mobile_device_id = $2")
        .bind(account_id)
        .bind(device_id)
        .execute(&mut *transaction)
        .await?;
    sqlx::query(
        r#"
        INSERT INTO abuse_tombstones (
            id, subject_kind, subject_hash, reason, created_at, expires_at
        ) VALUES ($1, 'fcm_token', $2, 'unregistered', $3, $4)
        "#,
    )
    .bind(Uuid::now_v7())
    .bind(Sha256::digest(token.as_bytes()).to_vec())
    .bind(now)
    .bind(now + TimeDelta::days(30))
    .execute(&mut *transaction)
    .await?;
    transaction.commit().await?;
    Ok(())
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
        let data = message_data(account_id, &event(json!({"workspaceId": "workspace-1"})));
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
