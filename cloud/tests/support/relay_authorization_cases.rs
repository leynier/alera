use axum::{
    body::{to_bytes, Body},
    http::{Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

pub async fn rejects_rotation_conflicts_and_revoked_renewals(
    app: &Router,
    pool: &PgPool,
    account_id: Uuid,
    device_id: &str,
    token: &str,
    runtime_id: &str,
) -> anyhow::Result<()> {
    let (status, error) = post(
        app,
        token,
        "/v1/relay/identity",
        json!({
            "publicKey": URL_SAFE_NO_PAD.encode([9_u8; 32]), "keyVersion": 1,
        }),
    )
    .await?;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(error["error"]["code"], "relay_key_rotation_conflict");

    sqlx::query("UPDATE mobile_devices SET revoked_at = NOW() WHERE account_id = $1 AND id = $2")
        .bind(account_id)
        .bind(device_id)
        .execute(pool)
        .await?;
    let (status, error) = post(
        app,
        token,
        "/v1/relay/grants",
        json!({"runtimeId": runtime_id}),
    )
    .await?;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(error["error"]["code"], "mobile_device_required");

    sqlx::query("UPDATE refresh_token_families SET revoked_at = NOW() WHERE account_id = $1")
        .bind(account_id)
        .execute(pool)
        .await?;
    let (status, error) = post(
        app,
        token,
        "/v1/relay/grants",
        json!({"runtimeId": runtime_id}),
    )
    .await?;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(error["error"]["code"], "session_revoked");
    Ok(())
}

async fn post(
    app: &Router,
    token: &str,
    uri: &str,
    body: Value,
) -> anyhow::Result<(StatusCode, Value)> {
    let request = Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(serde_json::to_vec(&body)?))?;
    let response = app.clone().oneshot(request).await?;
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 65536).await?;
    Ok((status, serde_json::from_slice(&bytes)?))
}

pub fn assert_grant_scope(grant: &Value, runtime_id: &str) -> anyhow::Result<()> {
    let grant_parts = grant["grant"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing relay grant"))?
        .split('.')
        .map(|part| URL_SAFE_NO_PAD.decode(part))
        .collect::<Result<Vec<_>, _>>()?;
    let grant_claims: Value = serde_json::from_slice(&grant_parts[1])?;
    assert_eq!(grant_claims["aud"].as_str(), Some("alera-relay"));
    assert_eq!(grant_claims["role"].as_str(), Some("mobile"));
    assert_eq!(grant_claims["runtimeId"].as_str(), Some(runtime_id));
    Ok(())
}
