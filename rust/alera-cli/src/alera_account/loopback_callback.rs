use anyhow::{anyhow, Context as _, Result};
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::TcpListener;
use tokio::sync::oneshot;
use url::Url;

const MAX_CALLBACK_BYTES: usize = 16 * 1024;

pub(crate) async fn bind_callback_listener() -> Result<(TcpListener, String)> {
    let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    Ok((listener, format!("http://127.0.0.1:{port}/callback")))
}

pub(crate) async fn wait_for_callback(
    listener: TcpListener,
    expected_state: &str,
    cancel: oneshot::Receiver<()>,
) -> Result<String> {
    tokio::select! {
        _ = cancel => Err(anyhow!("account sign-in was cancelled")),
        result = tokio::time::timeout(
            std::time::Duration::from_secs(5 * 60),
            receive_callback(listener, expected_state),
        ) => result.context("account sign-in timed out")?,
    }
}

async fn receive_callback(listener: TcpListener, expected_state: &str) -> Result<String> {
    let (mut stream, _) = listener.accept().await?;
    let mut request = vec![0_u8; MAX_CALLBACK_BYTES];
    let read = stream.read(&mut request).await?;
    request.truncate(read);
    let request = std::str::from_utf8(&request)?;
    let target = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| anyhow!("invalid OAuth callback request"))?;
    let url = Url::parse(&format!("http://127.0.0.1{target}"))?;
    let query: std::collections::HashMap<_, _> = url.query_pairs().into_owned().collect();
    let state = query
        .get("state")
        .ok_or_else(|| anyhow!("OAuth callback did not include state"))?;
    if state != expected_state {
        write_response(&mut stream, "400 Bad Request", callback_error_page()).await?;
        return Err(anyhow!("OAuth callback state did not match"));
    }
    if let Some(error) = query.get("error") {
        write_response(&mut stream, "400 Bad Request", callback_error_page()).await?;
        return Err(anyhow!("identity provider rejected sign-in: {error}"));
    }
    let code = query
        .get("code")
        .filter(|value| !value.is_empty())
        .cloned()
        .ok_or_else(|| anyhow!("OAuth callback did not include a code"))?;
    write_response(&mut stream, "200 OK", callback_success_page()).await?;
    Ok(code)
}

async fn write_response(
    stream: &mut tokio::net::TcpStream,
    status: &str,
    body: &str,
) -> Result<()> {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n{body}",
        body.len()
    );
    stream.write_all(response.as_bytes()).await?;
    stream.shutdown().await?;
    Ok(())
}

fn callback_success_page() -> &'static str {
    r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="refresh" content="2;url=https://alera.build/signed-in"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Signed In</title></head><body style="background:#090b10;color:#f4f5f7;font:16px system-ui;display:grid;min-height:100vh;place-items:center"><main><h1>Signed In</h1><p>You can return to Alera. This tab will continue to alera.build.</p></main></body></html>"#
}

fn callback_error_page() -> &'static str {
    r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Sign-In Failed</title></head><body style="background:#090b10;color:#f4f5f7;font:16px system-ui;display:grid;min-height:100vh;place-items:center"><main><h1>Sign-In Failed</h1><p>Return to Alera and try again.</p></main></body></html>"#
}

#[cfg(test)]
mod tests {
    use super::{bind_callback_listener, wait_for_callback};
    use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
    use tokio::sync::oneshot;

    #[tokio::test]
    async fn accepts_matching_state_and_returns_code() {
        let (listener, redirect) = bind_callback_listener().await.unwrap();
        assert_eq!(url::Url::parse(&redirect).unwrap().path(), "/callback");
        let port = url::Url::parse(&redirect).unwrap().port().unwrap();
        let (_cancel_tx, cancel_rx) = oneshot::channel();
        let callback = tokio::spawn(wait_for_callback(listener, "expected", cancel_rx));
        let mut stream = tokio::net::TcpStream::connect(("127.0.0.1", port))
            .await
            .unwrap();
        stream
            .write_all(
                b"GET /callback?code=code-1&state=expected HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
            )
            .await
            .unwrap();
        let mut response = Vec::new();
        stream.read_to_end(&mut response).await.unwrap();

        assert_eq!(callback.await.unwrap().unwrap(), "code-1");
        assert!(String::from_utf8(response).unwrap().contains("Signed In"));
    }

    #[tokio::test]
    async fn rejects_mismatched_state() {
        let (listener, redirect) = bind_callback_listener().await.unwrap();
        let port = url::Url::parse(&redirect).unwrap().port().unwrap();
        let (_cancel_tx, cancel_rx) = oneshot::channel();
        let callback = tokio::spawn(wait_for_callback(listener, "expected", cancel_rx));
        let mut stream = tokio::net::TcpStream::connect(("127.0.0.1", port))
            .await
            .unwrap();
        stream
            .write_all(b"GET /callback?code=code-1&state=other HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
            .await
            .unwrap();

        assert!(callback
            .await
            .unwrap()
            .unwrap_err()
            .to_string()
            .contains("state"));
    }
}
