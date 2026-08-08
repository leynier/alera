use std::collections::BTreeSet;

use base64::prelude::{Engine as _, BASE64_STANDARD};
use gpui::{
    canvas, div, prelude::FluentBuilder as _, AnyElement, ClipboardItem, Context, CursorStyle,
    ElementInputHandler, ExternalPaths, FontWeight, InteractiveElement as _, IntoElement as _,
    KeyDownEvent, Modifiers, MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent,
    ParentElement as _, Point, Rgba, ScrollWheelEvent, SharedString, Styled as _, Window,
};
use serde_json::{json, Value};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::model::WorkspaceTab;
use crate::terminal::{
    KeyModifiers, TerminalEmulator, TerminalPoint, TerminalSelectionKind, TerminalSession,
};
use crate::terminal_theme_catalog::terminal_theme_palette;
use crate::theme;

const TERMINAL_COLUMNS: usize = 100;
const TERMINAL_ROWS: usize = 30;

impl AleraApp {
    pub(super) fn ensure_selected_terminal(&mut self, cx: &mut Context<Self>) {
        let contexts = self.terminal_contexts();
        let expected = contexts
            .iter()
            .map(|context| context.0.clone())
            .collect::<BTreeSet<_>>();
        let stale = self
            .terminal_sessions
            .keys()
            .filter(|session_id| !expected.contains(*session_id))
            .cloned()
            .collect::<Vec<_>>();
        for session_id in stale {
            self.terminal_sessions.remove(&session_id);
            let bridge = self.bridge.clone();
            cx.spawn(async move |_, _| {
                let _ = bridge
                    .request("detach", json!({ "sessionId": session_id }))
                    .await;
            })
            .detach();
        }

        for (session_id, workspace_id, tab_id, working_directory) in contexts {
            if self.terminal_sessions.contains_key(&session_id) {
                continue;
            }
            self.terminal_sessions
                .insert(session_id.clone(), TerminalSession::new(session_id.clone()));
            let bridge = self.bridge.clone();
            let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
            cx.spawn(async move |this, cx| {
                let result = bridge
                    .request(
                        "createOrAttach",
                        json!({
                            "sessionId": session_id,
                            "workspaceId": workspace_id,
                            "tabId": tab_id,
                            "workingDirectory": working_directory,
                            "launch": {
                                "label": "Shell",
                                "shell": shell,
                                "arguments": [],
                                "environment": {
                                    "TERM": "xterm-256color",
                                    "COLORTERM": "truecolor",
                                },
                            },
                            "cols": TERMINAL_COLUMNS,
                            "rows": TERMINAL_ROWS,
                        }),
                    )
                    .await;
                let Some(this) = this.upgrade() else {
                    return;
                };
                let _ = this.update(cx, |this, cx| {
                    let Some(session) = this.terminal_sessions.get_mut(&session_id) else {
                        return;
                    };
                    session.attaching = false;
                    match result {
                        Ok(payload) => {
                            let columns = payload
                                .get("cols")
                                .and_then(Value::as_u64)
                                .map(|value| value as usize)
                                .unwrap_or(TERMINAL_COLUMNS);
                            let rows = payload
                                .get("rows")
                                .and_then(Value::as_u64)
                                .map(|value| value as usize)
                                .unwrap_or(TERMINAL_ROWS);
                            let mut emulator = TerminalEmulator::new(columns, rows);
                            session.running = payload
                                .get("running")
                                .and_then(Value::as_bool)
                                .unwrap_or(true);
                            if let Some(encoded) =
                                payload.get("snapshotBase64").and_then(Value::as_str)
                            {
                                match BASE64_STANDARD.decode(encoded) {
                                    Ok(bytes) => emulator.write(&bytes),
                                    Err(error) => session.error = Some(error.to_string()),
                                }
                            }
                            session.columns = columns;
                            session.rows = rows;
                            session.emulator = emulator;
                        }
                        Err(error) => session.error = Some(error),
                    }
                    cx.notify();
                });
            })
            .detach();
        }
    }

    fn terminal_contexts(&self) -> Vec<(String, String, String, String)> {
        let Some(workspace_id) = self.selected_workspace_id.as_deref() else {
            return Vec::new();
        };
        let Some(workspace) = self.snapshot.workspace(workspace_id) else {
            return Vec::new();
        };
        self.snapshot
            .tabs
            .iter()
            .filter(|tab| tab.kind == "terminal")
            .map(|tab| {
                (
                    terminal_session_id(tab).to_string(),
                    workspace.id.clone(),
                    tab.id.clone(),
                    workspace.path.clone(),
                )
            })
            .collect()
    }

    pub(super) fn handle_terminal_output(
        &mut self,
        session_id: &str,
        data: &[u8],
        cx: &mut Context<Self>,
    ) {
        let responses = {
            let Some(session) = self.terminal_sessions.get_mut(session_id) else {
                return;
            };
            session.emulator.write(data);
            session.emulator.take_pty_writes()
        };
        for response in responses {
            self.write_terminal_bytes_for(session_id, response);
        }
        self.reset_terminal_cursor_blink();
        cx.notify();
    }

