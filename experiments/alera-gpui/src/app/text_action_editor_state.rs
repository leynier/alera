use std::collections::BTreeMap;

use super::{TextActionSetting, ai_assist_settings_catalog as catalog, settings_state::SettingsState};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum TextActionField { Agent, Model, Reasoning }

impl TextActionField {
    pub fn index(self) -> usize { match self { Self::Agent => 0, Self::Model => 1, Self::Reasoning => 2 } }
    pub fn label(self) -> &'static str { match self { Self::Agent => "Agent", Self::Model => "Model", Self::Reasoning => "Reasoning" } }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct TextActionMenu {
    pub epoch: u64,
    pub action_id: String,
    pub field: TextActionField,
    pub agent: String,
    pub model: String,
}

pub(super) struct TextActionChoice { pub value: Option<String>, pub label: String }

#[derive(Clone, Debug)]
pub(super) struct TextActionDraft {
    pub enabled: bool,
    pub agent: Option<String>,
    pub model: Option<String>,
    pub reasoning: BTreeMap<String, String>,
}

impl Default for TextActionDraft {
    fn default() -> Self { Self { enabled: true, agent: None, model: None, reasoning: BTreeMap::new() } }
}

impl From<&TextActionSetting> for TextActionDraft {
    fn from(action: &TextActionSetting) -> Self {
        Self { enabled: action.enabled, agent: action.agent_override.clone(), model: action.model_override.clone(), reasoning: action.reasoning_by_model.clone() }
    }
}

impl TextActionDraft {
    pub fn agent<'a>(&'a self, settings: &'a SettingsState) -> &'a str {
        self.agent.as_deref().unwrap_or(&settings.ai_assist_agent)
    }

    pub fn model_id(&self, settings: &SettingsState) -> String {
        self.model.clone().filter(|id| !id.trim().is_empty()).unwrap_or_else(|| catalog::selected_model_id(settings, self.agent(settings)))
    }

    pub fn model(&self, settings: &SettingsState) -> catalog::AiAssistModelChoice {
        let id = self.model_id(settings);
        catalog::model_choices(settings, self.agent(settings)).into_iter().find(|model| model.id == id)
            .unwrap_or_else(|| catalog::AiAssistModelChoice { label: id.clone(), id, thinking_levels: Vec::new(), default_thinking: None })
    }

    pub fn value(&self, field: TextActionField, settings: &SettingsState) -> Option<String> {
        match field { TextActionField::Agent => self.agent.clone(), TextActionField::Model => self.model.clone(), TextActionField::Reasoning => self.reasoning.get(&self.model_id(settings)).cloned() }
    }

    pub fn choices(&self, field: TextActionField, settings: &SettingsState) -> Vec<TextActionChoice> {
        let (global, candidates) = match field {
            TextActionField::Agent => (
                format!("Global ({})", catalog::agent_label(&settings.ai_assist_agent)),
                catalog::agents().iter().map(|(id, label)| ((*id).to_owned(), (*label).to_owned())).collect::<Vec<_>>(),
            ),
            TextActionField::Model => (
                format!("Global ({})", catalog::selected_model_id(settings, self.agent(settings))),
                catalog::model_choices(settings, self.agent(settings)).into_iter().map(|model| (model.id, model.label)).collect(),
            ),
            TextActionField::Reasoning => {
                let model = self.model(settings);
                let inherited = settings.ai_assist_selected_thinking_by_model.get(&model.id).cloned()
                    .or(model.default_thinking).or_else(|| model.thinking_levels.first().map(|(id, _)| id.clone()));
                let label = model.thinking_levels.iter().find(|(id, _)| Some(id) == inherited.as_ref()).map(|(_, label)| label);
                (label.map_or_else(|| "Global".to_owned(), |label| format!("Global ({label})")), model.thinking_levels)
            }
        };
        let mut choices = vec![TextActionChoice { value: None, label: global }];
        choices.extend(candidates.into_iter().map(|(value, label)| TextActionChoice { value: Some(value), label }));
        if let Some(value) = self.value(field, settings) {
            if !choices.iter().any(|choice| choice.value.as_ref() == Some(&value)) {
                choices.push(TextActionChoice { label: value.clone(), value: Some(value) });
            }
        }
        choices
    }

    pub fn label(&self, field: TextActionField, settings: &SettingsState) -> String {
        let value = self.value(field, settings);
        self.choices(field, settings).into_iter().find(|choice| choice.value == value).map(|choice| choice.label).unwrap_or_default()
    }

    pub fn choose(&mut self, field: TextActionField, value: Option<String>, settings: &SettingsState) -> bool {
        if !self.choices(field, settings).iter().any(|choice| choice.value == value) { return false; }
        match field {
            TextActionField::Agent => { self.agent = value; self.model = None; }
            TextActionField::Model => self.model = value,
            TextActionField::Reasoning => {
                self.reasoning = super::text_action_edits::reasoning_after_edit(std::mem::take(&mut self.reasoning), &self.model_id(settings), value.as_deref().unwrap_or_default());
            }
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_action_draft_inherits_and_preserves_reasoning_across_model_changes() {
        let settings = SettingsState::default();
        let mut draft = TextActionDraft::default();
        assert_eq!(draft.label(TextActionField::Agent, &settings), "Global (Codex)");
        assert!(draft.enabled);
        let first = draft.model_id(&settings);
        assert!(draft.choose(TextActionField::Reasoning, Some("high".into()), &settings));
        assert!(draft.choose(TextActionField::Model, Some("gpt-5.4".into()), &settings));
        assert!(draft.choose(TextActionField::Reasoning, Some("low".into()), &settings));
        assert_eq!(draft.reasoning[&first], "high");
        assert!(draft.choose(TextActionField::Reasoning, None, &settings));
        assert!(!draft.reasoning.contains_key("gpt-5.4"));
        assert!(draft.choose(TextActionField::Agent, Some("claude".into()), &settings));
        assert!(draft.model.is_none());
        assert_eq!(draft.reasoning[&first], "high");
        assert!(!draft.choose(TextActionField::Agent, Some("not-an-agent".into()), &settings));
    }

    #[test]
    fn text_action_reopened_menu_has_a_new_callback_identity() {
        let original = TextActionMenu { epoch: 1, action_id: "a".into(), field: TextActionField::Model, agent: "codex".into(), model: "gpt-5.5".into() };
        let reopened = TextActionMenu { epoch: 3, ..original.clone() };
        assert_ne!(original, reopened);
    }
}
