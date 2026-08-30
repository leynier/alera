use super::*;

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn configuration_history_concurrency_ownership_and_deletion() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    let app = test_app(
        pool.clone(),
        url.clone(),
        format!("{}@example.test", Uuid::new_v4()),
        true,
        Arc::new(AtomicUsize::new(0)),
    )?;
    let runtime_id = format!("runtime-{}", Uuid::new_v4());
    let session = sign_in(&app, "google", &runtime_id).await?;
    let token = session["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("token missing"))?;
    let operation = json!({"operationId": Uuid::new_v4(), "expectedRevision": null,
        "deviceName": "Linux", "summary": "First upload", "document": {
          "schemaVersion": 1, "shared": {}, "desktop": {"prompt": "x".repeat(70_000)}, "mobile": {}}});
    let first = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/configuration",
            bearer: Some(token),
            body: operation.clone(),
        },
    )
    .await?;
    assert_eq!(first["revision"], 1);
    let retry = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/configuration",
            bearer: Some(token),
            body: operation.clone(),
        },
    )
    .await?;
    assert_eq!(first, retry);
    let mut next = operation.clone();
    next["expectedRevision"] = json!(1);
    next["operationId"] = json!(Uuid::new_v4());
    let mut other = next.clone();
    other["operationId"] = json!(Uuid::new_v4());
    let (a, b) = tokio::join!(
        call(
            &app,
            TestRequest {
                method: Method::POST,
                uri: "/v1/configuration",
                bearer: Some(token),
                body: next
            }
        ),
        call(
            &app,
            TestRequest {
                method: Method::POST,
                uri: "/v1/configuration",
                bearer: Some(token),
                body: other
            }
        )
    );
    assert_ne!(a.is_ok(), b.is_ok());
    let history = call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/configuration/history",
            bearer: Some(token),
            body: Value::Null,
        },
    )
    .await?;
    assert_eq!(history["revisions"].as_array().map(Vec::len), Some(2));
    let device_id = format!("phone-{}", Uuid::new_v4());
    let enrollment = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments",
            bearer: Some(token),
            body: json!({"runtimeId": runtime_id, "deviceId": device_id, "deviceName": "Phone"}),
        },
    )
    .await?;
    let mobile = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments/redeem",
            bearer: None,
            body: json!({"code": enrollment["code"], "deviceId": device_id, "deviceName": "Phone"}),
        },
    )
    .await?;
    let mobile_token = mobile["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("mobile token missing"))?;
    let mobile_head = call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/configuration",
            bearer: Some(mobile_token),
            body: Value::Null,
        },
    )
    .await?;
    assert_eq!(mobile_head["head"]["revision"], 2);
    let mobile_retry = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/configuration",
            bearer: Some(mobile_token),
            body: operation.clone(),
        },
    )
    .await?;
    assert_eq!(mobile_retry, first);
    let mut conflicting_retry = operation.clone();
    conflicting_retry["summary"] = json!("Changed content with the same operation id");
    assert!(call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/configuration",
            bearer: Some(token),
            body: conflicting_retry,
        }
    )
    .await
    .err()
    .ok_or_else(|| anyhow::anyhow!("expected configuration request to fail"))?
    .to_string()
    .contains("configuration_operation_conflict"));
    let other_app = test_app(
        pool.clone(),
        url,
        format!("{}@example.test", Uuid::new_v4()),
        true,
        Arc::new(AtomicUsize::new(0)),
    )?;
    let stranger = sign_in(&other_app, "github", &format!("runtime-{}", Uuid::new_v4())).await?;
    let stranger_token = stranger["accessToken"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("token missing"))?;
    assert!(call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/configuration/revisions/1",
            bearer: Some(stranger_token),
            body: Value::Null
        }
    )
    .await
    .is_err());
    let account_id = Uuid::parse_str(
        session["account"]["id"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("account missing"))?,
    )?;
    sqlx::query("INSERT INTO configuration_revisions (account_id, revision, operation_id, request_hash, document, device_name, client_id, summary) SELECT $1, n, gen_random_uuid(), 'seed', $2::jsonb, 'Fixture', 'fixture', 'Fixture' FROM generate_series(3, 102) n")
        .bind(account_id).bind(serde_json::to_string(&operation["document"])?).execute(&pool).await?;
    sqlx::query("UPDATE configuration_heads SET revision = 102 WHERE account_id = $1")
        .bind(account_id)
        .execute(&pool)
        .await?;
    let mut latest = operation.clone();
    latest["operationId"] = json!(Uuid::new_v4());
    latest["expectedRevision"] = json!(102);
    let published = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/configuration",
            bearer: Some(token),
            body: latest,
        },
    )
    .await?;
    assert_eq!(published["revision"], 103);
    let retained: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM configuration_revisions WHERE account_id = $1")
            .bind(account_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(retained, 100);
    assert!(call(
        &app,
        TestRequest {
            method: Method::GET,
            uri: "/v1/configuration/revisions/1",
            bearer: Some(token),
            body: Value::Null,
        }
    )
    .await
    .is_err());
    sqlx::query("UPDATE configuration_request_limits SET request_count = 20 WHERE account_id = $1 AND operation = 'write'").bind(account_id).execute(&pool).await?;
    assert!(call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/configuration",
            bearer: Some(token),
            body: operation,
        }
    )
    .await
    .err()
    .ok_or_else(|| anyhow::anyhow!("expected configuration request to fail"))?
    .to_string()
    .contains("configuration_rate_limited"));
    call(
        &app,
        TestRequest {
            method: Method::DELETE,
            uri: "/v1/account",
            bearer: Some(token),
            body: json!({"confirmation": "DELETE"}),
        },
    )
    .await?;
    let remaining: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM configuration_revisions WHERE account_id = $1")
            .bind(account_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(remaining, 0);
    sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(Uuid::parse_str(
            stranger["account"]["id"]
                .as_str()
                .ok_or_else(|| anyhow::anyhow!("account missing"))?,
        )?)
        .execute(&pool)
        .await?;
    Ok(())
}