    pub(super) fn handle_terminal_notification(
        &mut self,
        name: &str,
        payload: &Value,
        cx: &mut Context<Self>,
    ) {
        if name == "terminalDriverChanged" {
            self.handle_terminal_driver_changed(payload, cx);
            return;
        }
        let Some(session_id) = payload.get("sessionId").and_then(Value::as_str) else {
            return;
        };
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        match name {
            "exit" => {
                session.running = false;
                session.error = Some("The Terminal Process Exited.".to_owned());
            }
            "outputResyncRequired" => {
                let bridge = self.bridge.clone();
                let session_id = session_id.to_string();
                cx.spawn(async move |_, _| {
                    let _ = bridge
                        .request(
                            "setOutputPaused",
                            json!({ "sessionId": session_id, "paused": false }),
                        )
                        .await;
                })
                .detach();
            }
            _ => return,
        }
        cx.notify();
    }

    fn recover_terminal_session(
        &mut self,
        session_id: String,
        restart: bool,
        cx: &mut Context<Self>,
    ) {
        let Some((_, workspace_id, tab_id, working_directory)) = self
            .terminal_contexts()
            .into_iter()
            .find(|context| context.0 == session_id)
        else {
            return;
        };
        let Some(session) = self.terminal_sessions.get_mut(&session_id) else {
            return;
        };
        if session.attaching {
            return;
        }
        session.attaching = true;
        session.error = None;
        let columns = session.columns;
        let rows = session.rows;
        self.terminal_restart_confirmation = None;
        let bridge = self.bridge.clone();
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_owned());
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    if restart {
                        "terminal.restart"
                    } else {
                        "createOrAttach"
                    },
                    json!({
                        "sessionId": session_id.clone(),
                        "workspaceId": workspace_id,
                        "tabId": tab_id,
                        "workingDirectory": working_directory,
                        "launch": {
                            "label": "Shell",
                            "shell": shell,
                            "arguments": [],
                            "environment": {
                                "TERM": "xterm-256color",
                                "COLORTERM": "truecolor",
                            },
                        },
                        "cols": columns,
                        "rows": rows,
                    }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                let Some(session) = this.terminal_sessions.get_mut(&session_id) else {
                    return;
                };
                session.attaching = false;
                match result {
                    Ok(payload) => {
                        let columns = payload
                            .get("cols")
                            .and_then(Value::as_u64)
                            .map(|value| value as usize)
                            .unwrap_or(columns);
                        let rows = payload
                            .get("rows")
                            .and_then(Value::as_u64)
                            .map(|value| value as usize)
                            .unwrap_or(rows);
                        let mut emulator = TerminalEmulator::new(columns, rows);
                        if let Some(encoded) = payload.get("snapshotBase64").and_then(Value::as_str)
                        {
                            match BASE64_STANDARD.decode(encoded) {
                                Ok(bytes) => emulator.write(&bytes),
                                Err(error) => {
                                    session.error = Some(error.to_string());
                                    cx.notify();
                                    return;
                                }
                            }
                        }
                        session.columns = columns;
                        session.rows = rows;
                        session.emulator = emulator;
                        session.running = payload
                            .get("running")
                            .and_then(Value::as_bool)
                            .unwrap_or(true);
                        session.error =
                            (!session.running).then(|| "The Terminal Process Exited.".to_owned());
                    }
                    Err(error) => session.error = Some(error),
                }
                this.reset_terminal_cursor_blink();
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn refresh_terminal_viewport(&self, session_id: String, cx: &mut Context<Self>) {
        let Some(session) = self.terminal_sessions.get(&session_id) else {
            return;
        };
        let columns = session.columns;
        let rows = session.rows;
        let pulse_columns = if columns > 2 {
            columns - 1
        } else {
            columns + 1
        };
        let bridge = self.bridge.clone();
        cx.spawn(async move |_, _| {
            let _ = bridge
                .request(
                    "resize",
                    json!({
                        "sessionId": session_id.clone(),
                        "cols": pulse_columns,
                        "rows": rows,
                    }),
                )
                .await;
            let _ = bridge
                .request(
                    "resize",
                    json!({
                        "sessionId": session_id,
                        "cols": columns,
                        "rows": rows,
                    }),
                )
                .await;
        })
        .detach();
    }

    fn handle_terminal_key(
        &mut self,
        event: &KeyDownEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = self.selected_terminal_session_id() else {
            return;
        };
        self.reset_terminal_cursor_blink();
        let Some(session) = self.terminal_sessions.get(&session_id) else {
            return;
        };
        let modifiers = event.keystroke.modifiers;
        let copy_selection = event.keystroke.key.eq_ignore_ascii_case("c")
            && (modifiers.platform || modifiers.control && modifiers.shift);
        if copy_selection {
            if let Some(text) = session
                .emulator
                .selected_text()
                .filter(|text| !text.is_empty())
            {
                cx.write_to_clipboard(ClipboardItem::new_string(text));
                cx.stop_propagation();
            }
            return;
        }
        if self.is_terminal_mobile_driven(&session_id) {
            cx.stop_propagation();
            return;
        }
        if modifiers.control && modifiers.shift && event.keystroke.key.eq_ignore_ascii_case("v") {
            if let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) {
                let bytes = session.emulator.encode_paste(&text);
                self.terminal_input_text.clear();
                self.terminal_marked_text = None;
                self.write_terminal_bytes_for(&session_id, bytes);
                cx.stop_propagation();
            }
            return;
        }
        // Printable input must be left to the platform text input handler. On macOS this is
        // what lets the native input context keep a dead key marked until the next key arrives
        // (`'` + `a` becomes `á` instead of two independent bytes). The handler also owns IME
        // replacement ranges, so forwarding these keystrokes directly would bypass composition.
        if terminal_key_uses_text_input(
            &event.keystroke.key,
            event.keystroke.key_char.as_deref(),
            KeyModifiers {
                control: modifiers.control,
                alt: modifiers.alt,
                shift: modifiers.shift,
                platform: modifiers.platform,
                function: modifiers.function,
            },
        ) {
            return;
        }
        let bytes = session.emulator.encode_key(
            &event.keystroke.key,
            event.keystroke.key_char.as_deref(),
            KeyModifiers {
                control: modifiers.control,
                alt: modifiers.alt,
                shift: modifiers.shift,
                platform: modifiers.platform,
                function: modifiers.function,
            },
        );
        if bytes.is_empty() {
            return;
        }
        if let Some(session) = self.terminal_sessions.get_mut(&session_id) {
            session.emulator.clear_selection();
        }
        self.write_terminal_bytes_for(&session_id, bytes);
        cx.stop_propagation();
    }

