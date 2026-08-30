use super::settings_state::SettingsState;

// Initialization and rendering must enumerate the same prompts or the pane can
// request a control that was never created.
pub(super) const PROMPT_OPERATIONS: &[(&str, &str)] = &[
    ("commitMessage", "Commit Messages"),
    ("pullRequestDetails", "Pull Request Details"),
    ("readingDiff", "Reading Diffs"),
    ("workspaceIdentity", "Workspace Identity"),
    ("speechMessage", "Speech Messages"),
];

pub(super) const GROUP_TITLES: [&str; PROMPT_OPERATIONS.len() + 1] = {
    let mut titles = ["Generation"; PROMPT_OPERATIONS.len() + 1];
    let mut index = 0;
    while index < PROMPT_OPERATIONS.len() {
        titles[index + 1] = PROMPT_OPERATIONS[index].1;
        index += 1;
    }
    titles
};

pub(super) fn instruction_key(operation: &str) -> String {
    format!("ai-instructions-{operation}")
}

pub(super) fn instruction_values(
    settings: &SettingsState,
) -> impl Iterator<Item = (String, String)> + '_ {
    PROMPT_OPERATIONS.iter().map(|(operation, _)| {
        (
            instruction_key(operation),
            settings
                .ai_assist_instructions_by_operation
                .get(*operation)
                .cloned()
                .unwrap_or_default(),
        )
    })
}

pub(super) struct AiAssistModel {
    pub id: &'static str,
    pub label: &'static str,
    pub thinking_levels: &'static [(&'static str, &'static str)],
    pub default_thinking: Option<&'static str>,
}

#[derive(Clone, Debug)]
pub(super) struct AiAssistModelChoice {
    pub id: String,
    pub label: String,
    pub thinking_levels: Vec<(String, String)>,
    pub default_thinking: Option<String>,
}

const AGENTS: &[(&str, &str)] = &[
    ("codex", "Codex"),
    ("claude", "Claude Code"),
    ("copilot", "GitHub Copilot"),
    ("cursor", "Cursor"),
    ("agy", "Antigravity"),
    ("opencode", "OpenCode"),
    ("opencode2", "OpenCode 2"),
    ("pi", "Pi"),
    ("amp", "Amp"),
    ("grok", "Grok Build"),
    ("fx", "fx"),
    ("custom", "Custom Command"),
];

const BASIC_THINKING: &[(&str, &str)] = &[("low", "Low"), ("medium", "Medium"), ("high", "High")];
const OPENAI_THINKING: &[(&str, &str)] = &[
    ("low", "Low"),
    ("medium", "Medium"),
    ("high", "High"),
    ("xhigh", "Extra High"),
];
const CLAUDE_THINKING: &[(&str, &str)] = &[
    ("low", "Low"),
    ("medium", "Medium"),
    ("high", "High"),
    ("xhigh", "Extra High"),
    ("max", "Max"),
];
const GROK_THINKING: &[(&str, &str)] = &[
    ("default", "Grok Default"),
    ("none", "None"),
    ("minimal", "Minimal"),
    ("low", "Low"),
    ("medium", "Medium"),
    ("high", "High"),
    ("xhigh", "Extra High"),
];

const CLAUDE_MODELS: &[AiAssistModel] = &[
    model("haiku", "Haiku", &[], None),
    model("sonnet", "Sonnet", CLAUDE_THINKING, Some("low")),
    model("opus", "Opus", CLAUDE_THINKING, Some("low")),
];
const CODEX_MODELS: &[AiAssistModel] = &[
    model("gpt-5.5", "GPT-5.5", OPENAI_THINKING, Some("low")),
    model("gpt-5.4", "GPT-5.4", OPENAI_THINKING, Some("low")),
    model("gpt-5.4-mini", "GPT-5.4 Mini", OPENAI_THINKING, Some("low")),
];
const COPILOT_MODELS: &[AiAssistModel] = &[
    model("auto", "Auto", &[], None),
    model("gpt-5.4", "GPT-5.4", OPENAI_THINKING, Some("low")),
    model("gpt-5.4-mini", "GPT-5.4 Mini", OPENAI_THINKING, Some("low")),
];
const CURSOR_MODELS: &[AiAssistModel] = &[model("auto", "Auto", &[], None)];
const AGY_MODELS: &[AiAssistModel] = &[
    model(
        "Gemini 3.5 Flash (Medium)",
        "Gemini 3.5 Flash (Medium)",
        &[],
        None,
    ),
    model(
        "Gemini 3.5 Flash (High)",
        "Gemini 3.5 Flash (High)",
        &[],
        None,
    ),
    model(
        "Gemini 3.5 Flash (Low)",
        "Gemini 3.5 Flash (Low)",
        &[],
        None,
    ),
];
const OPENCODE_MODELS: &[AiAssistModel] = &[model(
    "opencode/deepseek-v4-flash-free",
    "OpenCode DeepSeek V4 Flash Free",
    &[],
    None,
)];
const PI_MODELS: &[AiAssistModel] = &[model(
    "github-copilot/gpt-5.4-mini",
    "GitHub Copilot GPT-5.4 Mini",
    OPENAI_THINKING,
    Some("low"),
)];
const AMP_MODELS: &[AiAssistModel] = &[
    model("smart", "Smart", &[], None),
    model("rush", "Rush", &[], None),
    model("large", "Large", BASIC_THINKING, Some("low")),
    model("deep", "Deep", BASIC_THINKING, Some("low")),
];
const GROK_MODELS: &[AiAssistModel] = &[model(
    "grok-4.6",
    "Grok 4.6",
    GROK_THINKING,
    Some("default"),
)];

