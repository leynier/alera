//! Bounded HTTP and byte-stream transports shared by network-backed providers.
//!
//! The public transport traits are deliberately small so adapters can be tested
//! with [`MockHttpTransport`] without binding their protocol code to reqwest.

mod error;
mod mock;
mod request;
mod reqwest_transport;

pub use error::{HttpError, HttpErrorBody};
pub use mock::MockHttpTransport;
pub use request::{HttpRequest, HttpResponse};
pub use reqwest_transport::{
    HttpClientConfig, ReqwestTransport, DEFAULT_MAX_RESPONSE_BYTES, DEFAULT_REQUEST_TIMEOUT,
};

use async_trait::async_trait;

/// A bounded stream of response bytes.
#[async_trait]
pub trait ByteStream: Send {
    /// Read the next non-empty chunk, or `None` after EOF.
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError>;

    /// Release the underlying response and any associated resources.
    async fn close(&mut self) -> Result<(), HttpError>;
}

/// HTTP transport boundary used by provider adapters.
#[async_trait]
pub trait HttpTransport: Send + Sync {
    /// Execute a bounded request and collect its response body.
    async fn request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError>;

    /// Execute a request and expose its response body incrementally.
    async fn open_stream(&self, request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError>;
}
