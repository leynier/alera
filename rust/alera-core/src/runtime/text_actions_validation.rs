use super::{canonical_agent_type, RuntimeTextActionsSettings};

pub const AI_ASSIST_AGENTS: [&str; 13] = [
    "chatgpt",
    "codex",
    "claude",
    "copilot",
    "cursor",
    "agy",
    "opencode",
    "opencode-go",
    "pi",
    "amp",
    "grok",
    "fx",
    "custom",
];

/// Whether settings may name `agent` for AI Assist. The retired `opencode2` key
/// of older settings is accepted and runs as `opencode`.
pub fn is_ai_assist_agent(agent: &str) -> bool {
    AI_ASSIST_AGENTS.contains(&canonical_agent_type(agent.trim()))
}

pub fn validate_text_actions_settings(settings: &RuntimeTextActionsSettings) -> anyhow::Result<()> {
    let mut ids = std::collections::HashSet::new();
    let mut names = std::collections::HashSet::new();
    for action in &settings.actions {
        if action.id.trim().is_empty()
            || action.name.trim().is_empty()
            || action.prompt.trim().is_empty()
        {
            return Err(anyhow::anyhow!(
                "textActions actions require an id, name, and prompt.",
            ));
        }
        if !ids.insert(action.id.trim()) {
            return Err(anyhow::anyhow!("textActions action ids must be unique."));
        }
        if !names.insert(action.name.trim().to_ascii_lowercase()) {
            return Err(anyhow::anyhow!("textActions action names must be unique.",));
        }
        if action
            .agent_override
            .as_deref()
            .is_some_and(|agent| !is_ai_assist_agent(agent))
        {
            return Err(anyhow::anyhow!(
                "textActions contains an unsupported agent.",
            ));
        }
    }
    Ok(())
}
