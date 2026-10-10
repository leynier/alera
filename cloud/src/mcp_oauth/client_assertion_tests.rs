use std::sync::OnceLock;

use async_trait::async_trait;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::Utc;
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use rsa::rand_core::OsRng;
use rsa::{pkcs1::EncodeRsaPrivateKey, traits::PublicKeyParts, RsaPrivateKey};
use serde_json::{json, Value};
use url::Url;

use super::{verify_assertion, AssertionPolicy, ClientCredentials};
use crate::mcp_oauth::{
    cimd::ClientMetadataFetcher, client_authentication::ClientAuthentication,
    client_jwks::ClientJwksCache, forms::FormFields,
};

const CLIENT: &str = "https://client.example/oauth/client.json";
const JWKS: &str = "https://client.example/oauth/jwks.json";
const ISSUER: &str = "https://api.example.test";
const TOKEN_ENDPOINT: &str = "https://api.example.test/oauth/token";

struct JwksFetcher(Value);

#[async_trait]
impl ClientMetadataFetcher for JwksFetcher {
    async fn fetch(&self, _url: &Url) -> anyhow::Result<Vec<u8>> {
        Ok(serde_json::to_vec(&self.0)?)
    }
}

struct Fixture {
    encoding: EncodingKey,
    fetcher: JwksFetcher,
    jwks: ClientJwksCache,
    authentication: ClientAuthentication,
}

/// RSA key generation is slow in debug builds, so every test shares one key.
fn test_key() -> &'static (EncodingKey, Value) {
    static KEY: OnceLock<(EncodingKey, Value)> = OnceLock::new();
    KEY.get_or_init(|| {
        let private = RsaPrivateKey::new(&mut OsRng, 2048)
            .unwrap_or_else(|error| panic!("generate ephemeral test RSA key: {error}"));
        let der = private
            .to_pkcs1_der()
            .unwrap_or_else(|error| panic!("encode ephemeral test RSA key: {error}"));
        let jwks = json!({"keys": [{
            "kty": "RSA",
            "kid": "client-key",
            "use": "sig",
            "alg": "RS256",
            "n": URL_SAFE_NO_PAD.encode(private.n().to_bytes_be()),
            "e": URL_SAFE_NO_PAD.encode(private.e().to_bytes_be()),
        }]});
        (EncodingKey::from_rsa_der(der.as_bytes()), jwks)
    })
}

fn fixture() -> Fixture {
    let (encoding, jwks) = test_key();
    Fixture {
        encoding: encoding.clone(),
        fetcher: JwksFetcher(jwks.clone()),
        jwks: ClientJwksCache::default(),
        authentication: ClientAuthentication::PrivateKeyJwt {
            jwks_uri: Url::parse(JWKS).unwrap_or_else(|error| panic!("parse JWKS URL: {error}")),
            signing_alg: Some(Algorithm::RS256),
        },
    }
}

fn claims() -> Value {
    let now = Utc::now().timestamp();
    json!({
        "iss": CLIENT,
        "sub": CLIENT,
        "aud": TOKEN_ENDPOINT,
        "iat": now,
        "exp": now + 60,
        "jti": uuid::Uuid::new_v4().to_string(),
    })
}

fn sign(fixture: &Fixture, claims: &Value, kid: Option<&str>) -> String {
    let mut header = Header::new(Algorithm::RS256);
    header.kid = kid.map(ToOwned::to_owned);
    encode(&header, claims, &fixture.encoding)
        .unwrap_or_else(|error| panic!("sign test assertion: {error}"))
}

async fn verify(fixture: &Fixture, assertion: &str) -> Result<String, &'static str> {
    verify_assertion(
        &fixture.jwks,
        &fixture.fetcher,
        assertion,
        &AssertionPolicy {
            client_id: CLIENT,
            authentication: &fixture.authentication,
            audiences: &[ISSUER, TOKEN_ENDPOINT],
            now: Utc::now(),
        },
    )
    .await
    .map(|verified| verified.jti)
}

fn with(claims: Value, name: &str, value: Value) -> Value {
    let mut claims = claims;
    claims[name] = value;
    claims
}

fn without(claims: Value, name: &str) -> Value {
    let mut claims = claims;
    if let Some(object) = claims.as_object_mut() {
        object.remove(name);
    }
    claims
}

