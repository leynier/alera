use super::{chatgpt_inference as inference, chatgpt_oauth as oauth};
use serde_json::json;

#[test]
fn callback_binds_state_and_registration() {
    let callback =
        |query| url::Url::parse(&format!("http://127.0.0.1:4321/auth/callback?{query}")).unwrap();
    assert_eq!(
        oauth::validate_callback(&callback("state=s&code=c&client_id=oaiapp_a"), "s", None)
            .unwrap(),
        ("c".into(), "oaiapp_a".into())
    );
    assert_eq!(
        oauth::validate_callback(&callback("state=s&code=c"), "s", Some("oaiapp_a"))
            .unwrap()
            .1,
        "oaiapp_a"
    );
    for query in [
        "state=bad&code=c&client_id=oaiapp_a",
        "state=s&code=c",
        "state=s&code=c&client_id=dynamic_agent_client",
        "state=s&state=s&code=c",
        "state=s&error=access_denied&code=c",
    ] {
        assert!(
            oauth::validate_callback(&callback(query), "s", None).is_err(),
            "{query}"
        );
    }
    assert!(oauth::validate_callback(
        &callback("state=s&code=c&client_id=oaiapp_b"),
        "s",
        Some("oaiapp_a")
    )
    .is_err());
}

#[tokio::test]
async fn authorization_uses_loopback_pkce_and_stable_host() {
    use base64::Engine;
    use sha2::Digest;
    let (attempt, url) = oauth::Attempt::prepare("urn:uuid:host", None)
        .await
        .unwrap();
    let url = url::Url::parse(&url).unwrap();
    let params = url
        .query_pairs()
        .collect::<std::collections::HashMap<_, _>>();
    assert_eq!(params["agent_name_hint"], "Alera");
    assert_eq!(params["ext_agent_host_id"], "urn:uuid:host");
    assert_eq!(params["client_id"], "dynamic_agent_client");
    assert_eq!(params["redirect_uri"], attempt.redirect);
    assert!(attempt.redirect.starts_with("http://127.0.0.1:"));
    assert_eq!(
        params["code_challenge"],
        base64::engine::general_purpose::URL_SAFE_NO_PAD
            .encode(sha2::Sha256::digest(attempt.verifier.as_bytes()))
    );
    assert!(params["scope"].contains("chatgpt.tokens.use.direct"));
    let (_, second_url) = oauth::Attempt::prepare("urn:uuid:host", None)
        .await
        .unwrap();
    assert_ne!(second_url, url.as_str());
}

#[test]
fn signed_identity_rejects_claim_and_signature_mismatches() {
    use aws_lc_rs::{
        rand::SystemRandom,
        rsa::{KeyPair, KeySize},
        signature::{KeyPair as _, RSA_PKCS1_SHA256},
    };
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    use jsonwebtoken::{encode, jwk::JwkSet, Algorithm, EncodingKey, Header};
    let key = KeyPair::generate(KeySize::Rsa2048).unwrap();
    let jwks: JwkSet = serde_json::from_value(json!({"keys":[{
        "kid":"test-key", "kty":"RSA", "alg":"RS256", "use":"sig",
        "n":URL_SAFE_NO_PAD.encode(key.public_key().modulus().big_endian_without_leading_zero()),
        "e":URL_SAFE_NO_PAD.encode(key.public_key().exponent().big_endian_without_leading_zero())
    }]}))
    .unwrap();
    let sign = |claims: &serde_json::Value| {
        let input = format!(
            "{}.{}",
            URL_SAFE_NO_PAD.encode(br#"{"alg":"RS256","kid":"test-key"}"#),
            URL_SAFE_NO_PAD.encode(serde_json::to_vec(claims).unwrap())
        );
        let mut signature = vec![0u8; key.public_modulus_len()];
        key.sign(
            &RSA_PKCS1_SHA256,
            &SystemRandom::new(),
            input.as_bytes(),
            &mut signature,
        )
        .unwrap();
        format!("{input}.{}", URL_SAFE_NO_PAD.encode(signature))
    };
    let now = chrono::Utc::now().timestamp();
    let claims = json!({"sub":"user-a", "iss":oauth::ISSUER, "aud":"oaiapp_a", "iat":now, "exp":now+300, "nonce":"nonce-a", "email":"a@example.test"});
    let token = sign(&claims);
    assert_eq!(
        oauth::validate_identity(&token, "oaiapp_a", Some("nonce-a"), &jwks)
            .unwrap()
            .sub,
        "user-a"
    );
    assert!(oauth::validate_identity(&token, "oaiapp_b", Some("nonce-a"), &jwks).is_err());
    assert!(oauth::validate_identity(&token, "oaiapp_a", Some("nonce-b"), &jwks).is_err());
    for (field, value) in [
        ("iss", json!("https://attacker.test")),
        ("sub", json!("")),
        ("exp", json!(now - 60)),
        ("aud", json!("other")),
        ("azp", json!("other")),
        ("aud", json!(["oaiapp_a", "other"])),
        ("iat", json!(now + 60)),
    ] {
        let mut altered = claims.clone();
        altered[field] = value;
        let token = sign(&altered);
        assert!(
            oauth::validate_identity(&token, "oaiapp_a", Some("nonce-a"), &jwks).is_err(),
            "{field}"
        );
    }
    let token = encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(b"not-an-rsa-key"),
    )
    .unwrap();
    assert!(oauth::validate_identity(&token, "oaiapp_a", None, &jwks).is_err());
    let mut damaged = sign(&claims).into_bytes();
    let index = damaged.len() - 20;
    damaged[index] = if damaged[index] == b'A' { b'B' } else { b'A' };
    assert!(oauth::validate_identity(
        std::str::from_utf8(&damaged).unwrap(),
        "oaiapp_a",
        None,
        &jwks
    )
    .is_err());
}

