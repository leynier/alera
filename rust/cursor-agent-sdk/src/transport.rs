use crate::error::CursorSdkError;
use alera_agent_http::{HttpClientConfig, HttpRequest, HttpTransport};
use async_trait::async_trait;
use serde_json::Value;
use std::time::Duration;

#[async_trait]
pub trait ByteStream: Send {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, CursorSdkError>;

    async fn close(&mut self) -> Result<(), CursorSdkError> {
        Ok(())
    }
}

#[async_trait]
pub trait BridgeTransport: Send + Sync {
    async fn unary(
        &self,
        path: &str,
        bearer_token: &str,
        body: Value,
        timeout: Duration,
    ) -> Result<Value, CursorSdkError>;

    async fn stream(
        &self,
        path: &str,
        bearer_token: &str,
        body: Vec<u8>,
        timeout: Duration,
    ) -> Result<Box<dyn ByteStream>, CursorSdkError>;

    async fn close(&self) -> Result<(), CursorSdkError> {
        Ok(())
    }
}

pub struct ReqwestBridgeTransport {
    client: alera_agent_http::ReqwestTransport,
}

impl ReqwestBridgeTransport {
    pub fn new(base_url: impl Into<String>) -> Result<Self, CursorSdkError> {
        Self::new_with_timeout(base_url, HttpClientConfig::default().request_timeout)
    }

    pub fn new_with_timeout(
        base_url: impl Into<String>,
        request_timeout: Duration,
    ) -> Result<Self, CursorSdkError> {
        let base_url = base_url.into().trim_end_matches('/').to_owned();
        let config = HttpClientConfig {
            base_url,
            request_timeout,
            ..HttpClientConfig::default()
        };
        Ok(Self {
            client: alera_agent_http::ReqwestTransport::new(config)?,
        })
    }
}

#[async_trait]
impl BridgeTransport for ReqwestBridgeTransport {
    async fn unary(
        &self,
        path: &str,
        bearer_token: &str,
        body: Value,
        timeout: Duration,
    ) -> Result<Value, CursorSdkError> {
        let mut request = HttpRequest::new("POST", path);
        request
            .headers
            .insert("authorization".into(), format!("Bearer {bearer_token}"));
        request
            .headers
            .insert("connect-protocol-version".into(), "1".into());
        request
            .headers
            .insert("content-type".into(), "application/json".into());
        request.body = serde_json::to_vec(&body)
            .map_err(|error| CursorSdkError::Protocol(format!("unary request JSON: {error}")))?;
        let response = tokio::time::timeout(timeout, self.client.request(request))
            .await
            .map_err(|_| CursorSdkError::Timeout {
                operation: path.to_owned(),
                timeout,
            })??;
        let status = response.status;
        let body = response.body;
        let value: Value = serde_json::from_slice(&body).map_err(|error| {
            CursorSdkError::Protocol(format!("unary response is not JSON: {error}"))
        })?;
        if !(200..=299).contains(&status) {
            return Err(parse_rpc_error(path, status, value));
        }
        if value.get("code").is_some() && value.get("message").is_some() {
            return Err(parse_rpc_error(path, status, value));
        }
        Ok(value)
    }

    async fn stream(
        &self,
        path: &str,
        bearer_token: &str,
        body: Vec<u8>,
        _timeout: Duration,
    ) -> Result<Box<dyn ByteStream>, CursorSdkError> {
        let mut request = HttpRequest::new("POST", path);
        request
            .headers
            .insert("authorization".into(), format!("Bearer {bearer_token}"));
        request
            .headers
            .insert("connect-protocol-version".into(), "1".into());
        request
            .headers
            .insert("content-type".into(), "application/connect+json".into());
        request.body = body;
        let response = self.client.open_stream(request).await?;
        Ok(Box::new(HttpByteStream { inner: response }))
    }
}

struct HttpByteStream {
    inner: Box<dyn alera_agent_http::ByteStream>,
}

#[async_trait]
impl ByteStream for HttpByteStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, CursorSdkError> {
        Ok(self.inner.next_chunk().await?)
    }

    async fn close(&mut self) -> Result<(), CursorSdkError> {
        Ok(self.inner.close().await?)
    }
}

fn parse_rpc_error(path: &str, status: u16, value: Value) -> CursorSdkError {
    let code = value
        .get("code")
        .and_then(Value::as_str)
        .unwrap_or("unknown")
        .to_owned();
    let message = value
        .get("message")
        .and_then(Value::as_str)
        .unwrap_or("bridge RPC failed")
        .to_owned();
    CursorSdkError::Rpc {
        method: path.to_owned(),
        code: if status == 401 {
            "unauthenticated".into()
        } else {
            code
        },
        message,
        details: Box::new(value),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn rpc_errors_preserve_response_details_and_existing_diagnostics() {
        let response = json!({
            "code": "permission_denied",
            "message": "Workspace access denied",
            "details": [{"reason": "workspace_scope", "workspaceId": "workspace-1"}],
        });
        for (status, expected_code) in [(403, "permission_denied"), (401, "unauthenticated")] {
            let error = parse_rpc_error("/workspace/open", status, response.clone());
            assert_eq!(
                error.to_string(),
                format!("cursor bridge RPC `/workspace/open` failed with {expected_code}: Workspace access denied")
            );
            let CursorSdkError::Rpc {
                method,
                code,
                message,
                details,
            } = error
            else {
                panic!("expected a typed RPC error");
            };
            assert_eq!(method, "/workspace/open");
            assert_eq!(code, expected_code);
            assert_eq!(message, "Workspace access denied");
            assert_eq!(serde_json::to_value(details).unwrap(), response);
        }
    }
}
