//! OpenCode provider adapter for the shared Alera provider contract.
//!
//! This crate implements the provider-facing behavior of the upstream OpenCode
//! driver for its legacy 1.x HTTP API and 2.x HTTP/SSE API. The OpenCode
//! executable is an external dependency; callers inject the shared HTTP
//! transport and may use its managed-process layer for local `serve` hosts.

mod config;
mod events;
mod mcp;
mod part_events;
mod provider;
mod request_events;
mod runtime_response;
mod tool_events;

pub use alera_provider_protocol;
pub use config::{
    OpenCodeConfig, OpenCodeConfigSupport, OpenCodeGeneration, OpenCodeProviderConfig,
};
pub use opencode_agent_sdk;
pub use opencode_agent_sdk::{
    ByteStream, ChunkStream, HttpClientConfig, HttpRequest, HttpResponse, HttpTransport,
    MockHttpTransport, ReqwestTransport,
};
pub use provider::OpenCodeProvider;
