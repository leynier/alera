use super::mcp_contract::delete_account;
use super::mcp_http::*;
use super::*;

use alera_cloud::mcp_oauth::{
    cimd::ClientMetadataFetcher, client_assertion::JWT_BEARER_ASSERTION_TYPE,
};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use rsa::{pkcs1::EncodeRsaPrivateKey, rand_core::OsRng, traits::PublicKeyParts, RsaPrivateKey};

const PRIVATE_KEY_JWT_CLIENT: &str = "https://pkjwt.example/oauth/client.json";
const PRIVATE_KEY_JWT_JWKS: &str = "https://pkjwt.example/oauth/jwks.json";
const FALLBACK_CLIENT: &str = "https://fallback.example/oauth/client.json";
const TOKEN_ENDPOINT: &str = "https://api.example.test/oauth/token";

struct ClientAuthFetcher {
    jwks: Value,
}

#[async_trait]
impl ClientMetadataFetcher for ClientAuthFetcher {
    async fn fetch(&self, url: &Url) -> anyhow::Result<Vec<u8>> {
        let body = match url.as_str() {
            PRIVATE_KEY_JWT_CLIENT => json!({
                "client_id": PRIVATE_KEY_JWT_CLIENT,
                "client_name": "Confidential Client",
                "redirect_uris": [REDIRECT_URI],
                "token_endpoint_auth_method": "private_key_jwt",
                "token_endpoint_auth_methods_supported": ["none", "private_key_jwt"],
                "token_endpoint_auth_signing_alg": "RS256",
                "jwks_uri": PRIVATE_KEY_JWT_JWKS,
            }),
            PRIVATE_KEY_JWT_JWKS => self.jwks.clone(),
            FALLBACK_CLIENT => json!({
                "client_id": FALLBACK_CLIENT,
                "client_name": "Fallback Client",
                "redirect_uris": [REDIRECT_URI],
                "token_endpoint_auth_method": "client_secret_basic",
                "token_endpoint_auth_methods_supported": ["client_secret_basic", "none"],
            }),
            other => anyhow::bail!("unexpected metadata fetch {other}"),
        };
        Ok(serde_json::to_vec(&body)?)
    }
}

fn client_key() -> anyhow::Result<(EncodingKey, Value)> {
    let private = RsaPrivateKey::new(&mut OsRng, 2048)?;
    let der = private.to_pkcs1_der()?;
    let jwks = json!({"keys": [{
        "kty": "RSA",
        "kid": "client-key",
        "use": "sig",
        "alg": "RS256",
        "n": URL_SAFE_NO_PAD.encode(private.n().to_bytes_be()),
        "e": URL_SAFE_NO_PAD.encode(private.e().to_bytes_be()),
    }]});
    Ok((EncodingKey::from_rsa_der(der.as_bytes()), jwks))
}

fn assertion(key: &EncodingKey, client_id: &str) -> anyhow::Result<String> {
    let now = chrono::Utc::now().timestamp();
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("client-key".to_owned());
    Ok(encode(
        &header,
        &json!({
            "iss": client_id,
            "sub": client_id,
            "aud": TOKEN_ENDPOINT,
            "iat": now,
            "exp": now + 60,
            "jti": Uuid::new_v4().to_string(),
        }),
        key,
    )?)
}

/// Approves a consent for every runtime and returns the authorization code.
async fn approved_code(app: &Router, client_id: &str) -> anyhow::Result<String> {
    let (_, request, token) = reach_consent(app, client_id, "mcp:read").await?;
    let approved = post_form(
        app,
        "/oauth/consent",
        &[
            ("request", request.as_str()),
            ("consent_token", token.as_str()),
            ("all_runtimes", "1"),
            ("action", "approve"),
        ],
    )
    .await?;
    anyhow::ensure!(
        approved.status == StatusCode::SEE_OTHER,
        "{}",
        approved.text()
    );
    Ok(query_value(&approved.location()?, "code").unwrap_or_default())
}

