use super::*;

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn account_enrollment_and_push_contract() -> anyhow::Result<()> {
    let database_url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&database_url)
        .await?;
    migrations::run(&pool).await?;
    let shared_email = format!("{}@example.test", Uuid::now_v7());
    let sent = Arc::new(AtomicUsize::new(0));
    let app = test_app(
        pool.clone(),
        database_url.clone(),
        shared_email,
        true,
        sent.clone(),
    )?;
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
    let runtime_identity = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/relay/identity",
            bearer: Some(runtime_token),
            body: json!({
                "publicKey": URL_SAFE_NO_PAD.encode([2_u8; 32]),
                "keyVersion": 1
            }),
        },
    )
    .await?;
    assert_eq!(
        runtime_identity["clientId"].as_str(),
        Some(runtime_one.as_str())
    );
    let mobile_identity = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/relay/identity",
            bearer: Some(mobile_token),
            body: json!({
                "publicKey": URL_SAFE_NO_PAD.encode([1_u8; 32]),
                "keyVersion": 1
            }),
        },
    )
    .await?;
    assert_eq!(
        mobile_identity["clientId"].as_str(),
        Some(device_id.as_str())
    );
    let runtimes = call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/mobile/runtimes",
            bearer: Some(mobile_token),
            body: Value::Null,
        },
    )
    .await?;
    assert_eq!(
        runtimes["runtimes"][0]["relayPublicKey"].as_str(),
        Some(URL_SAFE_NO_PAD.encode([2_u8; 32]).as_str())
    );
    let runtime_grant = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/relay/grants",
            bearer: Some(runtime_token),
            body: json!({"runtimeId": runtime_one}),
        },
    )
    .await?;
    assert_eq!(runtime_grant["clientKind"].as_str(), Some("runtime"));
    let mobile_grant = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/relay/grants",
            bearer: Some(mobile_token),
            body: json!({"runtimeId": runtime_one}),
        },
    )
    .await?;
    assert_eq!(mobile_grant["clientKind"].as_str(), Some("mobile"));
    relay_authorization_cases::assert_grant_scope(&mobile_grant, &runtime_one)?;
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
    sqlx::query(
        r#"
        DELETE FROM delivery_attempts
        WHERE event_id = (
            SELECT id
            FROM runtime_events
            WHERE runtime_id = $1 AND event_id = $2
        )
        "#,
    )
    .bind(&runtime_one)
    .bind(event_body["eventId"].as_str())
    .execute(&pool)
    .await?;
    assert_eq!(
        concurrent_duplicate_deliveries(&app, runtime_token, &event_body).await?,
        1
    );
    assert_eq!(sent.load(Ordering::SeqCst), 2);
    let duplicate_again = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/events",
            bearer: Some(runtime_token),
            body: event_body.clone(),
        },
    )
    .await?;
    assert_eq!(duplicate_again["duplicate"].as_bool(), Some(true));
    assert_eq!(duplicate_again["deliveriesQueued"].as_u64(), Some(0));
    assert_eq!(sent.load(Ordering::SeqCst), 2);
    sqlx::query(
        r#"
        UPDATE delivery_attempts
        SET status = 'pending',
            provider_message_id = NULL,
            error_code = NULL,
            created_at = NOW() - INTERVAL '31 seconds'
        WHERE event_id = (
            SELECT id
            FROM runtime_events
            WHERE runtime_id = $1 AND event_id = $2
        )
        "#,
    )
    .bind(&runtime_one)
    .bind(event_body["eventId"].as_str())
    .execute(&pool)
    .await?;
    assert_eq!(
        concurrent_duplicate_deliveries(&app, runtime_token, &event_body).await?,
        1
    );
    assert_eq!(sent.load(Ordering::SeqCst), 3);
    relay_authorization_cases::rejects_rotation_conflicts_and_revoked_renewals(
        &app,
        &pool,
        account_id,
        &device_id,
        mobile_token,
        &runtime_one,
    )
    .await?;

    let transfer_login = sign_in(&app, "google", &runtime_one).await?;
    let transfer_token = transfer_login["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing transfer runtime access token"))?;
    let target_app = test_app(
        pool.clone(),
        database_url.clone(),
        format!("target-{}@example.test", Uuid::now_v7()),
        true,
        sent.clone(),
    )?;
    let target_bootstrap = sign_in(
        &target_app,
        "google",
        &format!("target-runtime-{}", Uuid::now_v7()),
    )
    .await?;
    let target_account_id = Uuid::parse_str(
        target_bootstrap["account"]["id"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("missing target account id"))?,
    )?;
    let transfer = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/transfer",
            bearer: Some(transfer_token),
            body: json!({
                "runtimeId": runtime_one,
                "targetAccountId": target_account_id,
                "confirmation": runtime_one
            }),
        },
    )
    .await?;
    let target_account_id_text = target_account_id.to_string();
    assert_eq!(
        transfer["accountId"].as_str(),
        Some(target_account_id_text.as_str())
    );
    let target_runtime_login = sign_in(&target_app, "google", &runtime_one).await?;
    let target_runtime_token = target_runtime_login["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing target runtime access token"))?;
    let target_device_id = format!("target-mobile-{}", Uuid::now_v7());
    let target_enrollment = call(
        &target_app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments",
            bearer: Some(target_runtime_token),
            body: json!({
                "runtimeId": runtime_one,
                "deviceId": target_device_id,
                "deviceName": "Transferred Test Phone"
            }),
        },
    )
    .await?;
    let target_mobile = call(
        &target_app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments/redeem",
            bearer: None,
            body: json!({
                "code": target_enrollment["code"],
                "deviceId": target_device_id,
                "deviceName": "Transferred Test Phone"
            }),
        },
    )
    .await?;
    let target_mobile_token = target_mobile["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing target mobile access token"))?;
    call(
        &target_app,
        TestRequest {
            method: Method::PUT,
            uri: "/v1/mobile/push-token",
            bearer: Some(target_mobile_token),
            body: json!({"token": "fcm-target-token-with-valid-length", "platform": "android"}),
        },
    )
    .await?;
    call(
        &target_app,
        TestRequest {
            method: Method::PUT,
            uri: &format!("/v1/mobile/subscriptions/{runtime_one}"),
            bearer: Some(target_mobile_token),
            body: json!({"categories": {"attention": true, "done": false, "terminalExit": false}}),
        },
    )
    .await?;
    let transferred_duplicate = call(
        &target_app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/runtime/events",
            bearer: Some(target_runtime_token),
            body: event_body,
        },
    )
    .await?;
    assert_eq!(transferred_duplicate["duplicate"].as_bool(), Some(true));
    assert_eq!(transferred_duplicate["deliveriesQueued"].as_u64(), Some(0));
    assert_eq!(sent.load(Ordering::SeqCst), 3);

    sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(account_id)
        .execute(&pool)
        .await?;
    sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(target_account_id)
        .execute(&pool)
        .await?;
    pool.close().await;
    Ok(())
}

