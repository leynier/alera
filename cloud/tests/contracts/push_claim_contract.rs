use super::*;

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn retryable_claims_reclaim_without_double_quota_reservation() -> anyhow::Result<()> {
    let database_url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&database_url)
        .await?;
    migrations::run(&pool).await?;
    let sent = Arc::new(AtomicUsize::new(0));
    let app = test_app(
        pool.clone(),
        database_url.clone(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        sent.clone(),
    )?;
    let runtime_id = format!("runtime-{}", Uuid::now_v7());
    let login = sign_in(&app, "google", &runtime_id).await?;
    let account_id = Uuid::parse_str(
        login["account"]["id"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("missing account id"))?,
    )?;
    let runtime_token = login["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing runtime access token"))?;
    let device_id = format!("mobile-{}", Uuid::now_v7());
    let enrollment = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments",
            bearer: Some(runtime_token),
            body: json!({
                "runtimeId": runtime_id,
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
    let mobile_token = mobile["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing mobile access token"))?;
    call(
        &app,
        TestRequest {
            method: Method::PUT,
            uri: "/v1/mobile/push-token",
            bearer: Some(mobile_token),
            body: json!({
                "token": "fcm-registration-token-with-valid-length",
                "platform": "android"
            }),
        },
    )
    .await?;
    call(
        &app,
        TestRequest {
            method: Method::PUT,
            uri: &format!("/v1/mobile/subscriptions/{runtime_id}"),
            bearer: Some(mobile_token),
            body: json!({
                "categories": {"attention": true, "done": false, "terminalExit": false}
            }),
        },
    )
    .await?;
    let event_body = json!({
        "runtimeId": runtime_id,
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
    assert_eq!(sent.load(Ordering::SeqCst), 1);
    let database_event_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM runtime_events WHERE runtime_id = $1 AND event_id = $2",
    )
    .bind(event_body["runtimeId"].as_str())
    .bind(event_body["eventId"].as_str())
    .fetch_one(&pool)
    .await?;
    let claim_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM delivery_attempts WHERE event_id = $1 AND mobile_device_id = $2",
    )
    .bind(database_event_id)
    .bind(&device_id)
    .fetch_one(&pool)
    .await?;
    let quota_before = quota_counts(&pool, account_id).await?;
    sqlx::query(
        "UPDATE delivery_attempts SET status = 'pending', quota_reserved = TRUE, created_at = NOW() - INTERVAL '31 seconds' WHERE id = $1",
    )
    .bind(claim_id)
    .execute(&pool)
    .await?;
    assert!(
        alera_cloud::quota::reserve_push_delivery(
            &pool,
            claim_id,
            account_id,
            &test_config(database_url.clone())?.limits,
        )
        .await?
    );
    assert_eq!(quota_counts(&pool, account_id).await?, quota_before);
    let recovered = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/events",
            bearer: Some(runtime_token),
            body: event_body.clone(),
        },
    )
    .await?;
    assert_eq!(recovered["deliveriesQueued"].as_u64(), Some(1));
    assert_eq!(sent.load(Ordering::SeqCst), 2);
    let current_claim_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM delivery_attempts WHERE event_id = $1 AND mobile_device_id = $2",
    )
    .bind(database_event_id)
    .bind(&device_id)
    .fetch_one(&pool)
    .await?;
    sqlx::query("UPDATE delivery_attempts SET status = 'retryable' WHERE id = $1")
        .bind(current_claim_id)
        .execute(&pool)
        .await?;
    let immediate_retry = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/events",
            bearer: Some(runtime_token),
            body: event_body.clone(),
        },
    )
    .await?;
    assert_eq!(immediate_retry["deliveriesQueued"].as_u64(), Some(1));
    assert_eq!(sent.load(Ordering::SeqCst), 3);
    let fresh_claim_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM delivery_attempts WHERE event_id = $1 AND mobile_device_id = $2",
    )
    .bind(database_event_id)
    .bind(&device_id)
    .fetch_one(&pool)
    .await?;
    sqlx::query(
        "UPDATE delivery_attempts SET status = 'pending', created_at = NOW() WHERE id = $1",
    )
    .bind(fresh_claim_id)
    .execute(&pool)
    .await?;
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/v1/runtime/events")
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {runtime_token}"))
                .body(Body::from(serde_json::to_vec(&event_body)?))?,
        )
        .await?;
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    Ok(())
}

async fn quota_counts(pool: &sqlx::PgPool, account_id: Uuid) -> anyhow::Result<(i32, i32, i32)> {
    Ok(sqlx::query_as::<_, (i32, i32, i32)>(
        r#"
        SELECT
            COALESCE((SELECT count FROM push_quota_daily WHERE account_id = $1 AND day = CURRENT_DATE), 0),
            COALESCE((SELECT count FROM push_quota_hourly WHERE account_id = $1 AND hour = date_trunc('hour', NOW())), 0),
            COALESCE((SELECT count FROM push_quota_bursts WHERE account_id = $1 AND window_start = date_trunc('minute', NOW())), 0)
        "#,
    )
    .bind(account_id)
    .fetch_one(pool)
    .await?)
}
