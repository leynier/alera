use gpui::{Context, Window};
use uuid::Uuid;

use super::{AleraApp, TextActionSetting};

impl AleraApp {
    pub(super) fn new_text_action(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.text_actions_creating_new = true;
        self.text_actions_selected_id = Some(Uuid::new_v4().to_string());
        self.text_actions_error = None;
        self.text_actions_draft = Default::default();
        self.text_actions_menu = None;
        self.text_actions_name_input.update(cx, |input, cx| input.set_value("", window, cx));
        self.text_actions_prompt_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        cx.notify();
    }

    pub(super) fn select_text_action(
        &mut self,
        id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(action) = self
            .settings_state
            .text_actions
            .iter()
            .find(|action| action.id == id)
            .cloned()
        else {
            return;
        };
        self.text_actions_creating_new = false;
        self.text_actions_selected_id = Some(id);
        self.text_actions_error = None;
        self.seed_text_action_inputs(&action, window, cx);
        cx.notify();
    }

    fn seed_text_action_inputs(
        &mut self,
        action: &TextActionSetting,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.text_actions_draft = super::text_action_editor_state::TextActionDraft::from(action);
        self.text_actions_menu = None;
        self.text_actions_name_input
            .update(cx, |input, cx| input.set_value(&action.name, window, cx));
        self.text_actions_prompt_input
            .update(cx, |input, cx| input.set_value(&action.prompt, window, cx));
    }

    pub(super) fn toggle_text_action(&mut self, id: String, enabled: bool, cx: &mut Context<Self>) {
        if let Some(action) = self
            .settings_state
            .text_actions
            .iter_mut()
            .find(|action| action.id == id)
        {
            action.enabled = enabled;
            if self.text_actions_selected_id.as_deref() == Some(id.as_str()) {
                self.text_actions_draft.enabled = enabled;
            }
            self.persist_text_actions(cx);
        }
    }

    pub(super) fn duplicate_text_action(&mut self, id: String, window: &mut Window, cx: &mut Context<Self>) {
        let Some(source) = self
            .settings_state
            .text_actions
            .iter()
            .find(|action| action.id == id)
            .cloned()
        else {
            return;
        };
        let mut name = format!("{} Copy", source.name.trim());
        let names = self
            .settings_state
            .text_actions
            .iter()
            .map(|action| action.name.trim().to_lowercase())
            .collect::<std::collections::BTreeSet<_>>();
        let mut suffix = 2;
        while names.contains(&name.to_lowercase()) {
            name = format!("{} Copy {suffix}", source.name.trim());
            suffix += 1;
        }
        let clone = TextActionSetting {
            id: Uuid::new_v4().to_string(),
            name,
            ..source
        };
        let index = self
            .settings_state
            .text_actions
            .iter()
            .position(|action| action.id == id)
            .map(|index| index + 1)
            .unwrap_or(self.settings_state.text_actions.len());
        self.settings_state
            .text_actions
            .insert(index, clone.clone());
        self.text_actions_selected_id = Some(clone.id.clone());
        self.text_actions_creating_new = false;
        self.seed_text_action_inputs(&clone, window, cx);
        self.persist_text_actions(cx);
        cx.notify();
    }

    pub(super) fn save_text_action(&mut self, _window: &mut Window, cx: &mut Context<Self>) {
        if self.settings_state.loading { return; }
        let id = self
            .text_actions_selected_id
            .clone()
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let name = self.text_actions_name_input.read(cx).value().to_string();
        let prompt = self.text_actions_prompt_input.read(cx).value().to_string();
        let name = name.trim().to_owned();
        let prompt = prompt.trim().to_owned();
        if let Some(error) = super::text_action_edits::validation_error(&id, &name, &prompt,
            &self.settings_state.text_actions, (!self.text_actions_creating_new).then_some(id.as_str())) {
            self.text_actions_error = Some(error.into());
            cx.notify();
            return;
        }
        if !self.text_actions_creating_new && !self.settings_state.text_actions.iter().any(|action| action.id == id) {
            self.text_actions_error = Some("This text action is no longer available.".into());
            cx.notify();
            return;
        }
        let action = TextActionSetting {
            id: id.clone(),
            name,
            prompt,
            enabled: self.text_actions_draft.enabled,
            agent_override: self.text_actions_draft.agent.clone(),
            model_override: self.text_actions_draft.model.clone().filter(|id| !id.trim().is_empty()),
            reasoning_by_model: self.text_actions_draft.reasoning.clone(),
        };
        if self.text_actions_creating_new {
            self.settings_state.text_actions.push(action.clone());
        } else if let Some(existing) = self
            .settings_state
            .text_actions
            .iter_mut()
            .find(|candidate| candidate.id == id)
        {
            *existing = action.clone();
        } else {
            self.settings_state.text_actions.push(action.clone());
        }
        self.text_actions_creating_new = false;
        self.text_actions_selected_id = Some(id);
        self.text_actions_error = None;
        // Saving the same draft must not clear the input's undo history.
        self.persist_text_actions(cx);
        cx.notify();
    }

    pub(super) fn ensure_text_action_selected(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.show_settings_dialog || self.settings_pane != crate::activity::SettingsPane::TextActions
            || self.text_actions_creating_new || self.settings_state.loading { return; }
        if self.text_actions_selected_id.as_ref().is_some_and(|id| self.settings_state.text_actions.iter().any(|action| &action.id == id)) { return; }
        if let Some(action) = self.settings_state.text_actions.first().cloned() {
            self.select_text_action(action.id, window, cx);
        } else { self.text_actions_selected_id = None; }
    }

    pub(super) fn delete_text_action(&mut self, id: String, window: &mut Window, cx: &mut Context<Self>) {
        let was_selected = self.text_actions_selected_id.as_deref() == Some(id.as_str());
        self.settings_state
            .text_actions
            .retain(|action| action.id != id);
        if was_selected {
            self.text_actions_selected_id = None;
            self.text_actions_creating_new = false;
            if let Some(action) = self.settings_state.text_actions.first().cloned() { self.select_text_action(action.id, window, cx); }
        }
        self.persist_text_actions(cx);
        cx.notify();
    }

    pub(super) fn persist_text_actions(&mut self, cx: &mut Context<Self>) {
        self.persist_settings();
        self.update_runtime_setting(
            "textActions",
            self.settings_state.runtime_text_actions_payload(),
            cx,
        );
    }

}
