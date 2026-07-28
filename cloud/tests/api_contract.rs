use std::{
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
    time::Duration,
};

use alera_cloud::{
    api_models::{ProviderKind, ProviderKind::Github},
    config::{FcmConfig, LimitsConfig, OAuthProviderConfig, SigningConfig},
    fcm::{FcmMessage, FcmReceipt, FcmSender},
    oauth::{
        AuthorizationInput, ExchangeInput, OAuthProvider, OAuthProviderRegistry, ProviderIdentity,
    },
    router,
    signing::LocalEd25519Signer,
    AppConfig, AppState,
};
use async_trait::async_trait;
use axum::{
    body::{to_bytes, Body},
    http::{Method, Request, StatusCode},
    Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::postgres::PgPoolOptions;
use tower::ServiceExt;
use url::Url;
use uuid::Uuid;

struct FakeProvider {
    kind: ProviderKind,
    identity: ProviderIdentity,
}

#[async_trait]
impl OAuthProvider for FakeProvider {
    fn kind(&self) -> ProviderKind {
        self.kind
    }

    fn authorization_url(&self, input: AuthorizationInput<'_>) -> anyhow::Result<Url> {
        let mut url = Url::parse("https://identity.example/authorize")?;
        url.query_pairs_mut()
            .append_pair("state", input.state)
            .append_pair("redirect_uri", input.redirect_uri);
        Ok(url)
    }

    async fn exchange(&self, _input: ExchangeInput<'_>) -> anyhow::Result<ProviderIdentity> {
        Ok(self.identity.clone())
    }
}

struct RecordingFcm {
    sent: Arc<AtomicUsize>,
}

#[async_trait]
impl FcmSender for RecordingFcm {
    async fn send(&self, _message: FcmMessage) -> Result<FcmReceipt, alera_cloud::fcm::FcmError> {
        self.sent.fetch_add(1, Ordering::SeqCst);
        Ok(FcmReceipt {
            message_id: "projects/test/messages/1".to_owned(),
        })
    }
}

struct TestRequest<'a> {
    method: Method,
    uri: &'a str,
    bearer: Option<&'a str>,
    body: Value,
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn account_enrollment_and_push_contract() -> anyhow::Result<()> {
    let database_url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    let shared_email = format!("{}@example.test", Uuid::now_v7());
    let sent = Arc::new(AtomicUsize::new(0));
    let app = test_app(pool.clone(), database_url, shared_email, true, sent.clone())?;
    let runtime_one = format!("runtime-{}", Uuid::now_v7());
    let runtime_two = format!("runtime-{}", Uuid::now_v7());
    let first = sign_in(&app, "google", &runtime_one).await?;
    let second = sign_in(&app, "github", &runtime_two).await?;
    assert_eq!(
        first["account"]["id"].as_str(),
        second["account"]["id"].as_str()
    );
    let account_id = Uuid::parse_str(
        first["account"]["id"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("missing account id"))?,
    )?;
    let runtime_token = first["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing runtime access token"))?;

    let account = call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/account",
            bearer: Some(runtime_token),
            body: Value::Null,
        },
    )
    .await?;
    assert_eq!(account["identities"].as_array().map(Vec::len), Some(2));

    let device_id = format!("mobile-{}", Uuid::now_v7());
    let enrollment = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments",
            bearer: Some(runtime_token),
            body: json!({
                "runtimeId": runtime_one,
                "deviceId": device_id,
                "deviceName": "Test Phone"
            }),
        },
    )
    .await?;
    let mobile = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments/redeem",
            bearer: None,
            body: json!({
                "code": enrollment["code"],
                "deviceId": device_id,
                "deviceName": "Test Phone"
            }),
        },
    )
    .await?;
    assert_eq!(mobile["runtimeId"].as_str(), Some(runtime_one.as_str()));
    let mobile_token = mobile["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing mobile access token"))?;
    call(
        &app,
        TestRequest {
            method: Method::PUT,
            uri: "/v1/mobile/push-token",
            bearer: Some(mobile_token),
            body: json!({"token": "fcm-registration-token-with-valid-length", "platform": "android"}),
        },
    )
    .await?;
    call(
        &app,
        TestRequest {
            method: Method::PUT,
            uri: &format!("/v1/mobile/subscriptions/{runtime_one}"),
            bearer: Some(mobile_token),
            body: json!({"categories": {"attention": true, "done": false, "terminalExit": false}}),
        },
    )
    .await?;
    let subscriptions = call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/runtime/subscriptions",
            bearer: Some(runtime_token),
            body: Value::Null,
        },
    )
    .await?;
    assert_eq!(subscriptions["activeSubscriptions"].as_u64(), Some(1));
    let event_body = json!({
        "runtimeId": runtime_one,
        "eventId": format!("event-{}", Uuid::now_v7()),
        "category": "attention",
        "eventType": "agentWaiting",
        "title": "Agent Waiting",
        "body": "Workspace Alpha",
        "data": {"workspaceId": "workspace-1"},
        "occurredAt": chrono::Utc::now()
    });
    let event = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/events",
            bearer: Some(runtime_token),
            body: event_body.clone(),
        },
    )
    .await?;
    assert_eq!(event["deliveriesQueued"].as_u64(), Some(1));
    assert_eq!(event["activeSubscriptions"].as_u64(), Some(1));
    let duplicate = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/events",
            bearer: Some(runtime_token),
            body: event_body,
        },
    )
    .await?;
    assert_eq!(duplicate["duplicate"].as_bool(), Some(true));
    assert_eq!(sent.load(Ordering::SeqCst), 1);

    sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(account_id)
        .execute(&pool)
        .await?;
    pool.close().await;
    Ok(())
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn unverified_email_does_not_auto_link() -> anyhow::Result<()> {
    let database_url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    let email = format!("{}@example.test", Uuid::now_v7());
    let app = test_app(
        pool.clone(),
        database_url,
        email,
        false,
        Arc::new(AtomicUsize::new(0)),
    )?;
    let first = sign_in(&app, "google", &format!("runtime-{}", Uuid::now_v7())).await?;
    let second = sign_in(&app, "github", &format!("runtime-{}", Uuid::now_v7())).await?;
    assert_ne!(
        first["account"]["id"].as_str(),
        second["account"]["id"].as_str()
    );
    for response in [first, second] {
        let account_id = Uuid::parse_str(
            response["account"]["id"]
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("missing account id"))?,
        )?;
        sqlx::query("DELETE FROM accounts WHERE id = $1")
            .bind(account_id)
            .execute(&pool)
            .await?;
    }
    pool.close().await;
    Ok(())
}

