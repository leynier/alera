use std::future::Future;
use std::time::Duration;

use alera_agent_http::{HttpClientConfig, HttpError, HttpRequest, HttpTransport, ReqwestTransport};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;
use tokio::time::{sleep, timeout, Instant};

const REQUEST_TIMEOUT: Duration = Duration::from_millis(250);
const BODY_PAUSE: Duration = Duration::from_millis(500);
const TEST_TIMEOUT: Duration = Duration::from_secs(5);
const BODY_BUDGET: usize = 8;
const STREAM_PAYLOADS: [&[u8]; 3] = [b"one-one\n", b"two-two\n", b"tri-tri\n"];

struct LoopbackServer {
    base_url: String,
    task: JoinHandle<()>,
}

impl LoopbackServer {
    async fn finish(mut self) {
        timeout(TEST_TIMEOUT, &mut self.task)
            .await
            .expect("loopback server should finish")
            .expect("loopback server should succeed");
    }
}

impl Drop for LoopbackServer {
    fn drop(&mut self) {
        self.task.abort();
    }
}

async fn start_loopback<F, Fut>(respond: F) -> LoopbackServer
where
    F: FnOnce(TcpStream) -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("bind loopback listener");
    let base_url = format!(
        "http://{}",
        listener.local_addr().expect("listener address")
    );
    let task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.expect("accept HTTP request");
        let mut request = Vec::new();
        let mut buffer = [0_u8; 1024];
        loop {
            let read = socket.read(&mut buffer).await.expect("read HTTP request");
            assert_ne!(read, 0, "client closed before sending request headers");
            request.extend_from_slice(&buffer[..read]);
            assert!(
                request.len() <= 8192,
                "fixture request headers exceed limit"
            );
            if request.windows(4).any(|window| window == b"\r\n\r\n") {
                break;
            }
        }
        respond(socket).await;
    });
    LoopbackServer { base_url, task }
}

#[tokio::test]
async fn stream_survives_body_budget_and_header_deadline() {
    let (permit_chunk, mut chunk_permits) = mpsc::channel::<()>(1);
    let server = start_loopback(move |mut socket| async move {
        socket
            .write_all(
                b"HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n",
            )
            .await
            .expect("write stream response headers");
        for (index, payload) in STREAM_PAYLOADS.into_iter().enumerate() {
            // Consumer acknowledgements keep separately bounded payloads from coalescing.
            chunk_permits.recv().await.expect("permit the next payload");
            if index == 1 {
                sleep(BODY_PAUSE).await;
            }
            socket
                .write_all(format!("{:x}\r\n", payload.len()).as_bytes())
                .await
                .expect("write chunk length");
            socket
                .write_all(payload)
                .await
                .expect("write chunk payload");
            socket.write_all(b"\r\n").await.expect("write chunk ending");
        }
        chunk_permits.recv().await.expect("permit stream EOF");
        socket
            .write_all(b"0\r\n\r\n")
            .await
            .expect("write stream EOF");
        socket.shutdown().await.expect("close stream socket");
    })
    .await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: server.base_url.clone(),
        request_timeout: REQUEST_TIMEOUT,
        max_response_bytes: BODY_BUDGET,
        ..HttpClientConfig::default()
    })
    .expect("build HTTP transport");

    let started = Instant::now();
    let mut stream = timeout(
        TEST_TIMEOUT,
        transport.open_stream(HttpRequest::new("GET", "/events")),
    )
    .await
    .expect("stream headers should arrive")
    .expect("open stream");
    let mut body = Vec::new();
    for expected in STREAM_PAYLOADS {
        permit_chunk
            .send(())
            .await
            .expect("allow next stream payload");
        let mut payload = Vec::new();
        while payload.len() < expected.len() {
            let chunk = timeout(TEST_TIMEOUT, stream.next_chunk())
                .await
                .expect("stream read should finish")
                .expect("stream remains readable beyond the request deadline")
                .expect("payload arrives before EOF");
            assert!(
                !chunk.is_empty(),
                "stream payload chunks should not be empty"
            );
            assert!(chunk.len() <= BODY_BUDGET);
            payload.extend_from_slice(&chunk);
            assert!(payload.len() <= expected.len());
        }
        assert_eq!(payload.as_slice(), expected);
        body.extend_from_slice(&payload);
    }
    assert!(body.len() > BODY_BUDGET);
    assert_eq!(body, STREAM_PAYLOADS.concat());
    assert!(started.elapsed() > REQUEST_TIMEOUT);
    permit_chunk.send(()).await.expect("allow stream EOF");
    assert!(timeout(TEST_TIMEOUT, stream.next_chunk())
        .await
        .expect("stream EOF should arrive")
        .expect("read stream EOF")
        .is_none());
    stream.close().await.expect("close completed stream");
    server.finish().await;
}

#[tokio::test]
async fn delayed_headers_still_hit_request_deadline() {
    let (release_headers, headers_released) = oneshot::channel::<()>();
    let server = start_loopback(move |mut socket| async move {
        headers_released.await.expect("release delayed headers");
        socket
            .shutdown()
            .await
            .expect("close delayed response socket");
    })
    .await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: server.base_url.clone(),
        request_timeout: REQUEST_TIMEOUT,
        ..HttpClientConfig::default()
    })
    .expect("build HTTP transport");

    let error = match timeout(
        TEST_TIMEOUT,
        transport.open_stream(HttpRequest::new("GET", "/events")),
    )
    .await
    .expect("request deadline should finish the handshake")
    {
        Ok(_) => panic!("withheld response headers should time out"),
        Err(error) => error,
    };
    assert!(matches!(
        error,
        HttpError::Timeout { operation: "request", timeout } if timeout == REQUEST_TIMEOUT
    ));
    release_headers
        .send(())
        .expect("release the loopback server");
    server.finish().await;
}

#[tokio::test]
async fn unary_response_still_enforces_cumulative_body_budget() {
    let server = start_loopback(|mut socket| async move {
        socket
            .write_all(
                b"HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n8\r\none-one\n\r\n1\r\n!\r\n0\r\n\r\n",
            )
            .await
            .expect("write oversized unary response");
        socket
            .shutdown()
            .await
            .expect("close unary response socket");
    })
    .await;
    let transport = ReqwestTransport::new(HttpClientConfig {
        base_url: server.base_url.clone(),
        request_timeout: REQUEST_TIMEOUT,
        max_response_bytes: BODY_BUDGET,
        ..HttpClientConfig::default()
    })
    .expect("build HTTP transport");

    let error = timeout(
        TEST_TIMEOUT,
        transport.request(HttpRequest::new("GET", "/large")),
    )
    .await
    .expect("unary response should finish")
    .expect_err("oversized unary response should fail");
    assert!(matches!(
        error,
        HttpError::BodyTooLarge {
            kind: "response body",
            limit: BODY_BUDGET,
            observed: 9
        }
    ));
    server.finish().await;
}