fn code_fields<'a>(code: &'a str, extra: &[(&'a str, &'a str)]) -> Vec<(&'a str, &'a str)> {
    let mut fields = vec![
        ("grant_type", "authorization_code"),
        ("code", code),
        ("code_verifier", VERIFIER),
        ("redirect_uri", REDIRECT_URI),
    ];
    fields.extend_from_slice(extra);
    fields
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to an isolated PostgreSQL database"]
async fn mcp_token_endpoint_enforces_each_client_authentication_method() -> anyhow::Result<()> {
    let url = std::env::var("TEST_DATABASE_URL")?;
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&url)
        .await?;
    migrations::run(&pool).await?;
    let (key, jwks) = client_key()?;
    let state = test_state(
        pool.clone(),
        url.clone(),
        format!("{}@example.test", Uuid::now_v7()),
        true,
        Arc::new(AtomicUsize::new(0)),
    )?
    .with_client_metadata(Arc::new(ClientAuthFetcher { jwks }));
    let app = router(state);
    let runtime_id = format!("runtime-{}", Uuid::now_v7());
    let session = sign_in(&app, "google", &runtime_id).await?;

    let metadata = get(&app, "/.well-known/oauth-authorization-server", None)
        .await?
        .json();
    assert_eq!(
        metadata["token_endpoint_auth_methods_supported"],
        json!(["none", "private_key_jwt"])
    );
    assert_eq!(
        metadata["token_endpoint_auth_signing_alg_values_supported"],
        json!(["RS256", "PS256", "ES256"])
    );

    // A private_key_jwt client cannot redeem without an assertion, and the failed
    // attempt leaves the code redeemable.
    let code = approved_code(&app, PRIVATE_KEY_JWT_CLIENT).await?;
    // Another registered client cannot consume the code, nor revoke the grant by
    // presenting it twice.
    let public_client = register_client(&app, "Public Client").await?;
    for _ in 0..2 {
        let stolen = post_form(
            &app,
            "/oauth/token",
            &code_fields(&code, &[("client_id", public_client.as_str())]),
        )
        .await?;
        assert_eq!(stolen.status, StatusCode::BAD_REQUEST);
        assert!(
            stolen.text().contains("another client"),
            "{}",
            stolen.text()
        );
    }
    let unauthenticated = post_form(
        &app,
        "/oauth/token",
        &code_fields(&code, &[("client_id", PRIVATE_KEY_JWT_CLIENT)]),
    )
    .await?;
    assert_eq!(unauthenticated.status, StatusCode::UNAUTHORIZED);
    assert_eq!(unauthenticated.json()["error"], "invalid_client");
    let first = assertion(&key, PRIVATE_KEY_JWT_CLIENT)?;
    let tokens = post_form(
        &app,
        "/oauth/token",
        &code_fields(
            &code,
            &[
                ("client_assertion_type", JWT_BEARER_ASSERTION_TYPE),
                ("client_assertion", first.as_str()),
            ],
        ),
    )
    .await?;
    assert_eq!(tokens.status, StatusCode::OK, "{}", tokens.text());
    let claims = jwt_claims(tokens.json()["access_token"].as_str().unwrap_or_default())?;
    assert_eq!(claims["client_id"], PRIVATE_KEY_JWT_CLIENT);
    let refresh_token = tokens.json()["refresh_token"]
        .as_str()
        .unwrap_or_default()
        .to_owned();

    let refresh_fields = |assertion: Option<&str>| {
        let mut fields = vec![
            ("grant_type", "refresh_token".to_owned()),
            ("refresh_token", refresh_token.clone()),
        ];
        if let Some(assertion) = assertion {
            fields.push((
                "client_assertion_type",
                JWT_BEARER_ASSERTION_TYPE.to_owned(),
            ));
            fields.push(("client_assertion", assertion.to_owned()));
        }
        fields
    };
    let refresh = |fields: Vec<(&'static str, String)>| {
        let app = app.clone();
        async move {
            let fields: Vec<(&str, &str)> = fields
                .iter()
                .map(|(name, value)| (*name, value.as_str()))
                .collect();
            post_form(&app, "/oauth/token", &fields).await
        }
    };
    let without_assertion = refresh(refresh_fields(None)).await?;
    assert_eq!(without_assertion.status, StatusCode::UNAUTHORIZED);
    assert_eq!(without_assertion.json()["error"], "invalid_client");
    let replayed = refresh(refresh_fields(Some(&first))).await?;
    assert_eq!(replayed.status, StatusCode::UNAUTHORIZED);
    assert!(replayed.text().contains("already used"));
    let second = assertion(&key, PRIVATE_KEY_JWT_CLIENT)?;
    let refreshed = refresh(refresh_fields(Some(&second))).await?;
    assert_eq!(refreshed.status, StatusCode::OK, "{}", refreshed.text());

    // A client that declares an unsupported method but lists none is public: an
    // assertion is refused and PKCE alone redeems the code.
    let code = approved_code(&app, FALLBACK_CLIENT).await?;
    let fallback_assertion = assertion(&key, FALLBACK_CLIENT)?;
    let refused = post_form(
        &app,
        "/oauth/token",
        &code_fields(
            &code,
            &[
                ("client_id", FALLBACK_CLIENT),
                ("client_assertion_type", JWT_BEARER_ASSERTION_TYPE),
                ("client_assertion", fallback_assertion.as_str()),
            ],
        ),
    )
    .await?;
    assert_eq!(refused.status, StatusCode::UNAUTHORIZED);
    assert_eq!(refused.json()["error"], "invalid_client");
    let public = exchange_code(&app, FALLBACK_CLIENT, &code).await?;
    assert_eq!(public.status, StatusCode::OK, "{}", public.text());

    delete_account(&pool, session["account"]["id"].as_str()).await?;
    sqlx::query("DELETE FROM mcp_clients WHERE id = ANY($1)")
        .bind([PRIVATE_KEY_JWT_CLIENT, FALLBACK_CLIENT])
        .execute(&pool)
        .await?;
    sqlx::query("DELETE FROM mcp_client_assertions WHERE client_id = $1")
        .bind(PRIVATE_KEY_JWT_CLIENT)
        .execute(&pool)
        .await?;
    pool.close().await;
    Ok(())
}
