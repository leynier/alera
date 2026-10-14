//! Provider-facing Rust port of the public Muse MSP SDK surface.
//!
//! The crate owns JSON-RPC 2.0 framing, request correlation, command-id
//! replay protection, the initialize/initialized handshake, and the
//! version-aware session fold. It intentionally does not include the Muse
//! executable; callers provide a binary path or an injected transport.

mod actor;
mod client;
mod error;
mod session;
mod types;
mod wire;

pub use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig, TransportError};
pub use client::MuseClient;
pub use error::{MuseSdkError, Result};
pub use session::{ItemState, PendingApproval, PendingUserInput, SessionState};
pub use types::{
    CommandAck, InitializeResult, ModelInfo, MuseClientOptions, MuseFrame, PendingServerRequest,
    SessionSummary,
};

pub const SESSION_MCP_CAPABILITY: &str = "sessionMcp";