#[test]
fn token_refresh_rotates_credentials_and_retains_omitted_grants() {
    let initial = json!({"access_token":"access-a", "refresh_token":"refresh-a", "id_token":"identity-a", "token_type":"Bearer", "expires_in":3600, "scope":"openid chatgpt.tokens.use.direct"});
    let saved = oauth::parse_tokens(&initial, None).unwrap();
    let next = oauth::parse_tokens(&json!({"access_token":"access-b", "refresh_token":"refresh-b", "token_type":"Bearer", "expires_in":1800}), Some(&saved)).unwrap();
    assert_eq!(next.refresh_token.as_deref(), Some("refresh-b"));
    assert_eq!(next.id_token, "identity-a");
    assert!(next.can_infer());
    // Explicitly narrower grants must disable inference.
    let mut denied_value = initial.clone();
    denied_value["scope"] = json!("openid");
    assert!(!oauth::parse_tokens(&denied_value, None)
        .unwrap()
        .can_infer());
    for field in ["access_token", "id_token", "expires_in", "token_type"] {
        let mut invalid = initial.clone();
        invalid.as_object_mut().unwrap().remove(field);
        assert!(oauth::parse_tokens(&invalid, None).is_err(), "{field}");
    }
}

#[test]
fn catalog_filters_visibility_and_preserves_account_order() {
    let value = inference::catalog(&json!({"models":[
        {"slug":"hidden", "display_name":"Hidden", "visibility":"hide"},
        {"slug":"b", "display_name":"Model B", "visibility":"list"},
        {"slug":"a", "display_name":"Model A", "visibility":"list"}
    ]}))
    .unwrap();
    assert_eq!(value["defaultModelId"], "b");
    assert_eq!(value["models"].as_array().unwrap().len(), 2);
    assert_eq!(value["models"][1]["label"], "Model A");
    assert!(inference::catalog(&json!({"data":[]})).is_err());
}

#[test]
fn responses_require_a_completed_event_after_text() {
    let delta = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n";
    let completed =
        "data: {\"type\":\"response.completed\",\"response\":{\"output_text\":\"hello\"}}\n\n";
    assert_eq!(
        inference::parse_stream(format!("{delta}{completed}").as_bytes()).unwrap(),
        "hello"
    );
    assert_eq!(
        inference::parse_stream(
            format!("{delta}{completed}")
                .replace('\n', "\r\n")
                .as_bytes()
        )
        .unwrap(),
        "hello"
    );
    for suffix in ["", "data: [DONE]\n\n", "data: {\"type\":\"response.incomplete\"}\n\n", "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}\n\n"] {
        assert!(inference::parse_stream(format!("{delta}{suffix}").as_bytes()).is_err());
    }
    assert!(inference::parse_stream(completed.as_bytes()).is_err());
    let body = inference::request_body("context", "account-model");
    assert_eq!(
        body,
        json!({"model":"account-model", "input":[{"role":"user", "content":"context"}], "store":false, "stream":true})
    );
}
