//! Callback egress ignores proxy environment variables. A proxy would resolve the callback
//! host itself and bypass the pinned, checked address. This binary holds a single test
//! because it changes process-wide proxy variables.

use std::{
    io::{Read, Write},
    net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener},
    sync::Arc,
    thread,
};

use alera_cloud::{
    config::CallbackPolicy,
    events::callback::{CallbackClient, CallbackResolver},
};
use async_trait::async_trait;

/// Answers every lookup with loopback, as a DNS answer for a public-looking name would.
struct Loopback;

#[async_trait]
impl CallbackResolver for Loopback {
    async fn resolve(&self, _host: &str, port: u16) -> std::io::Result<Vec<SocketAddr>> {
        Ok(vec![SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port)])
    }
}

/// Accepts one request and answers `204 No Content`.
fn serve_once(listener: TcpListener) -> thread::JoinHandle<std::io::Result<String>> {
    thread::spawn(move || {
        let (mut stream, _) = listener.accept()?;
        let mut request = Vec::new();
        let mut chunk = [0_u8; 1024];
        loop {
            let read = stream.read(&mut chunk)?;
            request.extend_from_slice(&chunk[..read]);
            let text = String::from_utf8_lossy(&request).to_string();
            if let Some(end) = text.find("\r\n\r\n") {
                let length = text[..end]
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().ok())?
                    })
                    .unwrap_or(0);
                if read == 0 || request.len() >= end + 4 + length {
                    break;
                }
            } else if read == 0 {
                break;
            }
        }
        stream.write_all(
            b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        )?;
        Ok(String::from_utf8_lossy(&request).to_string())
    })
}

#[tokio::test]
async fn callbacks_connect_directly_even_when_a_proxy_is_configured() -> anyhow::Result<()> {
    // A proxy address that refuses connections: a client that honoured it would fail.
    let dead_proxy = TcpListener::bind("127.0.0.1:0")?.local_addr()?;
    let proxy = format!("http://{dead_proxy}");
    for name in [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
    ] {
        std::env::set_var(name, &proxy);
    }
    for name in ["NO_PROXY", "no_proxy", "REQUEST_METHOD"] {
        std::env::remove_var(name);
    }

    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    let server = serve_once(listener);
    let client = CallbackClient::new(CallbackPolicy {
        allow_any_port: false,
        allow_private_targets: true,
    })
    .with_resolver(Arc::new(Loopback));
    let reply = client
        .post(
            &format!("http://hooks.example.test:{port}/hook"),
            &[],
            b"{}".to_vec(),
        )
        .await
        .map_err(|error| anyhow::anyhow!("callback failed: {}", error.reason()))?;
    assert_eq!(reply.status, 204);
    let request = server
        .join()
        .map_err(|_| anyhow::anyhow!("server thread panicked"))??;
    assert!(
        request.starts_with("POST /hook HTTP/1.1"),
        "the pinned server got an origin-form request, not a proxy request: {request}"
    );
    Ok(())
}
