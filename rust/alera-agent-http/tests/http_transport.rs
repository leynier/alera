use std::collections::BTreeMap;
use std::time::Duration;

use alera_agent_http::{
    HttpClientConfig, HttpRequest, HttpResponse, HttpTransport, MockHttpTransport, ReqwestTransport,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

async fn start_server(response: &'static [u8]) -> String {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut request = Vec::new();
        let mut buffer = [0_u8; 1024];
        loop {
            let read = socket.read(&mut buffer).await.unwrap();
            if read == 0 {
                break;
            }
            request.extend_from_slice(&buffer[..read]);
            if request.windows(4).any(|window| window == b"\r\n\r\n") {
                break;
            }
        }
        socket.write_all(response).await.unwrap();
        socket.shutdown().await.unwrap();
    });
    format!("http://{address}")
}

#[tokio::test]
async fn request_collects_loopback_response_and_headers() {
    let base = start_server(
        b"HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 8\r\n\r\n{\"ok\":1}",
    )
    .await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: base,
        headers: BTreeMap::from([(String::from("x-client"), String::from("test"))]),
        request_timeout: Duration::from_secs(2),
        max_response_bytes: 1024,
    })
    .unwrap();
    let response = transport
        .request(HttpRequest::new("GET", "/health"))
        .await
        .unwrap();
    assert_eq!(response.status, 200);
    assert_eq!(response.body, br#"{"ok":1}"#);
    assert_eq!(
        response.headers.get("content-type"),
        Some(&String::from("application/json"))
    );
}

#[tokio::test]
async fn open_stream_collects_sse_bytes_until_eof() {
    let base = start_server(
        b"HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\ndata: one\n\ndata: two\n\n",
    )
    .await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: base,
        request_timeout: Duration::from_secs(2),
        max_response_bytes: 1024,
        ..HttpClientConfig::default()
    })
    .unwrap();
    let mut stream = transport
        .open_stream(HttpRequest::new("GET", "/api/event"))
        .await
        .unwrap();
    let mut body = Vec::new();
    while let Some(chunk) = stream.next_chunk().await.unwrap() {
        body.extend_from_slice(&chunk);
    }
    assert_eq!(body, b"data: one\n\ndata: two\n\n");
    stream.close().await.unwrap();
}

#[tokio::test]
async fn mock_captures_requests_and_scripts_stream() {
    let mock = MockHttpTransport::new();
    mock.push_response(HttpResponse::new(204, Vec::new()));
    mock.push_stream([b"one".to_vec(), b"two".to_vec()]);

    let response = mock
        .request(HttpRequest::new("POST", "/session"))
        .await
        .unwrap();
    assert_eq!(response.status, 204);
    let mut stream = mock
        .open_stream(HttpRequest::new("GET", "/events"))
        .await
        .unwrap();
    assert_eq!(stream.next_chunk().await.unwrap(), Some(b"one".to_vec()));
    assert_eq!(stream.next_chunk().await.unwrap(), Some(b"two".to_vec()));
    assert_eq!(stream.next_chunk().await.unwrap(), None);
    assert_eq!(mock.captured_requests().len(), 2);
}

#[tokio::test]
async fn response_limit_is_enforced_before_returning_body() {
    let base = start_server(b"HTTP/1.1 200 OK\r\ncontent-length: 4\r\n\r\nlong").await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: base,
        max_response_bytes: 3,
        request_timeout: Duration::from_secs(2),
        ..HttpClientConfig::default()
    })
    .unwrap();
    let error = transport
        .request(HttpRequest::new("GET", "/large"))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("response body"));
}

#[tokio::test]
async fn non_success_response_exposes_bounded_body_without_debug_leak() {
    let base = start_server(
        b"HTTP/1.1 401 Unauthorized\r\ncontent-type: application/json\r\nconnection: close\r\n\r\n{\"code\":\"unauthenticated\",\"secret\":\"nope\"}",
    )
    .await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: base,
        max_response_bytes: 1024,
        request_timeout: Duration::from_secs(2),
        ..HttpClientConfig::default()
    })
    .unwrap();
    let error = transport
        .request(HttpRequest::new("GET", "/private"))
        .await
        .unwrap_err();
    match &error {
        alera_agent_http::HttpError::Status { status, body } => {
            assert_eq!(*status, 401);
            assert!(body
                .as_bytes()
                .windows(b"unauthenticated".len())
                .any(|part| { part == b"unauthenticated" }));
        }
        other => panic!("unexpected error: {other:?}"),
    }
    let debug = format!("{error:?}");
    assert!(!debug.contains("secret"));
    assert!(!debug.contains("nope"));
}
