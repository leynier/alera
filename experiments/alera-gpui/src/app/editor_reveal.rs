use std::ops::Range;

use gpui::{App, Context, FocusHandle, Focusable as _, Window};

use super::{AleraApp, EditorDocument};
use super::editor_requests::EditorKey;

#[derive(Clone)]
pub(super) struct EditorReveal {
    pub key: EditorKey,
    pub line: usize,
    pub column: usize,
    pub length: usize,
    pub invoking_focus: Option<FocusHandle>,
}

impl EditorReveal {
    fn focus_is_current(&self, input_focus: &FocusHandle, window: &Window, cx: &App) -> bool {
        let current = window.focused(cx);
        current == self.invoking_focus || input_focus.is_focused(window)
    }
}

// Search columns/counts are Unicode scalars, not UTF-16 or byte offsets.
pub(super) fn scalar_range(text: &str, line: usize, column: usize, length: usize) -> Range<usize> {
    let mut start = 0;
    for (index, segment) in text.split_inclusive('\n').enumerate() {
        if index == line {
            let segment = segment.trim_end_matches(['\r', '\n']);
            let byte = |column| segment.char_indices().nth(column).map_or(segment.len(), |(byte, _)| byte);
            return (start + byte(column))..(start + byte(column.saturating_add(length)));
        }
        start += segment.len();
    }
    text.len()..text.len()
}

fn search_display_range(document: &EditorDocument, current: &str, reveal: &EditorReveal) -> Range<usize> {
    let raw_line = document.raw_content.split('\n').nth(reveal.line).unwrap_or("");
    let expanded_column = |count: usize| {
        raw_line.chars().take(count).fold(0, |column, ch| {
            if ch == '\t' { column + 4 - column % 4 } else { column + 1 }
        })
    };
    // WorkspaceService currently requests four-column expansion from the host.
    let start = expanded_column(reveal.column);
    let end = expanded_column(reveal.column.saturating_add(reveal.length));
    scalar_range(current, reveal.line, start, end.saturating_sub(start))
}

impl AleraApp {
    pub(super) fn apply_pending_editor_reveal(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(reveal) = self.pending_editor_cursor.clone() else { return; };
        if self.selected_editor_key().as_ref() != Some(&reveal.key) { return; }
        let Some(input) = self.owned_editor_input(&reveal.key) else { return; };
        let Some(document) = self.editor_documents.get(&reveal.key.path) else { return; };
        if !reveal.focus_is_current(&input.focus_handle(cx), window, cx) {
            self.pending_editor_cursor = None;
            return;
        }
        let content = input.read(cx).value().to_string();
        let range = search_display_range(document, &content, &reveal);
        self.pending_editor_cursor = None;
        input.update(cx, |input, cx| {
            input.set_selected_range(range, cx);
            input.focus(window, cx);
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn editor_reveal_uses_scalar_columns_and_utf8_ranges() {
        let text = "first\r\nİ😀e\u{301}界\r\n";
        let range = scalar_range(text, 1, 1, 4);
        assert_eq!(&text[range], "😀e\u{301}界");
        assert_eq!(scalar_range(text, 99, 1, 4), text.len()..text.len());
        let end = scalar_range(text, 1, usize::MAX, usize::MAX);
        assert!(end.is_empty());
    }

    #[test]
    fn editor_reveal_maps_raw_tabs_to_display_columns() {
        let document = EditorDocument {
            relative_path: "same.txt".into(), raw_content: "a\t😀é\r\n".into(),
            display_content: "a   😀é\r\n".into(), content_token: "token".into(),
        };
        let reveal = EditorReveal { key: EditorKey { workspace: "a".into(), path: "same.txt".into() }, line: 0, column: 2, length: 2, invoking_focus: None };
        let range = search_display_range(&document, &document.display_content, &reveal);
        assert_eq!(&document.display_content[range], "😀é");
    }

    #[cfg(feature = "gpui-tests")]
    #[gpui::test]
    fn editor_reveal_does_not_replace_a_new_focus_owner(cx: &mut gpui::TestAppContext) {
        let cx = cx.add_empty_window();
        cx.update(|window, cx| {
            let invoker = cx.focus_handle();
            let editor = cx.focus_handle();
            let other = cx.focus_handle();
            let reveal = EditorReveal { key: EditorKey { workspace: "a".into(), path: "same.txt".into() }, line: 0, column: 0, length: 0, invoking_focus: Some(invoker.clone()) };
            invoker.focus(window, cx);
            assert!(reveal.focus_is_current(&editor, window, cx));
            other.focus(window, cx);
            assert!(!reveal.focus_is_current(&editor, window, cx));
            editor.focus(window, cx);
            assert!(reveal.focus_is_current(&editor, window, cx));
        });
    }
}
