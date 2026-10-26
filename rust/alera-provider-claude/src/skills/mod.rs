//! Claude Code skills: discovering them on disk and dispatching `$name`
//! mentions as the `/name` commands the CLI expands.

mod discovery;
mod dispatch;
mod environment;
mod frontmatter;
mod lenient_json;
mod paths;
mod plugins;
mod settings;

pub(crate) use discovery::discover;
pub use discovery::discover_skills;
pub use dispatch::{
    claude_user_message_content, plan_claude_skill_dispatch, user_invocable_skills,
    ClaudeSkillDispatch,
};
pub(crate) use environment::SkillEnvironment;
