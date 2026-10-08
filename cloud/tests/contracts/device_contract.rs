use alera_cloud::signing::{JsonWebKey, TokenSigner};

use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::*;

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn device_authorization_signs_in_a_headless_runtime() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
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
    let reserved = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": "~mcp", "clientKind": "runtime", "deviceName": "Box"}),
    )
    .await?;
    assert_eq!(reserved.error_code(), "reserved_client_id");

    let runtime_id = format!("runtime-{}", Uuid::now_v7());
    let started = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": runtime_id, "clientKind": "runtime", "deviceName": "Build <Box>"}),
    )
    .await?;
    assert_eq!(started.status, StatusCode::OK, "{}", started.text());
    let started = started.json();
    let user_code = started["userCode"].as_str().unwrap_or_default().to_owned();
    let device_code = started["deviceCode"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    assert_eq!(user_code.len(), 9);
    assert_eq!(user_code.as_bytes()[4], b'-');
    assert_eq!(
        started["verificationUri"],
        "https://api.example.test/device"
    );
    assert_eq!(
        started["verificationUriComplete"],
        format!("https://api.example.test/device?user_code={user_code}")
    );
    assert_eq!(started["expiresIn"], 600);
    assert_eq!(started["interval"], 5);

    let poll = || {
        post_json(
            &app,
            "/v1/auth/device/token",
            None,
            json!({"deviceCode": device_code}),
        )
    };
    assert_eq!(poll().await?.error_code(), "authorization_pending");
    assert_eq!(poll().await?.error_code(), "slow_down");

    let entry = get(&app, "/device", None).await?;
    assert_eq!(entry.status, StatusCode::OK);
    assert!(entry.text().contains("name=\"user_code\""));
    let typed = user_code.replace('-', "").to_lowercase();
    let page = get(&app, &format!("/device?user_code={typed}"), None).await?;
    assert_eq!(page.status, StatusCode::OK, "{}", page.text());
    assert!(page.text().contains("Build &lt;Box&gt;"));
    let device = between(&page.text(), "/oauth/login?device=", "&amp;")?;
    let login = get(
        &app,
        &format!("/oauth/login?device={device}&provider=github"),
        None,
    )
    .await?;
    let state = query_value(&login.location()?, "state").unwrap_or_default();
    let confirm = get(
        &app,
        &format!("/oauth/callback?state={state}&code=provider-code-for-device"),
        None,
    )
    .await?;
    assert_eq!(confirm.status, StatusCode::OK, "{}", confirm.text());
    assert!(confirm.text().contains(&user_code));
    let consent_token = between(&confirm.text(), "name=\"consent_token\" value=\"", "\"")?;
    let replayed_state = get(
        &app,
        &format!("/oauth/callback?state={state}&code=provider-code-for-device"),
        None,
    )
    .await?;
    assert_eq!(replayed_state.status, StatusCode::BAD_REQUEST);
    // The runtime keeps polling while the confirmation page is open.
    assert_eq!(poll().await?.error_code(), "slow_down");
    let approved = post_form(
        &app,
        "/oauth/consent",
        &[
            ("device", device.as_str()),
            ("consent_token", consent_token.as_str()),
            ("action", "approve"),
        ],
    )
    .await?;
    assert_eq!(approved.status, StatusCode::OK, "{}", approved.text());
    assert!(approved.text().contains("Runtime connected"));

    let tokens = poll().await?;
    assert_eq!(tokens.status, StatusCode::OK, "{}", tokens.text());
    let tokens = tokens.json();
    assert_eq!(tokens["client"]["kind"], "runtime");
    assert_eq!(tokens["client"]["id"], runtime_id.as_str());
    assert!(tokens["refreshToken"].as_str().is_some());
    assert_eq!(poll().await?.error_code(), "expired_token");
    let account = get(&app, "/v1/account", tokens["accessToken"].as_str())
        .await?
        .json();
    assert_eq!(account["runtimes"][0]["name"], "Build <Box>");
    let again = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": runtime_id, "clientKind": "runtime", "deviceName": "Hijack"}),
    )
    .await?;
    assert_eq!(again.status, StatusCode::CONFLICT);
    assert_eq!(again.error_code(), "runtime_already_signed_in");
    // A session idle past its inactivity window no longer blocks a new sign-in.
    sqlx::query(
        r#"
        UPDATE refresh_tokens t SET inactivity_expires_at = NOW() - INTERVAL '1 minute'
        FROM refresh_token_families f
        WHERE t.family_id = f.id AND f.client_kind = 'runtime' AND f.client_id = $1
        "#,
    )
    .bind(&runtime_id)
    .execute(&pool)
    .await?;
    let idle = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": runtime_id, "clientKind": "runtime", "deviceName": "Build Box"}),
    )
    .await?;
    assert_eq!(idle.status, StatusCode::OK, "{}", idle.text());

    let denied = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": format!("runtime-{}", Uuid::now_v7()), "clientKind": "runtime", "deviceName": "Other"}),
    )
    .await?
    .json();
    let denied_code = denied["deviceCode"].as_str().unwrap_or_default().to_owned();
    let page = get(
        &app,
        &format!(
            "/device?user_code={}",
            denied["userCode"].as_str().unwrap_or_default()
        ),
        None,
    )
    .await?;
    let device = between(&page.text(), "/oauth/login?device=", "&amp;")?;
    let posted = post_form(
        &app,
        "/device",
        &[("user_code", denied["userCode"].as_str().unwrap_or_default())],
    )
    .await?;
    assert_eq!(posted.status, StatusCode::OK, "{}", posted.text());
    assert!(posted
        .text()
        .contains(&format!("/oauth/login?device={device}")));
    let login = get(
        &app,
        &format!("/oauth/login?device={device}&provider=google"),
        None,
    )
    .await?;
    let state = query_value(&login.location()?, "state").unwrap_or_default();
    let confirm = get(&app, &format!("/oauth/callback?state={state}&code=c"), None).await?;
    let consent_token = between(&confirm.text(), "name=\"consent_token\" value=\"", "\"")?;
    post_form(
        &app,
        "/oauth/consent",
        &[
            ("device", device.as_str()),
            ("consent_token", consent_token.as_str()),
            ("action", "deny"),
        ],
    )
    .await?;
    let refused = post_json(
        &app,
        "/v1/auth/device/token",
        None,
        json!({"deviceCode": denied_code}),
    )
    .await?;
    assert_eq!(refused.status, StatusCode::BAD_REQUEST);
    assert_eq!(refused.error_code(), "access_denied");

    let late = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": format!("runtime-{}", Uuid::now_v7()), "clientKind": "runtime", "deviceName": "Late"}),
    )
    .await?
    .json();
    let late_code = late["deviceCode"].as_str().unwrap_or_default().to_owned();
    sqlx::query(
        r#"
        UPDATE device_authorizations
        SET status = 'approved', account_id = $2, approved_at = NOW(),
            expires_at = NOW() - INTERVAL '1 minute'
        WHERE user_code = $1
        "#,
    )
    .bind(
        late["userCode"]
            .as_str()
            .unwrap_or_default()
            .replace('-', ""),
    )
    .bind(Uuid::parse_str(
        tokens["account"]["id"].as_str().unwrap_or_default(),
    )?)
    .execute(&pool)
    .await?;
    let expired = post_json(
        &app,
        "/v1/auth/device/token",
        None,
        json!({"deviceCode": late_code}),
    )
    .await?;
    assert_eq!(expired.error_code(), "expired_token");

    // Two approved codes for one signed-out runtime: only the first redeems.
    let twin_id = format!("runtime-{}", Uuid::now_v7());
    let mut twin_codes = Vec::new();
    for _ in 0..2 {
        let started = post_json(
            &app,
            "/v1/auth/device",
            None,
            json!({"clientId": twin_id, "clientKind": "runtime", "deviceName": "Twin"}),
        )
        .await?
        .json();
        twin_codes.push(
            started["deviceCode"]
                .as_str()
                .unwrap_or_default()
                .to_owned(),
        );
    }
    sqlx::query(
        "UPDATE device_authorizations SET status = 'approved', account_id = $2, approved_at = NOW() WHERE client_id = $1",
    )
    .bind(&twin_id)
    .bind(Uuid::parse_str(tokens["account"]["id"].as_str().unwrap_or_default())?)
    .execute(&pool)
    .await?;
    let first = post_json(
        &app,
        "/v1/auth/device/token",
        None,
        json!({"deviceCode": twin_codes[0]}),
    )
    .await?;
    assert_eq!(first.status, StatusCode::OK, "{}", first.text());
    let second = post_json(
        &app,
        "/v1/auth/device/token",
        None,
        json!({"deviceCode": twin_codes[1]}),
    )
    .await?;
    assert_eq!(second.status, StatusCode::CONFLICT);
    assert_eq!(second.error_code(), "runtime_already_signed_in");

    // A redemption whose token signing fails leaves no session behind, so the
    // runtime can start another device sign-in.
    let failing = router(test_state_with_signer(
        pool.clone(),
        url.clone(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        Arc::new(AtomicUsize::new(0)),
        Arc::new(FailingSigner),
    )?);
    let orphan_id = format!("runtime-{}", Uuid::now_v7());
    let orphan = post_json(
        &failing,
        "/v1/auth/device",
        None,
        json!({"clientId": orphan_id, "clientKind": "runtime", "deviceName": "Orphan"}),
    )
    .await?
    .json();
    sqlx::query(
        "UPDATE device_authorizations SET status = 'approved', account_id = $2, approved_at = NOW() WHERE client_id = $1",
    )
    .bind(&orphan_id)
    .bind(Uuid::parse_str(tokens["account"]["id"].as_str().unwrap_or_default())?)
    .execute(&pool)
    .await?;
    let redeemed = post_json(
        &failing,
        "/v1/auth/device/token",
        None,
        json!({"deviceCode": orphan["deviceCode"]}),
    )
    .await?;
    assert_eq!(redeemed.status, StatusCode::INTERNAL_SERVER_ERROR);
    let retried = post_json(
        &app,
        "/v1/auth/device",
        None,
        json!({"clientId": orphan_id, "clientKind": "runtime", "deviceName": "Orphan"}),
    )
    .await?;
    assert_eq!(retried.status, StatusCode::OK, "{}", retried.text());

    delete_account(&pool, tokens["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}

struct FailingSigner;

#[async_trait]
impl TokenSigner for FailingSigner {
    fn key_id(&self) -> &str {
        "failing"
    }

    fn public_keys(&self) -> Vec<JsonWebKey> {
        Vec::new()
    }

    async fn sign(&self, _message: &[u8]) -> anyhow::Result<Vec<u8>> {
        anyhow::bail!("signing is unavailable")
    }
}
