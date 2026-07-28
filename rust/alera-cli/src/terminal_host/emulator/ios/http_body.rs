use std::time::Duration;

use futures_util::StreamExt as _;

use super::super::contract::{EmulatorFailure, EmulatorResult};
use super::helper_runtime::helper_failure;

pub struct HttpBody {
    pub status: reqwest::StatusCode,
    pub bytes: Vec<u8>,
}

pub async fn get_bounded(
    url: &str,
    total_timeout: Duration,
    max_body_bytes: usize,
    operation: &str,
) -> EmulatorResult<HttpBody> {
    tokio::time::timeout(total_timeout, async {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .no_proxy()
            .build()
            .map_err(|error| {
                helper_failure(format!(
                    "Could not configure the serve-sim {operation} request: {error}"
                ))
            })?;
        let response = client.get(url).send().await.map_err(|error| {
            helper_failure(format!("serve-sim {operation} request failed: {error}"))
        })?;
        if response
            .content_length()
            .is_some_and(|length| length > max_body_bytes as u64)
        {
            return Err(body_limit_failure(operation, max_body_bytes));
        }
        let status = response.status();
        let mut stream = response.bytes_stream();
        let mut bytes = Vec::new();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|error| {
                helper_failure(format!(
                    "serve-sim {operation} response could not be read: {error}"
                ))
            })?;
            if bytes.len().saturating_add(chunk.len()) > max_body_bytes {
                return Err(body_limit_failure(operation, max_body_bytes));
            }
            bytes.extend_from_slice(&chunk);
        }
        Ok(HttpBody { status, bytes })
    })
    .await
    .map_err(|_| helper_failure(format!("serve-sim {operation} request timed out.")))?
}

fn body_limit_failure(operation: &str, max_body_bytes: usize) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        format!("serve-sim {operation} returned more than {max_body_bytes} bytes."),
        ["Restart the iOS Simulator and retry the snapshot."],
    )
}

#[cfg(test)]
mod tests {
    use std::time::Instant;

    use tokio::io::AsyncWriteExt as _;
    use tokio::net::TcpListener;

    use super::*;

    #[tokio::test]
    async fn rejects_content_length_over_the_body_cap() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            socket
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n")
                .await
                .unwrap();
        });
        let error = get_bounded(
            &format!("http://{address}/ax"),
            Duration::from_secs(1),
            16,
            "accessibility",
        )
        .await
        .err()
        .unwrap();
        assert_eq!(error.code, "provider_incompatible");
        server.await.unwrap();
    }

    #[tokio::test]
    async fn rejects_streamed_body_over_the_body_cap() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            socket
                .write_all(
                    b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nbody-without-content-length",
                )
                .await
                .unwrap();
        });
        let error = get_bounded(
            &format!("http://{address}/ax"),
            Duration::from_secs(1),
            8,
            "accessibility",
        )
        .await
        .err()
        .unwrap();
        assert_eq!(error.code, "provider_incompatible");
        server.await.unwrap();
    }

    #[tokio::test]
    async fn timeout_covers_a_stalled_response_body() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            socket
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nx")
                .await
                .unwrap();
            tokio::time::sleep(Duration::from_secs(2)).await;
        });
        let started = Instant::now();
        let error = get_bounded(
            &format!("http://{address}/config"),
            Duration::from_millis(100),
            16,
            "configuration",
        )
        .await
        .err()
        .unwrap();
        assert_eq!(error.code, "stream_failed");
        assert!(started.elapsed() < Duration::from_secs(1));
        server.abort();
    }
}
