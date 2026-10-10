use alera_cloud::events::{fanout::fan_out_pending, webhooks::MAX_WEBHOOKS_PER_ACCOUNT};

use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::webhook_contract::{deliver_all, event, post_events};
use super::webhook_receiver::Receiver;
use super::*;

fn subscribe_body(url: &str, cursor: Value) -> Value {
    json!({
        "name": "agent.status",
        "arguments": {},
        "delivery": {
            "mode": "webhook",
            "url": url,
            "secret": format!("whsec_{}", base64::engine::general_purpose::STANDARD.encode([9_u8; 32])),
        },
        "cursor": cursor,
    })
}

/// Status, attempts, and error of the delivery of `event` to `subscription_id`.
async fn row(
    pool: &sqlx::PgPool,
    event: &Value,
    subscription_id: &str,
) -> anyhow::Result<(String, i32, Option<String>)> {
    Ok(sqlx::query_as(
        r#"
        SELECT d.status, d.attempts, d.last_error
        FROM event_deliveries d JOIN domain_events e ON e.id = d.event_id
        WHERE e.event_id = $1 AND d.subscription_id = $2
        "#,
    )
    .bind(event["eventId"].as_str().unwrap_or_default())
    .bind(subscription_id)
    .fetch_one(pool)
    .await?)
}

/// Records a stopped delivery directly, as a past stop for `reason` would have left it.
async fn stopped_delivery(
    pool: &sqlx::PgPool,
    event: &Value,
    subscription_id: &str,
    reason: &str,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"
        INSERT INTO event_deliveries (
            id, subscription_id, event_id, status, attempts, next_attempt_at, created_at,
            last_error
        )
        SELECT gen_random_uuid(), $2, e.id, 'stopped', 1, now(), now(), $3
        FROM domain_events e WHERE e.event_id = $1
        "#,
    )
    .bind(event["eventId"].as_str().unwrap_or_default())
    .bind(subscription_id)
    .bind(reason)
    .execute(pool)
    .await?;
    Ok(())
}

