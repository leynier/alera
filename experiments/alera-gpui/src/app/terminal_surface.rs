use base64::prelude::{Engine as _, BASE64_STANDARD};
use gpui::{
    div, AnyElement, Context, InteractiveElement as _, IntoElement as _, KeyDownEvent, MouseButton,
    ParentElement as _, ScrollWheelEvent, Styled as _, Window,
};
use serde_json::{json, Value};

use super::AleraApp;
use crate::terminal::{KeyModifiers, TerminalSession};
use crate::theme;

const TERMINAL_COLUMNS: usize = 100;
const TERMINAL_ROWS: usize = 30;

impl AleraApp {
    pub(super) fn ensure_selected_terminal(&mut self, cx: &mut Context<Self>) {
        let context =
            self.selected_workspace_id
                .as_deref()
                .and_then(|workspace_id| {
                    let workspace = self.snapshot.workspace(workspace_id)?;
                    let tab = self.selected_tab_id.as_deref().and_then(|tab_id| {
                        self.snapshot.tabs.iter().find(|tab| tab.id == tab_id)
                    })?;
                    (tab.kind == "terminal").then(|| {
                        let session_id = tab
                            .payload
                            .get("terminalSessionId")
                            .and_then(Value::as_str)
                            .filter(|value| !value.trim().is_empty())
                            .unwrap_or(&tab.id);
                        (
                            session_id.to_string(),
                            workspace.id.clone(),
                            tab.id.clone(),
                            workspace.path.clone(),
                        )
                    })
                });

        let Some((session_id, workspace_id, tab_id, working_directory)) = context else {
            self.detach_terminal(cx);
            return;
        };
        if self
            .terminal_session
            .as_ref()
            .is_some_and(|session| session.session_id == session_id)
        {
            return;
        }

        self.detach_terminal(cx);
        self.terminal_generation += 1;
        let generation = self.terminal_generation;
        self.terminal_session = Some(TerminalSession::new(session_id.clone()));
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
                if this.terminal_generation != generation {
                    return;
                }
                let Some(session) = this.terminal_session.as_mut() else {
                    return;
                };
                session.attaching = false;
                match result {
                    Ok(payload) => {
                        session.running = payload
                            .get("running")
                            .and_then(Value::as_bool)
                            .unwrap_or(true);
                        if let Some(encoded) = payload.get("snapshotBase64").and_then(Value::as_str)
                        {
                            match BASE64_STANDARD.decode(encoded) {
                                Ok(bytes) => session.emulator.write(&bytes),
                                Err(error) => session.error = Some(error.to_string()),
                            }
                        }
                    }
                    Err(error) => session.error = Some(error),
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn detach_terminal(&mut self, cx: &mut Context<Self>) {
        let Some(session) = self.terminal_session.take() else {
            return;
        };
        self.terminal_generation += 1;
        let bridge = self.bridge.clone();
        cx.spawn(async move |_, _| {
            let _ = bridge
                .request("detach", json!({ "sessionId": session.session_id }))
                .await;
        })
        .detach();
    }

    pub(super) fn handle_terminal_output(
        &mut self,
        session_id: &str,
        data: &[u8],
        cx: &mut Context<Self>,
    ) {
        let responses = {
            let Some(session) = self
                .terminal_session
                .as_mut()
                .filter(|session| session.session_id == session_id)
            else {
                return;
            };
            session.emulator.write(data);
            session.emulator.take_pty_writes()
        };
        for response in responses {
            self.write_terminal_bytes(response, cx);
        }
        cx.notify();
    }

    pub(super) fn handle_terminal_notification(
        &mut self,
        name: &str,
        payload: &Value,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = payload.get("sessionId").and_then(Value::as_str) else {
            return;
        };
        let Some(session) = self
            .terminal_session
            .as_mut()
            .filter(|session| session.session_id == session_id)
        else {
            return;
        };
        match name {
            "exit" => session.running = false,
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

    fn handle_terminal_key(
        &mut self,
        event: &KeyDownEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session) = self.terminal_session.as_ref() else {
            return;
        };
        let modifiers = event.keystroke.modifiers;
        if modifiers.control && modifiers.shift && event.keystroke.key.eq_ignore_ascii_case("v") {
            if let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) {
                let bytes = session.emulator.encode_paste(&text);
                self.write_terminal_bytes(bytes, cx);
                cx.stop_propagation();
            }
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
        self.write_terminal_bytes(bytes, cx);
        cx.stop_propagation();
    }

    fn handle_terminal_scroll(
        &mut self,
        event: &ScrollWheelEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(session) = self.terminal_session.as_mut() else {
            return;
        };
        let lines = (event.delta.pixel_delta(gpui::px(19.0)).y / gpui::px(19.0)).round() as i32;
        if lines == 0 {
            return;
        }
        session.emulator.scroll_display(lines);
        cx.stop_propagation();
        cx.notify();
    }

    pub(super) fn sync_terminal_size(&mut self, window: &Window, cx: &mut Context<Self>) {
        let Some(session) = self.terminal_session.as_mut() else {
            return;
        };
        let viewport = window.viewport_size();
        let content_width =
            viewport.width - theme::activity_rail_width() - theme::sidebar_width() - gpui::px(24.0);
        let content_height = viewport.height
            - theme::title_bar_height()
            - theme::tab_bar_height()
            - theme::status_bar_height()
            - gpui::px(24.0);
        let columns = ((content_width / gpui::px(7.8)).floor() as usize).max(2);
        let rows = ((content_height / gpui::px(19.0)).floor() as usize).max(2);
        if session.columns == columns && session.rows == rows {
            return;
        }
        session.columns = columns;
        session.rows = rows;
        session.emulator.resize(columns, rows);
        let session_id = session.session_id.clone();
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

    fn write_terminal_bytes(&self, bytes: Vec<u8>, cx: &mut Context<Self>) {
        let Some(session_id) = self
            .terminal_session
            .as_ref()
            .map(|session| session.session_id.clone())
        else {
            return;
        };
        let bridge = self.bridge.clone();
        cx.spawn(async move |_, _| {
            let _ = bridge
                .request(
                    "write",
                    json!({
                        "sessionId": session_id,
                        "dataBase64": BASE64_STANDARD.encode(bytes),
                    }),
                )
                .await;
        })
        .detach();
    }

    pub(super) fn render_terminal_surface(&self, cx: &mut Context<Self>) -> AnyElement {
        let focus = self.terminal_focus.clone();
        let (body, title) = match &self.terminal_session {
            Some(session) => {
                let mut lines = session
                    .emulator
                    .visible_lines()
                    .into_iter()
                    .map(|line| {
                        div()
                            .h(gpui::px(19.0))
                            .line_height(gpui::px(19.0))
                            .child(line.text)
                    })
                    .collect::<Vec<_>>();
                if session.attaching {
                    lines.push(
                        div()
                            .text_color(theme::text_muted())
                            .child("Attaching To Runtime Terminal"),
                    );
                }
                (
                    div().flex().flex_col().children(lines).into_any_element(),
                    session
                        .emulator
                        .title()
                        .unwrap_or_else(|| format!("{} × {}", session.columns, session.rows)),
                )
            }
            None => (
                div()
                    .text_color(theme::text_muted())
                    .child("Terminal Is Not Attached")
                    .into_any_element(),
                "Detached".to_string(),
            ),
        };

        div()
            .id("terminal-surface")
            .flex_1()
            .overflow_hidden()
            .bg(theme::app_background())
            .p_3()
            .font_family("JetBrains Mono")
            .text_size(gpui::px(13.0))
            .track_focus(&self.terminal_focus)
            .on_key_down(cx.listener(Self::handle_terminal_key))
            .on_scroll_wheel(cx.listener(Self::handle_terminal_scroll))
            .on_mouse_down(MouseButton::Left, move |_, window, _| {
                window.focus(&focus);
            })
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pb_2()
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(title)
                    .child("Ctrl+Shift+V To Paste · Wheel To Scroll"),
            )
            .child(div().flex_1().overflow_hidden().child(body))
            .into_any_element()
    }
}
