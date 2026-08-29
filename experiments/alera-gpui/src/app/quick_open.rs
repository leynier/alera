use super::keyboard_settings::{KeyboardBindingDefinition, KEYBOARD_BINDINGS};
use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, KeyDownEvent, MouseButton, ParentElement as _, Role,
    SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::scroll::ScrollableElement as _;

const QUICK_OPEN_MAX_RESULTS: usize = 50;
#[derive(Clone, Copy)]
struct CommandPaletteMatch {
    definition: &'static KeyboardBindingDefinition,
    score: i32,
}

fn command_palette_matches(query: &str) -> Vec<CommandPaletteMatch> {
    let query = query.trim().to_ascii_lowercase();
    let mut matches = KEYBOARD_BINDINGS
        .iter()
        .filter_map(|definition| {
            let label = definition.label.to_ascii_lowercase();
            let description = definition.description.to_ascii_lowercase();
            let score = if query.is_empty() {
                0
            } else if label == query {
                100_000
            } else if label.starts_with(&query) {
                90_000
            } else if label.contains(&query) {
                80_000
            } else if description.contains(&query)
                || definition.id.to_ascii_lowercase().contains(&query)
            {
                60_000
            } else {
                let mut cursor = 0;
                let mut score = 1_000;
                for character in query.chars() {
                    let offset = label[cursor..].find(character)?;
                    let index = cursor + offset;
                    score += (index == cursor) as i32 * 20;
                    cursor = index + character.len_utf8();
                }
                score
            };
            Some(CommandPaletteMatch { definition, score })
        })
        .collect::<Vec<_>>();
    matches.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| left.definition.label.cmp(right.definition.label))
            .then_with(|| left.definition.id.cmp(right.definition.id))
    });
    matches.truncate(QUICK_OPEN_MAX_RESULTS);
    matches
}

