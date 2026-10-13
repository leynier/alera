//! Provider-facing Rust client for the public OpenCode HTTP/SSE APIs.
//!
//! The crate models both the 1.x `@opencode-ai/sdk` routes and the 2.x
//! `@opencode/client` routes. It deliberately does not bundle the OpenCode
//! executable. Production applications supply the shared HTTP/process layer;
//! tests use the scripted transport exported here.

mod catalog;
mod client;
mod error;
mod forms;
mod mcp;
mod model;
mod server;
mod session;
mod sse;
mod transport;
mod wire;

pub use client::{ClientConfig, Generation, OpenCodeClient, SessionRequest};
pub use error::OpenCodeError;
pub use mcp::{normalized_mcp_server_name, McpServerConfig, PermissionRule};
pub use model::{OpenCodeEvent, OpenCodeModel, OpenCodeResponse, OpenCodeSession, RuntimeRequest};
pub use server::{OpenCodeServer, OpenCodeServerConfig, OpenCodeServerError};
pub use sse::{SseDecoder, SseFrame};
pub use transport::{
    ByteStream, ChunkStream, HttpClientConfig, HttpError, HttpRequest, HttpResponse, HttpTransport,
    MockHttpTransport, ReqwestTransport,
};

pub const LEGACY_SOURCE: &str = "opencode.sdk.v1";
pub const V2_SOURCE: &str = "opencode.sdk.v2";
