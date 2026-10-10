use alera_cloud::events::{cursor, fanout::fan_out_pending};

use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::webhook_contract::{deliver_all, event, post_events, verify_signature};
use super::webhook_receiver::Receiver;
use super::*;

fn secret(byte: u8) -> String {
    format!(
        "whsec_{}",
        base64::engine::general_purpose::STANDARD.encode([byte; 32])
    )
}

fn subscribe_body(url: &str, secret: &str, arguments: Value, cursor: Value) -> Value {
    json!({
        "name": "inbox.reply",
        "arguments": arguments,
        "delivery": {"mode": "webhook", "url": url, "secret": secret},
        "cursor": cursor,
    })
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_events_subscriptions_follow_the_grant() -> anyhow::Result<()> {
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
    let runtime_token = session["accessToken"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    report_runtime(&app, &runtime_token, &runtime, "full", true).await?;
    let client_id = register_client(&app, "Events Client").await?;
    let (access, _, _) = authorize_runtimes(&app, &client_id, &[&runtime], false).await?;
    let receiver = Receiver::start().await?;
    let path = "/v1/mcp/event-subscriptions";
    let secret_one = secret(1);

    // A callback that does not echo the challenge is refused with its reason.
    let refused = post_json(
        &app,
        path,
        Some(&access),
        subscribe_body(
            &receiver.url("/noecho"),
            &secret_one,
            json!({}),
            Value::Null,
        ),
    )
    .await?;
    assert_eq!(
        refused.status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "{}",
        refused.text()
    );
    assert_eq!(refused.error_code(), "callback_endpoint_error");
    assert_eq!(refused.json()["error"]["message"], "challenge_failed");
    for (body, code) in [
        (
            subscribe_body(
                &receiver.url("/echo"),
                "whsec_c2hvcnQ=",
                json!({}),
                Value::Null,
            ),
            "invalid_event_subscription",
        ),
        (
            subscribe_body(
                &receiver.url("/echo"),
                &secret_one,
                json!({"prompt": "x"}),
                Value::Null,
            ),
            "invalid_event_subscription",
        ),
        (
            subscribe_body(
                &receiver.url("/echo"),
                &secret_one,
                json!({"runtime": "elsewhere"}),
                Value::Null,
            ),
            "runtime_not_found",
        ),
        (
            subscribe_body(
                &receiver.url("/echo"),
                &secret_one,
                json!({}),
                json!("bogus"),
            ),
            "invalid_event_subscription",
        ),
    ] {
        let reply = post_json(&app, path, Some(&access), body).await?;
        assert_eq!(reply.error_code(), code, "{}", reply.text());
    }

    // Subscribe: verified challenge, deterministic id, 24-hour cap, opaque cursor.
    let arguments = json!({"runtime": runtime, "threadId": "t1"});
    let echo = receiver.url("/echo");
    let created = post_json(
        &app,
        path,
        Some(&access),
        subscribe_body(&echo, &secret_one, arguments.clone(), Value::Null),
    )
    .await?;
    assert_eq!(created.status, StatusCode::OK, "{}", created.text());
    let created = created.json();
    let id = created["id"].as_str().unwrap_or_default().to_owned();
    assert!(id.starts_with("sub_"));
    assert_eq!(created["truncated"], false);
    let first_cursor = created["cursor"].as_str().unwrap_or_default().to_owned();
    let refresh = chrono::DateTime::parse_from_rfc3339(
        created["refreshBefore"].as_str().unwrap_or_default(),
    )?;
    let hours = (refresh.with_timezone(&chrono::Utc) - chrono::Utc::now()).num_minutes();
    assert!(
        (1430..=1440).contains(&hours),
        "default lifetime is 24 h, got {hours} min"
    );
    let challenge = receiver
        .received()
        .into_iter()
        .find(|item| item.path == "/echo")
        .ok_or_else(|| anyhow::anyhow!("no challenge"))?;
    assert!(verify_signature(&challenge, &secret_one));
    assert_eq!(challenge.header("x-mcp-subscription-id"), id);
    assert_eq!(
        get(
            &app,
            "/v1/runtime/event-subscriptions",
            Some(&runtime_token)
        )
        .await?
        .json()["activeSubscriptions"],
        1
    );

    // Delivery honours the filter and carries the subscription header.
    let wanted = event("inbox.reply", json!({"threadId": "t1", "questionId": "q1"}));
    let other = event("inbox.reply", json!({"threadId": "t2", "questionId": "q2"}));
    post_events(&app, &runtime_token, &runtime, vec![wanted.clone(), other]).await?;
    deliver_all(&state).await?;
    let delivered = receiver.events();
    assert_eq!(delivered.len(), 1);
    assert_eq!(delivered[0].header("x-mcp-subscription-id"), id);
    assert!(verify_signature(&delivered[0], &secret_one));
    let body = delivered[0].json();
    assert_eq!(body["eventId"], wanted["eventId"]);
    assert_eq!(body["name"], "inbox.reply");
    assert_eq!(body["data"]["threadId"], "t1");
    assert!(body["cursor"].is_string());

    // Refresh with the same identity and cursor: same id, no new challenge, no replay of
    // the acknowledged event. A rotated secret is challenged again.
    let challenges = receiver.challenges();
    let refreshed = post_json(
        &app,
        path,
        Some(&access),
        json!({
            "name": "inbox.reply", "arguments": arguments, "cursor": first_cursor, "ttlMs": 120_000,
            "delivery": {"mode": "webhook", "url": echo, "secret": secret_one},
        }),
    )
    .await?
    .json();
    assert_eq!(refreshed["id"], id.as_str());
    assert_eq!(refreshed["truncated"], false);
    let refresh = chrono::DateTime::parse_from_rfc3339(
        refreshed["refreshBefore"].as_str().unwrap_or_default(),
    )?;
    assert!((refresh.with_timezone(&chrono::Utc) - chrono::Utc::now()).num_seconds() <= 120);
    assert_eq!(receiver.challenges(), challenges);
    deliver_all(&state).await?;
    assert_eq!(
        receiver.events().len(),
        1,
        "acknowledged events are not replayed"
    );
    let old_cursor = cursor::encode(chrono::Utc::now() - chrono::TimeDelta::hours(25));
    let rotated = post_json(
        &app,
        path,
        Some(&access),
        subscribe_body(&echo, &secret(2), arguments.clone(), json!(old_cursor)),
    )
    .await?
    .json();
    assert_eq!(rotated["id"], id.as_str());
    assert_eq!(rotated["truncated"], true);
    assert_eq!(receiver.challenges(), challenges + 1);

    // Unsubscribe is idempotent.
    let second = post_json(
        &app,
        path,
        Some(&access),
        json!({
            "name": "agent.status", "arguments": {}, "cursor": null,
            "delivery": {"mode": "webhook", "url": echo, "secret": secret_one},
        }),
    )
    .await?;
    assert_eq!(second.status, StatusCode::OK, "{}", second.text());
    let unsubscribe = json!({"name": "agent.status", "arguments": {}, "delivery": {"mode": "webhook", "url": echo}});
    for _ in 0..2 {
        let reply = post_json(
            &app,
            &format!("{path}/unsubscribe"),
            Some(&access),
            unsubscribe.clone(),
        )
        .await?;
        assert_eq!(reply.status, StatusCode::NO_CONTENT, "{}", reply.text());
    }
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM event_subscriptions WHERE account_id = (SELECT account_id FROM runtimes WHERE id = $1)")
        .bind(&runtime)
        .fetch_one(&pool)
        .await?;
    assert_eq!(left, 1);

    // Revoking the grant stops queued deliveries and ends the subscription. The queued
    // delivery is inserted after the revoke, so a concurrent test's worker cannot send it
    // before the revoke lands.
    let grants = get(&app, "/v1/mcp/grants", Some(&runtime_token))
        .await?
        .json();
    let grant_id = grants["grants"][0]["id"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    let revoked = send(
        &app,
        Method::DELETE,
        &format!("/v1/mcp/grants/{grant_id}"),
        Some(&runtime_token),
        None,
        Vec::new(),
    )
    .await?;
    assert_eq!(revoked.status, StatusCode::NO_CONTENT);
    let queued = event("inbox.reply", json!({"threadId": "t1"}));
    post_events(&app, &runtime_token, &runtime, vec![queued.clone()]).await?;
    fan_out_pending(&state).await?;
    sqlx::query(
        r#"
        INSERT INTO event_deliveries (
            id, subscription_id, event_id, status, attempts, next_attempt_at, created_at
        )
        SELECT gen_random_uuid(), $2, e.id, 'pending', 0, now(), now()
        FROM domain_events e WHERE e.event_id = $1
        ON CONFLICT (subscription_id, event_id) DO NOTHING
        "#,
    )
    .bind(queued["eventId"].as_str().unwrap_or_default())
    .bind(&id)
    .execute(&pool)
    .await?;
    let before = receiver.events().len();
    deliver_all(&state).await?;
    post_events(
        &app,
        &runtime_token,
        &runtime,
        vec![event("inbox.reply", json!({"threadId": "t1"}))],
    )
    .await?;
    deliver_all(&state).await?;
    assert_eq!(
        receiver.events().len(),
        before,
        "a revoked grant receives nothing"
    );
    let status: String = sqlx::query_scalar("SELECT status FROM event_subscriptions WHERE id = $1")
        .bind(&id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(status, "revoked");
    assert_eq!(
        get(
            &app,
            "/v1/runtime/event-subscriptions",
            Some(&runtime_token)
        )
        .await?
        .json()["activeSubscriptions"],
        0
    );
    let after_revoke = post_json(
        &app,
        path,
        Some(&access),
        subscribe_body(&echo, &secret_one, json!({}), Value::Null),
    )
    .await?;
    assert_eq!(after_revoke.status, StatusCode::UNAUTHORIZED);

    // The switch hides the endpoints.
    let mut disabled = test_config(url.clone())?;
    disabled.events.mcp_events_enabled = false;
    let disabled_app = router(AppState::from_dependencies(
        pool.clone(),
        disabled,
        state.oauth.clone(),
        Arc::new(LocalEd25519Signer::from_seed_b64url(
            "api-contract".to_owned(),
            &URL_SAFE_NO_PAD.encode([23_u8; 32]),
        )?),
        state.fcm.clone(),
    ));
    let hidden = post_json(
        &disabled_app,
        path,
        Some(&access),
        subscribe_body(&echo, &secret_one, json!({}), Value::Null),
    )
    .await?;
    assert_eq!(hidden.error_code(), "mcp_events_disabled");
    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}
