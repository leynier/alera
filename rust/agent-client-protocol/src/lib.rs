//! Lossless, bounded Rust client for the Agent Client Protocol (ACP).
//!
//! ACP is JSON-RPC 2.0 over newline-delimited JSON. The client keeps native
//! request ids and raw frames intact so provider adapters can expose requests
//! and future protocol variants without guessing at fields.

mod callbacks;
mod client;
mod error;
mod handler;
mod response_frame;
mod rpc;
mod schema;
mod session;

pub use client::{AcpClient, AcpClientState, PendingCallKind};
pub use error::AcpError;
pub use handler::{AcpClientRequestHandler, AcpRequestHandlerContext};
pub use rpc::{AcpIncoming, AcpRequestId, AcpResponse, RpcError, RpcRequest};
pub use schema::{
    AcpAuthMethod, AcpCapabilities, AcpInitializeResponse, AcpPromptResponse,
    AcpProtocolGeneration, AcpSessionResponse,
};

pub use alera_agent_transport as transport;
