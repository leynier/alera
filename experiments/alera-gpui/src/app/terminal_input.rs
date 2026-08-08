use std::ops::Range;

use gpui::{
    actions, App, Bounds, ClipboardItem, Context, EntityInputHandler, KeyBinding, Pixels, Point,
    UTF16Selection, Window,
};

use super::AleraApp;
use crate::terminal::KeyModifiers;

actions!(
    alera_terminal,
    [
        TerminalEnter,
        TerminalBackspace,
        TerminalDelete,
        TerminalTab,
        TerminalBackTab,
        TerminalEscape,
        TerminalUp,
        TerminalDown,
        TerminalLeft,
        TerminalRight,
        TerminalHome,
        TerminalEnd,
        TerminalPageUp,
        TerminalPageDown,
        TerminalCopy,
        TerminalPaste,
        TerminalInterrupt,
    ]
);

pub(super) fn register(cx: &mut App) {
    cx.bind_keys([
        KeyBinding::new("enter", TerminalEnter, None),
        KeyBinding::new("backspace", TerminalBackspace, None),
        KeyBinding::new("delete", TerminalDelete, None),
        KeyBinding::new("tab", TerminalTab, None),
        KeyBinding::new("shift-tab", TerminalBackTab, None),
        KeyBinding::new("escape", TerminalEscape, None),
        KeyBinding::new("up", TerminalUp, None),
        KeyBinding::new("down", TerminalDown, None),
        KeyBinding::new("left", TerminalLeft, None),
        KeyBinding::new("right", TerminalRight, None),
        KeyBinding::new("home", TerminalHome, None),
        KeyBinding::new("end", TerminalEnd, None),
        KeyBinding::new("pageup", TerminalPageUp, None),
        KeyBinding::new("pagedown", TerminalPageDown, None),
        KeyBinding::new("cmd-c", TerminalCopy, None),
        KeyBinding::new("ctrl-shift-c", TerminalCopy, None),
        KeyBinding::new("cmd-v", TerminalPaste, None),
        KeyBinding::new("ctrl-shift-v", TerminalPaste, None),
        KeyBinding::new("ctrl-c", TerminalInterrupt, None),
    ]);
}