async fn concurrent_duplicate_deliveries(
    app: &Router,
    runtime_token: &str,
    event_body: &Value,
) -> anyhow::Result<u64> {
    let (first, second) = tokio::join!(
        call_status(app, duplicate_event_request(runtime_token, event_body)),
        call_status(app, duplicate_event_request(runtime_token, event_body)),
    );
    let (status_a, body_a) = first?;
    let (status_b, body_b) = second?;
    for status in [status_a, status_b] {
        assert!(matches!(
            status,
            StatusCode::OK | StatusCode::SERVICE_UNAVAILABLE
        ));
    }
    let mut queued = 0;
    for (status, body) in [(status_a, &body_a), (status_b, &body_b)] {
        if status == StatusCode::OK {
            assert_eq!(body["duplicate"].as_bool(), Some(true));
            queued += body["deliveriesQueued"].as_u64().unwrap_or_default();
        }
    }
    Ok(queued)
}

fn duplicate_event_request<'a>(runtime_token: &'a str, event_body: &Value) -> TestRequest<'a> {
    TestRequest {
        method: Method::POST,
        uri: "/v1/runtime/events",
        bearer: Some(runtime_token),
        body: event_body.clone(),
    }
}

async fn call_status(
    app: &Router,
    request: TestRequest<'_>,
) -> anyhow::Result<(StatusCode, Value)> {
    let mut builder = Request::builder()
        .method(request.method)
        .uri(request.uri)
        .header("content-type", "application/json");
    if let Some(bearer) = request.bearer {
        builder = builder.header("authorization", format!("Bearer {bearer}"));
    }
    let response = app
        .clone()
        .oneshot(builder.body(Body::from(serde_json::to_vec(&request.body)?))?)
        .await?;
    let status = response.status();
    let value = serde_json::from_slice(&to_bytes(response.into_body(), 1024 * 1024).await?)?;
    Ok((status, value))
}