#[tokio::test]
async fn accepts_a_signed_assertion_for_either_audience() {
    let fixture = fixture();
    let valid = claims();
    let jti = valid["jti"].as_str().unwrap_or_default().to_owned();
    assert_eq!(
        verify(&fixture, &sign(&fixture, &valid, Some("client-key"))).await,
        Ok(jti)
    );
    let issuer_audience = with(
        with(claims(), "aud", json!([ISSUER, "https://other.example"])),
        "nbf",
        json!(Utc::now().timestamp() - 10),
    );
    assert!(
        verify(&fixture, &sign(&fixture, &issuer_audience, None))
            .await
            .is_ok(),
        "a single published key may be used without a kid"
    );
}

#[tokio::test]
async fn rejects_assertions_with_wrong_claims() {
    let fixture = fixture();
    let now = Utc::now().timestamp();
    for (label, claims) in [
        (
            "issuer",
            with(claims(), "iss", json!("https://evil.example")),
        ),
        (
            "subject",
            with(claims(), "sub", json!("https://evil.example")),
        ),
        (
            "audience",
            with(claims(), "aud", json!("https://evil.example")),
        ),
        ("expired", with(claims(), "exp", json!(now - 120))),
        ("long-lived", with(claims(), "exp", json!(now + 3600))),
        ("future iat", with(claims(), "iat", json!(now + 600))),
        ("not yet valid", with(claims(), "nbf", json!(now + 180))),
        ("missing jti", without(claims(), "jti")),
        ("empty jti", with(claims(), "jti", json!(""))),
        ("missing exp", without(claims(), "exp")),
    ] {
        let assertion = sign(&fixture, &claims, Some("client-key"));
        assert!(verify(&fixture, &assertion).await.is_err(), "{label}");
    }
}

#[tokio::test]
async fn rejects_unknown_keys_and_unsupported_algorithms() {
    let fixture = fixture();
    let unknown_kid = sign(&fixture, &claims(), Some("other-key"));
    assert!(verify(&fixture, &unknown_kid).await.is_err());

    let hmac = encode(
        &Header::new(Algorithm::HS256),
        &claims(),
        &EncodingKey::from_secret(b"guessable"),
    )
    .unwrap_or_else(|error| panic!("sign HMAC assertion: {error}"));
    assert!(verify(&fixture, &hmac).await.is_err());

    let header = URL_SAFE_NO_PAD.encode(br#"{"alg":"none","typ":"JWT"}"#);
    let payload = URL_SAFE_NO_PAD.encode(claims().to_string());
    assert!(verify(&fixture, &format!("{header}.{payload}."))
        .await
        .is_err());

    let valid = sign(&fixture, &claims(), Some("client-key"));
    let mut parts: Vec<&str> = valid.split('.').collect();
    let forged_payload =
        URL_SAFE_NO_PAD.encode(with(claims(), "sub", json!("https://evil.example")).to_string());
    parts[1] = &forged_payload;
    assert!(verify(&fixture, &parts.join(".")).await.is_err());
}

#[tokio::test]
async fn public_clients_never_verify_assertions() {
    let mut fixture = fixture();
    fixture.authentication = ClientAuthentication::None;
    let assertion = sign(&fixture, &claims(), Some("client-key"));
    assert!(verify(&fixture, &assertion).await.is_err());
}

#[test]
fn credentials_require_type_and_assertion_together() {
    let form = FormFields::parse(b"client_assertion=abc");
    assert!(ClientCredentials::from_form(&form).is_err());
    let form = FormFields::parse(b"client_id=a&client_id=b");
    assert!(ClientCredentials::from_form(&form).is_err());
}

#[test]
fn client_id_comes_from_the_form_or_the_assertion_subject() {
    let fixture = fixture();
    let assertion = sign(&fixture, &claims(), Some("client-key"));
    let body = url::form_urlencoded::Serializer::new(String::new())
        .append_pair("client_assertion_type", super::JWT_BEARER_ASSERTION_TYPE)
        .append_pair("client_assertion", &assertion)
        .finish();
    let form = FormFields::parse(body.as_bytes());
    let Ok(credentials) = ClientCredentials::from_form(&form) else {
        panic!("credentials must parse");
    };
    assert_eq!(credentials.client_id(None).ok().as_deref(), Some(CLIENT));

    let conflicting = format!("{body}&client_id=https%3A%2F%2Fother.example%2Fc.json");
    let form = FormFields::parse(conflicting.as_bytes());
    let Ok(credentials) = ClientCredentials::from_form(&form) else {
        panic!("credentials must parse");
    };
    assert!(credentials.client_id(None).is_err());

    let form = FormFields::parse(b"grant_type=refresh_token");
    let Ok(credentials) = ClientCredentials::from_form(&form) else {
        panic!("credentials must parse");
    };
    assert_eq!(
        credentials.client_id(Some("fallback")).ok().as_deref(),
        Some("fallback")
    );
    assert!(credentials.client_id(None).is_err());
}