fn delivered_ids(receiver: &Receiver) -> Vec<String> {
    receiver
        .events()
        .into_iter()
        .filter_map(|item| item.json()["eventId"].as_str().map(ToOwned::to_owned))
        .collect()
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn refreshing_an_expired_subscription_resumes_its_stopped_deliveries() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let email = format!("{}@example.test", Uuid::now_v7());
    let state = test_state(
        pool.clone(),
        url.clone(),
        email,
        true,
        Arc::new(AtomicUsize::new(0)),
    )?;
    let app = router(state.clone());
    let runtime = format!("runtime-{}", Uuid::now_v7());
    let session = sign_in(&app, "google", &runtime).await?;
    let token = session["accessToken"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    report_runtime(&app, &token, &runtime, "full", true).await?;
    let client_id = register_client(&app, "Events Resume Client").await?;
    let (access, _, _) = authorize_runtimes(&app, &client_id, &[&runtime], false).await?;
    let receiver = Receiver::start().await?;
    let path = "/v1/mcp/event-subscriptions";
    let echo = receiver.url("/echo");
    let created = post_json(
        &app,
        path,
        Some(&access),
        subscribe_body(&echo, Value::Null),
    )
    .await?;
    assert_eq!(created.status, StatusCode::OK, "{}", created.text());
    let created = created.json();
    let id = created["id"].as_str().unwrap_or_default().to_owned();
    let cursor = created["cursor"].clone();

    // One acknowledged event, one failing with 503, and one still waiting.
    let acknowledged = event("agent.status", json!({"state": "idle"}));
    post_events(&app, &token, &runtime, vec![acknowledged.clone()]).await?;
    deliver_all(&state).await?;
    receiver.respond_with(&[503]);
    let failing = event("agent.status", json!({"state": "blocked"}));
    let waiting = event("agent.status", json!({"state": "waiting"}));
    post_events(
        &app,
        &token,
        &runtime,
        vec![failing.clone(), waiting.clone()],
    )
    .await?;
    fan_out_pending(&state).await?;
    sqlx::query(
        "UPDATE event_deliveries SET next_attempt_at = now() + interval '1 hour' WHERE subscription_id = $1 AND event_id = (SELECT id FROM domain_events WHERE event_id = $2)",
    )
    .bind(&id)
    .bind(waiting["eventId"].as_str().unwrap_or_default())
    .execute(&pool)
    .await?;
    deliver_all(&state).await?;
    assert_eq!(
        row(&pool, &failing, &id).await?,
        ("pending".to_owned(), 1, Some("http_503".to_owned()))
    );
    assert_eq!(
        row(&pool, &waiting, &id).await?,
        ("pending".to_owned(), 0, None)
    );

    // `refreshBefore` passes while the callback is failing: the retried delivery stops the
    // subscription, and the waiting one is stopped with it.
    sqlx::query(
        "UPDATE event_subscriptions SET refresh_before = now() - interval '1 second' WHERE id = $1",
    )
    .bind(&id)
    .execute(&pool)
    .await?;
    sqlx::query(
        "UPDATE event_deliveries SET next_attempt_at = now() WHERE subscription_id = $1 AND event_id = (SELECT id FROM domain_events WHERE event_id = $2)",
    )
    .bind(&id)
    .bind(failing["eventId"].as_str().unwrap_or_default())
    .execute(&pool)
    .await?;
    deliver_all(&state).await?;
    let status: String = sqlx::query_scalar("SELECT status FROM event_subscriptions WHERE id = $1")
        .bind(&id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(status, "expired");
    for stopped in [&failing, &waiting] {
        let (status, _, error) = row(&pool, stopped, &id).await?;
        assert_eq!(
            (status.as_str(), error.as_deref()),
            ("stopped", Some("subscription_expired"))
        );
    }

    // Deliveries stopped for other reasons, and one event fanned out to nobody while expired.
    let disabled = event("agent.status", json!({"state": "disabled"}));
    let revoked = event("agent.status", json!({"state": "revoked"}));
    let missed = event("agent.status", json!({"state": "missed"}));
    post_events(
        &app,
        &token,
        &runtime,
        vec![disabled.clone(), revoked.clone(), missed.clone()],
    )
    .await?;
    deliver_all(&state).await?;
    stopped_delivery(&pool, &disabled, &id, "runtime_mcp_disabled").await?;
    stopped_delivery(&pool, &revoked, &id, "subscription_inactive").await?;
    // The acknowledged delivery and the 503 attempt; nothing is sent while expired.
    let before = delivered_ids(&receiver).len();
    assert_eq!(before, 2, "nothing is sent while expired");

    // Refresh with the same identity and cursor: the expired deliveries resume with a fresh
    // retry budget, the missed event is queued, and nothing else is sent.
    let refreshed = post_json(&app, path, Some(&access), subscribe_body(&echo, cursor)).await?;
    assert_eq!(refreshed.status, StatusCode::OK, "{}", refreshed.text());
    assert_eq!(refreshed.json()["id"], id.as_str());
    deliver_all(&state).await?;
    let mut sent = delivered_ids(&receiver).split_off(before);
    sent.sort();
    let mut expected: Vec<String> = [&failing, &waiting, &missed]
        .iter()
        .map(|item| item["eventId"].as_str().unwrap_or_default().to_owned())
        .collect();
    expected.sort();
    assert_eq!(
        sent, expected,
        "the expired deliveries and the missed event go out; nothing else does"
    );
    for resumed in [&failing, &waiting, &missed] {
        assert_eq!(
            row(&pool, resumed, &id).await?,
            ("delivered".to_owned(), 1, None)
        );
    }
    assert_eq!(row(&pool, &acknowledged, &id).await?.0, "delivered");
    for (kept, reason) in [
        (&disabled, "runtime_mcp_disabled"),
        (&revoked, "subscription_inactive"),
    ] {
        let (status, _, error) = row(&pool, kept, &id).await?;
        assert_eq!(
            (status.as_str(), error.as_deref()),
            ("stopped", Some(reason))
        );
    }
    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn concurrent_webhook_creations_never_pass_the_limit() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let email = format!("{}@example.test", Uuid::now_v7());
    let state = test_state(
        pool.clone(),
        url.clone(),
        email,
        true,
        Arc::new(AtomicUsize::new(0)),
    )?;
    let app = router(state.clone());
    let runtime = format!("runtime-{}", Uuid::now_v7());
    let session = sign_in(&app, "google", &runtime).await?;
    let token = session["accessToken"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    let account_id: Uuid = session["account"]["id"]
        .as_str()
        .unwrap_or_default()
        .parse()?;
    sqlx::query(
        r#"
        INSERT INTO event_subscriptions (
            id, account_id, target_kind, callback_url, secret_ciphertext, kinds, all_runtimes,
            status, created_at, updated_at
        )
        SELECT gen_random_uuid()::text, $1, 'webhook', 'https://hooks.example.test/', 'x',
               ARRAY['agent.status'], true, 'active', now(), now()
        FROM generate_series(1, $2)
        "#,
    )
    .bind(account_id)
    .bind((MAX_WEBHOOKS_PER_ACCOUNT - 1) as i32)
    .execute(&pool)
    .await?;
    let receiver = Receiver::start().await?;
    // Several rounds at 19 webhooks, with the pool warmed so the requests really overlap.
    for round in 0..5 {
        let mut warm = Vec::new();
        for _ in 0..16 {
            warm.push(pool.acquire().await?);
        }
        drop(warm);
        let mut tasks = tokio::task::JoinSet::new();
        for _ in 0..12 {
            let app = app.clone();
            let token = token.clone();
            let body = json!({"url": receiver.url("/hook"), "kinds": ["agent.status"]});
            tasks.spawn(async move { post_json(&app, "/v1/webhooks", Some(&token), body).await });
        }
        let mut created = 0;
        while let Some(reply) = tasks.join_next().await {
            let reply = reply??;
            if reply.status == StatusCode::OK {
                created += 1;
            } else {
                assert_eq!(
                    reply.error_code(),
                    "webhook_limit_reached",
                    "{}",
                    reply.text()
                );
            }
        }
        assert_eq!(
            created, 1,
            "round {round}: one creation fits under the limit"
        );
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM event_subscriptions WHERE account_id = $1 AND target_kind = 'webhook'",
        )
        .bind(account_id)
        .fetch_one(&pool)
        .await?;
        assert_eq!(count, MAX_WEBHOOKS_PER_ACCOUNT);
        sqlx::query(
            "DELETE FROM event_subscriptions WHERE account_id = $1 AND callback_url <> 'https://hooks.example.test/'",
        )
        .bind(account_id)
        .execute(&pool)
        .await?;
    }
    delete_account(&pool, Some(&account_id.to_string())).await?;
    pool.close().await;
    Ok(())
}
