use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::*;

const ADMIN_SCOPES: &str = "mcp:read mcp:execute mcp:admin";

/// Runs consent for `scope` with the extra form fields and returns the reply.
async fn consent(
    app: &Router,
    client_id: &str,
    scope: &str,
    runtime_id: &str,
    extra: &[(&str, &str)],
) -> anyhow::Result<(Reply, Reply)> {
    let (page, request, token) = reach_consent(app, client_id, scope).await?;
    let mut fields = vec![
        ("request", request.as_str()),
        ("consent_token", token.as_str()),
        ("runtime", runtime_id),
        ("action", "approve"),
    ];
    fields.extend_from_slice(extra);
    let reply = post_form(app, "/oauth/consent", &fields).await?;
    Ok((page, reply))
}

/// Exchanges an approved consent redirect for its token response.
async fn tokens(app: &Router, client_id: &str, approved: &Reply) -> anyhow::Result<Value> {
    anyhow::ensure!(
        approved.status == StatusCode::SEE_OTHER,
        "{}",
        approved.text()
    );
    let code = query_value(&approved.location()?, "code").unwrap_or_default();
    let reply = exchange_code(app, client_id, &code).await?;
    anyhow::ensure!(reply.status == StatusCode::OK, "{}", reply.text());
    Ok(reply.json())
}

async fn admin_call(app: &Router, access: &str, runtime: &str) -> anyhow::Result<Reply> {
    post_json(
        app,
        "/v1/mcp/calls",
        Some(access),
        json!({"runtime": runtime, "tool": "update_runtime_settings", "access": "admin"}),
    )
    .await
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_admin_scope_needs_explicit_consent_and_an_admin_runtime() -> anyhow::Result<()> {
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
    let runtime = format!("runtime-{}", Uuid::now_v7());
    let session = sign_in(&app, "google", &runtime).await?;
    let runtime_token = session["accessToken"].as_str().unwrap_or_default();

    for path in [
        "/.well-known/oauth-authorization-server",
        "/.well-known/oauth-protected-resource/v1/mcp",
    ] {
        let metadata = get(&app, path, None).await?.json();
        assert_eq!(
            metadata["scopes_supported"],
            json!(ADMIN_SCOPES.split(' ').collect::<Vec<_>>())
        );
    }
    let registered = post_json(
        &app,
        "/oauth/register",
        None,
        json!({"redirect_uris": [REDIRECT_URI], "client_name": "Admin Client"}),
    )
    .await?;
    assert_eq!(
        registered.status,
        StatusCode::CREATED,
        "{}",
        registered.text()
    );
    assert_eq!(registered.json()["scope"], ADMIN_SCOPES);
    let client_id = registered.json()["client_id"]
        .as_str()
        .unwrap_or_default()
        .to_owned();

    let claims = report_runtime(&app, runtime_token, &runtime, "admin", true).await?;
    assert_eq!(claims["mcpAccess"], "admin");
    let reported = send(
        &app,
        Method::PUT,
        "/v1/runtime/capabilities",
        Some(runtime_token),
        Some("application/json"),
        serde_json::to_vec(&json!({"mcpAccess": "admin", "mobileAccess": true}))?,
    )
    .await?;
    assert_eq!(
        reported.status,
        StatusCode::NO_CONTENT,
        "{}",
        reported.text()
    );

    // The default request never offers administrative tools.
    let (page, _, _) = reach_consent(&app, &client_id, "mcp:read mcp:execute").await?;
    assert!(page.text().contains("MCP admin access"));
    assert!(!page.text().contains("name=\"admin\""));
    let (access, _, _) = authorize_runtimes(&app, &client_id, &[runtime.as_str()], false).await?;
    let refused = admin_call(&app, &access, &runtime).await?;
    assert_eq!(refused.status, StatusCode::FORBIDDEN);
    assert_eq!(refused.error_code(), "insufficient_scope");
    assert!(refused.json()["error"]["message"]
        .as_str()
        .unwrap_or_default()
        .contains("allow administrative tools"));

    // Requested but left unticked: the grant stays at read and execute.
    let (page, approved) = consent(
        &app,
        &client_id,
        ADMIN_SCOPES,
        &runtime,
        &[("execute", "1")],
    )
    .await?;
    assert!(page.text().contains(
        "<input type=\"checkbox\" name=\"admin\" value=\"1\"><span>Allow administrative tools"
    ));
    assert_eq!(
        tokens(&app, &client_id, &approved).await?["scope"],
        "mcp:read mcp:execute"
    );

    // Administrative tools without execute is refused on the page.
    let (_, inconsistent) =
        consent(&app, &client_id, ADMIN_SCOPES, &runtime, &[("admin", "1")]).await?;
    assert_eq!(inconsistent.status, StatusCode::OK);
    assert!(inconsistent
        .text()
        .contains("Administrative tools also need permission"));

    let (_, approved) = consent(
        &app,
        &client_id,
        ADMIN_SCOPES,
        &runtime,
        &[("execute", "1"), ("admin", "1")],
    )
    .await?;
    let granted = tokens(&app, &client_id, &approved).await?;
    assert_eq!(granted["scope"], ADMIN_SCOPES);
    let admin_access = granted["access_token"].as_str().unwrap_or_default();
    let created = admin_call(&app, admin_access, &runtime).await?;
    assert_eq!(created.status, StatusCode::OK, "{}", created.text());
    let call_id = created.json()["callId"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    let grant_claims = jwt_claims(created.json()["grant"].as_str().unwrap_or_default())?;
    assert_eq!(grant_claims["access"], "admin");
    let audit = sqlx::query_scalar::<_, String>("SELECT access FROM mcp_calls WHERE id = $1")
        .bind(Uuid::parse_str(&call_id)?)
        .fetch_one(&pool)
        .await?;
    assert_eq!(audit, "admin");
    let grants = get(&app, "/v1/mcp/grants", Some(runtime_token))
        .await?
        .json();
    assert!(grants["grants"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .iter()
        .any(|grant| grant["scopes"] == json!(["mcp:read", "mcp:execute", "mcp:admin"])));

    report_runtime(&app, runtime_token, &runtime, "full", true).await?;
    let not_admin = admin_call(&app, admin_access, &runtime).await?;
    assert_eq!(not_admin.status, StatusCode::FORBIDDEN);
    assert_eq!(not_admin.error_code(), "runtime_not_admin");
    let execute = post_json(
        &app,
        "/v1/mcp/calls",
        Some(admin_access),
        json!({"runtime": runtime, "tool": "terminal_send", "access": "execute"}),
    )
    .await?;
    assert_eq!(execute.status, StatusCode::OK, "{}", execute.text());

    delete_account(&pool, session["account"]["id"].as_str()).await?;
    pool.close().await;
    Ok(())
}
