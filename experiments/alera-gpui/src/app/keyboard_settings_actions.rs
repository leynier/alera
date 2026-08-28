use std::collections::BTreeSet;

use gpui::{Context, KeyBinding, KeyDownEvent, Keystroke, NoAction, Window};

use super::keyboard_actions::{canonical_to_gpui, key_binding_for_action};
use super::keyboard_settings::{
    defaults, effective_bindings, KeyboardBindingConflict, KEYBOARD_BINDINGS,
};
use super::AleraApp;

impl AleraApp {
    pub(super) fn keyboard_shortcut_for_keystroke(
        &self,
        keystroke: &Keystroke,
    ) -> Option<&'static super::keyboard_settings::KeyboardBindingDefinition> {
        let canonical = canonical_from_keystroke(keystroke)?;
        KEYBOARD_BINDINGS.iter().find(|definition| {
            effective_bindings(&self.settings_state, definition)
                .iter()
                .any(|binding| binding == &canonical)
        })
    }

    pub(super) fn set_keyboard_terminal_policy(
        &mut self,
        policy: &'static str,
        cx: &mut Context<Self>,
    ) {
        self.settings_state.keyboard_terminal_policy = policy.to_string();
        self.settings_store.save(&self.settings_state);
        self.persist_shared_flutter_settings(
            self.settings_state.shared_flutter_local_payload(),
            cx,
        );
        cx.notify();
    }

    pub(super) fn start_keyboard_recording(
        &mut self,
        id: &'static str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.keyboard_settings.recording_id == Some(id) {
            self.keyboard_settings.recording_id = None;
        } else {
            self.keyboard_settings.recording_id = Some(id);
            self.keyboard_settings.error = None;
            self.keyboard_settings.focus.focus(window, cx);
        }
        cx.notify();
    }

    pub(super) fn handle_keyboard_record_key(
        &mut self,
        event: &KeyDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.keyboard_settings.recording_id.is_none() {
            cx.propagate();
            return;
        }
        self.capture_keyboard_keystroke(&event.keystroke, window, cx);
    }

    pub(super) fn capture_keyboard_keystroke(
        &mut self,
        keystroke: &Keystroke,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(target_id) = self.keyboard_settings.recording_id else {
            cx.propagate();
            return;
        };
        cx.stop_propagation();
        if keystroke.key == "escape" {
            self.keyboard_settings.recording_id = None;
            self.keyboard_settings.error = None;
            cx.notify();
            return;
        }
        if is_modifier_key(&keystroke.key) {
            return;
        }
        let Some(chord) = canonical_from_keystroke(keystroke) else {
            self.keyboard_settings.error =
                Some((target_id, "Include At Least One Modifier Key.".into()));
            cx.notify();
            return;
        };
        self.keyboard_settings.recording_id = None;
        self.keyboard_settings.error = None;
        if let Some(owner_id) = self.find_keyboard_conflict(&chord, target_id) {
            self.keyboard_settings.conflict = Some(KeyboardBindingConflict {
                target_id,
                owner_id,
                chord,
            });
            cx.notify();
            return;
        }
        self.set_keyboard_bindings(target_id, Some(vec![chord]), cx);
    }

    pub(super) fn disable_keyboard_binding(&mut self, id: &'static str, cx: &mut Context<Self>) {
        self.set_keyboard_bindings(id, Some(Vec::new()), cx);
    }

    pub(super) fn reset_keyboard_binding(&mut self, id: &'static str, cx: &mut Context<Self>) {
        self.set_keyboard_bindings(id, None, cx);
    }

    pub(super) fn reset_keyboard_settings(&mut self, cx: &mut Context<Self>) {
        let ids = self
            .settings_state
            .keyboard_overrides
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        for id in ids {
            if let Some(definition) = KEYBOARD_BINDINGS
                .iter()
                .find(|definition| definition.id == id)
            {
                let old = effective_bindings(&self.settings_state, definition);
                self.settings_state.keyboard_overrides.remove(&id);
                self.install_keyboard_binding_change(definition.id, old, cx);
            }
        }
        self.settings_state.keyboard_terminal_policy = "appFirst".to_string();
        self.settings_store.save(&self.settings_state);
        self.persist_shared_flutter_settings(
            self.settings_state.shared_flutter_local_payload(),
            cx,
        );
        self.keyboard_settings.recording_id = None;
        self.keyboard_settings.error = None;
        self.keyboard_settings.conflict = None;
        cx.notify();
    }

    pub(super) fn cancel_keyboard_conflict(&mut self, cx: &mut Context<Self>) {
        self.keyboard_settings.conflict = None;
        cx.notify();
    }

    pub(super) fn confirm_keyboard_conflict(&mut self, cx: &mut Context<Self>) {
        let Some(conflict) = self.keyboard_settings.conflict.take() else {
            return;
        };
        let Some(owner) = KEYBOARD_BINDINGS
            .iter()
            .find(|definition| definition.id == conflict.owner_id)
        else {
            return;
        };
        let owner_bindings = effective_bindings(&self.settings_state, owner)
            .into_iter()
            .filter(|binding| binding != &conflict.chord)
            .collect::<Vec<_>>();
        self.set_keyboard_bindings(conflict.owner_id, Some(owner_bindings), cx);
        self.set_keyboard_bindings(conflict.target_id, Some(vec![conflict.chord]), cx);
    }

    pub(super) fn apply_saved_keyboard_overrides(&mut self, cx: &mut Context<Self>) {
        let ids = self
            .settings_state
            .keyboard_overrides
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        for id in ids {
            let Some(definition) = KEYBOARD_BINDINGS
                .iter()
                .find(|definition| definition.id == id)
            else {
                continue;
            };
            self.install_keyboard_binding_change(definition.id, defaults(definition), cx);
        }
    }

    fn set_keyboard_bindings(
        &mut self,
        id: &'static str,
        bindings: Option<Vec<String>>,
        cx: &mut Context<Self>,
    ) {
        let Some(definition) = KEYBOARD_BINDINGS
            .iter()
            .find(|definition| definition.id == id)
        else {
            return;
        };
        let old = effective_bindings(&self.settings_state, definition);
        match bindings {
            Some(bindings) => {
                self.settings_state
                    .keyboard_overrides
                    .insert(id.to_string(), bindings);
            }
            None => {
                self.settings_state.keyboard_overrides.remove(id);
            }
        }
        self.settings_store.save(&self.settings_state);
        self.persist_shared_flutter_settings(
            self.settings_state.shared_flutter_local_payload(),
            cx,
        );
        self.install_keyboard_binding_change(id, old, cx);
        cx.notify();
    }

    fn install_keyboard_binding_change(
        &self,
        id: &'static str,
        old_bindings: Vec<String>,
        cx: &mut Context<Self>,
    ) {
        let Some(definition) = KEYBOARD_BINDINGS
            .iter()
            .find(|definition| definition.id == id)
        else {
            return;
        };
        let current = effective_bindings(&self.settings_state, definition);
        let suppress = old_bindings
            .into_iter()
            .chain(defaults(definition))
            .filter_map(|canonical| canonical_to_gpui(&canonical))
            .collect::<BTreeSet<_>>();
        cx.bind_keys(
            suppress
                .into_iter()
                .map(|keystroke| KeyBinding::new(&keystroke, NoAction, None)),
        );
        cx.bind_keys(current.into_iter().filter_map(|canonical| {
            let keystroke = canonical_to_gpui(&canonical)?;
            key_binding_for_action(id, &keystroke)
        }));
    }

    fn find_keyboard_conflict(
        &self,
        chord: &str,
        excluding_id: &'static str,
    ) -> Option<&'static str> {
        KEYBOARD_BINDINGS
            .iter()
            .filter(|definition| definition.id != excluding_id)
            .find(|definition| {
                effective_bindings(&self.settings_state, definition)
                    .iter()
                    .any(|binding| binding == chord)
            })
            .map(|definition| definition.id)
    }
}

