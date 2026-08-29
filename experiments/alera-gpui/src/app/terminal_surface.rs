use std::{collections::BTreeSet, path::Path};

use base64::prelude::{Engine as _, BASE64_STANDARD};
use gpui::{
    canvas, div, font, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, ClipboardItem,
    Context, CursorStyle, ElementInputHandler, ExternalPaths, FontWeight, InteractiveElement as _,
    IntoElement as _, KeyDownEvent, Modifiers, MouseButton, MouseDownEvent, MouseMoveEvent,
    MouseUpEvent, ParentElement as _, Pixels, Point, Render, Rgba, Role, ScrollWheelEvent,
    SharedString, StatefulInteractiveElement as _, Styled as _, Window,
};
use serde_json::{json, Value};

use super::{AleraApp, ExplorerDragData, TerminalSearchState};
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::model::WorkspaceTab;
use crate::terminal::{
    KeyModifiers, TerminalEmulator, TerminalPoint, TerminalSelectionKind, TerminalSession,
    TerminalSessionOperation,
};
use crate::terminal_theme_catalog::terminal_theme_palette;
use crate::theme;

struct TerminalFrameLine {
    text: SharedString,
    highlights: Vec<(std::ops::Range<usize>, gpui::HighlightStyle)>,
    cursor_column: Option<usize>,
    selection_range: Option<(usize, usize)>,
    hovered_link: Option<(usize, usize)>,
}

struct TerminalFrameSnapshot {
    lines: Vec<TerminalFrameLine>,
    attaching: bool,
    running: bool,
    error: Option<String>,
    line_height: Pixels,
    character_width: Pixels,
    cursor_color: Rgba,
    cursor_shape: String,
    cursor_opacity: f32,
    selection_color: Rgba,
}

pub(super) struct TerminalFrameView {
    snapshot: TerminalFrameSnapshot,
}

impl TerminalFrameView {
    fn empty() -> Self {
        Self {
            snapshot: TerminalFrameSnapshot {
                lines: Vec::new(),
                attaching: true,
                running: true,
                error: None,
                line_height: gpui::px(19.0),
                character_width: gpui::px(7.8),
                cursor_color: theme::text(),
                cursor_shape: "block".to_owned(),
                cursor_opacity: 1.0,
                selection_color: theme::text_selection(),
            },
        }
    }
}

