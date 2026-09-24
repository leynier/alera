use axum::{
    extract::{Path, State},
    http::HeaderMap,
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::authenticate, error::ApiError, state::AppState};

pub const MAX_DOCUMENT_BYTES: usize = 512 * 1024;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PublishConfiguration {
    pub operation_id: Uuid,
    pub expected_revision: Option<i64>,
    pub document: Value,
    pub device_name: String,
    pub summary: String,
}

pub async fn head(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let auth = authenticate(&headers, &state, "configuration:read").await?;
    limit_requests(&state, auth.account_id, "read", 120).await?;
    let row = sqlx::query("SELECT revision, document::text, device_name, summary, created_at::text FROM configuration_revisions WHERE account_id = $1 ORDER BY revision DESC LIMIT 1")
        .bind(auth.account_id).fetch_optional(&state.pool).await?;
    Ok(Json(json!({"head": row.map(revision_json).transpose()?})))
}

pub async fn history(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let auth = authenticate(&headers, &state, "configuration:read").await?;
    limit_requests(&state, auth.account_id, "read", 120).await?;
    let rows = sqlx::query("SELECT revision, device_name, summary, created_at::text FROM configuration_revisions WHERE account_id = $1 ORDER BY revision DESC LIMIT 100")
        .bind(auth.account_id).fetch_all(&state.pool).await?;
    let items: Result<Vec<_>, sqlx::Error> = rows
        .into_iter()
        .map(|row| {
            Ok(json!({
                "revision": row.try_get::<i64, _>("revision")?,
                "deviceName": row.try_get::<String, _>("device_name")?,
                "summary": row.try_get::<String, _>("summary")?,
                "createdAt": row.try_get::<String, _>("created_at")?,
            }))
        })
        .collect();
    Ok(Json(json!({"revisions": items?})))
}

pub async fn revision(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(revision): Path<i64>,
) -> Result<Json<Value>, ApiError> {
    let auth = authenticate(&headers, &state, "configuration:read").await?;
    limit_requests(&state, auth.account_id, "read", 120).await?;
    let row = sqlx::query("SELECT revision, document::text, device_name, summary, created_at::text FROM configuration_revisions WHERE account_id = $1 AND revision = $2")
        .bind(auth.account_id).bind(revision).fetch_optional(&state.pool).await?
        .ok_or_else(|| ApiError::not_found("configuration_not_found", "Configuration revision is unavailable."))?;
    Ok(Json(revision_json(row)?))
}

pub async fn publish(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<PublishConfiguration>,
) -> Result<Json<Value>, ApiError> {
    let auth = authenticate(&headers, &state, "configuration:write").await?;
    validate(&request)?;
    limit_requests(&state, auth.account_id, "write", 20).await?;
    let document = serde_json::to_string(&request.document).map_err(ApiError::internal)?;
    let fingerprint = hex::encode(Sha256::digest(
        serde_json::to_vec(&json!({
            "document": request.document, "expectedRevision": request.expected_revision,
            "deviceName": request.device_name, "summary": request.summary,
        }))
        .map_err(ApiError::internal)?,
    ));
    let mut tx = state.pool.begin().await?;
    sqlx::query("INSERT INTO configuration_heads (account_id) VALUES ($1) ON CONFLICT DO NOTHING")
        .bind(auth.account_id)
        .execute(&mut *tx)
        .await?;
    let current: i64 = sqlx::query_scalar(
        "SELECT revision FROM configuration_heads WHERE account_id = $1 FOR UPDATE",
    )
    .bind(auth.account_id)
    .fetch_one(&mut *tx)
    .await?;
    // Check the operation before the head: a response may have been lost after commit.
    if let Some(row) = sqlx::query("SELECT revision, document::text, device_name, summary, created_at::text, request_hash FROM configuration_revisions WHERE account_id = $1 AND operation_id = $2")
        .bind(auth.account_id).bind(request.operation_id).fetch_optional(&mut *tx).await? {
        if row.try_get::<String, _>("request_hash")? != fingerprint {
            return Err(ApiError::conflict("configuration_operation_conflict", "This operation was already used for different content."));
        }
        let response = revision_json(row)?;
        tx.commit().await?;
        return Ok(Json(response));
    }
    if request.expected_revision.unwrap_or(0) != current {
        return Err(ApiError::conflict(
            "configuration_revision_conflict",
            "The shared configuration changed. Review the latest version.",
        ));
    }
    let next = current + 1;
    let row = sqlx::query("INSERT INTO configuration_revisions (account_id, revision, operation_id, request_hash, document, device_name, client_id, summary) VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8) RETURNING revision, document::text, device_name, summary, created_at::text")
        .bind(auth.account_id).bind(next).bind(request.operation_id).bind(fingerprint)
        .bind(document).bind(request.device_name).bind(auth.client_id).bind(request.summary)
        .fetch_one(&mut *tx).await?;
    sqlx::query("UPDATE configuration_heads SET revision = $2 WHERE account_id = $1")
        .bind(auth.account_id)
        .bind(next)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM configuration_revisions WHERE account_id = $1 AND revision <= $2")
        .bind(auth.account_id)
        .bind(next - 100)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(revision_json(row)?))
}

