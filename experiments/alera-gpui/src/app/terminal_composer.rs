use std::collections::BTreeSet;

use gpui::{
    div, px, AppContext as _, Context, CursorStyle, Entity, KeyDownEvent, InteractiveElement as _,
    IntoElement, MouseButton, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::{InputEvent, Textarea, TextareaState};

use super::state_types::TextActionTarget;
use super::text_actions_execution::textarea_context_menu;
use super::{AleraApp, TextActionSetting};
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::terminal::KeyModifiers;
use crate::theme;

impl AleraApp {
    pub(super) fn ensure_terminal_composer_inputs(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let session_ids = self
            .snapshot
            .tabs
            .iter()
            .filter(|tab| tab.kind == "terminal")
            .map(super::terminal_surface::terminal_session_id)
            .map(str::to_owned)
            .collect::<BTreeSet<_>>();
        self.terminal_composer_inputs
            .retain(|session_id, _| session_ids.contains(session_id));
        self.terminal_composer_visible
            .retain(|session_id| session_ids.contains(session_id));
        if self
            .terminal_composer_menu_open
            .as_ref()
            .is_some_and(|session_id| !session_ids.contains(session_id))
        {
            self.terminal_composer_menu_open = None;
        }
        for session_id in session_ids {
            if self.terminal_composer_inputs.contains_key(&session_id) {
                continue;
            }
            let input = cx.new(|cx| {
                TextareaState::new(window, cx)
                    .placeholder("Write A Prompt For This Terminal")
                    .auto_grow(2, 6)
                    .soft_wrap(true)
            });
            self._subscriptions.push(cx.subscribe_in(
                &input,
                window,
                |_, _, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Change) {
                        cx.notify();
                    }
                },
            ));
            self.terminal_composer_inputs.insert(session_id, input);
        }
    }

    pub(super) fn on_toggle_terminal_composer(
        &mut self,
        _: &super::keyboard_actions::ToggleTerminalComposer,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = self.selected_terminal_session_id() else {
            cx.propagate();
            return;
        };
        self.toggle_terminal_composer(session_id, window, cx);
    }

    fn toggle_terminal_composer(
        &mut self,
        session_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.terminal_composer_inputs.contains_key(&session_id) {
            return;
        }
        if !self.terminal_composer_visible.remove(&session_id) {
            self.terminal_composer_visible.insert(session_id.clone());
            if let Some(input) = self.terminal_composer_inputs.get(&session_id) {
                input.update(cx, |input, cx| input.focus(window, cx));
            }
        } else {
            window.focus(&self.terminal_focus, cx);
        }
        self.terminal_composer_menu_open = None;
        cx.stop_propagation();
        cx.notify();
    }

    fn close_terminal_composer(&mut self, session_id: &str, window: &mut Window, cx: &mut Context<Self>) {
        if self.terminal_composer_visible.remove(session_id) {
            self.terminal_composer_menu_open = None;
            window.focus(&self.terminal_focus, cx);
            cx.notify();
        }
    }

    fn submit_terminal_composer(
        &mut self,
        session_id: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(input) = self.terminal_composer_inputs.get(session_id).cloned() else {
            return;
        };
        let prompt = input.read(cx).value().to_string();
        if prompt.trim().is_empty() {
            return;
        }
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        session.emulator.clear_restore_prompt_cleanup();
        session.emulator.clear_selection();
        let mut bytes = session.emulator.encode_paste(&prompt);
        bytes.extend(session.emulator.encode_key("enter", None, KeyModifiers::default()));
        self.write_terminal_bytes_for(session_id, bytes);
        input.update(cx, |input, cx| input.set_value("", window, cx));
        input.update(cx, |input, cx| input.focus(window, cx));
        self.reset_terminal_cursor_blink();
        self.terminal_composer_menu_open = None;
        cx.notify();
    }

    pub(super) fn render_terminal_composer(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> gpui::AnyElement {
        let Some(input) = self.terminal_composer_inputs.get(session_id).cloned() else {
            return div().into_any_element();
        };
        let actions = self
            .settings_state
            .text_actions
            .iter()
            .filter(|action| action.enabled)
            .cloned()
            .collect::<Vec<_>>();
        let has_selection = !input.read(cx).selected_range().is_empty();
        let ai_text_enabled = self.settings_state.ai_text_enabled;
        let actions_enabled = ai_text_enabled && has_selection && !actions.is_empty();
        let session_for_key = session_id.to_owned();
        let session_for_send = session_id.to_owned();
        let session_for_close = session_id.to_owned();
        let session_for_menu = session_id.to_owned();
        let session_for_text_menu = session_id.to_owned();
        let input_for_context_menu = input.clone();
        let menu_open = self.terminal_composer_menu_open.as_deref() == Some(session_id);
        let mut composer = div()
            .id("terminal-composer")
            .relative()
            .p_3()
            .rounded_xl()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_selected())
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .capture_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                let key = event.keystroke.key.as_str();
                if key.eq_ignore_ascii_case("escape") {
                    this.close_terminal_composer(&session_for_key, window, cx);
                    cx.stop_propagation();
                } else if key.eq_ignore_ascii_case("enter") && !event.keystroke.modifiers.shift {
                    this.submit_terminal_composer(&session_for_key, window, cx);
                    cx.stop_propagation();
                }
            }))
            .child(
                Textarea::new(&input)
                    .aria_label("Terminal Prompt Composer")
                    .bordered(false)
                    .h(px(92.0))
                    .context_menu({
                        let actions = actions.clone();
                        move |menu, _window, cx| {
                            textarea_context_menu(
                                menu,
                                input_for_context_menu.clone(),
                                actions.clone(),
                                ai_text_enabled,
                                cx,
                            )
                        }
                    }),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .mt_2()
                    .gap_2()
                    .child(
                        design_system::button(
                            "terminal-composer-text-actions",
                            "Text Actions",
                            ButtonKind::Text,
                            !actions_enabled,
                        )
                        .cursor(if actions_enabled {
                            CursorStyle::PointingHand
                        } else {
                            CursorStyle::Arrow
                        })
                        .on_click(cx.listener(move |this, _, _, cx| {
                            if actions_enabled {
                                if this.terminal_composer_menu_open.as_deref()
                                    == Some(session_for_text_menu.as_str())
                                {
                                    this.terminal_composer_menu_open = None;
                                } else {
                                    this.terminal_composer_menu_open =
                                        Some(session_for_text_menu.clone());
                                }
                                cx.notify();
                            }
                        }))
                        .child(icon(AleraIcon::Ai, 14.0, theme::text_muted()))
                        .child("Text Actions")
                        .child(icon(AleraIcon::ChevronDown, 14.0, theme::text_faint())),
                    )
                    .child(div().flex_1())
                    .child(
                        design_system::icon_button(
                            "terminal-composer-send",
                            "Send Prompt",
                            AleraIcon::Send,
                            !prompt_can_send(&input, cx),
                            32.0,
                            Some(theme::accent()),
                            None,
                        )
                        .on_click(cx.listener(move |this, _, window, cx| {
                            this.submit_terminal_composer(&session_for_send, window, cx);
                        })),
                    ),
            );
        if menu_open {
            composer = composer.child(self.render_terminal_composer_actions(
                &session_for_menu,
                actions,
                actions_enabled,
                cx,
            ));
        }
        let _ = session_for_close;
        composer.into_any_element()
    }

    fn render_terminal_composer_actions(
        &self,
        session_id: &str,
        actions: Vec<TextActionSetting>,
        enabled: bool,
        cx: &mut Context<Self>,
    ) -> gpui::AnyElement {
        let session_id = session_id.to_owned();
        div()
            .id("terminal-composer-actions")
            .absolute()
            .left(px(12.0))
            .bottom(px(48.0))
            .min_w(px(220.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_1()
            .role(Role::Menu)
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .children(actions.into_iter().map(|action| {
                let id = action.id.clone();
                let session_id = session_id.clone();
                div()
                    .id(gpui::SharedString::from(format!("terminal-composer-action-{}", action.id)))
                    .role(Role::MenuItem)
                    .cursor(if enabled { CursorStyle::PointingHand } else { CursorStyle::Arrow })
                    .px_2()
                    .py_2()
                    .rounded_md()
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(move |this, _, window, cx| {
                        if !enabled {
                            return;
                        }
                        let Some(input) = this.terminal_composer_inputs.get(&session_id).cloned() else {
                            return;
                        };
                        let captured_text = input.read(cx).value().to_string();
                        let selected_range = input.read(cx).selected_range();
                        let Some(workspace_path) = this.selected_source_control_path() else {
                            return;
                        };
                        this.terminal_composer_menu_open = None;
                        this.start_text_action(
                            id.clone(),
                            TextActionTarget::TerminalComposer {
                                session_id: session_id.clone(),
                            },
                            captured_text,
                            selected_range,
                            workspace_path,
                            window,
                            cx,
                        );
                    }))
                    .child(action.name)
            }))
            .into_any_element()
    }
}

fn prompt_can_send(input: &Entity<TextareaState>, cx: &Context<AleraApp>) -> bool {
    !input.read(cx).value().trim().is_empty()
}
