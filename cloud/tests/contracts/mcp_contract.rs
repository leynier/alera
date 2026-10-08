use super::mcp_http::*;
use super::*;

use alera_cloud::mcp_oauth::cimd::ClientMetadataFetcher;

const CIMD_CLIENT: &str = "https://cimd.example/client.json";

struct FakeMetadataFetcher;

#[async_trait]
impl ClientMetadataFetcher for FakeMetadataFetcher {
    async fn fetch(&self, url: &Url) -> anyhow::Result<Vec<u8>> {
        let body = match url.as_str() {
            CIMD_CLIENT => json!({
                "client_id": CIMD_CLIENT,
                "client_name": "Metadata Client",
                "redirect_uris": [REDIRECT_URI],
                "token_endpoint_auth_method": "none",
            }),
            _ => {
                json!({"client_id": "https://other.example/x.json", "redirect_uris": [REDIRECT_URI]})
            }
        };
        Ok(serde_json::to_vec(&body)?)
    }
}

async fn mcp_app(pool: &sqlx::PgPool, url: &str) -> anyhow::Result<Router> {
    let state = test_state(
        pool.clone(),
        url.to_owned(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        Arc::new(AtomicUsize::new(0)),
    )?
    .with_client_metadata(Arc::new(FakeMetadataFetcher));
    Ok(router(state))
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_oauth_authorization_code_refresh_and_revocation() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(6)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let app = mcp_app(&pool, &url).await?;
    let runtime_id = format!("runtime-{}", Uuid::now_v7());
    let session = sign_in(&app, "google", &runtime_id).await?;
    let runtime_token = session["accessToken"].as_str().unwrap_or_default();

    let metadata = get(&app, "/.well-known/oauth-authorization-server", None).await?;
    assert_eq!(metadata.header("access-control-allow-origin"), "*");
    let metadata = metadata.json();
    assert_eq!(metadata["issuer"], "https://api.example.test");
    assert_eq!(metadata["client_id_metadata_document_supported"], true);
    assert_eq!(
        metadata["authorization_response_iss_parameter_supported"],
        true
    );
    assert_eq!(
        metadata["code_challenge_methods_supported"],
        json!(["S256"])
    );
    for path in [
        "/.well-known/oauth-protected-resource",
        "/.well-known/oauth-protected-resource/v1/mcp",
    ] {
        let resource = get(&app, path, None).await?.json();
        assert_eq!(resource["resource"], RESOURCE);
        assert_eq!(
            resource["authorization_servers"],
            json!(["https://api.example.test"])
        );
    }

    let rejected = post_json(
        &app,
        "/oauth/register",
        None,
        json!({"redirect_uris": ["http://evil.example/cb"]}),
    )
    .await?;
    assert_eq!(rejected.status, StatusCode::BAD_REQUEST);
    assert_eq!(rejected.error_code(), "invalid_redirect_uri");
    let client_id = register_client(&app, "Test <Client>").await?;

    let unknown = get(&app, &authorize_uri("mcp_missing", "mcp:read"), None).await?;
    assert_eq!(unknown.status, StatusCode::BAD_REQUEST);
    assert!(unknown.header("location").is_empty());
    let wrong_redirect = get(
        &app,
        &authorize_uri(&client_id, "mcp:read").replace("client.example", "attacker.example"),
        None,
    )
    .await?;
    assert_eq!(wrong_redirect.status, StatusCode::BAD_REQUEST);
    assert!(wrong_redirect.header("location").is_empty());
    let bad_resource = get(
        &app,
        &authorize_uri(&client_id, "mcp:read").replace("%2Fv1%2Fmcp", "%2Fother"),
        None,
    )
    .await?;
    // Request errors render a page: redirecting them would turn any
    // self-registered URI into an open redirect.
    assert_eq!(bad_resource.status, StatusCode::BAD_REQUEST);
    assert!(bad_resource.header("location").is_empty());

    // A provider callback without a code (the person declined) renders a page:
    // the callback needs no provider authentication, so redirecting from it
    // would be an open redirect.
    let declined_sign_in = get(&app, &authorize_uri(&client_id, "mcp:read"), None).await?;
    let declined_request = between(&declined_sign_in.text(), "/oauth/login?request=", "&amp;")?;
    let declined_login = get(
        &app,
        &format!("/oauth/login?request={declined_request}&provider=google"),
        None,
    )
    .await?;
    let declined_state = query_value(&declined_login.location()?, "state").unwrap_or_default();
    let declined = get(
        &app,
        &format!("/oauth/callback?state={declined_state}&error=access_denied"),
        None,
    )
    .await?;
    assert_eq!(declined.status, StatusCode::BAD_REQUEST);
    assert!(declined.header("location").is_empty());

    let (consent, request, consent_token) =
        reach_consent(&app, &client_id, "mcp:read mcp:execute").await?;
    let page = consent.text();
    assert!(page.contains("Test &lt;Client&gt;"));
    assert!(page.contains(&runtime_id));
    assert!(page.contains("All runtimes, including ones added later"));
    assert!(consent
        .header("content-security-policy")
        .contains("form-action 'self' https://client.example;"));
    assert_eq!(consent.header("x-frame-options"), "DENY");
    let forged = post_form(
        &app,
        "/oauth/consent",
        &[
            ("request", request.as_str()),
            ("consent_token", "act_forged-token-value"),
            ("action", "approve"),
            ("all_runtimes", "1"),
        ],
    )
    .await?;
    assert_eq!(forged.status, StatusCode::BAD_REQUEST);
    let empty = post_form(
        &app,
        "/oauth/consent",
        &[
            ("request", request.as_str()),
            ("consent_token", consent_token.as_str()),
            ("action", "approve"),
        ],
    )
    .await?;
    assert_eq!(empty.status, StatusCode::OK);
    assert!(empty.text().contains("Choose at least one runtime"));
    let approved = post_form(
        &app,
        "/oauth/consent",
        &[
            ("request", request.as_str()),
            ("consent_token", consent_token.as_str()),
            ("runtime", runtime_id.as_str()),
            ("action", "approve"),
        ],
    )
    .await?;
    assert_eq!(approved.status, StatusCode::SEE_OTHER);
    let location = approved.location()?;
    assert!(location.as_str().starts_with(REDIRECT_URI));
    assert_eq!(
        query_value(&location, "state").as_deref(),
        Some("client-state")
    );
    assert_eq!(
        query_value(&location, "iss").as_deref(),
        Some("https://api.example.test")
    );
    let code = query_value(&location, "code").unwrap_or_default();

    let wrong_verifier = post_form(
        &app,
        "/oauth/token",
        &[
            ("grant_type", "authorization_code"),
            ("code", "amc_not-a-real-code"),
            ("code_verifier", VERIFIER),
            ("client_id", client_id.as_str()),
        ],
    )
    .await?;
    assert_eq!(wrong_verifier.status, StatusCode::BAD_REQUEST);
    assert_eq!(wrong_verifier.json()["error"], "invalid_grant");
    let tokens = exchange_code(&app, &client_id, &code).await?;
    assert_eq!(tokens.status, StatusCode::OK, "{}", tokens.text());
    assert_eq!(tokens.header("cache-control"), "no-store");
    assert_eq!(tokens.header("access-control-allow-origin"), "*");
    let tokens = tokens.json();
    assert_eq!(tokens["token_type"], "Bearer");
    assert_eq!(tokens["scope"], "mcp:read");
    let access = tokens["access_token"].as_str().unwrap_or_default();
    let claims = jwt_claims(access)?;
    assert_eq!(claims["aud"], RESOURCE);
    assert_eq!(claims["client_kind"], "mcp");
    assert_eq!(claims["client_id"], client_id.as_str());
    assert!(claims["gid"].is_string());

    let account = get(&app, "/v1/account", Some(access)).await?;
    assert_eq!(account.status, StatusCode::UNAUTHORIZED);
    let runtimes = get(&app, "/v1/mcp/runtimes", Some(access)).await?;
    assert_eq!(runtimes.status, StatusCode::OK, "{}", runtimes.text());
    assert!(get(&app, "/v1/mcp/runtimes", Some(runtime_token))
        .await?
        .status
        .is_client_error());

    let refresh = tokens["refresh_token"].as_str().unwrap_or_default();
    // A signing failure during refresh must not spend the refresh token.
    let failing = router(test_state_with_signer(
        pool.clone(),
        url.clone(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        Arc::new(AtomicUsize::new(0)),
        Arc::new(super::device_contract::FailingSigner),
    )?);
    let unsigned = post_form(
        &failing,
        "/oauth/token",
        &[
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh),
            ("client_id", client_id.as_str()),
        ],
    )
    .await?;
    assert_eq!(unsigned.status, StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(unsigned.json()["error"], "server_error");
    let refreshed = post_form(
        &app,
        "/oauth/token",
        &[
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh),
            ("client_id", client_id.as_str()),
        ],
    )
    .await?;
    assert_eq!(refreshed.status, StatusCode::OK, "{}", refreshed.text());
    let native_refresh = post_json(
        &app,
        "/v1/auth/refresh",
        None,
        json!({"refreshToken": refreshed.json()["refresh_token"]}),
    )
    .await?;
    assert_eq!(native_refresh.status, StatusCode::UNAUTHORIZED);
    let reused = post_form(
        &app,
        "/oauth/token",
        &[("grant_type", "refresh_token"), ("refresh_token", refresh)],
    )
    .await?;
    assert_eq!(reused.json()["error"], "invalid_grant");

    let replayed = exchange_code(&app, &client_id, &code).await?;
    assert_eq!(replayed.json()["error"], "invalid_grant");
    let after_replay = get(&app, "/v1/mcp/runtimes", Some(access)).await?;
    assert_eq!(after_replay.status, StatusCode::UNAUTHORIZED);

    let (fresh_access, fresh_refresh, _) = authorize_runtimes(&app, &client_id, &[], true).await?;
    let revoked = post_form(&app, "/oauth/revoke", &[("token", fresh_refresh.as_str())]).await?;
    assert_eq!(revoked.status, StatusCode::OK);
    let unknown_revoke = post_form(&app, "/oauth/revoke", &[("token", "garbage")]).await?;
    assert_eq!(unknown_revoke.status, StatusCode::OK);
    let after_revoke = get(&app, "/v1/mcp/runtimes", Some(&fresh_access)).await?;
    assert_eq!(after_revoke.status, StatusCode::UNAUTHORIZED);

    let (_, request, consent_token) = reach_consent(&app, &client_id, "mcp:read").await?;
    let denied = post_form(
        &app,
        "/oauth/consent",
        &[
            ("request", request.as_str()),
            ("consent_token", consent_token.as_str()),
            ("action", "deny"),
        ],
    )
    .await?;
    let location = denied.location()?;
    assert_eq!(
        query_value(&location, "error").as_deref(),
        Some("access_denied")
    );
    assert_eq!(
        query_value(&location, "state").as_deref(),
        Some("client-state")
    );

    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_client_metadata_documents_authorize() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let app = mcp_app(&pool, &url).await?;
    let page = get(&app, &authorize_uri(CIMD_CLIENT, "mcp:read"), None).await?;
    assert_eq!(page.status, StatusCode::OK, "{}", page.text());
    assert!(page.text().contains("Metadata Client"));
    let mismatched = get(
        &app,
        &authorize_uri("https://cimd.example/mismatch.json", "mcp:read"),
        None,
    )
    .await?;
    assert_eq!(mismatched.status, StatusCode::BAD_REQUEST);
    assert!(mismatched.text().contains("different client_id"));
    sqlx::query("DELETE FROM mcp_clients WHERE id = $1")
        .bind(CIMD_CLIENT)
        .execute(&pool)
        .await?;
    alera_cloud::maintenance::run_once(&pool).await?;
    pool.close().await;
    Ok(())
}

pub async fn delete_account(pool: &sqlx::PgPool, account_id: Option<&str>) -> anyhow::Result<()> {
    let account_id = Uuid::parse_str(account_id.unwrap_or_default())?;
    sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(account_id)
        .execute(pool)
        .await?;
    Ok(())
}
