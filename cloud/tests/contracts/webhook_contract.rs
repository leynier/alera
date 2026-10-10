use alera_cloud::events::{
    delivery::run_pass,
    secrets::{sign, signing_key},
};

use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::webhook_receiver::{Received, Receiver};
use super::*;

/// One domain event in the runtime wire format.
pub fn event(kind: &str, data: Value) -> Value {
    json!({
        "eventId": Uuid::new_v4().to_string(),
        "seq": 1,
        "kind": kind,
        "workspaceId": "workspace-1",
        "data": data,
        "occurredAt": chrono::Utc::now().to_rfc3339(),
    })
}

pub async fn post_events(
    app: &Router,
    token: &str,
    runtime: &str,
    events: Vec<Value>,
) -> anyhow::Result<Reply> {
    post_json(
        app,
        "/v1/runtime/domain-events",
        Some(token),
        json!({"runtimeId": runtime, "events": events}),
    )
    .await
}

/// Runs worker passes until no delivery is due or in flight. Contract tests share the
/// database, so a pass may also send another test's deliveries; wait for those too.
pub async fn deliver_all(state: &AppState) -> anyhow::Result<()> {
    for _ in 0..100 {
        run_pass(state).await?;
        let busy: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM event_deliveries WHERE status = 'sending' OR (status = 'pending' AND next_attempt_at <= now())",
        )
        .fetch_one(&state.pool)
        .await?;
        if busy == 0 {
            return Ok(());
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    anyhow::bail!("deliveries did not settle")
}

pub fn verify_signature(item: &Received, secret: &str) -> bool {
    let Some(key) = signing_key(secret) else {
        return false;
    };
    let timestamp: i64 = item.header("webhook-timestamp").parse().unwrap_or_default();
    let expected = sign(&key, &item.header("webhook-id"), timestamp, &item.body);
    item.header("webhook-signature")
        .split(' ')
        .any(|signature| signature == expected)
}

async fn delivery_row(
    pool: &sqlx::PgPool,
    event_id: &str,
) -> anyhow::Result<(String, i32, Option<String>)> {
    Ok(sqlx::query_as::<_, (String, i32, Option<String>)>(
        r#"
        SELECT d.status, d.attempts, d.last_error
        FROM event_deliveries d JOIN domain_events e ON e.id = d.event_id
        WHERE e.event_id = $1
        "#,
    )
    .bind(event_id)
    .fetch_one(pool)
    .await?)
}

async fn active_count(app: &Router, token: &str) -> anyhow::Result<Value> {
    Ok(get(app, "/v1/runtime/event-subscriptions", Some(token))
        .await?
        .json()["activeSubscriptions"]
        .clone())
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn runtime_events_reach_signed_webhooks_with_retries() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let email = format!("{}@example.test", Uuid::now_v7());
    let sent = Arc::new(AtomicUsize::new(0));
    let state = test_state(pool.clone(), url.clone(), email.clone(), true, sent.clone())?;
    let app = router(state.clone());
    let runtime = format!("runtime-{}", Uuid::now_v7());
    let session = sign_in(&app, "google", &runtime).await?;
    let token = session["accessToken"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    assert!(jwt_claims(&token)?["scope"]
        .as_str()
        .unwrap_or_default()
        .contains("events:send"));
    let receiver = Receiver::start().await?;
    assert_eq!(active_count(&app, &token).await?, 0);

    let created = post_json(
        &app,
        "/v1/webhooks",
        Some(&token),
        json!({"url": receiver.url("/hook"), "kinds": ["inbox.reply", "agent.status", "inbox.reply"]}),
    )
    .await?;
    assert_eq!(created.status, StatusCode::OK, "{}", created.text());
    let created = created.json();
    let secret = created["secret"].as_str().unwrap_or_default().to_owned();
    assert!(secret.starts_with("whsec_"));
    let webhook_id = created["webhook"]["id"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    assert_eq!(
        created["webhook"]["kinds"],
        json!(["agent.status", "inbox.reply"])
    );
    assert_eq!(created["webhook"]["runtimeIds"], json!([runtime]));
    assert_eq!(created["webhook"]["status"], "active");
    let listed = get(&app, "/v1/webhooks", Some(&token)).await?.json();
    assert_eq!(listed["webhooks"][0]["id"], webhook_id.as_str());
    assert!(listed["webhooks"][0].get("secret").is_none());
    let stored: String =
        sqlx::query_scalar("SELECT secret_ciphertext FROM event_subscriptions WHERE id = $1")
            .bind(&webhook_id)
            .fetch_one(&pool)
            .await?;
    assert!(
        !stored.contains(&secret[6..]),
        "secrets are encrypted at rest"
    );
    assert_eq!(active_count(&app, &token).await?, 1);

    for (body, code) in [
        (
            json!({"url": receiver.url("/hook"), "kinds": ["unknown.kind"]}),
            "invalid_webhook_kinds",
        ),
        (
            json!({"url": receiver.url("/hook"), "kinds": ["inbox.reply"], "runtimeIds": ["other-runtime"]}),
            "runtime_not_found",
        ),
        (
            json!({"url": "ftp://example.test/hook", "kinds": ["inbox.reply"]}),
            "invalid_webhook_url",
        ),
    ] {
        let refused = post_json(&app, "/v1/webhooks", Some(&token), body).await?;
        assert_eq!(refused.error_code(), code, "{}", refused.text());
    }

    // Ingest: idempotent by event id, payload policy enforced, runtime ownership checked.
    let reply = event(
        "inbox.reply",
        json!({"threadId": "t1", "questionId": "q1", "extra": "dropped"}),
    );
    let waiting = event(
        "agent.status",
        json!({"tabId": "tab-1", "state": "waiting"}),
    );
    let exited = event("terminal.exit", json!({"tabId": "tab-1", "exitCode": 0}));
    let batch = vec![reply.clone(), waiting.clone(), exited, reply.clone()];
    let first = post_events(&app, &token, &runtime, batch.clone()).await?;
    assert_eq!(first.status, StatusCode::OK, "{}", first.text());
    assert_eq!(
        first.json(),
        json!({"accepted": 3, "duplicate": 1, "activeSubscriptions": 1})
    );
    let again = post_events(&app, &token, &runtime, batch).await?.json();
    assert_eq!(again["accepted"], 0);
    assert_eq!(again["duplicate"], 4);
    let foreign = post_events(
        &app,
        &token,
        "another-runtime",
        vec![event("agent.status", json!({}))],
    )
    .await?;
    assert_eq!(foreign.status, StatusCode::FORBIDDEN);
    // One bad event is rejected on its own; the rest of the batch is stored.
    let mut skewed = event("agent.status", json!({"state": "idle"}));
    skewed["occurredAt"] = json!((chrono::Utc::now() + chrono::TimeDelta::hours(1)).to_rfc3339());
    let fine = event("terminal.exit", json!({"tabId": "tab-2", "exitCode": 1}));
    let mixed = post_events(
        &app,
        &token,
        &runtime,
        vec![
            event("inbox.reply", json!({"replyText": "secret"})),
            event("alera.test", json!({})),
            skewed.clone(),
            fine,
        ],
    )
    .await?;
    assert_eq!(mixed.status, StatusCode::OK, "{}", mixed.text());
    let mixed = mixed.json();
    assert_eq!(mixed["accepted"], 1);
    let codes: Vec<&str> = mixed["rejected"]
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item["code"].as_str())
                .collect()
        })
        .unwrap_or_default();
    assert_eq!(
        codes,
        [
            "sensitive_event_data",
            "unknown_event_kind",
            "invalid_event_time"
        ]
    );
    assert_eq!(mixed["rejected"][2]["eventId"], skewed["eventId"]);
    let too_many: Vec<Value> = (0..101).map(|_| event("agent.status", json!({}))).collect();
    let oversized = post_events(&app, &token, &runtime, too_many).await?;
    assert_eq!(oversized.error_code(), "invalid_event_batch");

    // Delivery: only subscribed kinds, signed, catalog keys only, envelope fields added.
    deliver_all(&state).await?;
    let events = receiver.events();
    assert_eq!(events.len(), 2);
    for item in &events {
        assert!(verify_signature(item, &secret), "signature must verify");
        assert_eq!(item.header("x-alera-webhook-id"), webhook_id);
        assert_eq!(item.header("content-type"), "application/json");
        assert_eq!(
            item.header("webhook-id"),
            item.json()["eventId"].as_str().unwrap_or_default()
        );
    }
    let delivered_reply = events
        .iter()
        .map(Received::json)
        .find(|body| body["name"] == "inbox.reply")
        .unwrap_or(Value::Null);
    assert_eq!(delivered_reply["eventId"], reply["eventId"]);
    assert_eq!(
        delivered_reply["data"],
        json!({"threadId": "t1", "questionId": "q1", "runtimeId": runtime, "workspaceId": "workspace-1", "seq": 1})
    );
    assert!(delivered_reply["cursor"].is_string());
    deliver_all(&state).await?;
    assert_eq!(receiver.events().len(), 2, "nothing is sent twice");

    // 503 retries after five seconds; 413 is dead; both keep the webhook active.
    receiver.respond_with(&[503]);
    let retried = event("agent.status", json!({"state": "blocked"}));
    post_events(&app, &token, &runtime, vec![retried.clone()]).await?;
    deliver_all(&state).await?;
    let retried_id = retried["eventId"].as_str().unwrap_or_default();
    assert_eq!(
        delivery_row(&pool, retried_id).await?,
        ("pending".to_owned(), 1, Some("http_503".to_owned()))
    );
    let wait: f64 = sqlx::query_scalar(
        "SELECT EXTRACT(EPOCH FROM d.next_attempt_at - now())::float8 FROM event_deliveries d JOIN domain_events e ON e.id = d.event_id WHERE e.event_id = $1",
    )
    .bind(retried_id)
    .fetch_one(&pool)
    .await?;
    assert!(
        (2.0..=6.0).contains(&wait),
        "first retry waits about 5 s, got {wait}"
    );
    sqlx::query("UPDATE event_deliveries SET next_attempt_at = now() WHERE status = 'pending' AND event_id IN (SELECT id FROM domain_events WHERE runtime_id = $1)")
        .bind(&runtime)
        .execute(&pool)
        .await?;
    deliver_all(&state).await?;
    assert_eq!(delivery_row(&pool, retried_id).await?.0, "delivered");
    receiver.respond_with(&[413]);
    let too_large = event("agent.status", json!({"state": "done"}));
    post_events(&app, &token, &runtime, vec![too_large.clone()]).await?;
    deliver_all(&state).await?;
    let dead = delivery_row(&pool, too_large["eventId"].as_str().unwrap_or_default()).await?;
    assert_eq!(
        (dead.0.as_str(), dead.2.as_deref()),
        ("dead", Some("http_413"))
    );

    // The test endpoint sends a signed alera.test delivery.
    let test = post_json(
        &app,
        &format!("/v1/webhooks/{webhook_id}/test"),
        Some(&token),
        json!({}),
    )
    .await?;
    assert_eq!(test.status, StatusCode::OK, "{}", test.text());
    assert!(test.json()["deliveryId"].is_string());
    deliver_all(&state).await?;
    let last = receiver
        .events()
        .pop()
        .map(|item| item.json())
        .unwrap_or(Value::Null);
    assert_eq!(last["name"], "alera.test");
    assert_eq!(last["data"], json!({"runtimeId": runtime, "seq": 0}));

    // 410 stops the webhook and its queue.
    receiver.respond_with(&[410]);
    post_events(
        &app,
        &token,
        &runtime,
        vec![event("agent.status", json!({}))],
    )
    .await?;
    deliver_all(&state).await?;
    let listed = get(&app, "/v1/webhooks", Some(&token)).await?.json();
    assert_eq!(listed["webhooks"][0]["status"], "stopped");
    assert_eq!(listed["webhooks"][0]["lastError"], "http_410");
    assert!(listed["webhooks"][0]["lastDeliveryAt"].is_string());
    assert_eq!(active_count(&app, &token).await?, 0);
    let stopped_test = post_json(
        &app,
        &format!("/v1/webhooks/{webhook_id}/test"),
        Some(&token),
        json!({}),
    )
    .await?;
    assert_eq!(stopped_test.error_code(), "webhook_inactive");
    let removed = send(
        &app,
        Method::DELETE,
        &format!("/v1/webhooks/{webhook_id}"),
        Some(&token),
        None,
        Vec::new(),
    )
    .await?;
    assert_eq!(removed.status, StatusCode::NO_CONTENT);
    let missing = send(
        &app,
        Method::DELETE,
        &format!("/v1/webhooks/{webhook_id}"),
        Some(&token),
        None,
        Vec::new(),
    )
    .await?;
    assert_eq!(missing.status, StatusCode::NOT_FOUND);

    // Without the encryption key, nothing can be created.
    let mut unconfigured = test_config(url.clone())?;
    unconfigured.events.secret_key = None;
    let unconfigured_app = router(AppState::from_dependencies(
        pool.clone(),
        unconfigured,
        state.oauth.clone(),
        Arc::new(LocalEd25519Signer::from_seed_b64url(
            "api-contract".to_owned(),
            &URL_SAFE_NO_PAD.encode([23_u8; 32]),
        )?),
        state.fcm.clone(),
    ));
    let refused = post_json(
        &unconfigured_app,
        "/v1/webhooks",
        Some(&token),
        json!({"url": receiver.url("/hook"), "kinds": ["inbox.reply"]}),
    )
    .await?;
    assert_eq!(refused.status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(refused.error_code(), "webhooks_not_configured");

    // Retention: maintenance removes events after 24 hours with their deliveries.
    sqlx::query(
        "UPDATE domain_events SET received_at = now() - interval '25 hours' WHERE runtime_id = $1",
    )
    .bind(&runtime)
    .execute(&pool)
    .await?;
    alera_cloud::maintenance::run_once(&pool).await?;
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM domain_events WHERE runtime_id = $1")
        .bind(&runtime)
        .fetch_one(&pool)
        .await?;
    assert_eq!(left, 0);
    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}