const fn model(
    id: &'static str,
    label: &'static str,
    thinking_levels: &'static [(&'static str, &'static str)],
    default_thinking: Option<&'static str>,
) -> AiAssistModel {
    AiAssistModel {
        id,
        label,
        thinking_levels,
        default_thinking,
    }
}

pub(super) fn agent_label(agent: &str) -> &'static str {
    AGENTS
        .iter()
        .find(|(key, _)| *key == agent)
        .map(|(_, label)| *label)
        .unwrap_or("Codex")
}

pub(super) fn agent_key(label: &str) -> Option<&'static str> {
    AGENTS
        .iter()
        .find(|(_, candidate)| *candidate == label)
        .map(|(key, _)| *key)
}

pub(super) fn agents() -> &'static [(&'static str, &'static str)] {
    AGENTS
}

pub(super) fn models_for(agent: &str) -> &'static [AiAssistModel] {
    match agent {
        "claude" => CLAUDE_MODELS,
        "codex" => CODEX_MODELS,
        "copilot" => COPILOT_MODELS,
        "cursor" => CURSOR_MODELS,
        "agy" => AGY_MODELS,
        "opencode" | "opencode2" => OPENCODE_MODELS,
        "pi" => PI_MODELS,
        "amp" => AMP_MODELS,
        "grok" => GROK_MODELS,
        "fx" => &[],
        _ => &[],
    }
}

pub(super) fn default_model(agent: &str) -> &'static str {
    match agent {
        "claude" => "sonnet",
        "codex" => "gpt-5.5",
        "copilot" => "gpt-5.4",
        "cursor" => "auto",
        // An empty model lets AGY use its own configured/default model.
        "agy" => "",
        "opencode" | "opencode2" => "opencode/deepseek-v4-flash-free",
        "pi" => "github-copilot/gpt-5.4-mini",
        "amp" => "smart",
        "grok" => "grok-4.6",
        "fx" => "",
        _ => "",
    }
}

pub(super) fn model_choices(settings: &SettingsState, agent: &str) -> Vec<AiAssistModelChoice> {
    let mut models = models_for(agent)
        .iter()
        .map(|model| AiAssistModelChoice {
            id: model.id.to_string(),
            label: model.label.to_string(),
            thinking_levels: model
                .thinking_levels
                .iter()
                .map(|(id, label)| ((*id).to_string(), (*label).to_string()))
                .collect(),
            default_thinking: model.default_thinking.map(str::to_string),
        })
        .collect::<Vec<_>>();
    if let Some(discovered) = settings.ai_assist_discovered_models_by_agent.get(agent) {
        for discovered in discovered {
            let choice = AiAssistModelChoice {
                id: discovered.id.clone(),
                label: discovered.label.clone(),
                thinking_levels: discovered
                    .thinking_levels
                    .iter()
                    .map(|level| (level.id.clone(), level.label.clone()))
                    .collect(),
                default_thinking: discovered.default_thinking_level.clone(),
            };
            if let Some(existing) = models.iter_mut().find(|model| model.id == choice.id) {
                *existing = choice;
            } else {
                models.push(choice);
            }
        }
    }
    models
}

pub(super) fn selected_model_id(settings: &SettingsState, agent: &str) -> String {
    settings
        .ai_assist_selected_model_by_agent
        .get(agent)
        .cloned()
        .or_else(|| {
            settings
                .ai_assist_discovered_default_model_by_agent
                .get(agent)
                .cloned()
        })
        .unwrap_or_else(|| default_model(agent).to_string())
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{
        instruction_key, instruction_values, SettingsState, GROUP_TITLES, PROMPT_OPERATIONS,
    };

    #[test]
    fn ai_assist_initializes_instructions_for_every_rendered_prompt() {
        let settings = SettingsState::default();
        let values = instruction_values(&settings).collect::<BTreeMap<_, _>>();
        assert_eq!(values.len(), 5);
        for operation in [
            "commitMessage",
            "pullRequestDetails",
            "readingDiff",
            "workspaceIdentity",
            "speechMessage",
        ] {
            assert_eq!(
                values.get(&instruction_key(operation)),
                Some(&String::new())
            );
        }
    }

    #[test]
    fn ai_assist_instruction_fields_preserve_saved_multiline_text() {
        let mut settings = SettingsState::default();
        for &(operation, _) in PROMPT_OPERATIONS {
            settings.ai_assist_instructions_by_operation.insert(
                operation.to_owned(),
                format!("Guía para {operation}\nMantén el contexto."),
            );
        }
        let mut restored = SettingsState::default();
        restored.apply_runtime_settings(
            &serde_json::json!({"aiTextGeneration": settings.runtime_ai_assist_payload()}),
        );
        for (key, value) in instruction_values(&restored) {
            let operation = key.strip_prefix("ai-instructions-").unwrap();
            assert_eq!(
                value,
                settings.ai_assist_instructions_by_operation[operation]
            );
        }
    }

    #[test]
    fn ai_assist_navigation_includes_every_prompt_in_render_order() {
        assert_eq!(GROUP_TITLES[0], "Generation");
        assert_eq!(GROUP_TITLES.last(), Some(&"Speech Messages"));
        for (index, &(_, title)) in PROMPT_OPERATIONS.iter().enumerate() {
            assert_eq!(GROUP_TITLES[index + 1], title);
        }
    }
}
