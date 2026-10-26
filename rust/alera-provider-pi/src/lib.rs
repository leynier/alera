//! Rust adapter for Pi's public `pi --mode rpc` JSONL protocol.
//!
//! Pi has no provider SDK to port. Pi owns its session files, extensions and
//! user configuration while the adapter speaks the RPC protocol over an
//! injected transport.

mod api;
mod commands;
mod config;
mod event_core;
mod events;
mod lifecycle;
mod mcp_extension;
mod payload;
mod policy;
mod provider;
mod rpc;
mod runtime;

pub use config::{PiConfig, PiProviderConfig};
pub use provider::PiProvider;