impl EntityInputHandler for AleraApp {
    fn text_for_range(
        &mut self,
        range: Range<usize>,
        adjusted_range: &mut Option<Range<usize>>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<String> {
        let start = byte_index_for_utf16(&self.terminal_input_text, range.start);
        let end = byte_index_for_utf16(&self.terminal_input_text, range.end);
        let actual_start = self.terminal_input_text[..start].encode_utf16().count();
        let actual_end = self.terminal_input_text[..end].encode_utf16().count();
        adjusted_range.replace(actual_start..actual_end);
        Some(self.terminal_input_text[start..end].to_owned())
    }

    fn selected_text_range(
        &mut self,
        _: bool,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<UTF16Selection> {
        let end = self.terminal_input_text.encode_utf16().count();
        Some(UTF16Selection {
            range: end..end,
            reversed: false,
        })
    }

    fn marked_text_range(&self, _: &mut Window, _: &mut Context<Self>) -> Option<Range<usize>> {
        self.terminal_marked_text
            .as_ref()
            .map(|text| 0..text.encode_utf16().count())
    }

    fn unmark_text(&mut self, _: &mut Window, cx: &mut Context<Self>) {
        if let Some(text) = self.terminal_marked_text.take() {
            self.apply_terminal_text_replacement(None, &text, cx);
        }
    }

    fn replace_text_in_range(
        &mut self,
        range: Option<Range<usize>>,
        text: &str,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.terminal_marked_text = None;
        self.apply_terminal_text_replacement(range, text, cx);
    }

    fn replace_and_mark_text_in_range(
        &mut self,
        _: Option<Range<usize>>,
        new_text: &str,
        _: Option<Range<usize>>,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.terminal_marked_text = Some(new_text.to_owned());
        cx.notify();
    }

    fn bounds_for_range(
        &mut self,
        _: Range<usize>,
        element_bounds: Bounds<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<Bounds<Pixels>> {
        Some(Bounds::new(
            element_bounds.origin,
            gpui::size(gpui::px(1.0), self.terminal_line_height()),
        ))
    }

    fn character_index_for_point(
        &mut self,
        _: Point<Pixels>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<usize> {
        Some(0)
    }
}

impl AleraApp {
    fn apply_terminal_text_replacement(
        &mut self,
        range_utf16: Option<Range<usize>>,
        replacement: &str,
        cx: &mut Context<Self>,
    ) {
        let range_utf16 = range_utf16.unwrap_or_else(|| {
            let end = self.terminal_input_text.encode_utf16().count();
            end..end
        });
        let start = byte_index_for_utf16(&self.terminal_input_text, range_utf16.start);
        let end = byte_index_for_utf16(&self.terminal_input_text, range_utf16.end);
        let mut next = self.terminal_input_text.clone();
        next.replace_range(start..end, replacement);
        let common_bytes = self
            .terminal_input_text
            .char_indices()
            .zip(next.chars())
            .take_while(|((_, old), new)| old == new)
            .last()
            .map(|((index, character), _)| index + character.len_utf8())
            .unwrap_or(0);
        let removed = self.terminal_input_text[common_bytes..].chars().count();
        let added = &next[common_bytes..];
        let mut bytes = vec![0x7f; removed];
        bytes.extend_from_slice(added.as_bytes());
        self.terminal_input_text = next;
        if bytes.is_empty() {
            cx.notify();
            return;
        }
        let Some(session_id) = self.selected_terminal_session_id() else {
            return;
        };
        if self.is_terminal_mobile_driven(&session_id) {
            self.terminal_input_text.clear();
            self.terminal_marked_text = None;
            cx.stop_propagation();
            cx.notify();
            return;
        }
        if let Some(session) = self.terminal_sessions.get_mut(&session_id) {
            session.emulator.clear_selection();
        }
        self.reset_terminal_cursor_blink();
        self.write_terminal_bytes_for(&session_id, bytes);
        cx.notify();
    }

    fn send_terminal_named_key(
        &mut self,
        key: &str,
        modifiers: KeyModifiers,
        cx: &mut Context<Self>,
    ) {
        let Some(session_id) = self.selected_terminal_session_id() else {
            return;
        };
        if self.is_terminal_mobile_driven(&session_id) {
            cx.stop_propagation();
            return;
        }
        let Some(session) = self.terminal_sessions.get_mut(&session_id) else {
            return;
        };
        session.emulator.clear_selection();
        let bytes = session.emulator.encode_key(key, None, modifiers);
        if bytes.is_empty() {
            return;
        }
        match key {
            "backspace" => {
                self.terminal_input_text.pop();
            }
            _ => self.terminal_input_text.clear(),
        }
        self.terminal_marked_text = None;
        self.reset_terminal_cursor_blink();
        self.write_terminal_bytes_for(&session_id, bytes);
        cx.stop_propagation();
    }

    pub(super) fn on_terminal_copy(
        &mut self,
        _: &TerminalCopy,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.terminal_focus.is_focused(window) {
            cx.propagate();
            return;
        }
        let Some(text) = self
            .selected_terminal_session_id()
            .and_then(|session_id| self.terminal_sessions.get(&session_id))
            .and_then(|session| session.emulator.selected_text())
            .filter(|text| !text.is_empty())
        else {
            cx.propagate();
            return;
        };
        cx.write_to_clipboard(ClipboardItem::new_string(text));
        cx.stop_propagation();
    }

    pub(super) fn on_terminal_paste(
        &mut self,
        _: &TerminalPaste,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.terminal_focus.is_focused(window) {
            cx.propagate();
            return;
        }
        let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) else {
            cx.propagate();
            return;
        };
        let Some(session_id) = self.selected_terminal_session_id() else {
            return;
        };
        if self.is_terminal_mobile_driven(&session_id) {
            cx.stop_propagation();
            return;
        }
        let Some(session) = self.terminal_sessions.get_mut(&session_id) else {
            return;
        };
        session.emulator.clear_selection();
        let bytes = session.emulator.encode_paste(&text);
        self.terminal_input_text.clear();
        self.terminal_marked_text = None;
        self.reset_terminal_cursor_blink();
        self.write_terminal_bytes_for(&session_id, bytes);
        cx.stop_propagation();
    }
}

fn byte_index_for_utf16(text: &str, utf16_offset: usize) -> usize {
    let mut current = 0;
    for (index, character) in text.char_indices() {
        if current >= utf16_offset {
            return index;
        }
        current += character.len_utf16();
        if current > utf16_offset {
            return index;
        }
    }
    text.len()
}

macro_rules! terminal_key_action {
    ($method:ident, $action:ty, $key:literal) => {
        impl AleraApp {
            pub(super) fn $method(
                &mut self,
                _: &$action,
                window: &mut Window,
                cx: &mut Context<Self>,
            ) {
                if !self.terminal_focus.is_focused(window) {
                    cx.propagate();
                    return;
                }
                self.send_terminal_named_key($key, KeyModifiers::default(), cx);
            }
        }
    };
    ($method:ident, $action:ty, $key:literal, shift) => {
        impl AleraApp {
            pub(super) fn $method(
                &mut self,
                _: &$action,
                window: &mut Window,
                cx: &mut Context<Self>,
            ) {
                if !self.terminal_focus.is_focused(window) {
                    cx.propagate();
                    return;
                }
                self.send_terminal_named_key(
                    $key,
                    KeyModifiers {
                        shift: true,
                        ..KeyModifiers::default()
                    },
                    cx,
                );
            }
        }
    };
    ($method:ident, $action:ty, $key:literal, control) => {
        impl AleraApp {
            pub(super) fn $method(
                &mut self,
                _: &$action,
                window: &mut Window,
                cx: &mut Context<Self>,
            ) {
                if !self.terminal_focus.is_focused(window) {
                    cx.propagate();
                    return;
                }
                self.send_terminal_named_key(
                    $key,
                    KeyModifiers {
                        control: true,
                        ..KeyModifiers::default()
                    },
                    cx,
                );
            }
        }
    };
}

terminal_key_action!(on_terminal_enter, TerminalEnter, "enter");
terminal_key_action!(on_terminal_backspace, TerminalBackspace, "backspace");
terminal_key_action!(on_terminal_delete, TerminalDelete, "delete");
terminal_key_action!(on_terminal_tab, TerminalTab, "tab");
terminal_key_action!(on_terminal_back_tab, TerminalBackTab, "tab", shift);
terminal_key_action!(on_terminal_escape, TerminalEscape, "escape");
terminal_key_action!(on_terminal_up, TerminalUp, "up");
terminal_key_action!(on_terminal_down, TerminalDown, "down");
terminal_key_action!(on_terminal_left, TerminalLeft, "left");
terminal_key_action!(on_terminal_right, TerminalRight, "right");
terminal_key_action!(on_terminal_home, TerminalHome, "home");
terminal_key_action!(on_terminal_end, TerminalEnd, "end");
terminal_key_action!(on_terminal_page_up, TerminalPageUp, "pageup");
terminal_key_action!(on_terminal_page_down, TerminalPageDown, "pagedown");
terminal_key_action!(on_terminal_interrupt, TerminalInterrupt, "c", control);