async fn sign_in(app: &Router, provider: &str, runtime_id: &str) -> anyhow::Result<Value> {
    let verifier = "v".repeat(43);
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let transaction = call(
        app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/auth/transactions",
            bearer: None,
            body: json!({
                "provider": provider,
                "redirectUri": format!("http://127.0.0.1:43121/callback/{provider}"),
                "codeChallenge": challenge,
                "clientId": runtime_id,
                "clientKind": "runtime",
                "deviceName": "Test Runtime"
            }),
        },
    )
    .await?;
    call(
        app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/auth/exchange",
            bearer: None,
            body: json!({
                "transactionId": transaction["transactionId"],
                "state": transaction["state"],
                "code": "authorization-code-for-contract",
                "codeVerifier": verifier
            }),
        },
    )
    .await
}

async fn call(app: &Router, request: TestRequest<'_>) -> anyhow::Result<Value> {
    let mut builder = Request::builder()
        .method(request.method)
        .uri(request.uri)
        .header("content-type", "application/json");
    if let Some(bearer) = request.bearer {
        builder = builder.header("authorization", format!("Bearer {bearer}"));
    }
    let body = if request.body.is_null() {
        Body::empty()
    } else {
        Body::from(serde_json::to_vec(&request.body)?)
    };
    let response = app.clone().oneshot(builder.body(body)?).await?;
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await?;
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes)?
    };
    if status != StatusCode::OK && status != StatusCode::NO_CONTENT {
        anyhow::bail!("request failed with {status}: {value}");
    }
    Ok(value)
}

fn test_config(database_url: String) -> anyhow::Result<AppConfig> {
    let endpoint = OAuthProviderConfig {
        client_id: "test-client".to_owned(),
        client_secret: "test-secret".to_owned(),
        authorization_url: Url::parse("https://identity.example/authorize")?,
        token_url: Url::parse("https://identity.example/token")?,
        user_url: Url::parse("https://identity.example/user")?,
        emails_url: None,
        jwks_url: None,
    };
    Ok(AppConfig {
        bind: "127.0.0.1:0".parse()?,
        database_url,
        public_base_url: Url::parse("https://api.example.test")?,
        issuer: "https://api.example.test".to_owned(),
        audience: "alera-cloud".to_owned(),
        edge_origin_token: None,
        edge_previous_origin_token: None,
        allow_direct_origin: true,
        signing: SigningConfig::Local {
            key_id: "unused".to_owned(),
            seed_b64url: URL_SAFE_NO_PAD.encode([1_u8; 32]),
        },
        google: endpoint.clone(),
        github: endpoint,
        fcm: FcmConfig::Disabled,
        push_delivery_enabled: true,
        tombstone_pepper: "test-pepper-with-at-least-thirty-two-characters".to_owned(),
        http_timeout: Duration::from_secs(2),
        limits: LimitsConfig {
            max_runtimes_per_account: 10,
            max_mobile_devices_per_account: 5,
            push_daily: 500,
            push_hourly: 60,
            push_burst: 10,
        },
    })
}

fn test_app(
    pool: sqlx::PgPool,
    database_url: String,
    email: String,
    github_verified: bool,
    sent: Arc<AtomicUsize>,
) -> anyhow::Result<Router> {
    let providers = OAuthProviderRegistry::new(vec![
        Arc::new(FakeProvider {
            kind: ProviderKind::Google,
            identity: ProviderIdentity {
                provider: ProviderKind::Google,
                provider_user_id: format!("google-{}", Uuid::now_v7()),
                email: email.clone(),
                email_verified: true,
            },
        }),
        Arc::new(FakeProvider {
            kind: Github,
            identity: ProviderIdentity {
                provider: Github,
                provider_user_id: format!("github-{}", Uuid::now_v7()),
                email,
                email_verified: github_verified,
            },
        }),
    ]);
    let signer = Arc::new(LocalEd25519Signer::from_seed_b64url(
        "api-contract".to_owned(),
        &URL_SAFE_NO_PAD.encode([23_u8; 32]),
    )?);
    let fcm = Arc::new(RecordingFcm { sent });
    Ok(router(AppState::from_dependencies(
        pool,
        test_config(database_url)?,
        providers,
        signer,
        fcm,
    )))
}
