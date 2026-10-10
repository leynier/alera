use alera_cloud::events::{delivery::run_pass, fanout::fan_out_pending};

use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::webhook_contract::{deliver_all, event, post_events};
use super::webhook_receiver::Receiver;
use super::*;

fn mcp_subscription(url: &str, arguments: Value) -> Value {
    json!({
        "name": "agent.status",
        "arguments": arguments,
        "delivery": {
            "mode": "webhook",
            "url": url,
            "secret": format!("whsec_{}", base64::engine::general_purpose::STANDARD.encode([7_u8; 32])),
        },
    })
}

async fn active_count(app: &Router, token: &str) -> anyhow::Result<Value> {
    Ok(get(app, "/v1/runtime/event-subscriptions", Some(token))
        .await?
        .json()["activeSubscriptions"]
        .clone())
}

fn paths(receiver: &Receiver) -> Vec<String> {
    receiver
        .events()
        .into_iter()
        .map(|item| item.path)
        .collect()
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_events_follow_the_runtime_mcp_control_but_webhooks_do_not() -> anyhow::Result<()> {
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
    let client_id = register_client(&app, "Events Access Client").await?;
    let (access, _, _) = authorize_runtimes(&app, &client_id, &[&runtime], false).await?;
    let receiver = Receiver::start().await?;
    let path = "/v1/mcp/event-subscriptions";

    // One webhook and one all-runtimes MCP Events subscription for the same kind.
    let hook = post_json(
        &app,
        "/v1/webhooks",
        Some(&token),
        json!({"url": receiver.url("/hook"), "kinds": ["agent.status"]}),
    )
    .await?;
    assert_eq!(hook.status, StatusCode::OK, "{}", hook.text());
    let subscribed = post_json(
        &app,
        path,
        Some(&access),
        mcp_subscription(&receiver.url("/echo"), json!({})),
    )
    .await?;
    assert_eq!(subscribed.status, StatusCode::OK, "{}", subscribed.text());
    let subscription_id = subscribed.json()["id"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    assert_eq!(active_count(&app, &token).await?, 2);
    post_events(
        &app,
        &token,
        &runtime,
        vec![event("agent.status", json!({}))],
    )
    .await?;
    deliver_all(&state).await?;
    let mut delivered = paths(&receiver);
    delivered.sort();
    assert_eq!(delivered, ["/echo", "/hook"]);

    // Off: fan-out leaves MCP Events out, and a delivery queued before the switch (inserted
    // directly, so a concurrent worker cannot send it first) is dropped on the recheck.
    // The subscription stays active for when MCP Control comes back on.
    report_runtime(&app, &token, &runtime, "off", true).await?;
    let queued = event("agent.status", json!({"state": "waiting"}));
    post_events(&app, &token, &runtime, vec![queued.clone()]).await?;
    fan_out_pending(&state).await?;
    sqlx::query(
        r#"
        INSERT INTO event_deliveries (
            id, subscription_id, event_id, status, attempts, next_attempt_at, created_at
        )
        SELECT gen_random_uuid(), $2, e.id, 'pending', 0, now(), now()
        FROM domain_events e WHERE e.event_id = $1
        "#,
    )
    .bind(queued["eventId"].as_str().unwrap_or_default())
    .bind(&subscription_id)
    .execute(&pool)
    .await?;
    deliver_all(&state).await?;
    assert_eq!(paths(&receiver).len(), 3, "the webhook still receives");
    assert_eq!(
        paths(&receiver)
            .iter()
            .filter(|path| *path == "/echo")
            .count(),
        1,
        "MCP Events receives nothing while MCP Control is off"
    );
    let dropped: (String, Option<String>) = sqlx::query_as(
        r#"
        SELECT d.status, d.last_error
        FROM event_deliveries d JOIN domain_events e ON e.id = d.event_id
        WHERE e.event_id = $1 AND d.subscription_id = $2
        "#,
    )
    .bind(queued["eventId"].as_str().unwrap_or_default())
    .bind(&subscription_id)
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        (dropped.0.as_str(), dropped.1.as_deref()),
        ("stopped", Some("runtime_mcp_disabled"))
    );
    let status: String = sqlx::query_scalar("SELECT status FROM event_subscriptions WHERE id = $1")
        .bind(&subscription_id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(status, "active");

    // While off: the count leaves MCP Events out, fan-out skips them, and naming the
    // runtime in a new subscription is refused with a clear error.
    assert_eq!(active_count(&app, &token).await?, 1);
    post_events(
        &app,
        &token,
        &runtime,
        vec![event("agent.status", json!({}))],
    )
    .await?;
    deliver_all(&state).await?;
    let fanned: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM event_deliveries WHERE subscription_id = $1")
            .bind(&subscription_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(fanned, 2, "no new MCP Events delivery while off");
    assert_eq!(paths(&receiver).len(), 4);
    let refused = post_json(
        &app,
        path,
        Some(&access),
        mcp_subscription(&receiver.url("/echo"), json!({"runtime": runtime})),
    )
    .await?;
    assert_eq!(refused.status, StatusCode::CONFLICT, "{}", refused.text());
    assert_eq!(refused.error_code(), "runtime_mcp_disabled");
    assert!(refused.text().contains("MCP Control is off"));

    // Back on: MCP Events resume.
    report_runtime(&app, &token, &runtime, "read", true).await?;
    assert_eq!(active_count(&app, &token).await?, 2);
    post_events(
        &app,
        &token,
        &runtime,
        vec![event("agent.status", json!({}))],
    )
    .await?;
    deliver_all(&state).await?;
    assert_eq!(
        paths(&receiver)
            .iter()
            .filter(|path| *path == "/echo")
            .count(),
        2
    );
    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}

/// The status, attempts, and error of the delivery of `event_id` to `subscription_id`.
async fn delivery_row(
    pool: &sqlx::PgPool,
    event_id: &str,
    subscription_id: &str,
) -> anyhow::Result<(String, i32, Option<String>)> {
    Ok(sqlx::query_as(
        r#"
        SELECT d.status, d.attempts, d.last_error
        FROM event_deliveries d JOIN domain_events e ON e.id = d.event_id
        WHERE e.event_id = $1 AND d.subscription_id = $2
        "#,
    )
    .bind(event_id)
    .bind(subscription_id)
    .fetch_one(pool)
    .await?)
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn the_mcp_events_switch_pauses_deliveries_without_revoking() -> anyhow::Result<()> {
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
    let client_id = register_client(&app, "Events Pause Client").await?;
    let (access, _, _) = authorize_runtimes(&app, &client_id, &[&runtime], false).await?;
    let receiver = Receiver::start().await?;
    let subscribed = post_json(
        &app,
        "/v1/mcp/event-subscriptions",
        Some(&access),
        mcp_subscription(&receiver.url("/echo"), json!({})),
    )
    .await?;
    assert_eq!(subscribed.status, StatusCode::OK, "{}", subscribed.text());
    let subscription_id = subscribed.json()["id"]
        .as_str()
        .unwrap_or_default()
        .to_owned();

    // Switch off: a delivery queued for a valid grant is neither attempted nor stopped,
    // and the subscription is not revoked.
    let mut config = test_config(url.clone())?;
    config.events.mcp_events_enabled = false;
    let paused = AppState::from_dependencies(
        pool.clone(),
        config,
        state.oauth.clone(),
        Arc::new(LocalEd25519Signer::from_seed_b64url(
            "api-contract".to_owned(),
            &URL_SAFE_NO_PAD.encode([23_u8; 32]),
        )?),
        state.fcm.clone(),
    );
    let paused_app = router(paused.clone());
    let queued = event("agent.status", json!({"state": "waiting"}));
    let queued_id = queued["eventId"].as_str().unwrap_or_default().to_owned();
    post_events(&paused_app, &token, &runtime, vec![queued]).await?;
    fan_out_pending(&paused).await?;
    sqlx::query(
        r#"
        INSERT INTO event_deliveries (
            id, subscription_id, event_id, status, attempts, next_attempt_at, created_at
        )
        SELECT gen_random_uuid(), $2, e.id, 'pending', 0, now(), now()
        FROM domain_events e WHERE e.event_id = $1
        "#,
    )
    .bind(&queued_id)
    .bind(&subscription_id)
    .execute(&pool)
    .await?;
    for _ in 0..3 {
        run_pass(&paused).await?;
    }
    let row = delivery_row(&pool, &queued_id, &subscription_id).await?;
    assert_eq!((row.0.as_str(), row.1, row.2), ("pending", 0, None));
    let status: String = sqlx::query_scalar("SELECT status FROM event_subscriptions WHERE id = $1")
        .bind(&subscription_id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(status, "active");
    assert!(paths(&receiver).is_empty(), "nothing is sent while paused");

    // Switch back on: the queued delivery goes out.
    deliver_all(&state).await?;
    let row = delivery_row(&pool, &queued_id, &subscription_id).await?;
    assert_eq!(row.0, "delivered");
    let delivered = receiver.events();
    assert_eq!(delivered.len(), 1);
    assert_eq!(delivered[0].json()["eventId"], queued_id.as_str());
    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}

async fn pump(app: &Router, origin_token: Option<&str>) -> anyhow::Result<StatusCode> {
    let mut builder = Request::builder()
        .method(Method::POST)
        .uri("/v1/internal/event-deliveries/pump");
    if let Some(origin_token) = origin_token {
        builder = builder.header("x-alera-origin-auth", origin_token);
    }
    let response = app.clone().oneshot(builder.body(Body::empty())?).await?;
    Ok(response.status())
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn the_delivery_pump_requires_the_origin_token_even_with_direct_origin() -> anyhow::Result<()>
{
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let state = test_state(
        pool.clone(),
        url.clone(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        Arc::new(AtomicUsize::new(0)),
    )?;
    // Direct origin access with no token configured: the pump is closed.
    let open = router(state.clone());
    assert!(state.config.allow_direct_origin);
    assert_eq!(pump(&open, None).await?, StatusCode::UNAUTHORIZED);
    assert_eq!(
        pump(&open, Some("anything")).await?,
        StatusCode::UNAUTHORIZED
    );

    // With a token: only the current or previous token runs a drain.
    let mut config = test_config(url.clone())?;
    config.edge_origin_token = Some("pump-current".to_owned());
    config.edge_previous_origin_token = Some("pump-previous".to_owned());
    let guarded = router(AppState::from_dependencies(
        pool.clone(),
        config,
        state.oauth.clone(),
        Arc::new(LocalEd25519Signer::from_seed_b64url(
            "api-contract".to_owned(),
            &URL_SAFE_NO_PAD.encode([23_u8; 32]),
        )?),
        state.fcm.clone(),
    ));
    assert_eq!(pump(&guarded, None).await?, StatusCode::UNAUTHORIZED);
    assert_eq!(
        pump(&guarded, Some("wrong")).await?,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(pump(&guarded, Some("pump-current")).await?, StatusCode::OK);
    assert_eq!(pump(&guarded, Some("pump-previous")).await?, StatusCode::OK);
    pool.close().await;
    Ok(())
}