    fn handle_terminal_scroll(
        &mut self,
        event: &ScrollWheelEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = self.selected_terminal_session_id() else {
            return;
        };
        let line_height = self.terminal_line_height();
        let sensitivity = self.settings_state.terminal_tui_scroll_sensitivity as i32;
        let Some(session) = self.terminal_sessions.get_mut(&session_id) else {
            return;
        };
        let lines =
            ((event.delta.pixel_delta(line_height).y / line_height).round() as i32) * sensitivity;
        if lines == 0 {
            return;
        }
        session.emulator.scroll_display(lines);
        cx.stop_propagation();
        cx.notify();
    }

    fn terminal_point_at(
        &self,
        session_id: &str,
        position: Point<gpui::Pixels>,
    ) -> Option<TerminalPoint> {
        let bounds = self.terminal_surface_bounds.get(session_id)?;
        let session = self.terminal_sessions.get(session_id)?;
        let character_width =
            gpui::px((self.settings_state.terminal_font_size * 0.6).max(1.0) as f32);
        let line_height = self.terminal_line_height();
        let x =
            position.x - bounds.origin.x - gpui::px(self.settings_state.terminal_padding_x as f32);
        let y =
            position.y - bounds.origin.y - gpui::px(self.settings_state.terminal_padding_y as f32);
        let column = if x <= gpui::px(0.0) {
            0
        } else {
            (x / character_width).floor() as usize
        };
        let row = if y <= gpui::px(0.0) {
            0
        } else {
            (y / line_height).floor() as usize
        };
        Some(TerminalPoint {
            row: row.min(session.rows.saturating_sub(1)),
            column: column.min(session.columns.saturating_sub(1)),
        })
    }

    fn begin_terminal_selection(
        &mut self,
        session_id: &str,
        event: &MouseDownEvent,
        cx: &mut Context<Self>,
    ) {
        let Some(point) = self.terminal_point_at(session_id, event.position) else {
            return;
        };
        if let Some(session) = self.terminal_sessions.get_mut(session_id) {
            let kind = match event.click_count {
                2 => TerminalSelectionKind::Semantic,
                count if count >= 3 => TerminalSelectionKind::Lines,
                _ => TerminalSelectionKind::Simple,
            };
            session.emulator.begin_selection(
                point,
                kind,
                self.settings_state.terminal_word_separators.as_deref(),
            );
            cx.notify();
        }
    }

    fn update_terminal_link_hover(
        &mut self,
        session_id: &str,
        event: &MouseMoveEvent,
        cx: &mut Context<Self>,
    ) {
        let next = terminal_link_modifier(event.modifiers)
            .then(|| self.terminal_point_at(session_id, event.position))
            .flatten()
            .and_then(|point| {
                self.terminal_sessions
                    .get(session_id)
                    .and_then(|session| session.emulator.link_at(point))
            })
            .map(|link| (session_id.to_owned(), link));
        if self.terminal_hovered_link != next {
            self.terminal_hovered_link = next;
            cx.notify();
        }
    }

    fn activate_terminal_link(
        &mut self,
        session_id: &str,
        event: &MouseDownEvent,
        cx: &mut Context<Self>,
    ) -> bool {
        if !terminal_link_modifier(event.modifiers) {
            return false;
        }
        let Some(link) = self
            .terminal_point_at(session_id, event.position)
            .and_then(|point| {
                self.terminal_sessions
                    .get(session_id)
                    .and_then(|session| session.emulator.link_at(point))
            })
        else {
            return false;
        };
        if let Some(session) = self.terminal_sessions.get_mut(session_id) {
            session.emulator.clear_selection();
        }
        cx.open_url(&link.uri);
        cx.stop_propagation();
        true
    }

    fn update_terminal_selection(
        &mut self,
        session_id: &str,
        event: &MouseMoveEvent,
        cx: &mut Context<Self>,
    ) {
        if !event.dragging() {
            return;
        }
        let Some(point) = self.terminal_point_at(session_id, event.position) else {
            return;
        };
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        session.emulator.update_selection(point);
        cx.notify();
    }

