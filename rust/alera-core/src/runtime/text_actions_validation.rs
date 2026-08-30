use super::RuntimeTextActionsSettings;

pub const AI_ASSIST_AGENTS: [&str; 12] = [
    "codex",
    "claude",
    "copilot",
    "cursor",
    "agy",
    "opencode",
    "opencode2",
    "pi",
    "amp",
    "grok",
    "fx",
    "custom",
];

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
            .is_some_and(|agent| !AI_ASSIST_AGENTS.contains(&agent.trim()))
        {
            return Err(anyhow::anyhow!(
                "textActions contains an unsupported agent.",
            ));
        }
    }
    Ok(())
}
