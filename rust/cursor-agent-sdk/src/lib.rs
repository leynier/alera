//! Rust client for Cursor's public `sdk.v1` bridge contract.
//!
//! The bridge embeds Cursor's proprietary TypeScript SDK. This crate only
//! implements the public MIT Connect contract and expects the bridge binary to
//! be supplied by the host.

mod client;
mod error;
mod framing;
mod mock;
mod models;
mod process;
mod transport;
mod types;

pub use client::{CursorClient, CursorClientConfig, CursorRunStream};
pub use error::CursorSdkError;
pub use framing::{encode_connect_frame, ConnectFrameDecoder, MAX_CONNECT_FRAME_BYTES};
pub use mock::MockBridgeTransport;
pub use models::*;
pub use process::{process_config, CursorBridge, CursorBridgeConfig};
pub use transport::{BridgeTransport, ByteStream, ReqwestBridgeTransport};
pub use types::*;
