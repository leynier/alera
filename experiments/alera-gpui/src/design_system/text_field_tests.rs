use super::*;
use gpui::AppContext as _;

#[gpui::test]
fn input_label_follows_focus_and_unicode_value(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let cx = cx.add_empty_window();
    cx.update(|window, cx| {
        let input = cx.new(|cx| InputState::new(window, cx));
        let floats = |window: &Window, cx: &App| label_floats(
            input.focus_handle(cx).is_focused(window), !input.read(cx).value().is_empty(),
        );
        assert!(!floats(window, cx));
        input.update(cx, |input, cx| input.focus(window, cx));
        assert!(floats(window, cx));
        let other = cx.focus_handle();
        other.focus(window, cx);
        assert!(!floats(window, cx));
        input.update(cx, |input, cx| input.set_value("á界", window, cx));
        assert!(floats(window, cx));
        input.update(cx, |input, cx| input.set_value("", window, cx));
        assert!(!floats(window, cx));
    });
}
