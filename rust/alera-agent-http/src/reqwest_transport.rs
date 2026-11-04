use std::collections::BTreeMap;
use std::fmt;
use std::pin::Pin;
use std::time::Duration;

use async_trait::async_trait;
use bytes::Bytes;
use futures_util::stream::{Stream, StreamExt};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::{Client, Method, Response, Url};

use crate::{ByteStream, HttpError, HttpErrorBody, HttpRequest, HttpResponse, HttpTransport};

/// Defaults for response/request body bounding and operation deadlines.
pub const DEFAULT_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
pub const DEFAULT_MAX_RESPONSE_BYTES: usize = 16 * 1024 * 1024;

/// Configuration shared by all requests made through a [`ReqwestTransport`].
#[derive(Clone)]
pub struct HttpClientConfig {
    /// Absolute HTTP or HTTPS origin used to resolve relative request paths.
    pub base_url: String,
    /// Headers applied to every request before per-request headers.
    pub headers: BTreeMap<String, String>,
    /// Deadline applied to request headers and collected response reads.
    /// Open streams remain readable until the caller closes or drops them.
    pub request_timeout: Duration,
    /// Maximum request and response body size in bytes.
    pub max_response_bytes: usize,
}

impl fmt::Debug for HttpClientConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpClientConfig")
            .field("base_url", &"<redacted>")
            .field("header_count", &self.headers.len())
            .field("request_timeout", &self.request_timeout)
            .field("max_response_bytes", &self.max_response_bytes)
            .finish()
    }
}

impl Default for HttpClientConfig {
    fn default() -> Self {
        Self {
            base_url: String::new(),
            headers: BTreeMap::new(),
            request_timeout: DEFAULT_REQUEST_TIMEOUT,
            max_response_bytes: DEFAULT_MAX_RESPONSE_BYTES,
        }
    }
}

/// A reqwest-backed implementation of [`HttpTransport`].
#[derive(Clone)]
pub struct ReqwestTransport {
    client: Client,
    config: HttpClientConfig,
    base_url: Url,
    default_headers: HeaderMap,
}

impl fmt::Debug for ReqwestTransport {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ReqwestTransport")
            .field("config", &self.config)
            .field("default_header_count", &self.default_headers.len())
            .finish()
    }
}

impl ReqwestTransport {
    /// Build a transport after validating its URL, headers, bounds, and timeout.
    pub fn new(config: HttpClientConfig) -> Result<Self, HttpError> {
        if config.base_url.trim().is_empty() {
            return Err(HttpError::InvalidConfig {
                reason: "base_url must not be empty",
            });
        }
        if config.request_timeout.is_zero() {
            return Err(HttpError::InvalidConfig {
                reason: "request_timeout must be greater than zero",
            });
        }
        if config.max_response_bytes == 0 {
            return Err(HttpError::InvalidConfig {
                reason: "max_response_bytes must be greater than zero",
            });
        }

        let base_url = Url::parse(&config.base_url)
            .map_err(|_| HttpError::InvalidInput { kind: "base URL" })?;
        if base_url.scheme() != "http" && base_url.scheme() != "https" {
            return Err(HttpError::InvalidInput { kind: "base URL" });
        }
        let default_headers = build_headers(&config.headers)?;
        let client = Client::builder()
            .default_headers(default_headers.clone())
            .build()
            .map_err(|_| HttpError::Request {
                operation: "client build",
            })?;

        Ok(Self {
            client,
            config,
            base_url,
            default_headers,
        })
    }

    fn prepare(&self, request: &HttpRequest) -> Result<reqwest::RequestBuilder, HttpError> {
        if request.body.len() > self.config.max_response_bytes {
            return Err(HttpError::BodyTooLarge {
                kind: "request body",
                limit: self.config.max_response_bytes,
                observed: request.body.len(),
            });
        }
        let method = Method::from_bytes(request.method.as_bytes())
            .map_err(|_| HttpError::InvalidInput { kind: "method" })?;
        let url = resolve_url(&self.base_url, &request.path)?;
        let mut headers = self.default_headers.clone();
        for (name, value) in &request.headers {
            let name =
                HeaderName::from_bytes(name.as_bytes()).map_err(|_| HttpError::InvalidInput {
                    kind: "header name",
                })?;
            let value = HeaderValue::from_str(value).map_err(|_| HttpError::InvalidInput {
                kind: "header value",
            })?;
            headers.insert(name, value);
        }
        Ok(self
            .client
            .request(method, url)
            .headers(headers)
            .body(request.body.clone()))
    }

    async fn send(&self, request: HttpRequest) -> Result<Response, HttpError> {
        tokio::time::timeout(self.config.request_timeout, self.prepare(&request)?.send())
            .await
            .map_err(|_| HttpError::Timeout {
                operation: "request",
                timeout: self.config.request_timeout,
            })?
            .map_err(|_| HttpError::Request {
                operation: "request",
            })
    }

    fn response_headers(response: &Response) -> BTreeMap<String, String> {
        response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.as_str().to_string(), value.to_string()))
            })
            .collect()
    }
}

