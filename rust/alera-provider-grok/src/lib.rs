//! Rust provider boundary for the Grok ACP agent.
//!
//! Grok is launched as `grok agent stdio` and is driven through the shared ACP
//! runtime. This crate owns only Grok's launch policy and provider flavor.

mod config;
mod provider;

pub use alera_provider_protocol;
pub use config::{grok_spawn_args, GrokAuthMethod, GrokProviderConfig};
pub use provider::GrokProvider;
