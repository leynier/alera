use std::collections::BTreeMap;
use std::fmt;

/// An HTTP request relative to a configured transport base URL.
#[derive(Clone, PartialEq, Eq)]
pub struct HttpRequest {
    /// HTTP method such as `GET` or `POST`.
    pub method: String,
    /// Relative path, optionally including a query string.
    pub path: String,
    /// Per-request headers. These override client defaults by name.
    pub headers: BTreeMap<String, String>,
    /// Request body bytes.
    pub body: Vec<u8>,
}

impl fmt::Debug for HttpRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpRequest")
            .field("method", &self.method)
            .field("path", &"<redacted>")
            .field("header_count", &self.headers.len())
            .field("body_len", &self.body.len())
            .finish()
    }
}

impl HttpRequest {
    /// Construct a request with no headers or body.
    pub fn new(method: impl Into<String>, path: impl Into<String>) -> Self {
        Self {
            method: method.into(),
            path: path.into(),
            headers: BTreeMap::new(),
            body: Vec::new(),
        }
    }
}

/// The bounded result of an HTTP request.
#[derive(Clone, PartialEq, Eq)]
pub struct HttpResponse {
    /// HTTP status code.
    pub status: u16,
    /// Response headers keyed by their lowercase wire names.
    pub headers: BTreeMap<String, String>,
    /// Response body bytes.
    pub body: Vec<u8>,
}

impl fmt::Debug for HttpResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpResponse")
            .field("status", &self.status)
            .field("header_count", &self.headers.len())
            .field("body_len", &self.body.len())
            .finish()
    }
}

impl HttpResponse {
    /// Construct a response fixture with no headers.
    pub fn new(status: u16, body: impl Into<Vec<u8>>) -> Self {
        Self {
            status,
            headers: BTreeMap::new(),
            body: body.into(),
        }
    }
}
