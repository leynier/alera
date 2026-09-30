mod fx_herdr_receiver;
mod hook_receiver;
mod identity;
mod integration_config;
mod integration_hook_scripts;
mod integration_plugins;
mod launch_environment;
mod normalize;
mod normalize_claude_subagents;
mod normalize_grok;
mod normalize_lifecycle;

pub use fx_herdr_receiver::start_fx_herdr_receiver;
pub use hook_receiver::{start_hook_receiver, AgentHookEvent};
pub use identity::{resolve_agent_status_identity, AGENT_STATUS_IDENTITY_STALE_THRESHOLD};
pub use integration_config::{reconcile_agent_integrations, start_agent_integrations};
pub use launch_environment::prepare_launch_environment;
pub use normalize::normalize_hook_event;
pub use normalize_claude_subagents::normalize_claude_hook_event;
pub use normalize_lifecycle::{
    event_agent_pid, event_runs_in_multiplexer, event_turn_id, hook_event_closes_session,
    hook_event_resets_session, hook_event_starts_unsaved_session, hook_identifies_child_agent,
};
