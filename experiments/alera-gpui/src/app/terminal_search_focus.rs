use gpui::{App, FocusHandle, Window};

pub(super) fn restore_search_owner_focus(
    searched_session: &str,
    active_session: Option<&str>,
    terminal_focus: &FocusHandle,
    window: &mut Window,
    cx: &mut App,
) {
    // A hidden search can be dismissed after switching to an editor or another
    // terminal. Only return focus while its original terminal is still active.
    if active_session == Some(searched_session) {
        terminal_focus.focus(window, cx);
    }
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;

    #[gpui::test]
    fn closing_search_restores_only_its_active_terminal(cx: &mut gpui::TestAppContext) {
        let cx = cx.add_empty_window();
        cx.update(|window, cx| {
            let input_focus = cx.focus_handle();
            let terminal_focus = cx.focus_handle();
            input_focus.focus(window, cx);
            restore_search_owner_focus("one", Some("one"), &terminal_focus, window, cx);
            assert!(terminal_focus.is_focused(window));

            for active in [None, Some("two")] {
                input_focus.focus(window, cx);
                restore_search_owner_focus("one", active, &terminal_focus, window, cx);
                assert!(input_focus.is_focused(window));
            }
        });
    }
}
