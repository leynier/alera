//! Claude Code adapter for Alera's provider protocol.
//!
//! The adapter keeps Claude's native session identifier separate from the
//! caller-owned thread and turn identifiers. It uses the Rust port of the
//! Claude Agent SDK for both process and injected transports.

mod provider;

pub use claude_agent_sdk::ClaudeAgentOptions;
pub use provider::{ClaudeProvider, ClaudeProviderConfig};
