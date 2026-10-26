//! Rust provider boundary for the Grok ACP agent.
//!
//! Grok is launched as `grok agent stdio` and is driven through the shared ACP
//! runtime. This crate owns only Grok's launch policy and provider flavor.

mod config;
mod provider;
mod skill_invocation;
mod skills;

pub use alera_provider_protocol;
pub use config::{grok_spawn_args, GrokAuthMethod, GrokProviderConfig};
pub use provider::GrokProvider;
pub use skill_invocation::rewrite_leading_skill_mention;
pub use skills::{decode_inspect_skills, discover_skills};