fn revision_json(row: sqlx::postgres::PgRow) -> Result<Value, ApiError> {
    let document: String = row.try_get("document")?;
    Ok(json!({"revision": row.try_get::<i64, _>("revision")?,
        "document": serde_json::from_str::<Value>(&document).map_err(ApiError::internal)?,
        "deviceName": row.try_get::<String, _>("device_name")?,
        "summary": row.try_get::<String, _>("summary")?,
        "createdAt": row.try_get::<String, _>("created_at")?,
    }))
}

async fn limit_requests(
    state: &AppState,
    account: Uuid,
    operation: &str,
    limit: i32,
) -> Result<(), ApiError> {
    // One account bucket is shared across service replicas and is deleted with the account.
    let count: Option<i32> = sqlx::query_scalar("INSERT INTO configuration_request_limits (account_id, operation) VALUES ($1, $2) ON CONFLICT (account_id, operation) DO UPDATE SET window_started_at = CASE WHEN configuration_request_limits.window_started_at <= now() - interval '1 minute' THEN now() ELSE configuration_request_limits.window_started_at END, request_count = CASE WHEN configuration_request_limits.window_started_at <= now() - interval '1 minute' THEN 1 ELSE configuration_request_limits.request_count + 1 END WHERE configuration_request_limits.window_started_at <= now() - interval '1 minute' OR configuration_request_limits.request_count < $3 RETURNING request_count")
        .bind(account).bind(operation).bind(limit).fetch_optional(&state.pool).await?;
    if count.is_none() {
        return Err(ApiError::too_many(
            "configuration_rate_limited",
            "Too many configuration requests. Try again in a minute.",
        ));
    }
    Ok(())
}

fn validate(request: &PublishConfiguration) -> Result<(), ApiError> {
    let fail = || {
        ApiError::bad_request(
            "invalid_configuration",
            "Configuration format or size is invalid. Update Alera if necessary.",
        )
    };
    if request
        .document
        .get("schemaVersion")
        .and_then(Value::as_u64)
        != Some(1)
        || ["shared", "desktop", "mobile"]
            .iter()
            .any(|key| !request.document.get(key).is_some_and(Value::is_object))
        || serde_json::to_vec(&request.document)
            .map_err(ApiError::internal)?
            .len()
            > MAX_DOCUMENT_BYTES
        || request.device_name.trim().is_empty()
        || request.device_name.len() > 128
        || request.summary.len() > 512
        || request.expected_revision.is_some_and(|v| v < 1)
    {
        return Err(fail());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_unknown_formats_and_oversized_payloads() {
        let mut request = PublishConfiguration {
            operation_id: Uuid::new_v4(),
            expected_revision: None,
            document: json!({"schemaVersion": 1, "shared": {}, "desktop": {}, "mobile": {}}),
            device_name: "Linux".into(),
            summary: String::new(),
        };
        assert!(validate(&request).is_ok());
        request.document["schemaVersion"] = json!(2);
        assert!(validate(&request).is_err());
        request.document["schemaVersion"] = json!(1);
        request.document["desktop"]["prompt"] = json!("a".repeat(MAX_DOCUMENT_BYTES));
        assert!(validate(&request).is_err());
    }
}
