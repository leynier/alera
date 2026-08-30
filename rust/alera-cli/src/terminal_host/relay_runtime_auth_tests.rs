use super::*;
use ed25519_dalek::{Signer, SigningKey};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

fn claims() -> Value {
    let now = chrono::Utc::now().timestamp();
    json!({"iss":"https://fixture.test", "aud":"alera-relay", "iat":now, "nbf":now, "exp":now+120, "jti":"grant", "accountId":"account", "runtimeId":"runtime", "clientId":"mobile", "role":"mobile", "keyVersion":1, "clientPublicKey":encode([1;32]), "runtimePublicKey":encode([2;32])})
}
fn token(key: &SigningKey, kid: &str, value: &Value) -> String {
    let header =
        encode(serde_json::to_vec(&json!({"alg":"EdDSA", "typ":"relay+jwt", "kid":kid})).unwrap());
    let input = format!("{header}.{}", encode(serde_json::to_vec(value).unwrap()));
    format!("{input}.{}", encode(key.sign(input.as_bytes()).to_bytes()))
}
fn jwks(key: &SigningKey, kid: &str) -> String {
    json!({"keys":[{"kty":"OKP", "crv":"Ed25519", "alg":"EdDSA", "kid":kid, "x":encode(key.verifying_key().to_bytes())}]}).to_string()
}
async fn origin(
    body: String,
) -> (
    GrantVerifier,
    Arc<Mutex<String>>,
    Arc<AtomicUsize>,
    tokio::task::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let body = Arc::new(Mutex::new(body));
    let count = Arc::new(AtomicUsize::new(0));
    let stored = body.clone();
    let requests = count.clone();
    let server = tokio::spawn(async move {
        loop {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut buffer = [0; 4096];
            let read = socket.read(&mut buffer).await.unwrap();
            if read == 0 {
                continue;
            }
            requests.fetch_add(1, Ordering::SeqCst);
            let body = stored.lock().await.clone();
            socket
                .write_all(
                    format!(
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    )
                    .as_bytes(),
                )
                .await
                .unwrap();
        }
    });
    (
        GrantVerifier::with_url(
            "https://fixture.test".into(),
            format!("http://{address}/jwks"),
        )
        .unwrap(),
        body,
        count,
        server,
    )
}

#[tokio::test]
async fn relay_jwks_is_shared_and_unknown_kid_refresh_is_throttled() {
    let key = SigningKey::from_bytes(&[4; 32]);
    let (verifier, body, count, server) = origin(jwks(&key, "one")).await;
    let grant = token(&key, "one", &claims());
    let results = futures_util::future::join_all((0..8).map(|_| verifier.verify(&grant))).await;
    assert!(results.iter().all(Result::is_ok));
    assert_eq!(count.load(Ordering::SeqCst), 1);
    let rotated = SigningKey::from_bytes(&[5; 32]);
    let new_grant = token(&rotated, "two", &claims());
    *body.lock().await = jwks(&rotated, "two");
    assert!(verifier.verify(&new_grant).await.is_ok());
    assert_eq!(count.load(Ordering::SeqCst), 2);
    assert!(verifier
        .verify(&token(&key, "unknown", &claims()))
        .await
        .is_err());
    assert_eq!(count.load(Ordering::SeqCst), 2);
    server.abort();
}

#[tokio::test]
async fn relay_jwks_oversize_failure_does_not_trigger_a_lookup_per_peer() {
    let key = SigningKey::from_bytes(&[4; 32]);
    let (verifier, _, count, server) = origin(" ".repeat(65537)).await;
    let grant = token(&key, "one", &claims());
    for _ in 0..8 {
        assert!(verifier
            .verify(&grant)
            .await
            .unwrap_err()
            .is::<GrantKeysUnavailable>());
    }
    assert_eq!(count.load(Ordering::SeqCst), 1);
    server.abort();
}

#[tokio::test]
async fn relay_invalid_scope_lifetime_and_expiry_fail_before_network_access() {
    let key = SigningKey::from_bytes(&[4; 32]);
    let (verifier, _, count, server) = origin(jwks(&key, "one")).await;
    let original = claims();
    for (field, value) in [
        ("exp", json!(0)),
        ("exp", json!(original["iat"].as_i64().unwrap() + 121)),
        ("role", json!("admin")),
        ("clientId", json!("")),
        ("keyVersion", json!(0)),
        ("runtimePublicKey", json!("broken")),
    ] {
        let mut invalid = original.clone();
        invalid[field] = value;
        assert!(verifier
            .verify(&token(&key, "one", &invalid))
            .await
            .is_err());
    }
    assert_eq!(count.load(Ordering::SeqCst), 0);
    server.abort();
}
