use super::settings_state::SettingsState;

pub(super) struct AiTextModel {
    pub id: &'static str,
    pub label: &'static str,
    pub thinking_levels: &'static [(&'static str, &'static str)],
    pub default_thinking: Option<&'static str>,
}

#[derive(Clone, Debug)]
pub(super) struct AiTextModelChoice {
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
    ("pi", "Pi"),
    ("amp", "Amp"),
    ("grok", "Grok Build"),
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

const CLAUDE_MODELS: &[AiTextModel] = &[
    model("haiku", "Haiku", &[], None),
    model("sonnet", "Sonnet", CLAUDE_THINKING, Some("low")),
    model("opus", "Opus", CLAUDE_THINKING, Some("low")),
];
const CODEX_MODELS: &[AiTextModel] = &[
    model("gpt-5.5", "GPT-5.5", OPENAI_THINKING, Some("low")),
    model("gpt-5.4", "GPT-5.4", OPENAI_THINKING, Some("low")),
    model("gpt-5.4-mini", "GPT-5.4 Mini", OPENAI_THINKING, Some("low")),
];
const COPILOT_MODELS: &[AiTextModel] = &[
    model("auto", "Auto", &[], None),
    model("gpt-5.4", "GPT-5.4", OPENAI_THINKING, Some("low")),
    model("gpt-5.4-mini", "GPT-5.4 Mini", OPENAI_THINKING, Some("low")),
];
const CURSOR_MODELS: &[AiTextModel] = &[model("auto", "Auto", &[], None)];
const AGY_MODELS: &[AiTextModel] = &[
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
const OPENCODE_MODELS: &[AiTextModel] = &[model(
    "opencode/deepseek-v4-flash-free",
    "OpenCode DeepSeek V4 Flash Free",
    &[],
    None,
)];
const PI_MODELS: &[AiTextModel] = &[model(
    "github-copilot/gpt-5.4-mini",
    "GitHub Copilot GPT-5.4 Mini",
    OPENAI_THINKING,
    Some("low"),
)];
const AMP_MODELS: &[AiTextModel] = &[
    model("smart", "Smart", &[], None),
    model("rush", "Rush", &[], None),
    model("large", "Large", BASIC_THINKING, Some("low")),
    model("deep", "Deep", BASIC_THINKING, Some("low")),
];
const GROK_MODELS: &[AiTextModel] = &[model(
    "grok-4.5",
    "Grok 4.5",
    GROK_THINKING,
    Some("default"),
)];

const fn model(
    id: &'static str,
    label: &'static str,
    thinking_levels: &'static [(&'static str, &'static str)],
    default_thinking: Option<&'static str>,
) -> AiTextModel {
    AiTextModel {
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

pub(super) fn models_for(agent: &str) -> &'static [AiTextModel] {
    match agent {
        "claude" => CLAUDE_MODELS,
        "codex" => CODEX_MODELS,
        "copilot" => COPILOT_MODELS,
        "cursor" => CURSOR_MODELS,
        "agy" => AGY_MODELS,
        "opencode" => OPENCODE_MODELS,
        "pi" => PI_MODELS,
        "amp" => AMP_MODELS,
        "grok" => GROK_MODELS,
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
        "opencode" => "opencode/deepseek-v4-flash-free",
        "pi" => "github-copilot/gpt-5.4-mini",
        "amp" => "smart",
        "grok" => "grok-4.5",
        _ => "",
    }
}

pub(super) fn model_choices(settings: &SettingsState, agent: &str) -> Vec<AiTextModelChoice> {
    let mut models = models_for(agent)
        .iter()
        .map(|model| AiTextModelChoice {
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
    if let Some(discovered) = settings.ai_text_discovered_models_by_agent.get(agent) {
        for discovered in discovered {
            let choice = AiTextModelChoice {
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
        .ai_text_selected_model_by_agent
        .get(agent)
        .cloned()
        .or_else(|| {
            settings
                .ai_text_discovered_default_model_by_agent
                .get(agent)
                .cloned()
        })
        .unwrap_or_else(|| default_model(agent).to_string())
}
