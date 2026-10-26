//! UI-independent provider lifecycle and normalized runtime event contract.

mod command;
mod error;
mod event;
mod failure;
mod feedback;
mod goal;
mod mcp;
mod native_history;
mod native_task;
mod payload;
mod provider;
mod reasoning_effort;
mod request;
mod session;
mod skill;
mod skill_frontmatter;
mod skill_mention;
mod skill_order;
mod slash_command;
mod subagent;
mod validation;
mod workflow;

pub use command::*;
pub use error::*;
pub use event::*;
pub use failure::*;
pub use feedback::*;
pub use goal::*;
pub use mcp::*;
pub use native_history::*;
pub use native_task::*;
pub use payload::*;
pub use provider::*;
pub use reasoning_effort::*;
pub use request::*;
pub use session::*;
pub use skill::*;
pub use skill_frontmatter::*;
pub use skill_mention::*;
pub use skill_order::*;
pub use slash_command::*;
pub use subagent::*;
pub use workflow::*;

pub use alera_agent_transport as transport;
