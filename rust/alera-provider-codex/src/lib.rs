//! Rust adapter for the Codex app-server JSON-lines protocol.
//!
//! The adapter keeps Codex's native thread, turn, item, and request ids in the
//! shared event envelope while exposing the caller-owned session identity to
//! the rest of Alera. A transport can be injected for deterministic tests;
//! production construction uses the bounded windowless child-process transport.

mod children;
mod config;
mod events;
mod failure;
mod history;
mod lineage;
mod mcp;
mod payloads;
mod policy;
mod provider;
mod reasoning_effort;
mod responses;
mod rpc;
mod session_approvals;
mod skills;
mod state;
mod wire;

pub use config::{CodexConfig, CodexProviderConfig};
pub use provider::CodexProvider;
pub use skills::probe_skills;

pub use alera_agent_transport::{JsonLineProcess, JsonTransport, MockTransport, ProcessConfig};
pub use alera_provider_protocol;