    fn finish_terminal_selection(
        &mut self,
        session_id: &str,
        _: &MouseUpEvent,
        cx: &mut Context<Self>,
    ) {
        if !self.settings_state.terminal_clipboard_on_select {
            return;
        }
        let Some(text) = self
            .terminal_sessions
            .get(session_id)
            .and_then(|session| session.emulator.selected_text())
            .filter(|text| !text.is_empty())
        else {
            return;
        };
        cx.write_to_clipboard(ClipboardItem::new_string(text));
    }

    pub(super) fn sync_terminal_size(&mut self, window: &Window, cx: &mut Context<Self>) {
        let viewport = window.viewport_size();
        let left_sidebar_width = if self.sidebar_collapsed {
            gpui::px(52.0)
        } else {
            gpui::px(self.sidebar_width)
        };
        let right_sidebar_width = if self.context_sidebar_collapsed {
            gpui::px(42.0)
        } else {
            gpui::px(self.context_sidebar_width)
        };
        let fallback_width = viewport.width
            - left_sidebar_width
            - right_sidebar_width
            - gpui::px((self.settings_state.terminal_padding_x * 2.0) as f32);
        let fallback_height = viewport.height
            - theme::tab_bar_height()
            - theme::status_bar_height()
            - gpui::px((self.settings_state.terminal_padding_y * 2.0) as f32);
        let character_width =
            gpui::px((self.settings_state.terminal_font_size * 0.6).max(1.0) as f32);
        let line_height = self.terminal_line_height();
        let mut resized = Vec::new();
        for session in self.terminal_sessions.values_mut() {
            let (content_width, content_height) = self
                .terminal_surface_bounds
                .get(&session.session_id)
                .map(|bounds| {
                    (
                        bounds.size.width
                            - gpui::px((self.settings_state.terminal_padding_x * 2.0) as f32),
                        bounds.size.height
                            - gpui::px((self.settings_state.terminal_padding_y * 2.0) as f32),
                    )
                })
                .unwrap_or((fallback_width, fallback_height));
            let columns = ((content_width / character_width).floor() as usize).max(2);
            let rows = ((content_height / line_height).floor() as usize).max(2);
            if session.columns == columns && session.rows == rows {
                continue;
            }
            session.columns = columns;
            session.rows = rows;
            session.emulator.resize(columns, rows);
            resized.push((session.session_id.clone(), columns, rows));
        }
        for (session_id, columns, rows) in resized {
            let bridge = self.bridge.clone();
            cx.spawn(async move |_, _| {
                let _ = bridge
                    .request(
                        "resize",
                        json!({
                            "sessionId": session_id,
                            "cols": columns,
                            "rows": rows,
                        }),
                    )
                    .await;
            })
            .detach();
        }
    }

