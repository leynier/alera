use super::{RuntimeAiAssistSettings, AI_ASSIST_AGENTS};

pub fn validate_ai_assist_settings(settings: &RuntimeAiAssistSettings) -> anyhow::Result<()> {
    if !AI_ASSIST_AGENTS.contains(&settings.agent.trim()) {
        return Err(anyhow::anyhow!("AI Assist agent is unsupported."));
    }
    if settings
        .prompt_settings_by_operation
        .values()
        .filter_map(|prompt| prompt.agent.as_deref())
        .any(|agent| !AI_ASSIST_AGENTS.contains(&agent.trim()))
    {
        return Err(anyhow::anyhow!("AI Assist prompt agent is unsupported."));
    }
    let uses_custom_agent = settings.agent.trim() == "custom"
        || settings
            .prompt_settings_by_operation
            .values()
            .any(|prompt| {
                prompt
                    .agent
                    .as_deref()
                    .is_some_and(|agent| agent.trim() == "custom")
            });
    if uses_custom_agent && settings.custom_command.trim().is_empty() {
        return Err(anyhow::anyhow!(
            "AI Assist custom command is required for the custom agent.",
        ));
    }
    if !(10..=600).contains(&settings.timeout_seconds) {
        return Err(anyhow::anyhow!(
            "AI Assist timeout must be between 10 and 600 seconds.",
        ));
    }
    Ok(())
}