fn is_modifier_key(key: &str) -> bool {
    matches!(
        key,
        "shift" | "control" | "ctrl" | "alt" | "platform" | "cmd" | "super" | "fn"
    )
}

fn canonical_from_keystroke(keystroke: &Keystroke) -> Option<String> {
    let modifiers = keystroke.modifiers;
    let safe_bare = keystroke
        .key
        .strip_prefix('f')
        .and_then(|number| number.parse::<u8>().ok())
        .is_some_and(|number| (1..=24).contains(&number));
    if !modifiers.modified() && !safe_bare {
        return None;
    }
    let mut parts = Vec::new();
    if modifiers.platform {
        parts.push("Mod".to_string());
    }
    if modifiers.control {
        parts.push("Ctrl".to_string());
    }
    if modifiers.alt {
        parts.push("Alt".to_string());
    }
    if modifiers.shift {
        parts.push("Shift".to_string());
    }
    let key = match keystroke.key.as_str() {
        "," => "Comma".to_string(),
        "." => "Period".to_string(),
        "/" => "Slash".to_string(),
        "\\" => "Backslash".to_string(),
        "[" => "BracketLeft".to_string(),
        "]" => "BracketRight".to_string(),
        "-" => "Minus".to_string(),
        "=" => "Equal".to_string(),
        ";" => "Semicolon".to_string(),
        "'" => "Quote".to_string(),
        "`" => "Backquote".to_string(),
        key if key.len() == 1 => key.to_ascii_uppercase(),
        key => {
            let mut chars = key.chars();
            let first = chars.next()?.to_ascii_uppercase();
            format!("{first}{}", chars.as_str())
        }
    };
    parts.push(key);
    Some(parts.join("+"))
}

#[cfg(test)]
mod tests {
    use gpui::{Keystroke, Modifiers};

    use super::{canonical_from_keystroke, is_modifier_key};

    #[test]
    fn captured_mac_shortcuts_serialize_to_platform_neutral_mod() {
        let stroke = Keystroke {
            modifiers: Modifiers::command_shift(),
            key: "p".into(),
            key_char: None,
        };
        assert_eq!(
            canonical_from_keystroke(&stroke).as_deref(),
            Some("Mod+Shift+P")
        );
    }

    #[test]
    fn bare_letters_are_rejected_but_function_keys_are_supported() {
        assert!(canonical_from_keystroke(&Keystroke::parse("a").unwrap()).is_none());
        assert_eq!(
            canonical_from_keystroke(&Keystroke::parse("f4").unwrap()).as_deref(),
            Some("F4")
        );
        assert!(is_modifier_key("shift"));
    }
}
