use super::{
    is_ai_assist_agent, RuntimeAiAssistSettings, CHAT_GPT_SERVICE_TIER_DEFAULT,
    CHAT_GPT_SERVICE_TIER_FAST,
};

pub fn validate_ai_assist_settings(settings: &RuntimeAiAssistSettings) -> anyhow::Result<()> {
    if !is_ai_assist_agent(&settings.agent) {
        return Err(anyhow::anyhow!("AI Assist agent is unsupported."));
    }
    if settings
        .prompt_settings_by_operation
        .values()
        .filter_map(|prompt| prompt.agent.as_deref())
        .any(|agent| !is_ai_assist_agent(agent))
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
    if !matches!(
        settings
            .chat_gpt_service_tier
            .trim()
            .to_ascii_lowercase()
            .as_str(),
        CHAT_GPT_SERVICE_TIER_DEFAULT | CHAT_GPT_SERVICE_TIER_FAST
    ) {
        return Err(anyhow::anyhow!(
            "ChatGPT service tier must be default or fast.",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_the_retired_opencode2_agent_as_opencode() {
        let settings = RuntimeAiAssistSettings {
            agent: "opencode2".to_string(),
            ..RuntimeAiAssistSettings::default()
        };
        assert!(validate_ai_assist_settings(&settings).is_ok());
        assert!(!super::super::AI_ASSIST_AGENTS.contains(&"opencode2"));
    }

    #[test]
    fn accepts_direct_providers() {
        for agent in ["opencode-go", "chatgpt"] {
            assert!(super::super::AI_ASSIST_AGENTS.contains(&agent));
            let settings = RuntimeAiAssistSettings {
                agent: agent.to_string(),
                ..RuntimeAiAssistSettings::default()
            };
            assert!(validate_ai_assist_settings(&settings).is_ok());
        }
    }

    #[test]
    fn normalizes_chatgpt_service_tier_and_defaults_legacy_settings() {
        let parsed: RuntimeAiAssistSettings =
            serde_json::from_value(serde_json::json!({"chatGptServiceTier":" FAST "})).unwrap();
        assert_eq!(parsed.normalized().chat_gpt_service_tier, "fast");
        assert_eq!(
            RuntimeAiAssistSettings::default().chat_gpt_service_tier,
            "default"
        );
        let legacy: RuntimeAiAssistSettings =
            serde_json::from_value(serde_json::json!({})).unwrap();
        assert_eq!(legacy.chat_gpt_service_tier, "default");
    }

    #[test]
    fn rejects_unknown_chatgpt_service_tier_before_persistence() {
        let settings = RuntimeAiAssistSettings {
            chat_gpt_service_tier: "turbo".to_string(),
            ..RuntimeAiAssistSettings::default()
        };
        assert!(validate_ai_assist_settings(&settings).is_err());
    }
}
