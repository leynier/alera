use super::*;

fn assert_render_search(terminal: &TerminalEmulator, query: &str) -> usize {
    let query = TerminalSearchQuery::new(query, false);
    let mut count = 0;
    for line in terminal.visible_lines("Alera Dark") {
        count += query.ranges(&line.plain_text).len();
        let highlights = search_highlights(
            &line.plain_text,
            line.highlights,
            &query,
            gpui::rgb(0xffff00).into(),
        );
        let mut end = 0;
        for (range, _) in &highlights {
            assert_eq!(range.start, end);
            assert!(line.plain_text.get(range.clone()).is_some());
            end = range.end;
        }
        assert_eq!(end, line.plain_text.len());
        let _ = StyledText::new(line.plain_text).with_highlights(highlights);
    }
    count
}

#[test]
fn terminal_search_redraw_replaces_cached_ascii_hits_with_current_unicode() {
    let mut terminal = TerminalEmulator::new(30, 3);
    terminal.write(b"a");
    let old_revision = terminal.search_revision();
    assert_eq!(terminal.search_matches("a", false).len(), 1);
    assert_eq!(assert_render_search(&terminal, "a"), 1);
    terminal.write("\r\u{1b}[2Ké".as_bytes());
    assert_ne!(old_revision, terminal.search_revision());
    assert_eq!(assert_render_search(&terminal, "a"), 0);
    assert_eq!(assert_render_search(&terminal, "é"), 1);
    terminal.write("\r\u{1b}[2Kİstanbul".as_bytes());
    assert_eq!(terminal.search_matches("i", false)[0].end, 2);
    assert_eq!(assert_render_search(&terminal, "i"), 1);
}

#[test]
fn terminal_search_reflow_and_scrollback_eviction_invalidate_results() {
    let mut terminal = TerminalEmulator::new(10, 3);
    terminal.write("a İ e\u{301} 界 long line".as_bytes());
    let before = terminal.search_revision();
    terminal.resize(5, 3);
    assert_ne!(before, terminal.search_revision());
    assert_render_search(&terminal, "i");
    let before = terminal.search_revision();
    // Erasing the screen can push its rows into history, so clear history last.
    terminal.write(b"\x1b[2J\x1b[3J\x1b[H");
    assert_ne!(before, terminal.search_revision());
    assert!(terminal.search_matches("i", false).is_empty());
    assert_eq!(assert_render_search(&terminal, "i"), 0);
    assert_ne!(
        terminal.search_revision(),
        TerminalEmulator::new(5, 3).search_revision()
    );
}

#[test]
fn terminal_search_batches_match_the_full_scrollback_query() {
    let mut terminal = TerminalEmulator::new(24, 3);
    for _ in 0..300 {
        terminal.write("\x1b[31mİ hit\x1b[0m\r\n".as_bytes());
    }
    let matcher = TerminalSearchQuery::new("i", false);
    let (_, history, rows) = terminal.scroll_metrics();
    let batched = (0..history + rows)
        .step_by(128)
        .flat_map(|start| terminal.search_matches_in_rows(&matcher, start..start + 128))
        .collect::<Vec<_>>();
    assert_eq!(batched, terminal.search_matches("i", false));
    assert_render_search(&terminal, "hit");
}

#[cfg(feature = "gpui-tests")]
#[gpui::test]
fn terminal_search_renders_unicode_and_ansi_after_redraw(cx: &mut gpui::TestAppContext) {
    use gpui::{ParentElement as _, Styled as _};
    struct SearchView {
        terminal: TerminalEmulator,
    }
    impl gpui::Render for SearchView {
        fn render(
            &mut self,
            _: &mut gpui::Window,
            _: &mut gpui::Context<Self>,
        ) -> impl gpui::IntoElement {
            let query = TerminalSearchQuery::new("i", false);
            gpui::div().flex().flex_col().children(
                self.terminal
                    .visible_lines("Alera Dark")
                    .into_iter()
                    .map(|line| {
                        let highlights = search_highlights(
                            &line.plain_text,
                            line.highlights,
                            &query,
                            gpui::rgb(0xffff00).into(),
                        );
                        gpui::StyledText::new(line.plain_text).with_highlights(highlights)
                    }),
            )
        }
    }
    let window = cx.add_window(|_, _| {
        let mut terminal = TerminalEmulator::new(30, 3);
        terminal.write("\u{1b}[31mİstanbul i\u{1b}[0m".as_bytes());
        SearchView { terminal }
    });
    cx.run_until_parked();
    window
        .update(cx, |view, _, cx| {
            view.terminal.write("\r\u{1b}[2Ké i".as_bytes());
            view.terminal.resize(12, 3);
            cx.notify();
        })
        .unwrap();
    cx.run_until_parked();
}
