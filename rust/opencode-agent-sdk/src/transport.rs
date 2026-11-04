pub use alera_agent_http::{
    ByteStream, HttpClientConfig, HttpRequest, HttpResponse, HttpTransport, ReqwestTransport,
};
use async_trait::async_trait;
use std::collections::VecDeque;

pub use alera_agent_http::HttpError;

pub use alera_agent_http::MockHttpTransport;

/// A deterministic byte stream for SDK and provider tests.
///
/// The actual HTTP boundary remains [`alera_agent_http::HttpTransport`]; this
/// helper only scripts an already-open response body.
#[derive(Debug)]
pub struct ChunkStream {
    chunks: VecDeque<Result<Option<Vec<u8>>, HttpError>>,
}

impl ChunkStream {
    pub fn from_chunks(chunks: impl IntoIterator<Item = impl Into<Vec<u8>>>) -> Self {
        Self {
            chunks: chunks
                .into_iter()
                .map(|chunk| Ok(Some(chunk.into())))
                .chain(std::iter::once(Ok(None)))
                .collect(),
        }
    }

    pub fn empty() -> Self {
        Self {
            chunks: VecDeque::from([Ok(None)]),
        }
    }
}

#[async_trait]
impl ByteStream for ChunkStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError> {
        self.chunks.pop_front().unwrap_or(Ok(None))
    }

    async fn close(&mut self) -> Result<(), HttpError> {
        self.chunks.clear();
        Ok(())
    }
}

pub(crate) fn json_body(value: &serde_json::Value) -> Result<Vec<u8>, crate::OpenCodeError> {
    serde_json::to_vec(value).map_err(|error| {
        crate::OpenCodeError::Protocol(format!("failed to encode JSON body: {error}"))
    })
}

pub(crate) fn parse_json_body(
    response: HttpResponse,
) -> Result<(u16, serde_json::Value), crate::OpenCodeError> {
    let body = if response.body.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&response.body).map_err(|error| {
            crate::OpenCodeError::Protocol(format!("invalid JSON response: {error}"))
        })?
    };
    Ok((response.status, body))
}

pub(crate) fn request_with_body(
    mut request: HttpRequest,
    body: Option<serde_json::Value>,
) -> Result<HttpRequest, crate::OpenCodeError> {
    if let Some(body) = body {
        request.body = json_body(&body)?;
        request
            .headers
            .insert("content-type".into(), "application/json".into());
    }
    Ok(request)
}
