use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::{error::UrlError, http::header, Error};

use super::{connect_async, relay_request, RELAY_PRESENCE_INTERVAL};

#[test]
fn relay_presence_refreshes_before_cloud_expiry() {
    assert!(RELAY_PRESENCE_INTERVAL < std::time::Duration::from_secs(180));
}

#[test]
fn relay_request_preserves_websocket_handshake_headers() {
    let request = relay_request("wss://relay.example/v1/relay/runtime", "relay-grant")
        .expect("relay request");

    assert_eq!(request.headers()[header::CONNECTION], "Upgrade");
    assert_eq!(request.headers()[header::UPGRADE], "websocket");
    assert_eq!(request.headers()[header::SEC_WEBSOCKET_VERSION], "13");
    assert!(request.headers().contains_key(header::SEC_WEBSOCKET_KEY));
    assert_eq!(
        request.headers()[header::AUTHORIZATION],
        "Bearer relay-grant"
    );
    assert_eq!(request.headers()[header::ORIGIN], "https://app.alera.build");
}

#[tokio::test]
async fn websocket_client_supports_wss() {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        drop(stream);
    });

    let request = relay_request(&format!("wss://{address}"), "relay-grant").unwrap();
    let error = connect_async(request)
        .await
        .expect_err("the local test server does not complete a TLS handshake");
    server.abort();

    assert!(!matches!(error, Error::Url(UrlError::TlsFeatureNotEnabled)));
}