impl AleraApp {
    pub(super) fn open_quick_open(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let Some(workspace) = self.snapshot.workspace(&workspace_id) else {
            return;
        };
        self.command_palette_open = false;
        self.quick_open_open = true;
        self.quick_open_loading = true;
        self.quick_open_error = None;
        self.quick_open_session = None;
        self.quick_open_matches.clear();
        self.quick_open_selected_index = 0;
        self.quick_open_generation = self.quick_open_generation.wrapping_add(1);
        let generation = self.quick_open_generation;
        self.quick_open_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.quick_open_input
            .update(cx, |input, cx| input.focus(window, cx));
        let workspace_path = workspace.path.clone();
        let (sender, receiver) = async_channel::bounded(1);
        std::thread::Builder::new()
            .name("alera-gpui-quick-open".to_owned())
            .spawn(move || {
                let result =
                    alera_native::api::workspace_files::start_workspace_quick_open_session(
                        workspace_path,
                    )
                    .map_err(|error| format!("{error:?}"));
                let _ = sender.send_blocking(result);
            })
            .ok();
        cx.spawn(async move |this, cx| {
            let result = receiver
                .recv()
                .await
                .unwrap_or_else(|_| Err("Quick Open worker stopped.".to_owned()));
            let _ = this.update(cx, |this, cx| {
                if generation != this.quick_open_generation || !this.quick_open_open {
                    return;
                }
                this.quick_open_loading = false;
                match result {
                    Ok(session) => {
                        this.quick_open_session = Some(session);
                        this.search_quick_open_session(cx);
                    }
                    Err(error) => this.quick_open_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn update_quick_open_query(&mut self, query: String, cx: &mut Context<Self>) {
        if !self.quick_open_open {
            return;
        }
        let _ = query;
        self.search_quick_open_session(cx);
    }

    fn search_quick_open_session(&mut self, cx: &mut Context<Self>) {
        let Some(session) = self.quick_open_session.clone() else {
            return;
        };
        let query = self.quick_open_input.read(cx).value().to_string();
        self.quick_open_generation = self.quick_open_generation.wrapping_add(1);
        let generation = self.quick_open_generation;
        self.quick_open_loading = true;
        self.quick_open_matches.clear();
        self.quick_open_selected_index = 0;
        let (sender, receiver) = async_channel::bounded(1);
        std::thread::Builder::new()
            .name("alera-gpui-quick-open-search".to_owned())
            .spawn(move || {
                let result =
                    alera_native::api::workspace_files::search_workspace_quick_open_session(
                        session,
                        query,
                        QUICK_OPEN_MAX_RESULTS as u32,
                    )
                    .map_err(|error| format!("{error:?}"));
                let _ = sender.send_blocking(result);
            })
            .ok();
        cx.spawn(async move |this, cx| {
            let result = receiver
                .recv()
                .await
                .unwrap_or_else(|_| Err("Quick Open search worker stopped.".to_owned()));
            let _ = this.update(cx, |this, cx| {
                if generation != this.quick_open_generation || !this.quick_open_open {
                    return;
                }
                this.quick_open_loading = false;
                match result {
                    Ok(matches) => this.quick_open_matches = matches,
                    Err(error) => this.quick_open_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn move_quick_open_selection(&mut self, delta: i32, cx: &mut Context<Self>) {
        if self.quick_open_matches.is_empty() {
            return;
        }
        let len = self.quick_open_matches.len() as i32;
        self.quick_open_selected_index =
            (self.quick_open_selected_index as i32 + delta).rem_euclid(len) as usize;
        cx.notify();
    }

    pub(super) fn execute_quick_open(&mut self, cx: &mut Context<Self>) {
        let Some(path) = self
            .quick_open_matches
            .get(self.quick_open_selected_index)
            .map(|item| item.relative_path.clone())
        else {
            return;
        };
        self.close_quick_open(cx);
        self.open_file_preview_tab(path, cx);
    }

    pub(super) fn close_quick_open(&mut self, cx: &mut Context<Self>) {
        if !self.quick_open_open {
            return;
        }
        self.quick_open_open = false;
        self.quick_open_loading = false;
        self.quick_open_generation = self.quick_open_generation.wrapping_add(1);
        if let Some(session) = self.quick_open_session.take() {
            std::thread::spawn(move || {
                alera_native::api::workspace_files::stop_workspace_quick_open_session(session);
            });
        }
        cx.notify();
    }

    pub(super) fn open_command_palette(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.quick_open_open = false;
        self.command_palette_open = true;
        self.command_palette_selected_index = 0;
        self.command_palette_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.command_palette_input
            .update(cx, |input, cx| input.focus(window, cx));
        cx.notify();
    }

    pub(super) fn update_command_palette_query(&mut self, _: String, cx: &mut Context<Self>) {
        if self.command_palette_open {
            self.command_palette_selected_index = 0;
            cx.notify();
        }
    }

    pub(super) fn move_command_palette_selection(&mut self, delta: i32, cx: &mut Context<Self>) {
        let matches = command_palette_matches(self.command_palette_input.read(cx).value().as_ref());
        if matches.is_empty() {
            return;
        }
        let len = matches.len() as i32;
        self.command_palette_selected_index =
            (self.command_palette_selected_index as i32 + delta).rem_euclid(len) as usize;
        cx.notify();
    }

    pub(super) fn execute_command_palette(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let matches = command_palette_matches(self.command_palette_input.read(cx).value().as_ref());
        let Some(selected) = matches.get(self.command_palette_selected_index) else {
            return;
        };
        let Some(action) = super::keyboard_actions::action_for_id(selected.definition.id) else {
            return;
        };
        self.close_command_palette(cx);
        window.dispatch_action(action, cx);
    }

    pub(super) fn close_command_palette(&mut self, cx: &mut Context<Self>) {
        if self.command_palette_open {
            self.command_palette_open = false;
            cx.notify();
        }
    }

    pub(super) fn render_quick_open_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        let input = self.quick_open_input.clone();
        let matches = self.quick_open_matches.clone();
        let selected = self.quick_open_selected_index;
        let loading = self.quick_open_loading;
        let error = self.quick_open_error.clone();
        let has_error = error.is_some();
        div()
            .id("quick-open-overlay")
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .flex()
            .items_start()
            .justify_center()
            .pt(px(82.0))
            .bg(theme::overlay_scrim())
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.close_quick_open(cx);
                }),
            )
            .child(
                design_system::dialog_shell("quick-open-dialog", "Quick Open", 640.0)
                    .w(px(640.0))
                    .h(px(520.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .capture_key_down(cx.listener(|this, event: &KeyDownEvent, _, cx| {
                        if event.keystroke.key.eq_ignore_ascii_case("escape") {
                            this.close_quick_open(cx);
                        } else if event.keystroke.key.eq_ignore_ascii_case("up") {
                            this.move_quick_open_selection(-1, cx);
                        } else if event.keystroke.key.eq_ignore_ascii_case("down") {
                            this.move_quick_open_selection(1, cx);
                        } else if event.keystroke.key.eq_ignore_ascii_case("enter") {
                            this.execute_quick_open(cx);
                        } else {
                            return;
                        }
                        cx.stop_propagation();
                    }))
                    .child(
                        design_system::text_field(&input)
                            .search()
                            .height(px(40.0))
                            .prefix(icon(AleraIcon::Search, 16.0, theme::text_muted())),
                    )
                    .child(
                        div()
                            .mt_3()
                            .flex_1()
                            .min_h_0()
                            .overflow_y_scrollbar()
                            .when(loading, |list| {
                                list.child(
                                    div()
                                        .p_4()
                                        .text_color(theme::text_muted())
                                        .child("Loading workspace files…"),
                                )
                            })
                            .when_some(error, |list, error| {
                                list.child(div().p_4().text_color(theme::danger()).child(error))
                            })
                            .when(!loading && matches.is_empty() && !has_error, |list| {
                                list.child(
                                    div()
                                        .p_4()
                                        .text_color(theme::text_muted())
                                        .child("No matching files."),
                                )
                            })
                            .children(matches.into_iter().enumerate().map(|(index, item)| {
                                let path = item.relative_path;
                                div()
                                    .id(SharedString::from(format!("quick-open-row-{index}")))
                                    .role(Role::ListBoxOption)
                                    .aria_label(path.clone())
                                    .aria_selected(index == selected)
                                    .px_3()
                                    .py_2()
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .when(index == selected, |row| row.bg(theme::accent_subtle()))
                                    .hover(|style| style.bg(theme::surface_selected()))
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.quick_open_selected_index = index;
                                        this.execute_quick_open(cx);
                                    }))
                                    .child(path)
                            })),
                    ),
            )
            .into_any_element()
    }

    pub(super) fn render_command_palette_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        let input = self.command_palette_input.clone();
        let matches = command_palette_matches(self.command_palette_input.read(cx).value().as_ref());
        let selected = self.command_palette_selected_index;
        div()
            .id("command-palette-overlay")
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .flex()
            .items_start()
            .justify_center()
            .pt(px(82.0))
            .bg(theme::overlay_scrim())
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.close_command_palette(cx);
                }),
            )
            .child(
                design_system::dialog_shell("command-palette-dialog", "Command Palette", 640.0)
                    .w(px(640.0))
                    .h(px(520.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .capture_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                        if event.keystroke.key.eq_ignore_ascii_case("escape") {
                            this.close_command_palette(cx);
                        } else if event.keystroke.key.eq_ignore_ascii_case("up") {
                            this.move_command_palette_selection(-1, cx);
                        } else if event.keystroke.key.eq_ignore_ascii_case("down") {
                            this.move_command_palette_selection(1, cx);
                        } else if event.keystroke.key.eq_ignore_ascii_case("enter") {
                            this.execute_command_palette(window, cx);
                        } else {
                            return;
                        }
                        cx.stop_propagation();
                    }))
                    .child(
                        design_system::text_field(&input)
                            .search()
                            .height(px(40.0))
                            .prefix(icon(AleraIcon::Search, 16.0, theme::text_muted())),
                    )
                    .child(
                        div()
                            .mt_3()
                            .flex_1()
                            .min_h_0()
                            .overflow_y_scrollbar()
                            .children(matches.into_iter().enumerate().map(|(index, item)| {
                                let label = item.definition.label;
                                let description = item.definition.description;
                                let id = item.definition.id;
                                div()
                                    .id(SharedString::from(format!("command-palette-row-{index}")))
                                    .role(Role::ListBoxOption)
                                    .aria_label(label)
                                    .aria_selected(index == selected)
                                    .px_3()
                                    .py_2()
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .when(index == selected, |row| row.bg(theme::accent_subtle()))
                                    .hover(|style| style.bg(theme::surface_selected()))
                                    .on_click(cx.listener(move |this, _, window, cx| {
                                        this.command_palette_selected_index = index;
                                        let Some(action) =
                                            super::keyboard_actions::action_for_id(id)
                                        else {
                                            return;
                                        };
                                        this.close_command_palette(cx);
                                        window.dispatch_action(action, cx);
                                    }))
                                    .child(
                                        div()
                                            .text_size(px(13.0))
                                            .font_weight(gpui::FontWeight::MEDIUM)
                                            .child(label),
                                    )
                                    .child(
                                        div()
                                            .mt_1()
                                            .text_size(px(11.0))
                                            .text_color(theme::text_muted())
                                            .child(description),
                                    )
                            })),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_size(px(11.0))
                            .text_color(theme::text_faint())
                            .child(
                                "Use Up and Down to navigate, Enter to run, or Escape to close.",
                            ),
                    ),
            )
            .into_any_element()
    }
}

#[cfg(test)]
mod tests {
    use super::command_palette_matches;

    #[test]
    fn command_palette_prefers_exact_label_matches() {
        let matches = command_palette_matches("quick open");
        assert_eq!(
            matches.first().map(|item| item.definition.id),
            Some("openQuickOpen")
        );
    }

    #[test]
    fn command_palette_keeps_fuzzy_labels_searchable() {
        assert!(command_palette_matches("cmdp")
            .iter()
            .any(|item| { item.definition.id == "openCommandPalette" }));
    }
}
