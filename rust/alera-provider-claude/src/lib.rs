//! Claude Code adapter for Alera's provider protocol.
//!
//! The adapter keeps Claude's native session identifier separate from the
//! caller-owned thread and turn identifiers. It uses the Rust port of the
//! Claude Agent SDK for both process and injected transports.

mod provider;
mod skills;

pub use claude_agent_sdk::ClaudeAgentOptions;
pub use provider::{ClaudeProvider, ClaudeProviderConfig};
pub use skills::{
    claude_user_message_content, discover_skills, plan_claude_skill_dispatch,
    user_invocable_skills, ClaudeSkillDispatch,
};
