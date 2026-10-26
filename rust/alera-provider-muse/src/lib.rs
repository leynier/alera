//! Muse Session Protocol adapter for Alera.
//!
//! The external `muse serve` executable remains the provider runtime. This
//! crate ports the public MIT MSP client boundary into Rust and maps its
//! session, turn, item, approval, and user-input frames to the shared provider
//! contract.

mod config;
mod event_mapping;
mod events;
mod lifecycle;
mod provider;
mod responses;
mod session_mcp;

pub use config::MuseProviderConfig;
pub use provider::MuseProvider;

pub use alera_agent_transport::{JsonLineProcess, JsonTransport, MockTransport, ProcessConfig};
pub use alera_provider_protocol;
pub use muse_agent_sdk;
