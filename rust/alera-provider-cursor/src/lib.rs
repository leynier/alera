//! Cursor provider adapter over the public MIT `sdk.v1` bridge contract.

mod config;
mod mapping;
mod mcp;
mod provider;
mod skills;
mod stream_state;

pub use config::CursorProviderConfig;
pub use provider::reasoning_effort::{default_model_reasoning_effort, model_reasoning_efforts};
pub use provider::skill_invocation::rewrite_cursor_skill_mentions;
pub use provider::CursorProvider;
pub use skills::{discover_skills, discover_skills_lenient, skill_home_directory};