impl Render for TerminalFrameView {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
        let snapshot = &self.snapshot;
        let mut lines = snapshot
            .lines
            .iter()
            .map(|line| {
                div()
                    .relative()
                    .flex_shrink_0()
                    .h(snapshot.line_height)
                    .line_height(snapshot.line_height)
                    .overflow_hidden()
                    .whitespace_nowrap()
                    .when_some(line.selection_range, |row, (start, end)| {
                        row.child(terminal_selection_overlay(
                            start,
                            end,
                            snapshot.character_width,
                            snapshot.line_height,
                            snapshot.selection_color,
                        ))
                    })
                    .when_some(line.hovered_link, |row, (start, end)| {
                        row.child(terminal_link_overlay(
                            start,
                            end,
                            snapshot.character_width,
                            snapshot.line_height,
                        ))
                    })
                    .child(
                        gpui::StyledText::new(line.text.clone())
                            .with_highlights(line.highlights.clone()),
                    )
                    .when_some(line.cursor_column, |row, column| {
                        row.child(terminal_cursor(
                            column,
                            snapshot.character_width,
                            snapshot.line_height,
                            &snapshot.cursor_shape,
                            snapshot.cursor_color,
                            snapshot.cursor_opacity,
                        ))
                    })
            })
            .collect::<Vec<_>>();
        if snapshot.attaching {
            lines.push(
                div()
                    .text_color(theme::text_muted())
                    .child("Attaching To Runtime Terminal"),
            );
        } else if !snapshot.running {
            lines.push(
                div()
                    .text_color(theme::warning())
                    .child("Terminal Exited - Create A New Terminal To Continue"),
            );
        }
        if let Some(error) = &snapshot.error {
            lines.push(div().text_color(theme::danger()).child(error.clone()));
        }
        div().flex().flex_col().children(lines)
    }
}

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
            self.terminal_frame_views.remove(&session_id);
            self.terminal_output_dirty_sessions.remove(&session_id);
            self.terminal_resize_pending.remove(&session_id);
            self.terminal_resize_generation.remove(&session_id);
            self.terminal_scrollbar_last_activity.remove(&session_id);
            if self
                .terminal_pulse_dialog_session
                .as_deref()
                .is_some_and(|active| active == session_id)
            {
                self.close_terminal_pulse_dialog(cx);
            }
            if self
                .terminal_scrollbar_drag
                .as_deref()
                .is_some_and(|active| active == session_id)
            {
                self.terminal_scrollbar_drag = None;
            }
            if self
                .terminal_hovered_link
                .as_ref()
                .is_some_and(|(active, _)| active == &session_id)
            {
                self.terminal_hovered_link = None;
            }
            let bridge = self.bridge.clone();
            cx.spawn(async move |_, _| {
                let _ = bridge
                    .request("detach", json!({ "sessionId": session_id }))
                    .await;
            })
            .detach();
        }

        for (session_id, workspace_id, tab_id, working_directory) in contexts {
            if !self.terminal_sessions.contains_key(&session_id) {
                self.terminal_sessions
                    .insert(session_id.clone(), TerminalSession::new(session_id.clone()));
                self.terminal_frame_views
                    .insert(session_id.clone(), cx.new(|_| TerminalFrameView::empty()));
            }
            let attach_pending = self
                .terminal_sessions
                .get(&session_id)
                .is_some_and(|session| session.attaching && session.operation_started_at.is_none());
            if !attach_pending {
                continue;
            }
            // Flutter starts a terminal only after its TerminalView has
            // reported its measured cell dimensions. Do the same in GPUI so
            // a restored prompt is parsed at the viewport width rather than
            // the arbitrary 100-column fallback used during the first frame.
            let Some((attach_columns, attach_rows)) = self.terminal_dimensions_for_tab(&tab_id)
            else {
                continue;
            };
            if let Some(session) = self.terminal_sessions.get_mut(&session_id) {
                session.operation_started_at = Some(std::time::Instant::now());
                session.columns = attach_columns;
                session.rows = attach_rows;
                session.emulator.resize(attach_columns, attach_rows);
            }
            let bridge = self.bridge.clone();
            let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
            let command_startup = self
                .command_terminal
                .as_ref()
                .filter(|command| command.session_id == session_id)
                .map(|command| command.request.command.clone());
            cx.spawn(async move |this, cx| {
                let result = bridge
                    .request_with_timeout(
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
                            "cols": attach_columns,
                            "rows": attach_rows,
                        }),
                        std::time::Duration::from_secs(10),
                    )
                    .await;
                let Some(this) = this.upgrade() else {
                    return;
                };
                let attach_succeeded = result.is_ok();
                this.update(cx, |this, cx| {
                    let Some(session) = this.terminal_sessions.get_mut(&session_id) else {
                        return;
                    };
                    session.attaching = false;
                    session.operation = None;
                    session.operation_started_at = None;
                    let mut restore_generation = None;
                    match result {
                        Ok(payload) => {
                            let snapshot_dimensions = terminal_snapshot_dimensions(&payload);
                            let emulator = TerminalEmulator::new(attach_columns, attach_rows);
                            session.running = payload
                                .get("running")
                                .and_then(Value::as_bool)
                                .unwrap_or(true);
                            let restored_bytes = payload
                                .get("snapshotBase64")
                                .and_then(Value::as_str)
                                .map(|encoded| BASE64_STANDARD.decode(encoded))
                                .transpose();
                            let restored_bytes = match restored_bytes {
                                Ok(bytes) => bytes,
                                Err(error) => {
                                    session.error = Some(error.to_string());
                                    None
                                }
                            };
                            session.emulator = emulator;
                            session.columns = attach_columns;
                            session.rows = attach_rows;
                            if payload
                                .get("snapshotBase64")
                                .and_then(Value::as_str)
                                .is_some()
                            {
                                if let Some(bytes) = restored_bytes {
                                    restore_generation = Some(
                                        session.begin_restore_at_dimensions(
                                            bytes,
                                            snapshot_dimensions,
                                        ),
                                    );
                                }
                            }
                        }
                        Err(error) => session.error = Some(error),
                    }
                    if let Some(generation) = restore_generation {
                        this.schedule_terminal_restore(session_id.clone(), generation, cx);
                    }
                    if attach_succeeded {
                        if let Some(command) = command_startup {
                            this.schedule_command_terminal_startup(
                                session_id.clone(),
                                command,
                                cx,
                            );
                        }
                    }
                    cx.notify();
                });
            })
            .detach();
        }
    }

    /// Resolve the same measured cell viewport that Flutter passes to
    /// `createOrAttach`. The terminal surface is not painted on the first
    /// render, so fall back to the already measured pane and remove its tab
    /// bar before deriving rows.
    fn terminal_dimensions_for_tab(&self, tab_id: &str) -> Option<(usize, usize)> {
        if self
            .command_terminal
            .as_ref()
            .is_some_and(|command| command.session_id == tab_id)
        {
            // The command dialog has a fixed 720 x 560 logical surface. Keep
            // a conservative cell grid until its canvas reports real bounds.
            return Some((88, 20));
        }
        let tab = self.snapshot.tabs.iter().find(|tab| tab.id == tab_id)?;
        let session_id = terminal_session_id(tab);
        let (bounds, includes_tab_bar) =
            if let Some(bounds) = self.terminal_surface_bounds.get(session_id) {
                (*bounds, false)
            } else {
                let group_id =
                    self.snapshot
                        .layout
                        .as_ref()?
                        .groups
                        .values()
                        .find_map(|group| {
                            group
                                .tab_ids
                                .iter()
                                .any(|candidate| candidate == tab_id)
                                .then_some(group.id.as_str())
                        })?;
                (*self.pane_bounds.get(group_id)?, true)
            };
        let width = bounds.size.width / gpui::px(1.0);
        let tab_bar_height = includes_tab_bar.then(|| theme::tab_bar_height() / gpui::px(1.0));
        let height = bounds.size.height / gpui::px(1.0) - tab_bar_height.unwrap_or(0.0);
        let content_width = width - self.settings_state.terminal_padding_x as f32 * 2.0;
        let content_height = height - self.settings_state.terminal_padding_y as f32 * 2.0;
        let line_height = self.terminal_line_height() / gpui::px(1.0);
        let columns = (content_width / self.terminal_character_width.max(1.0)).floor() as usize;
        let rows = (content_height / line_height.max(1.0)).floor() as usize;
        Some((columns.max(2), rows.max(2)))
    }

    fn terminal_contexts(&self) -> Vec<(String, String, String, String)> {
        let mut contexts = self
            .command_terminal
            .as_ref()
            .map(|command| {
                vec![(
                    command.session_id.clone(),
                    super::command_terminal::command_terminal_workspace_id().to_owned(),
                    command.session_id.clone(),
                    command.working_directory.clone(),
                )]
            })
            .unwrap_or_default();
        let Some(workspace_id) = self.selected_workspace_id.as_deref() else {
            return contexts;
        };
        let Some(workspace) = self.snapshot.workspace(workspace_id) else {
            return contexts;
        };
        contexts.extend(self.snapshot
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
            .collect::<Vec<_>>());
        contexts
    }

    fn terminal_frame_snapshot(&self, session_id: &str) -> Option<TerminalFrameSnapshot> {
        let session = self.terminal_sessions.get(session_id)?;
        let active = self.selected_terminal_session_id().as_deref() == Some(session_id);
        let cursor_visible =
            !self.settings_state.terminal_cursor_blink || self.terminal_cursor_visible;
        let hovered_link = self
            .terminal_hovered_link
            .as_ref()
            .filter(|(hovered_session_id, _)| hovered_session_id == session_id)
            .map(|(_, link)| link);
        let search_matches = self
            .terminal_search
            .as_ref()
            .filter(|search| search.session_id == session_id)
            .map(|search| search.matches.clone())
            .unwrap_or_default();
        let (display_offset, history, screen_lines) = session.emulator.scroll_metrics();
        let visible_top = history.saturating_sub(display_offset);
        let lines = session
            .emulator
            .visible_lines(&self.settings_state.terminal_theme_name)
            .into_iter()
            .enumerate()
            .map(|(row_index, line)| {
                let text = line.plain_text;
                let mut highlights = line.highlights;
                let absolute_row = visible_top + row_index.min(screen_lines.saturating_sub(1));
                for search_match in search_matches
                    .iter()
                    .filter(|search_match| search_match.line_index == absolute_row)
                {
                    let start = search_match.start.min(text.len());
                    let end = search_match.end.min(text.len());
                    if start < end {
                        highlights.push((
                            start..end,
                            gpui::HighlightStyle {
                                background_color: Some(theme::accent_subtle().into()),
                                ..gpui::HighlightStyle::default()
                            },
                        ));
                    }
                }
                TerminalFrameLine {
                    cursor_column: (active && cursor_visible)
                        .then_some(line.cursor_column)
                        .flatten(),
                    selection_range: line.source_row.and_then(|source_row| {
                        session
                            .emulator
                            .selection_range_for_viewport_row(source_row)
                    }),
                    hovered_link: hovered_link
                        .filter(|link| link.row == row_index)
                        .map(|link| (link.start_column, link.end_column)),
                    text: SharedString::from(text),
                    highlights,
                }
            })
            .collect();
        Some(TerminalFrameSnapshot {
            lines,
            attaching: session.attaching,
            running: session.running,
            error: session.error.clone(),
            line_height: self.terminal_line_height(),
            character_width: gpui::px(self.terminal_character_width.max(1.0)),
            cursor_color: self.terminal_cursor_color(),
            cursor_shape: self.settings_state.terminal_cursor_shape.clone(),
            cursor_opacity: self.settings_state.terminal_cursor_opacity as f32,
            selection_color: self.terminal_selection_color(),
        })
    }

    pub(super) fn open_terminal_search(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = self.selected_terminal_session_id() else {
            return;
        };
        let same_session = self
            .terminal_search
            .as_ref()
            .is_some_and(|search| search.session_id == session_id);
        let query = if same_session {
            self.terminal_search_input.read(cx).value().to_string()
        } else {
            String::new()
        };
        if !same_session {
            self.terminal_search_input
                .update(cx, |input, cx| input.set_value("", window, cx));
        }
        let matches = self
            .terminal_sessions
            .get(&session_id)
            .map(|session| session.emulator.search_matches(&query, false))
            .unwrap_or_default();
        self.terminal_search = Some(TerminalSearchState {
            session_id,
            query,
            matches,
            selected_index: 0,
        });
        self.terminal_search_input
            .update(cx, |input, cx| input.focus(window, cx));
        self.refresh_terminal_frame_views(cx);
        cx.notify();
    }

    pub(super) fn update_terminal_search_query(
        &mut self,
        query: String,
        cx: &mut Context<Self>,
    ) {
        let Some(search) = self.terminal_search.as_ref() else {
            return;
        };
        let query = query.trim().to_owned();
        let session_id = search.session_id.clone();
        let matches = self
            .terminal_sessions
            .get(&session_id)
            .map(|session| session.emulator.search_matches(&query, false))
            .unwrap_or_default();
        if let Some(search) = self.terminal_search.as_mut() {
            search.query = query;
            search.matches = matches;
            search.selected_index = 0;
        }
        if let Some(search_match) = self
            .terminal_search
            .as_ref()
            .and_then(|search| search.matches.first())
        {
            self.scroll_terminal_to_search_match(&session_id, search_match.line_index, cx);
        }
        self.refresh_terminal_frame_views(cx);
        cx.notify();
    }

    pub(super) fn next_terminal_search(&mut self, cx: &mut Context<Self>) {
        let Some(search) = self.terminal_search.as_mut() else {
            return;
        };
        if search.matches.is_empty() {
            return;
        }
        search.selected_index = (search.selected_index + 1) % search.matches.len();
        let line_index = search.matches[search.selected_index].line_index;
        let session_id = search.session_id.clone();
        self.scroll_terminal_to_search_match(&session_id, line_index, cx);
        self.refresh_terminal_frame_views(cx);
        cx.notify();
    }

    pub(super) fn previous_terminal_search(&mut self, cx: &mut Context<Self>) {
        let Some(search) = self.terminal_search.as_mut() else {
            return;
        };
        if search.matches.is_empty() {
            return;
        }
        search.selected_index = if search.selected_index == 0 {
            search.matches.len() - 1
        } else {
            search.selected_index - 1
        };
        let line_index = search.matches[search.selected_index].line_index;
        let session_id = search.session_id.clone();
        self.scroll_terminal_to_search_match(&session_id, line_index, cx);
        self.refresh_terminal_frame_views(cx);
        cx.notify();
    }

    pub(super) fn close_terminal_search(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.terminal_search.take().is_none() {
            return;
        }
        self.terminal_search_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.refresh_terminal_frame_views(cx);
        cx.notify();
    }

    fn scroll_terminal_to_search_match(
        &mut self,
        session_id: &str,
        line_index: usize,
        cx: &mut Context<Self>,
    ) {
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        let (current, history, _) = session.emulator.scroll_metrics();
        let desired = history.saturating_sub(line_index);
        let delta = desired as i32 - current as i32;
        if delta != 0 {
            session.emulator.scroll_display(delta);
            self.terminal_scrollbar_last_activity
                .insert(session_id.to_owned(), std::time::Instant::now());
            cx.notify();
        }
    }

    fn render_terminal_search_overlay(
        &self,
        session_id: &str,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let Some(search) = self
            .terminal_search
            .as_ref()
            .filter(|search| search.session_id == session_id)
        else {
            return div().into_any_element();
        };
        let count = if search.matches.is_empty() {
            "No Matches".to_owned()
        } else {
            format!("{} of {}", search.selected_index + 1, search.matches.len())
        };
        let toolbar_corner = self.settings_state.terminal_toolbar_corner.as_str();
        let toolbar_button_count = 3
            + usize::from(self.terminal_pulse_supported())
            + usize::from(!self.agent_canvas_values.is_empty());
        let toolbar_inset = 48.0 * toolbar_button_count as f32 + 4.0;
        div()
            .id("terminal-search-overlay")
            .absolute()
            .top(px(12.0))
            .when(toolbar_corner == "topLeft", |overlay| {
                overlay.left(px(toolbar_inset))
            })
            .when(toolbar_corner == "topRight", |overlay| {
                overlay.right(px(toolbar_inset))
            })
            .when(
                matches!(toolbar_corner, "bottomLeft" | "bottomRight"),
                |overlay| overlay.right(px(18.0)),
            )
            .w(px(360.0))
            .p_2()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
            .capture_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key.eq_ignore_ascii_case("escape") {
                    this.close_terminal_search(window, cx);
                } else if event.keystroke.key.eq_ignore_ascii_case("enter") {
                    if event.keystroke.modifiers.shift {
                        this.previous_terminal_search(cx);
                    } else {
                        this.next_terminal_search(cx);
                    }
                } else {
                    return;
                }
                cx.stop_propagation();
            }))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(
                        design_system::text_field(&self.terminal_search_input)
                            .dense()
                            .search()
                            .height(px(34.0)),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child(count),
                    ),
            )
            .child(
                div()
                    .mt_2()
                    .flex()
                    .justify_end()
                    .gap_1()
                    .child(
                        design_system::icon_button(
                            "terminal-search-previous",
                            "Previous Match",
                            AleraIcon::ChevronUp,
                            true,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.previous_terminal_search(cx);
                        })),
                    )
                    .child(
                        design_system::icon_button(
                            "terminal-search-next",
                            "Next Match",
                            AleraIcon::ChevronDown,
                            true,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.next_terminal_search(cx);
                        })),
                    )
                    .child(
                        design_system::icon_button(
                            "terminal-search-close",
                            "Close Search",
                            AleraIcon::Close,
                            true,
                            30.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.close_terminal_search(window, cx);
                        })),
                    ),
            )
            .into_any_element()
    }

    fn refresh_terminal_frame_view(&self, session_id: &str, cx: &mut Context<Self>) {
        let Some(snapshot) = self.terminal_frame_snapshot(session_id) else {
            return;
        };
        let Some(view) = self.terminal_frame_views.get(session_id).cloned() else {
            return;
        };
        view.update(cx, |view, cx| {
            view.snapshot = snapshot;
            cx.notify();
        });
    }

    pub(super) fn refresh_terminal_frame_views(&self, cx: &mut Context<Self>) {
        for session_id in self.terminal_frame_views.keys() {
            self.refresh_terminal_frame_view(session_id, cx);
        }
    }

    pub(super) fn flush_terminal_output_frames(&mut self, cx: &mut Context<Self>) {
        let dirty = std::mem::take(&mut self.terminal_output_dirty_sessions);
        for session_id in dirty {
            self.refresh_terminal_frame_view(&session_id, cx);
        }
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
            session.write_output(data);
            session.emulator.take_pty_writes()
        };
        for response in responses {
            self.write_terminal_bytes_for(session_id, response);
        }
        self.reset_terminal_cursor_blink();
        self.terminal_output_dirty_sessions
            .insert(session_id.to_owned());
        if self.terminal_app_foreground {
            self.schedule_terminal_output_frame(cx);
        }
    }

    /// PTY output can arrive in many small chunks during a command burst or a
    /// scrollback restore. Keep parser state current for every chunk, but pace
    /// sustained shaping to roughly 12 fps. The first output after an idle
    /// period still paints immediately, keeping typed-command echo responsive.
    fn schedule_terminal_output_frame(&mut self, cx: &mut Context<Self>) {
        if self.terminal_output_frame_scheduled {
            return;
        }
        const TERMINAL_STREAM_FRAME_INTERVAL: std::time::Duration =
            std::time::Duration::from_millis(50);
        let elapsed = self.terminal_output_last_frame_at.elapsed();
        if elapsed >= TERMINAL_STREAM_FRAME_INTERVAL {
            self.terminal_output_last_frame_at = std::time::Instant::now();
            self.flush_terminal_output_frames(cx);
            return;
        }
        self.terminal_output_frame_scheduled = true;
        let remaining = TERMINAL_STREAM_FRAME_INTERVAL - elapsed;
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(remaining).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                this.terminal_output_frame_scheduled = false;
                this.terminal_output_last_frame_at = std::time::Instant::now();
                this.flush_terminal_output_frames(cx);
            });
        })
        .detach();
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
        if name == "exit" {
            {
                let Some(session) = self.terminal_sessions.get_mut(session_id) else {
                    return;
                };
                session.running = false;
                session.operation = None;
                session.operation_started_at = None;
                session.error = Some("The Terminal Process Exited.".to_owned());
            }

            // Flutter removes an exited terminal tab through its exit
            // coordinator. GPUI must do the same itself instead of relying on
            // another client to refresh the shared snapshot.
            let tab_id = self
                .terminal_contexts()
                .into_iter()
                .find(|(handle, _, _, _)| handle == session_id)
                .map(|(_, _, tab_id, _)| tab_id);
            let auto_close_on_success = tab_id.as_ref().and_then(|tab_id| {
                self.snapshot
                    .tabs
                    .iter()
                    .find(|tab| &tab.id == tab_id)
                    .and_then(|tab| tab.payload.get("autoCloseOnSuccess"))
                    .and_then(Value::as_bool)
            }) == Some(true);
            let exit_code = payload.get("exitCode").and_then(Value::as_i64);
            if auto_close_on_success && exit_code != Some(0) {
                // Deferred Setup tabs are intentionally kept on failure so
                // the user can read the diagnostics and rerun the command.
                cx.notify();
                return;
            }
            if let Some(tab_id) = tab_id {
                self.close_exited_terminal_tab(tab_id, cx);
            }
            cx.notify();
            return;
        }
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        match name {
            "outputResyncRequired" => {
                if session.attaching || session.restore_in_progress() {
                    session.output_resync_deferred = true;
                    cx.notify();
                    return;
                }
                self.request_terminal_output_resync(session_id, cx);
            }
            _ => return,
        }
        cx.notify();
    }

    fn close_exited_terminal_tab(&mut self, tab_id: String, cx: &mut Context<Self>) {
        if !self.snapshot.tabs.iter().any(|tab| tab.id == tab_id) {
            return;
        }
        if !self.tab_mutation_busy {
            self.request_close_tab(tab_id, cx);
            return;
        }

        // A terminal can exit while another tab/layout mutation is still in
        // flight. Flutter's exit coordinator waits for that mutation; dropping
        // the close here leaves a durable tab pointing at a dead session.
        cx.spawn(async move |this, cx| loop {
            cx.background_executor()
                .timer(std::time::Duration::from_millis(50))
                .await;
            let Some(this) = this.upgrade() else {
                break;
            };
            let should_stop = this.update(cx, |this, cx| {
                if !this.snapshot.tabs.iter().any(|tab| tab.id == tab_id) {
                    return true;
                }
                if this.tab_mutation_busy {
                    return false;
                }
                this.request_close_tab(tab_id.clone(), cx);
                true
            });
            if should_stop {
                break;
            }
        })
        .detach();
    }

    /// Resume a client whose bounded output lane fell behind. A delta resume
    /// arrives on the terminal lane and is already handled by
    /// `handle_terminal_output`; a full resume carries a snapshot in the
    /// request response and must replace the emulator before new output is
    /// accepted. Ignoring that response leaves stale/duplicated scrollback in
    /// GPUI after reconnects or a long background pause.
    fn request_terminal_output_resync(&mut self, session_id: &str, cx: &mut Context<Self>) {
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
            return;
        };
        if session.output_resync_in_flight {
            return;
        }
        session.output_resync_in_flight = true;
        let bridge = self.bridge.clone();
        let session_id = session_id.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "setOutputPaused",
                    json!({ "sessionId": session_id, "paused": false }),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                let Some(session) = this.terminal_sessions.get_mut(&session_id) else {
                    return;
                };
                session.output_resync_in_flight = false;
                let mut restore_generation = None;
                let mut recover_attachment = false;
                match result {
                    Ok(payload)
                        if payload
                            .get("delta")
                            .and_then(Value::as_bool)
                            .unwrap_or(false) =>
                    {
                        // The host queued the missed bytes ahead of the
                        // resume response. No emulator replacement is needed.
                    }
                    Ok(payload) => {
                        let snapshot_dimensions = terminal_snapshot_dimensions(&payload);
                        let columns = session.columns;
                        let rows = session.rows;
                        let snapshot = payload
                            .get("snapshotBase64")
                            .and_then(Value::as_str)
                            .map(|encoded| BASE64_STANDARD.decode(encoded))
                            .transpose();
                        match snapshot {
                            Ok(Some(bytes)) => {
                                session.columns = columns;
                                session.rows = rows;
                                session.emulator = TerminalEmulator::new(columns, rows);
                                if payload
                                    .get("resetInteractionModes")
                                    .and_then(Value::as_bool)
                                    .unwrap_or(false)
                                {
                                    session.emulator.clear_selection();
                                }
                                restore_generation = Some(
                                    session.begin_restore_at_dimensions(
                                        bytes,
                                        snapshot_dimensions,
                                    ),
                                );
                                session.error = None;
                            }
                            Ok(None) => {
                                session.error =
                                    Some("Runtime returned an empty terminal snapshot.".into());
                            }
                            Err(error) => {
                                session.error =
                                    Some(format!("Terminal snapshot decode failed: {error}"));
                            }
                        }
                    }
                    Err(error) => {
                        if terminal_attachment_lost(&error) {
                            session.output_resync_deferred = true;
                            recover_attachment = true;
                        } else {
                            session.error = Some(format!("Terminal host unavailable: {error}"));
                        }
                    }
                }
                if let Some(generation) = restore_generation {
                    this.schedule_terminal_restore(session_id.clone(), generation, cx);
                }
                if this
                    .terminal_hovered_link
                    .as_ref()
                    .is_some_and(|(hovered_session, _)| hovered_session == &session_id)
                {
                    this.terminal_hovered_link = None;
                }
                if recover_attachment {
                    this.recover_terminal_session(session_id.clone(), false, cx);
                }
                cx.notify();
            });
        })
        .detach();
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
        session.operation = Some(if restart {
            TerminalSessionOperation::Restarting
        } else {
            TerminalSessionOperation::Reconnecting
        });
        session.operation_started_at = Some(std::time::Instant::now());
        session.error = None;
        let columns = session.columns;
        let rows = session.rows;
        self.terminal_restart_confirmation = None;
        let bridge = self.bridge.clone();
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_owned());
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
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
                    std::time::Duration::from_secs(10),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                let Some(session) = this.terminal_sessions.get_mut(&session_id) else {
                    return;
                };
                session.attaching = false;
                session.operation = None;
                session.operation_started_at = None;
                let mut restore_generation = None;
                let mut reattached = false;
                match result {
                    Ok(payload) => {
                        reattached = true;
                        let snapshot_dimensions = terminal_snapshot_dimensions(&payload);
                        let emulator = TerminalEmulator::new(columns, rows);
                        let restored_bytes = payload
                            .get("snapshotBase64")
                            .and_then(Value::as_str)
                            .map(|encoded| BASE64_STANDARD.decode(encoded))
                            .transpose();
                        let restored_bytes = match restored_bytes {
                            Ok(bytes) => bytes,
                            Err(error) => {
                                session.error = Some(error.to_string());
                                None
                            }
                        };
                        session.emulator = emulator;
                        session.columns = columns;
                        session.rows = rows;
                        if payload
                            .get("snapshotBase64")
                            .and_then(Value::as_str)
                            .is_some()
                        {
                            if let Some(bytes) = restored_bytes {
                                restore_generation = Some(
                                    session.begin_restore_at_dimensions(
                                        bytes,
                                        snapshot_dimensions,
                                    ),
                                );
                            }
                        }
                        session.running = payload
                            .get("running")
                            .and_then(Value::as_bool)
                            .unwrap_or(true);
                        session.error =
                            (!session.running).then(|| "The Terminal Process Exited.".to_owned());
                    }
                    Err(error) => {
                        session.error = Some(format!("Terminal host unavailable: {error}"));
                    }
                }
                let resume_deferred = reattached
                    && restore_generation.is_none()
                    && session.output_resync_deferred;
                if resume_deferred {
                    session.output_resync_deferred = false;
                }
                if let Some(generation) = restore_generation {
                    this.schedule_terminal_restore(session_id.clone(), generation, cx);
                }
                if resume_deferred {
                    this.request_terminal_output_resync(&session_id, cx);
                }
                this.reset_terminal_cursor_blink();
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn schedule_terminal_restore(
        &mut self,
        session_id: String,
        generation: u64,
        cx: &mut Context<Self>,
    ) {
        let batch_session_id = session_id.clone();
        cx.spawn(async move |this, cx| loop {
            cx.background_executor()
                .timer(std::time::Duration::from_millis(16))
                .await;
            let Some(this) = this.upgrade() else {
                break;
            };
            let (finished, deferred_resync) = this.update(cx, |this, cx| {
                let Some(session) = this.terminal_sessions.get_mut(&batch_session_id) else {
                    return (true, false);
                };
                if session.restore_generation() != generation {
                    return (true, false);
                }
                let active = session.restore_next_chunk(32 * 1024);
                let deferred_resync = !active && session.output_resync_deferred;
                if deferred_resync {
                    session.output_resync_deferred = false;
                }
                cx.notify();
                (!active, deferred_resync)
            });
            if deferred_resync {
                let session_id = batch_session_id.clone();
                this.update(cx, |this, cx| {
                    this.request_terminal_output_resync(&session_id, cx);
                });
            }
            if finished {
                break;
            }
        })
        .detach();
    }

    pub(super) fn refresh_terminal_viewport(&self, session_id: String, cx: &mut Context<Self>) {
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
                        "sessionId": session_id.clone(),
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
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if event.keystroke.key.eq_ignore_ascii_case("escape") {
            let toolbar_dragged = self.terminal_toolbar_drag.take().is_some();
            let toolbar_menu_closed = self.terminal_toolbar_menu.take().is_some();
            if toolbar_dragged || toolbar_menu_closed {
                cx.notify();
                cx.stop_propagation();
                return;
            }
        }
        if let Some(definition) = self.keyboard_shortcut_for_keystroke(&event.keystroke) {
            let terminal_first = self.settings_state.keyboard_terminal_policy == "terminalFirst";
            if !terminal_first || definition.allow_in_terminal {
                if let Some(action) = super::keyboard_actions::action_for_id(definition.id) {
                    // Flutter resolves application shortcuts inside the terminal
                    // focus handler before deciding whether to pass the key to the
                    // PTY. GPUI's terminal key context otherwise hides global
                    // bindings even though they are registered without a context.
                    window.dispatch_action(action, cx);
                    cx.stop_propagation();
                    return;
                }
            }
        }
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
                if let Some(session) = self.terminal_sessions.get_mut(&session_id) {
                    session.emulator.clear_restore_prompt_cleanup();
                }
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
            session.emulator.clear_restore_prompt_cleanup();
            session.emulator.clear_selection();
        }
        self.write_terminal_bytes_for(&session_id, bytes);
        cx.stop_propagation();
    }

    fn handle_terminal_scroll(
        &mut self,
        session_id: &str,
        event: &ScrollWheelEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let line_height = self.terminal_line_height();
        let sensitivity = self.settings_state.terminal_tui_scroll_sensitivity as i32;
        self.terminal_scrollbar_last_activity
            .insert(session_id.to_owned(), std::time::Instant::now());
        let Some(session) = self.terminal_sessions.get_mut(session_id) else {
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
        let character_width = gpui::px(self.terminal_character_width.max(1.0));
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
        let rendered_row = if y <= gpui::px(0.0) {
            0
        } else {
            (y / line_height).floor() as usize
        };
        let row = session
            .emulator
            .source_row_for_rendered_row(rendered_row.min(session.rows.saturating_sub(1)))?;
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
            // Keep an explicit drag owner. Some platform mouse bridges do not
            // set `MouseMoveEvent::dragging` for every intermediate move, but
            // Flutter continues extending the selection until pointer-up.
            self.terminal_selection_drag = Some(session_id.to_owned());
            cx.notify();
        }
    }

    fn update_terminal_link_hover(
        &mut self,
        session_id: &str,
        event: &MouseMoveEvent,
        cx: &mut Context<Self>,
    ) {
        // Flutter resolves the link on every hover so the cursor and
        // underline are visible before the user presses Cmd/Ctrl. The
        // modifier is required only by the activation path in
        // `activate_terminal_link`.
        let next = self
            .terminal_point_at(session_id, event.position)
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
        if !event.dragging() && self.terminal_selection_drag.as_deref() != Some(session_id) {
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
        self.terminal_selection_drag = None;
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
        let line_height = self.terminal_line_height();
        let family = if self.settings_state.terminal_font_family.trim().is_empty() {
            "monospace"
        } else {
            self.settings_state.terminal_font_family.trim()
        };
        let font_id = window.text_system().resolve_font(&font(family.to_owned()));
        self.terminal_character_width = window
            .text_system()
            .ch_advance(
                font_id,
                gpui::px(self.settings_state.terminal_font_size as f32),
            )
            .map(|width| f32::from(width).max(1.0))
            .unwrap_or_else(|_| (self.settings_state.terminal_font_size * 0.6).max(1.0) as f32);
        let character_width = gpui::px(self.terminal_character_width);
        let mut resized = Vec::new();
        for session in self.terminal_sessions.values_mut() {
            // Replay the host snapshot at the dimensions it was produced
            // with. Resizing an emulator halfway through restore makes zsh's
            // cursor-up prompt redraws become visible scrollback rows when a
            // window is zoomed during startup.
            if session.restore_in_progress() {
                continue;
            }
            // Wait for the rendered surface to report its real bounds. A
            // provisional window fallback can alternate with the measured
            // split bounds while GPUI is laying out, producing repeated PTY
            // SIGWINCH redraws and duplicated prompts in the host scrollback.
            let Some(bounds) = self.terminal_surface_bounds.get(&session.session_id) else {
                continue;
            };
            let content_width =
                bounds.size.width - gpui::px((self.settings_state.terminal_padding_x * 2.0) as f32);
            let content_height = bounds.size.height
                - gpui::px((self.settings_state.terminal_padding_y * 2.0) as f32);
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
            self.schedule_terminal_resize(session_id, columns, rows, cx);
        }
    }

    fn schedule_terminal_resize(
        &mut self,
        session_id: String,
        columns: usize,
        rows: usize,
        cx: &mut Context<Self>,
    ) {
        self.terminal_resize_pending
            .insert(session_id.clone(), (columns, rows));
        // A zoom animation can continue emitting bounds after an earlier
        // debounce timer fires. Incrementing the generation on every update
        // makes older timers inert, so only the final settled bounds reach the
        // PTY and zsh cannot redraw its prompt into the shared scrollback.
        let generation = self
            .terminal_resize_generation
            .entry(session_id.clone())
            .and_modify(|value| *value = value.wrapping_add(1))
            .or_insert(1)
            .to_owned();
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let mut first_wait = true;
            let (columns, rows) = loop {
                // Window zoom emits several intermediate bounds in GPUI. Give
                // the first request time to settle, then poll the shared
                // attachment lane without racing an attach or output resync.
                cx.background_executor()
                    .timer(std::time::Duration::from_millis(if first_wait {
                        650
                    } else {
                        50
                    }))
                    .await;
                first_wait = false;
                let Some(this) = this.upgrade() else {
                    return;
                };
                let (finished, request) = this.update(cx, |this, _| {
                    if this.terminal_resize_generation.get(&session_id).copied()
                        != Some(generation)
                    {
                        return (true, None);
                    }
                    let waiting = this
                        .terminal_sessions
                        .get(&session_id)
                        .is_some_and(|session| {
                            session.attaching
                                || session.output_resync_in_flight
                                || session.restore_in_progress()
                        });
                    if waiting {
                        return (false, None);
                    }
                    (true, this.terminal_resize_pending.remove(&session_id))
                });
                if !finished {
                    continue;
                }
                let Some(request) = request else {
                    return;
                };
                break request;
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let restore_generation = this.update(cx, |this, _| {
                this.terminal_sessions
                    .get_mut(&session_id)
                    .and_then(|session| session.rebuild_for_dimensions(columns, rows))
            });
            if let Some(restore_generation) = restore_generation {
                let restore_session_id = session_id.clone();
                this.update(cx, |this, cx| {
                    this.schedule_terminal_restore(restore_session_id, restore_generation, cx);
                });
            }
            let result = bridge
                .request(
                    "resize",
                    json!({
                        "sessionId": session_id.clone(),
                        "cols": columns,
                        "rows": rows,
                    }),
                )
                .await;
            if let Err(error) = result {
                if terminal_attachment_lost(&error) {
                    this.update(cx, |this, cx| {
                        this.recover_terminal_session(session_id, false, cx);
                    });
                }
            }
        })
        .detach();
    }

    pub(super) fn selected_terminal_session_id(&self) -> Option<String> {
        if let Some(command) = self.command_terminal.as_ref() {
            return Some(command.session_id.clone());
        }
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

    pub(super) fn write_terminal_bytes_with_deferred_enter_for(
        &self,
        session_id: &str,
        bytes: Vec<u8>,
    ) {
        let _ = self.bridge.send_ordered(
            "write",
            json!({
                "sessionId": session_id,
                "dataBase64": BASE64_STANDARD.encode(bytes),
                "deferredEnter": true,
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
        let body = session_id
            .and_then(|session_id| self.terminal_frame_views.get(session_id))
            .cloned()
            .map(|view| view.into_any_element())
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
        let hover_session_id = owned_session_id.clone();
        let finish_session_id = owned_session_id.clone();
        let finish_out_session_id = owned_session_id.clone();
        let bounds_session_id = owned_session_id.clone();
        let bounds_app = cx.entity().downgrade();
        let input_app = cx.entity();
        let input_focus = self.terminal_focus.clone();
        let focus = self.terminal_focus.clone();
        let drop_focus = self.terminal_focus.clone();
        let drop_session_id = owned_session_id.clone();
        // Keep the workspace root with the drop handler so paths from the file picker
        // are pasted relative to the same directory as the terminal session.
        let drop_workspace_path = self.selected_workspace_path();
        let scroll_session_id = owned_session_id.clone();
        let explorer_drop_focus = self.terminal_focus.clone();
        let explorer_drop_session_id = owned_session_id.clone();
        let background = self.terminal_background();
        let hovering_link = self
            .terminal_hovered_link
            .as_ref()
            .is_some_and(|(hovered_session_id, _)| hovered_session_id == &owned_session_id);
        let scrollbar = session_id
            .and_then(|session_id| self.terminal_sessions.get(session_id))
            .filter(|_| {
                self.terminal_scrollbar_drag.as_deref() == Some(owned_session_id.as_str())
                    || self
                        .terminal_scrollbar_last_activity
                        .get(&owned_session_id)
                        .is_some_and(|last| last.elapsed() < std::time::Duration::from_millis(800))
            })
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
                    session.operation,
                    session.error.clone().or_else(|| {
                        (!session.running).then(|| "The Terminal Process Exited.".to_owned())
                    }),
                )
            });
        let restore_progress = session_id
            .and_then(|session_id| self.terminal_sessions.get(session_id))
            .and_then(TerminalSession::restore_progress);
        let operation = terminal_state
            .as_ref()
            .and_then(|(_, operation, error)| error.is_none().then_some(*operation))
            .flatten()
            .map(|operation| {
                let elapsed = session_id
                    .and_then(|id| self.terminal_sessions.get(id))
                    .and_then(|session| session.operation_started_at)
                    .map(|started| started.elapsed().as_secs());
                self.render_terminal_operation_state(operation, elapsed)
            });
        let recovery = terminal_state
            .as_ref()
            .and_then(|(_, _, error)| error.as_deref())
            .map(|error| {
                self.render_terminal_recovery_state(&owned_session_id, error.to_owned(), cx)
            });
        let restart_confirmation = (self.terminal_restart_confirmation.as_deref()
            == Some(owned_session_id.as_str()))
        .then(|| self.render_terminal_restart_confirmation(&owned_session_id, cx));
        let toolbar = session_id
            .is_some()
            .then(|| self.render_terminal_toolbar(&owned_session_id, cx));
        let toolbar_menu = session_id
            .and_then(|_| self.render_terminal_toolbar_menu(&owned_session_id, cx));
        let mobile_driver_overlay = self.render_mobile_driver_overlay(&owned_session_id, cx);
        let search_overlay = session_id
            .as_deref()
            .filter(|_| self.terminal_search.is_some())
            .map(|session_id| self.render_terminal_search_overlay(session_id, cx));
        let composer_visible = active
            && self.terminal_composer_visible.contains(&owned_session_id)
            && self.terminal_composer_inputs.contains_key(&owned_session_id);
        let terminal_font_family = self.settings_state.terminal_font_family.clone();
        let toolbar_bounds_session_id = owned_session_id.clone();
        let toolbar_bounds_app = cx.entity();
        div()
            .id(SharedString::from(format!(
                "terminal-surface-{}",
                session_id.unwrap_or("none")
            )))
            .relative()
            .flex_1()
            .flex()
            .flex_col()
            .overflow_hidden()
            .bg(background)
            .px(gpui::px(self.settings_state.terminal_padding_x as f32))
            .py(gpui::px(self.settings_state.terminal_padding_y as f32))
            .when(!terminal_font_family.trim().is_empty(), |surface| {
                surface.font_family(terminal_font_family)
            })
            .font_weight(FontWeight(self.settings_state.terminal_font_weight as f32))
            .text_size(gpui::px(self.settings_state.terminal_font_size as f32))
            // Flutter's terminal view exposes a text cursor over the whole
            // surface and switches to a hand only for a resolved link.
            .cursor(if hovering_link {
                CursorStyle::PointingHand
            } else {
                CursorStyle::IBeam
            })
            .on_hover(cx.listener(move |this, hovered: &bool, _, cx| {
                if *hovered {
                    return;
                }
                if this
                    .terminal_hovered_link
                    .as_ref()
                    .is_some_and(|(session_id, _)| session_id == &hover_session_id)
                {
                    this.terminal_hovered_link = None;
                    cx.notify();
                }
            }))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseDownEvent, window, cx| {
                    if this.terminal_toolbar_menu.take().is_some() {
                        cx.notify();
                    }
                    if this.terminal_composer_menu_open.take().is_some() {
                        cx.notify();
                    }
                    if let Some(tab_id) = tab_id.clone() {
                        this.activate_workspace_tab(tab_id, cx);
                    }
                    this.reset_terminal_cursor_blink();
                    if this.activate_terminal_link(&selection_session_id, event, cx) {
                        window.focus(&focus, cx);
                        return;
                    }
                    this.begin_terminal_selection(&selection_session_id, event, cx);
                    window.focus(&focus, cx);
                }),
            )
            .on_mouse_move(cx.listener(move |this, event: &MouseMoveEvent, _, cx| {
                this.update_terminal_toolbar_drag(event.position, cx);
                this.update_terminal_link_hover(&link_session_id, event, cx);
                this.update_terminal_selection(&move_session_id, event, cx);
            }))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseUpEvent, window, cx| {
                    this.finish_terminal_selection(&finish_session_id, event, cx);
                    this.finish_terminal_toolbar_drag(window, cx);
                }),
            )
            .on_mouse_up_out(
                MouseButton::Left,
                cx.listener(move |this, event: &MouseUpEvent, window, cx| {
                    this.finish_terminal_selection(&finish_out_session_id, event, cx);
                    this.finish_terminal_toolbar_drag(window, cx);
                }),
            )
            .on_drop(cx.listener(move |this, paths: &ExternalPaths, window, cx| {
                if this.is_terminal_mobile_driven(&drop_session_id) {
                    cx.stop_propagation();
                    return;
                }
                let text = format_paths_for_terminal_paste(paths, drop_workspace_path.as_deref());
                if text.is_empty() {
                    return;
                }
                let bytes = this
                    .terminal_sessions
                    .get(&drop_session_id)
                    .map(|session| session.emulator.encode_paste(&text));
                if let Some(bytes) = bytes {
                    if let Some(session) = this.terminal_sessions.get_mut(&drop_session_id) {
                        session.emulator.clear_restore_prompt_cleanup();
                    }
                    this.write_terminal_bytes_for(&drop_session_id, bytes);
                    this.reset_terminal_cursor_blink();
                    window.focus(&drop_focus, cx);
                    cx.notify();
                }
            }))
            .on_drop(
                cx.listener(move |this, drag: &ExplorerDragData, window, cx| {
                    if this.is_terminal_mobile_driven(&explorer_drop_session_id) {
                        cx.stop_propagation();
                        return;
                    }
                    let text = format_terminal_path_for_paste(&drag.relative_path);
                    if text.is_empty() {
                        return;
                    }
                    let bytes = this
                        .terminal_sessions
                        .get(&explorer_drop_session_id)
                        .map(|session| session.emulator.encode_paste(&text));
                    if let Some(bytes) = bytes {
                        if let Some(session) =
                            this.terminal_sessions.get_mut(&explorer_drop_session_id)
                        {
                            session.emulator.clear_restore_prompt_cleanup();
                        }
                        this.write_terminal_bytes_for(&explorer_drop_session_id, bytes);
                        this.reset_terminal_cursor_blink();
                        window.focus(&explorer_drop_focus, cx);
                        cx.notify();
                    }
                }),
            )
            .child(
                div()
                    .relative()
                    .flex_1()
                    .overflow_hidden()
                    .track_focus(&self.terminal_focus)
                    .key_context("terminal")
                    .when(active, |terminal| {
                        terminal
                            .on_key_down(cx.listener(Self::handle_terminal_key))
                            .on_scroll_wheel(cx.listener(move |this, event, window, cx| {
                                this.handle_terminal_scroll(&scroll_session_id, event, window, cx);
                            }))
                    })
                    .child(body)
                    .when_some(toolbar, |viewport, toolbar| viewport.child(toolbar))
                    .when_some(toolbar_menu, |viewport, menu| viewport.child(menu))
                    .when_some(search_overlay, |viewport, overlay| viewport.child(overlay))
                    .child(
                        canvas(
                            move |bounds, _, cx| {
                                let _ = toolbar_bounds_app.update(cx, |this, _| {
                                    this.terminal_toolbar_viewport_bounds
                                        .insert(toolbar_bounds_session_id.clone(), bounds);
                                });
                            },
                            |_, _, _, _| {},
                        )
                        .absolute()
                        .inset_0(),
                    ),
            )
            .when_some(scrollbar, |surface, scrollbar| surface.child(scrollbar))
            .when_some(recovery, |surface, recovery| surface.child(recovery))
            .when_some(operation, |surface, operation| surface.child(operation))
            .when_some(restore_progress, |surface, (written, total)| {
                surface.child(self.render_terminal_restore_state(written, total))
            })
            .when_some(restart_confirmation, |surface, confirmation| {
                surface.child(confirmation)
            })
            .when(composer_visible, |surface| {
                surface.child(self.render_terminal_composer(&owned_session_id, cx))
            })
            .child(
                canvas(
                    move |bounds, _, cx| {
                        let _ = bounds_app.update(cx, |this, cx| {
                            let changed = this
                                .terminal_surface_bounds
                                .get(&bounds_session_id)
                                .is_none_or(|previous| *previous != bounds);
                            this.terminal_surface_bounds
                                .insert(bounds_session_id.clone(), bounds);
                            if changed {
                                cx.notify();
                            }
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

    fn render_terminal_operation_state(
        &self,
        operation: TerminalSessionOperation,
        elapsed: Option<u64>,
    ) -> AnyElement {
        let label = match operation {
            TerminalSessionOperation::Starting => "Starting Terminal",
            TerminalSessionOperation::Reconnecting => "Reconnecting Terminal",
            TerminalSessionOperation::Restarting => "Restarting Terminal",
        };
        div()
            .id("terminal-operation-state")
            .role(Role::ProgressIndicator)
            .aria_label(label)
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
            .font_family("Inter")
            .bg(self.terminal_background())
            .child(icon(AleraIcon::Loading, 36.0, theme::text_muted()))
            .child(div().text_size(gpui::px(13.0)).child(label))
            .when_some(
                elapsed.filter(|seconds| *seconds >= 3),
                |column, seconds| {
                    column.child(
                        div()
                            .text_size(gpui::px(12.0))
                            .text_color(theme::text_muted())
                            .child(format!("Elapsed: {seconds}s")),
                    )
                },
            )
            .into_any_element()
    }

    fn render_terminal_restore_state(&self, written: usize, total: usize) -> AnyElement {
        let fraction = (written as f32 / total.max(1) as f32).clamp(0.0, 1.0);
        let progress_width = 180.0 * fraction;
        div()
            .id("terminal-restore-state")
            .role(Role::ProgressIndicator)
            .aria_label("Restoring Terminal")
            .aria_numeric_value(f64::from(fraction))
            .aria_min_numeric_value(0.0)
            .aria_max_numeric_value(1.0)
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
            .font_family("Inter")
            .bg(self.terminal_background())
            .child(div().text_size(gpui::px(13.0)).child("Restoring Terminal"))
            .child(
                div()
                    .w(gpui::px(180.0))
                    .h(gpui::px(4.0))
                    .rounded(gpui::px(2.0))
                    .bg(theme::surface_raised())
                    .child(
                        div()
                            .h_full()
                            .w(gpui::px(progress_width))
                            .rounded(gpui::px(2.0))
                            .bg(theme::accent()),
                    ),
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
            .font_family("Inter")
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
                            .text_size(gpui::px(14.0))
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
                design_system::dialog_shell(
                    "restart-terminal-dialog",
                    "Restart Terminal?",
                    460.0,
                )
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
                // Flutter xterm measures a Paragraph and receives an integral
                // cell height from Skia. Match that rasterized row geometry
                // instead of rendering the raw fractional multiplier.
                .floor()
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
                        this.terminal_scrollbar_last_activity
                            .insert(down_session_id.clone(), std::time::Instant::now());
                        this.scroll_terminal_to_pointer(&down_session_id, event.position.y, cx);
                        cx.stop_propagation();
                    }),
                )
                .on_mouse_move(cx.listener(move |this, event: &MouseMoveEvent, _, cx| {
                    if event.dragging()
                        && this.terminal_scrollbar_drag.as_deref() == Some(move_session_id.as_str())
                    {
                        this.terminal_scrollbar_last_activity
                            .insert(move_session_id.clone(), std::time::Instant::now());
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

fn terminal_attachment_lost(error: &str) -> bool {
    error.contains("Terminal session is not attached")
        || error.contains("Terminal host connection closed")
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

fn format_paths_for_terminal_paste(paths: &ExternalPaths, workspace_path: Option<&str>) -> String {
    paths
        .paths()
        .iter()
        .filter_map(|path| {
            let value = workspace_relative_path(workspace_path, &path.to_string_lossy())
                .trim()
                .replace('\u{1b}', "\u{241b}");
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

fn format_terminal_path_for_paste(path: &str) -> String {
    let value = path.trim().replace('\u{1b}', "\u{241b}");
    if value.is_empty() {
        return String::new();
    }
    if value.chars().any(char::is_whitespace) {
        format!("'{}' ", value.replace('\'', "'\\''"))
    } else {
        format!("{value} ")
    }
}

fn workspace_relative_path(workspace_path: Option<&str>, file_path: &str) -> String {
    let Some(workspace_path) = workspace_path else {
        return file_path.to_owned();
    };
    let Ok(relative) = Path::new(file_path).strip_prefix(Path::new(workspace_path)) else {
        return file_path.to_owned();
    };
    let value = relative.to_string_lossy().to_string();
    if value.is_empty() {
        file_path.to_owned()
    } else {
        value
    }
}

fn terminal_snapshot_dimensions(payload: &Value) -> Option<(usize, usize)> {
    let columns = payload
        .get("snapshotCols")
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
        .filter(|value| *value > 0)?;
    let rows = payload
        .get("snapshotRows")
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
        .filter(|value| *value > 0)?;
    Some((columns, rows))
}

pub(super) fn terminal_session_id(tab: &WorkspaceTab) -> &str {
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

    #[test]
    fn snapshot_dimensions_require_two_positive_values() {
        assert_eq!(
            terminal_snapshot_dimensions(&json!({
                "snapshotCols": 180,
                "snapshotRows": 50,
            })),
            Some((180, 50))
        );
        assert_eq!(
            terminal_snapshot_dimensions(&json!({ "snapshotCols": 180 })),
            None
        );
        assert_eq!(
            terminal_snapshot_dimensions(&json!({
                "snapshotCols": 0,
                "snapshotRows": 50,
            })),
            None
        );
    }

    #[test]
    fn attachment_recovery_recognizes_host_detach_and_connection_loss() {
        assert!(terminal_attachment_lost(
            "Terminal session is not attached: session-1"
        ));
        assert!(terminal_attachment_lost(
            "Terminal host connection closed during resize"
        ));
        assert!(!terminal_attachment_lost("permission denied"));
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
