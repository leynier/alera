use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::*;

async fn create_call(app: &Router, token: &str, body: Value) -> anyhow::Result<Reply> {
    post_json(app, "/v1/mcp/calls", Some(token), body).await
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_gateway_resolution_grants_and_runtime_settings() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let app = test_app(
        pool.clone(),
        url.clone(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        Arc::new(AtomicUsize::new(0)),
    )?;
    let laptop = format!("runtime-{}", Uuid::now_v7());
    let server = format!("runtime-{}", Uuid::now_v7());
    let ungranted = format!("runtime-{}", Uuid::now_v7());
    let laptop_session = sign_in(&app, "google", &laptop).await?;
    let server_session = sign_in(&app, "github", &server).await?;
    let ungranted_session = sign_in(&app, "google", &ungranted).await?;
    assert_eq!(
        laptop_session["account"]["id"],
        server_session["account"]["id"]
    );
    let laptop_token = laptop_session["accessToken"].as_str().unwrap_or_default();
    let server_token = server_session["accessToken"].as_str().unwrap_or_default();
    let ungranted_token = ungranted_session["accessToken"]
        .as_str()
        .unwrap_or_default();

    let renamed = send(
        &app,
        Method::PUT,
        "/v1/runtime/name",
        Some(laptop_token),
        Some("application/json"),
        serde_json::to_vec(&json!({"name": " Laptop "}))?,
    )
    .await?;
    assert_eq!(renamed.status, StatusCode::OK, "{}", renamed.text());
    assert_eq!(renamed.json(), json!({"id": laptop, "name": "Laptop"}));
    let taken = send(
        &app,
        Method::PUT,
        "/v1/runtime/name",
        Some(server_token),
        Some("application/json"),
        serde_json::to_vec(&json!({"name": "LAPTOP"}))?,
    )
    .await?;
    assert_eq!(taken.status, StatusCode::CONFLICT);
    assert_eq!(taken.error_code(), "runtime_name_taken");

    let claims = report_runtime(&app, laptop_token, &laptop, "full", true).await?;
    assert_eq!(claims["mcpAccess"], "full");
    assert_eq!(claims["mobileAccess"], true);
    report_runtime(&app, server_token, &server, "read", true).await?;
    report_runtime(&app, ungranted_token, &ungranted, "full", true).await?;

    let client_id = register_client(&app, "Gateway Client").await?;
    let (access, _, _) =
        authorize_runtimes(&app, &client_id, &[laptop.as_str(), server.as_str()], false).await?;
    let listed = get(&app, "/v1/mcp/runtimes", Some(&access)).await?.json();
    let runtimes = listed["runtimes"].as_array().cloned().unwrap_or_default();
    assert_eq!(runtimes.len(), 2);
    assert_eq!(runtimes[0]["name"], "Laptop");
    assert_eq!(runtimes[0]["online"], true);
    assert_eq!(runtimes[0]["mcpAccess"], "full");
    assert_eq!(runtimes[1]["mcpAccess"], "read");

    let required = create_call(
        &app,
        &access,
        json!({"tool": "workspace_list", "access": "read"}),
    )
    .await?;
    assert_eq!(required.status, StatusCode::CONFLICT);
    assert_eq!(required.error_code(), "runtime_required");
    assert!(required.json()["error"]["message"]
        .as_str()
        .unwrap_or_default()
        .contains("Laptop"));
    let hidden = create_call(
        &app,
        &access,
        json!({"runtime": ungranted, "tool": "workspace_list", "access": "read"}),
    )
    .await?;
    assert_eq!(hidden.status, StatusCode::NOT_FOUND);
    assert_eq!(hidden.error_code(), "runtime_not_found");
    let read_only = create_call(
        &app,
        &access,
        json!({"runtime": server, "tool": "terminal_send", "access": "execute"}),
    )
    .await?;
    assert_eq!(read_only.status, StatusCode::FORBIDDEN);
    assert_eq!(read_only.error_code(), "runtime_read_only");

    let created = create_call(
        &app,
        &access,
        json!({"runtime": "laptop", "tool": "terminal_send", "access": "execute"}),
    )
    .await?;
    assert_eq!(created.status, StatusCode::OK, "{}", created.text());
    let created = created.json();
    assert_eq!(created["runtimeId"], laptop.as_str());
    assert_eq!(created["runtimeName"], "Laptop");
    assert_eq!(created["expiresIn"], 120);
    let call_id = created["callId"].as_str().unwrap_or_default().to_owned();
    let grant_claims = jwt_claims(created["grant"].as_str().unwrap_or_default())?;
    assert_eq!(grant_claims["aud"], "alera-runtime-mcp");
    assert_eq!(grant_claims["jti"], call_id.as_str());
    assert_eq!(grant_claims["clientName"], "Gateway Client");
    assert_eq!(grant_claims["tool"], "terminal_send");
    assert_eq!(grant_claims["access"], "execute");
    assert_eq!(grant_claims["accountId"], laptop_session["account"]["id"]);
    let outcome_uri = format!("/v1/mcp/calls/{call_id}/outcome");
    let outcome = json!({"outcome": "ok", "durationMs": 42});
    let first = post_json(&app, &outcome_uri, Some(&access), outcome.clone()).await?;
    assert_eq!(first.status, StatusCode::NO_CONTENT);
    let second = post_json(&app, &outcome_uri, Some(&access), outcome).await?;
    assert_eq!(second.status, StatusCode::CONFLICT);
    let audit = sqlx::query_as::<_, (String, Option<String>, Option<i32>)>(
        "SELECT tool, outcome, duration_ms FROM mcp_calls WHERE id = $1",
    )
    .bind(Uuid::parse_str(&call_id)?)
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        audit,
        ("terminal_send".to_owned(), Some("ok".to_owned()), Some(42))
    );

    report_runtime(&app, server_token, &server, "off", true).await?;
    let single = create_call(
        &app,
        &access,
        json!({"tool": "workspace_list", "access": "read"}),
    )
    .await?;
    assert_eq!(single.json()["runtimeId"], laptop.as_str());
    let disabled = create_call(
        &app,
        &access,
        json!({"runtime": server, "tool": "workspace_list", "access": "read"}),
    )
    .await?;
    assert_eq!(disabled.status, StatusCode::CONFLICT);
    assert_eq!(disabled.error_code(), "runtime_mcp_disabled");

    let reported = send(
        &app,
        Method::PUT,
        "/v1/runtime/capabilities",
        Some(laptop_token),
        Some("application/json"),
        serde_json::to_vec(&json!({"mcpAccess": "off", "mobileAccess": false}))?,
    )
    .await?;
    assert_eq!(
        reported.status,
        StatusCode::NO_CONTENT,
        "{}",
        reported.text()
    );
    let listed = get(&app, "/v1/mcp/runtimes", Some(&access)).await?.json();
    assert_eq!(listed["runtimes"][0]["mcpAccess"], "off");
    assert_eq!(listed["runtimes"][0]["online"], false);
    let from_client = send(
        &app,
        Method::PUT,
        "/v1/runtime/capabilities",
        Some(&access),
        Some("application/json"),
        serde_json::to_vec(&json!({"mcpAccess": "full", "mobileAccess": true}))?,
    )
    .await?;
    assert_eq!(from_client.status, StatusCode::UNAUTHORIZED);
    report_runtime(&app, laptop_token, &laptop, "full", true).await?;

    let grants = get(&app, "/v1/mcp/grants", Some(laptop_token))
        .await?
        .json();
    let grant = grants["grants"][0].clone();
    assert_eq!(grant["clientName"], "Gateway Client");
    assert_eq!(grant["redirectHost"], "client.example");
    assert_eq!(grant["scopes"], json!(["mcp:read", "mcp:execute"]));
    assert_eq!(grant["allRuntimes"], false);
    assert!(grant["lastUsedAt"].is_string());
    let mut expected_ids = vec![laptop.clone(), server.clone()];
    expected_ids.sort();
    assert_eq!(grant["runtimeIds"], json!(expected_ids));
    let grant_id = grant["id"].as_str().unwrap_or_default();
    let revoke = send(
        &app,
        Method::DELETE,
        &format!("/v1/mcp/grants/{grant_id}"),
        Some(server_token),
        None,
        Vec::new(),
    )
    .await?;
    assert_eq!(revoke.status, StatusCode::NO_CONTENT);
    let after = get(&app, "/v1/mcp/runtimes", Some(&access)).await?;
    assert_eq!(after.status, StatusCode::UNAUTHORIZED);
    let missing = send(
        &app,
        Method::DELETE,
        &format!("/v1/mcp/grants/{}", Uuid::now_v7()),
        Some(server_token),
        None,
        Vec::new(),
    )
    .await?;
    assert_eq!(missing.status, StatusCode::NOT_FOUND);

    let device_id = format!("phone-{}", Uuid::now_v7());
    let enrollment = call(
        &app,
        TestRequest {
            method: Method::POST,
            uri: "/v1/mobile/enrollments",
            bearer: Some(laptop_token),
            body: json!({"runtimeId": laptop, "deviceId": device_id, "deviceName": "Phone"}),
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
    let mobile_token = mobile["accessToken"].as_str().unwrap_or_default();
    let visible = get(&app, "/v1/mobile/runtimes", Some(mobile_token))
        .await?
        .json();
    assert!(visible.to_string().contains(&laptop));
    report_runtime(&app, laptop_token, &laptop, "full", false).await?;
    let hidden = get(&app, "/v1/mobile/runtimes", Some(mobile_token))
        .await?
        .json();
    assert!(!hidden.to_string().contains(&laptop));
    let reserved = post_json(
        &app,
        "/v1/mobile/enrollments",
        Some(laptop_token),
        json!({"runtimeId": laptop, "deviceId": "~mcp", "deviceName": "Phone"}),
    )
    .await?;
    assert_eq!(reserved.error_code(), "reserved_client_id");

    delete_account(&pool, laptop_session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}