    pub(super) fn selected_terminal_session_id(&self) -> Option<String> {
        let tab_id = self.selected_tab_id.as_deref()?;
        self.snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id && tab.kind == "terminal")
            .map(|tab| terminal_session_id(tab).to_string())
    }

    pub(super) fn write_terminal_bytes_for(&self, session_id: &str, bytes: Vec<u8>) {
        let _ = self.bridge.send_ordered(
            "write",
            json!({
                "sessionId": session_id,
                "dataBase64": BASE64_STANDARD.encode(bytes),
            }),
        );
    }

    pub(super) fn render_terminal_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let tab = self.selected_tab_id.as_deref().and_then(|tab_id| {
            self.snapshot
                .tabs
                .iter()
                .find(|tab| tab.id == tab_id && tab.kind == "terminal")
        });
        self.render_terminal_surface_for(tab, true, cx)
    }

    pub(super) fn render_terminal_surface_for(
        &self,
        tab: Option<&WorkspaceTab>,
        active: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let session_id = tab.map(terminal_session_id);
        let line_height = self.terminal_line_height();
        let character_width =
            gpui::px((self.settings_state.terminal_font_size * 0.6).max(1.0) as f32);
        let cursor_color = self.terminal_cursor_color();
        let cursor_shape = self.settings_state.terminal_cursor_shape.clone();
        let cursor_opacity = self.settings_state.terminal_cursor_opacity as f32;
        let selection_color = self.terminal_selection_color();
        let cursor_visible =
            !self.settings_state.terminal_cursor_blink || self.terminal_cursor_visible;
        let body = session_id
            .and_then(|session_id| self.terminal_sessions.get(session_id))
            .map(|session| {
                let hovered_link = self
                    .terminal_hovered_link
                    .as_ref()
                    .filter(|(hovered_session_id, _)| hovered_session_id == &session.session_id)
                    .map(|(_, link)| link);
                let mut lines = session
                    .emulator
                    .visible_lines(&self.settings_state.terminal_theme_name)
                    .into_iter()
                    .enumerate()
                    .map(|(row_index, line)| {
                        let cursor_column = (active && cursor_visible)
                            .then_some(line.cursor_column)
                            .flatten();
                        let selection_range =
                            session.emulator.selection_range_for_viewport_row(row_index);
                        div()
                            .relative()
                            .flex_shrink_0()
                            .h(line_height)
                            .line_height(line_height)
                            .overflow_hidden()
                            .whitespace_nowrap()
                            .when_some(selection_range, |row, (start, end)| {
                                row.child(terminal_selection_overlay(
                                    start,
                                    end,
                                    character_width,
                                    line_height,
                                    selection_color,
                                ))
                            })
                            .when_some(
                                hovered_link.filter(|link| link.row == row_index),
                                |row, link| {
                                    row.child(terminal_link_overlay(
                                        link.start_column,
                                        link.end_column,
                                        character_width,
                                        line_height,
                                    ))
                                },
                            )
                            .child(line.text)
                            .when_some(cursor_column, |row, column| {
                                row.child(terminal_cursor(
                                    column,
                                    character_width,
                                    line_height,
                                    &cursor_shape,
                                    cursor_color,
                                    cursor_opacity,
                                ))
                            })
                    })
                    .collect::<Vec<_>>();
                if session.attaching {
                    lines.push(
                        div()
                            .text_color(theme::text_muted())
                            .child("Attaching To Runtime Terminal"),
                    );
                } else if !session.running {
                    lines.push(
                        div()
                            .text_color(theme::warning())
                            .child("Terminal Exited - Create A New Terminal To Continue"),
                    );
                }
                if let Some(error) = &session.error {
                    lines.push(div().text_color(theme::danger()).child(error.clone()));
                }
                div().flex().flex_col().children(lines).into_any_element()
            })
            .unwrap_or_else(|| {
                div()
                    .text_color(theme::text_muted())
                    .child("Terminal Is Not Attached")
                    .into_any_element()
            });
        let tab_id = tab.map(|tab| tab.id.clone());
        let owned_session_id = session_id.unwrap_or("none").to_owned();
        let selection_session_id = owned_session_id.clone();
        let move_session_id = owned_session_id.clone();
        let link_session_id = owned_session_id.clone();
        let finish_session_id = owned_session_id.clone();
        let finish_out_session_id = owned_session_id.clone();
        let bounds_session_id = owned_session_id.clone();
        let bounds_app = cx.entity().downgrade();
        let input_app = cx.entity();
        let input_focus = self.terminal_focus.clone();
        let focus = self.terminal_focus.clone();
        let drop_focus = self.terminal_focus.clone();
        let drop_session_id = owned_session_id.clone();
        let background = self.terminal_background();
        let hovering_link = self
            .terminal_hovered_link
            .as_ref()
            .is_some_and(|(hovered_session_id, _)| hovered_session_id == &owned_session_id);
        let scrollbar = session_id
            .and_then(|session_id| self.terminal_sessions.get(session_id))
            .and_then(|session| {
                self.render_terminal_scrollbar(
                    &owned_session_id,
                    session.emulator.scroll_metrics(),
                    cx,
                )
            });
        let terminal_state = session_id
            .and_then(|session_id| self.terminal_sessions.get(session_id))
            .map(|session| {
                (
                    session.attaching,
                    session.error.clone().or_else(|| {
                        (!session.running).then(|| "The Terminal Process Exited.".to_owned())
                    }),
                )
            });
        let operation = terminal_state
            .as_ref()
            .is_some_and(|(attaching, error)| *attaching && error.is_none())
            .then(|| self.render_terminal_operation_state());
        let recovery = terminal_state
            .as_ref()
            .and_then(|(_, error)| error.as_deref())
            .map(|error| {
                self.render_terminal_recovery_state(&owned_session_id, error.to_owned(), cx)
            });
        let restart_confirmation = (self.terminal_restart_confirmation.as_deref()
            == Some(owned_session_id.as_str()))
        .then(|| self.render_terminal_restart_confirmation(&owned_session_id, cx));
        let refresh_button = session_id
            .is_some()
            .then(|| self.render_terminal_refresh_button(&owned_session_id, cx));
        let mobile_driver_overlay = self.render_mobile_driver_overlay(&owned_session_id, cx);
        div()
            .id(SharedString::from(format!(
                "terminal-surface-{}",
                session_id.unwrap_or("none")
            )))
            .relative()
            .flex_1()
            .overflow_hidden()
            .bg(background)
            .px(gpui::px(self.settings_state.terminal_padding_x as f32))
            .py(gpui::px(self.settings_state.terminal_padding_y as f32))
            .font_family(self.settings_state.terminal_font_family.clone())
            .font_weight(FontWeight(self.settings_state.terminal_font_weight as f32))
            .text_size(gpui::px(self.settings_state.terminal_font_size as f32))
            .when(hovering_link, |surface| {
                surface.cursor(CursorStyle::PointingHand)
            })
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseDownEvent, window, cx| {
                    if let Some(tab_id) = tab_id.clone() {
                        this.activate_workspace_tab(tab_id, cx);
                    }
                    this.reset_terminal_cursor_blink();
                    if this.activate_terminal_link(&selection_session_id, event, cx) {
                        window.focus(&focus);
                        return;
                    }
                    this.begin_terminal_selection(&selection_session_id, event, cx);
                    window.focus(&focus);
                }),
            )
            .on_mouse_move(cx.listener(move |this, event: &MouseMoveEvent, _, cx| {
                this.update_terminal_link_hover(&link_session_id, event, cx);
                this.update_terminal_selection(&move_session_id, event, cx);
            }))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseUpEvent, _, cx| {
                    this.finish_terminal_selection(&finish_session_id, event, cx);
                }),
            )
            .on_mouse_up_out(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseUpEvent, _, cx| {
                    this.finish_terminal_selection(&finish_out_session_id, event, cx);
                }),
            )
            .on_drop(cx.listener(move |this, paths: &ExternalPaths, window, cx| {
                if this.is_terminal_mobile_driven(&drop_session_id) {
                    cx.stop_propagation();
                    return;
                }
                let text = format_paths_for_terminal_paste(paths);
                if text.is_empty() {
                    return;
                }
                let bytes = this
                    .terminal_sessions
                    .get(&drop_session_id)
                    .map(|session| session.emulator.encode_paste(&text));
                if let Some(bytes) = bytes {
                    this.write_terminal_bytes_for(&drop_session_id, bytes);
                    this.reset_terminal_cursor_blink();
                    window.focus(&drop_focus);
                    cx.notify();
                }
            }))
            .child(
                div()
                    .flex_1()
                    .overflow_hidden()
                    .track_focus(&self.terminal_focus)
                    .key_context("terminal")
                    .when(active, |terminal| {
                        terminal
                            .on_key_down(cx.listener(Self::handle_terminal_key))
                            .on_scroll_wheel(cx.listener(Self::handle_terminal_scroll))
                    })
                    .child(body),
            )
            .when_some(scrollbar, |surface, scrollbar| surface.child(scrollbar))
            .when_some(refresh_button, |surface, button| surface.child(button))
            .when_some(recovery, |surface, recovery| surface.child(recovery))
            .when_some(operation, |surface, operation| surface.child(operation))
            .when_some(restart_confirmation, |surface, confirmation| {
                surface.child(confirmation)
            })
            .child(
                canvas(
                    move |bounds, _, cx| {
                        let _ = bounds_app.update(cx, |this, _| {
                            this.terminal_surface_bounds
                                .insert(bounds_session_id.clone(), bounds);
                        });
                    },
                    move |bounds, _, window, cx| {
                        if active {
                            window.handle_input(
                                &input_focus,
                                ElementInputHandler::new(bounds, input_app.clone()),
                                cx,
                            );
                        }
                    },
                )
                .absolute()
                .top_0()
                .right_0()
                .bottom_0()
                .left_0(),
            )
            .when_some(mobile_driver_overlay, |surface, overlay| {
                surface.child(overlay)
            })
            .into_any_element()
    }

    fn render_terminal_refresh_button(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let session_id = session_id.to_owned();
        design_system::icon_button(
            SharedString::from(format!("terminal-refresh-{session_id}")),
            AleraIcon::Refresh,
            true,
            28.0,
            Some(theme::surface_raised()),
            Some(theme::border_subtle()),
        )
        .absolute()
        .top(gpui::px(4.0))
        .right(gpui::px(4.0))
        .on_mouse_down(
            MouseButton::Left,
            cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                this.refresh_terminal_viewport(session_id.clone(), cx);
                cx.stop_propagation();
            }),
        )
        .into_any_element()
    }

    fn render_terminal_operation_state(&self) -> AnyElement {
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .gap_3()
            .bg(self.terminal_background())
            .child(icon(AleraIcon::Loading, 20.0, theme::text_muted()))
            .child(
                div()
                    .text_size(gpui::px(13.0))
                    .child("Reconnecting Terminal"),
            )
            .into_any_element()
    }

    fn render_terminal_recovery_state(
        &self,
        session_id: &str,
        message: String,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let reconnect_session_id = session_id.to_owned();
        let restart_session_id = session_id.to_owned();
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .flex()
            .items_center()
            .justify_center()
            .bg(self.terminal_background())
            .child(
                div()
                    .w(gpui::px(420.0))
                    .p(gpui::px(20.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .child(
                        div()
                            .text_size(gpui::px(16.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("Terminal Unavailable"),
                    )
                    .child(
                        div()
                            .mt_2()
                            .text_size(gpui::px(12.0))
                            .text_color(theme::text_muted())
                            .child(message),
                    )
                    .child(
                        div()
                            .flex()
                            .gap_2()
                            .mt_4()
                            .child(
                                design_system::button(
                                    SharedString::from(format!(
                                        "terminal-reconnect-{reconnect_session_id}"
                                    )),
                                    "Reconnect",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                        this.recover_terminal_session(
                                            reconnect_session_id.clone(),
                                            false,
                                            cx,
                                        );
                                        cx.stop_propagation();
                                    }),
                                ),
                            )
                            .child(
                                design_system::button(
                                    SharedString::from(format!(
                                        "terminal-restart-{restart_session_id}"
                                    )),
                                    "Restart Terminal",
                                    ButtonKind::Outlined,
                                    false,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                        this.terminal_restart_confirmation =
                                            Some(restart_session_id.clone());
                                        cx.stop_propagation();
                                        cx.notify();
                                    }),
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn render_terminal_restart_confirmation(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let restart_session_id = session_id.to_owned();
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                design_system::dialog_shell(460.0)
                    .child(
                        div()
                            .text_size(gpui::px(16.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("Restart Terminal?"),
                    )
                    .child(
                        div()
                            .mt_2()
                            .text_size(gpui::px(13.0))
                            .text_color(theme::text_muted())
                            .child(
                                "This Will Stop The Current Process Tree And Start A New Shell. Terminal History Will Be Preserved.",
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_4()
                            .child(
                                design_system::button(
                                    "cancel-terminal-restart",
                                    "Cancel",
                                    ButtonKind::Text,
                                    false,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _: &MouseDownEvent, _, cx| {
                                        this.terminal_restart_confirmation = None;
                                        cx.stop_propagation();
                                        cx.notify();
                                    }),
                                ),
                            )
                            .child(
                                design_system::button(
                                    "confirm-terminal-restart",
                                    "Restart Terminal",
                                    ButtonKind::Filled,
                                    false,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(
                                        move |this, _: &MouseDownEvent, _, cx| {
                                            this.recover_terminal_session(
                                                restart_session_id.clone(),
                                                true,
                                                cx,
                                            );
                                            cx.stop_propagation();
                                        },
                                    ),
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }

    pub(super) fn terminal_line_height(&self) -> gpui::Pixels {
        gpui::px(
            (self.settings_state.terminal_font_size * self.settings_state.terminal_line_height)
                .max(1.0) as f32,
        )
    }

    fn terminal_background(&self) -> Rgba {
        let color = self
            .settings_state
            .terminal_color_overrides
            .get("background")
            .and_then(|value| parse_hex_rgb(value))
            .unwrap_or_else(|| {
                gpui::rgb(
                    terminal_theme_palette(&self.settings_state.terminal_theme_name).background,
                )
            });
        Rgba {
            a: color.a * self.settings_state.terminal_background_opacity as f32,
            ..color
        }
    }

    fn terminal_cursor_color(&self) -> Rgba {
        self.settings_state
            .terminal_color_overrides
            .get("cursor")
            .and_then(|value| parse_hex_rgb(value))
            .unwrap_or_else(|| {
                gpui::rgb(terminal_theme_palette(&self.settings_state.terminal_theme_name).cursor)
            })
    }

    fn terminal_selection_color(&self) -> Rgba {
        self.settings_state
            .terminal_color_overrides
            .get("selection")
            .and_then(|value| parse_hex_rgb(value))
            .unwrap_or_else(|| {
                gpui::rgb(
                    terminal_theme_palette(&self.settings_state.terminal_theme_name).selection,
                )
            })
    }

    pub(super) fn reset_terminal_cursor_blink(&mut self) {
        self.terminal_cursor_visible = true;
        self.terminal_cursor_last_activity = std::time::Instant::now();
    }

    fn render_terminal_scrollbar(
        &self,
        session_id: &str,
        metrics: (usize, usize, usize),
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let (display_offset, history, screen_lines) = metrics;
        if history == 0 || screen_lines == 0 {
            return None;
        }
        let total = history + screen_lines;
        let height = (screen_lines as f32 / total as f32).clamp(0.08, 1.0);
        let top = ((history.saturating_sub(display_offset)) as f32 / total as f32)
            .clamp(0.0, 1.0 - height);
        let down_session_id = session_id.to_owned();
        let move_session_id = session_id.to_owned();
        Some(
            div()
                .id(SharedString::from(format!(
                    "terminal-scrollbar-{session_id}"
                )))
                .absolute()
                .top_0()
                .right_0()
                .bottom_0()
                .w(gpui::px(8.0))
                .cursor(CursorStyle::ResizeUpDown)
                .on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                        this.terminal_scrollbar_drag = Some(down_session_id.clone());
                        this.scroll_terminal_to_pointer(&down_session_id, event.position.y, cx);
                        cx.stop_propagation();
                    }),
                )
                .on_mouse_move(cx.listener(move |this, event: &MouseMoveEvent, _, cx| {
                    if event.dragging()
                        && this.terminal_scrollbar_drag.as_deref() == Some(move_session_id.as_str())
                    {
                        this.scroll_terminal_to_pointer(&move_session_id, event.position.y, cx);
                        cx.stop_propagation();
                    }
                }))
                .on_mouse_up(
                    MouseButton::Left,
                    cx.listener(|this, _: &MouseUpEvent, _, cx| {
                        this.terminal_scrollbar_drag = None;
                        cx.stop_propagation();
                    }),
                )
                .on_mouse_up_out(
                    MouseButton::Left,
                    cx.listener(|this, _: &MouseUpEvent, _, cx| {
                        this.terminal_scrollbar_drag = None;
                        cx.stop_propagation();
                    }),
                )
                .child(
                    div()
                        .absolute()
                        .top(gpui::relative(top))
                        .right(gpui::px(2.0))
                        .h(gpui::relative(height))
                        .w(gpui::px(3.0))
                        .rounded_full()
                        .bg(theme::text_faint()),
                )
                .into_any_element(),
        )
    }

    fn scroll_terminal_to_pointer(
        &mut self,
        session_id: &str,
        pointer_y: gpui::Pixels,
        cx: &mut Context<Self>,
    ) {
        let Some(bounds) = self.terminal_surface_bounds.get(session_id) else {
            return;
        };
        let track_height = bounds.size.height / gpui::px(1.0);
        if track_height <= 0.0 {
            return;
        }
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        let (current, history, screen_lines) = session.emulator.scroll_metrics();
        if history == 0 || screen_lines == 0 {
            return;
        }
        let total = history + screen_lines;
        let thumb_height = (screen_lines as f32 / total as f32).clamp(0.08, 1.0);
        let local_y = (pointer_y - bounds.origin.y) / gpui::px(1.0);
        let thumb_top =
            (local_y / track_height - thumb_height / 2.0).clamp(0.0, 1.0 - thumb_height);
        let desired = (history as f32 - thumb_top * total as f32)
            .round()
            .clamp(0.0, history as f32) as usize;
        let delta = desired as i32 - current as i32;
        if delta != 0 {
            session.emulator.scroll_display(delta);
            cx.notify();
        }
    }
}

fn terminal_selection_overlay(
    start: usize,
    end: usize,
    character_width: gpui::Pixels,
    line_height: gpui::Pixels,
    color: Rgba,
) -> gpui::Div {
    div()
        .absolute()
        .top_0()
        .left(character_width * start as f32)
        .w(character_width * end.saturating_sub(start) as f32)
        .h(line_height)
        .bg(color)
}

fn terminal_cursor(
    column: usize,
    character_width: gpui::Pixels,
    line_height: gpui::Pixels,
    shape: &str,
    color: Rgba,
    opacity: f32,
) -> gpui::Div {
    let color = Rgba {
        a: color.a * opacity.clamp(0.0, 1.0),
        ..color
    };
    let cursor = div()
        .absolute()
        .left(character_width * column as f32)
        .bg(color);
    match shape {
        "bar" => cursor.top_0().bottom_0().w(gpui::px(2.0)),
        "underline" => cursor.bottom_0().w(character_width).h(gpui::px(2.0)),
        _ => cursor.top_0().w(character_width).h(line_height),
    }
}

fn terminal_link_overlay(
    start: usize,
    end: usize,
    character_width: gpui::Pixels,
    line_height: gpui::Pixels,
) -> gpui::Div {
    div()
        .absolute()
        .left(character_width * start as f32)
        .top(line_height - gpui::px(1.0))
        .w(character_width * end.saturating_sub(start) as f32)
        .h(gpui::px(1.0))
        .bg(theme::accent())
}

fn terminal_link_modifier(modifiers: Modifiers) -> bool {
    if cfg!(target_os = "macos") {
        modifiers.platform
    } else {
        modifiers.control
    }
}

fn terminal_key_uses_text_input(
    key: &str,
    key_char: Option<&str>,
    modifiers: KeyModifiers,
) -> bool {
    if modifiers.control || modifiers.platform || modifiers.function {
        return false;
    }

    // Keep keys that have terminal protocol semantics on the key-down path. In particular,
    // Enter must send CR and Tab must not be turned into focus traversal by the host window.
    if matches!(
        key,
        "enter"
            | "tab"
            | "backspace"
            | "delete"
            | "escape"
            | "up"
            | "down"
            | "left"
            | "right"
            | "home"
            | "end"
            | "pageup"
            | "pagedown"
    ) {
        return false;
    }

    // Option/Alt is a text-composition modifier on macOS. Other platforms reserve it for the
    // terminal's ESC-prefixed meta keys, whose bytes still need to be encoded here.
    if modifiers.alt && !cfg!(target_os = "macos") {
        return false;
    }

    key_char.is_some_and(|text| {
        !text.is_empty() && text.chars().any(|character| !character.is_control())
    }) || key.chars().count() == 1
}

fn format_paths_for_terminal_paste(paths: &ExternalPaths) -> String {
    paths
        .paths()
        .iter()
        .filter_map(|path| {
            let value = path.to_string_lossy().trim().replace('\u{1b}', "\u{241b}");
            if value.is_empty() {
                return None;
            }
            if value.chars().any(char::is_whitespace) {
                Some(format!("'{}' ", value.replace('\'', "'\\''")))
            } else {
                Some(format!("{value} "))
            }
        })
        .collect()
}

fn terminal_session_id(tab: &WorkspaceTab) -> &str {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(&tab.id)
}

fn parse_hex_rgb(value: &str) -> Option<Rgba> {
    let digits = value.trim().strip_prefix('#').unwrap_or(value.trim());
    (digits.len() == 6)
        .then(|| u32::from_str_radix(digits, 16).ok())
        .flatten()
        .map(gpui::rgb)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn printable_keys_use_platform_text_input() {
        assert!(terminal_key_uses_text_input(
            "a",
            Some("a"),
            KeyModifiers::default()
        ));
        assert!(terminal_key_uses_text_input(
            "'",
            Some("'"),
            KeyModifiers::default()
        ));
        assert!(terminal_key_uses_text_input(
            "'",
            None,
            KeyModifiers::default()
        ));
    }

    #[test]
    fn terminal_control_keys_stay_on_key_down_path() {
        assert!(!terminal_key_uses_text_input(
            "enter",
            Some("\n"),
            KeyModifiers::default()
        ));
        assert!(!terminal_key_uses_text_input(
            "left",
            None,
            KeyModifiers::default()
        ));
        assert!(!terminal_key_uses_text_input(
            "c",
            Some("c"),
            KeyModifiers {
                control: true,
                ..KeyModifiers::default()
            }
        ));
        assert!(!terminal_key_uses_text_input(
            "c",
            Some("c"),
            KeyModifiers {
                platform: true,
                ..KeyModifiers::default()
            }
        ));
    }

    #[cfg(not(target_os = "macos"))]
    #[test]
    fn alt_keys_keep_terminal_meta_encoding_off_macos() {
        assert!(!terminal_key_uses_text_input(
            "x",
            Some("x"),
            KeyModifiers {
                alt: true,
                ..KeyModifiers::default()
            }
        ));
    }
}
