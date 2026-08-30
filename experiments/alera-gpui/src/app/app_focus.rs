use gpui::{App, FocusHandle, Window};

pub(super) fn initialize_shell_focus(window: &mut Window, cx: &mut App) -> FocusHandle {
    let focus = cx.focus_handle();
    if window.focused(cx).is_none() {
        focus.focus(window, cx);
    }
    focus
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Context, InteractiveElement as _, IntoElement, KeyBinding, ParentElement as _, Render, TestAppContext, div};
    use crate::app::keyboard_actions::OpenAutomations;

    struct Probe { focus: FocusHandle, calls: usize }
    impl Render for Probe {
        fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
            div().id("framework-root").child(div().id("application-root").track_focus(&self.focus)
                .on_action(cx.listener(|this, _: &OpenAutomations, _, cx| { this.calls += 1; cx.notify(); }))
                .child("Welcome"))
        }
    }

    #[gpui::test]
    fn shell_focus_dispatches_shortcuts_without_a_terminal_or_input(cx: &mut TestAppContext) {
        cx.update(|cx| cx.bind_keys([KeyBinding::new("cmd-shift-a", OpenAutomations, None)]));
        let (view, cx) = cx.add_window_view(|window, cx| Probe { focus: initialize_shell_focus(window, cx), calls: 0 });
        cx.run_until_parked();
        cx.simulate_keystrokes("cmd-shift-a");
        cx.update(|_, cx| assert_eq!(view.read(cx).calls, 1));
    }

    #[gpui::test]
    fn shell_focus_initialization_preserves_an_existing_focus_owner(cx: &mut TestAppContext) {
        cx.add_window_view(|window, cx| {
            let previous = cx.focus_handle();
            previous.focus(window, cx);
            let focus = initialize_shell_focus(window, cx);
            assert!(previous.is_focused(window));
            assert!(!focus.is_focused(window));
            Probe { focus, calls: 0 }
        });
    }
}