#[async_trait]
impl HttpTransport for ReqwestTransport {
    async fn request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
        let response = self.send(request).await?;
        let status = response.status().as_u16();
        if !(200..=299).contains(&status) {
            return Err(status_error(response, &self.config).await);
        }
        let headers = Self::response_headers(&response);
        let mut body = Vec::new();
        let mut stream = response.bytes_stream();
        while let Some(chunk) = tokio::time::timeout(self.config.request_timeout, stream.next())
            .await
            .map_err(|_| HttpError::Timeout {
                operation: "response body",
                timeout: self.config.request_timeout,
            })?
        {
            let chunk = chunk.map_err(|_| HttpError::Request {
                operation: "response body",
            })?;
            let observed = body.len().saturating_add(chunk.len());
            if observed > self.config.max_response_bytes {
                return Err(HttpError::BodyTooLarge {
                    kind: "response body",
                    limit: self.config.max_response_bytes,
                    observed,
                });
            }
            body.extend_from_slice(&chunk);
        }
        Ok(HttpResponse {
            status,
            headers,
            body,
        })
    }

    async fn open_stream(&self, request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError> {
        let response = self.send(request).await?;
        let status = response.status().as_u16();
        if !(200..=299).contains(&status) {
            return Err(status_error(response, &self.config).await);
        }
        Ok(Box::new(ReqwestByteStream::new(
            response.bytes_stream(),
            self.config.max_response_bytes,
        )))
    }
}

fn build_headers(headers: &BTreeMap<String, String>) -> Result<HeaderMap, HttpError> {
    let mut result = HeaderMap::new();
    for (name, value) in headers {
        let name =
            HeaderName::from_bytes(name.as_bytes()).map_err(|_| HttpError::InvalidInput {
                kind: "header name",
            })?;
        let value = HeaderValue::from_str(value).map_err(|_| HttpError::InvalidInput {
            kind: "header value",
        })?;
        result.insert(name, value);
    }
    Ok(result)
}

fn resolve_url(base: &Url, path: &str) -> Result<Url, HttpError> {
    if path.starts_with("http://") || path.starts_with("https://") {
        return Url::parse(path).map_err(|_| HttpError::InvalidInput {
            kind: "request URL",
        });
    }
    base.join(path).map_err(|_| HttpError::InvalidInput {
        kind: "request path",
    })
}

async fn status_error(response: Response, config: &HttpClientConfig) -> HttpError {
    let status = response.status().as_u16();
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    while body.len() < config.max_response_bytes {
        let next = tokio::time::timeout(config.request_timeout, stream.next()).await;
        let chunk = match next {
            Ok(Some(Ok(chunk))) => chunk,
            _ => break,
        };
        let remaining = config.max_response_bytes - body.len();
        let take = remaining.min(chunk.len());
        body.extend_from_slice(&chunk[..take]);
        if take < chunk.len() {
            break;
        }
    }
    HttpError::Status {
        status,
        body: HttpErrorBody::new(body),
    }
}

type ResponseStream = Pin<Box<dyn Stream<Item = Result<Bytes, reqwest::Error>> + Send>>;

struct ReqwestByteStream {
    stream: Option<ResponseStream>,
    max_bytes: usize,
    closed: bool,
}

impl ReqwestByteStream {
    fn new<S>(stream: S, max_bytes: usize) -> Self
    where
        S: Stream<Item = Result<Bytes, reqwest::Error>> + Send + 'static,
    {
        Self {
            stream: Some(Box::pin(stream)),
            max_bytes,
            closed: false,
        }
    }
}

#[async_trait]
impl ByteStream for ReqwestByteStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError> {
        if self.closed {
            return Err(HttpError::Closed);
        }
        let stream = self.stream.as_mut().ok_or(HttpError::Closed)?;
        match stream.next().await {
            None => {
                self.closed = true;
                self.stream = None;
                Ok(None)
            }
            Some(Err(_)) => {
                self.closed = true;
                self.stream = None;
                Err(HttpError::Request {
                    operation: "stream read",
                })
            }
            Some(Ok(chunk)) => {
                if chunk.len() > self.max_bytes {
                    self.closed = true;
                    self.stream = None;
                    return Err(HttpError::BodyTooLarge {
                        kind: "response body",
                        limit: self.max_bytes,
                        observed: chunk.len(),
                    });
                }
                Ok(Some(chunk.to_vec()))
            }
        }
    }

    async fn close(&mut self) -> Result<(), HttpError> {
        self.closed = true;
        self.stream = None;
        Ok(())
    }
}

impl std::fmt::Debug for ReqwestByteStream {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ReqwestByteStream")
            .field("max_bytes", &self.max_bytes)
            .field("closed", &self.closed)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::ReqwestByteStream;
    use crate::ByteStream;
    use bytes::Bytes;
    use futures_util::stream;

    #[tokio::test]
    async fn stream_limit_applies_per_chunk_not_to_the_whole_stream() {
        let chunks = stream::iter([
            Ok(Bytes::from_static(b"1234")),
            Ok(Bytes::from_static(b"5678")),
        ]);
        let mut response = ReqwestByteStream::new(chunks, 4);
        assert_eq!(response.next_chunk().await.unwrap(), Some(b"1234".to_vec()));
        assert_eq!(response.next_chunk().await.unwrap(), Some(b"5678".to_vec()));
        assert_eq!(response.next_chunk().await.unwrap(), None);
    }
}
