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

struct LabelGeometry { input: Entity<InputState> }
impl gpui::Render for LabelGeometry {
    fn render(&mut self, _: &mut Window, _: &mut gpui::Context<Self>) -> impl IntoElement {
        div().p(px(20.0)).w(px(420.0)).child(text_field(&self.input).label("Workspace Name"))
    }
}

#[gpui::test]
fn input_label_notch_covers_the_outline_without_a_crossed_label(cx: &mut gpui::TestAppContext) {
    cx.update(gpui_component::init);
    let (view, cx) = cx.add_window_view(|window, cx| {
        let input = cx.new(|cx| InputState::new(window, cx));
        input.update(cx, |input, cx| input.set_value("Fixture", window, cx));
        LabelGeometry { input }
    });
    cx.run_until_parked();
    let field_id = cx.update(|window, cx| { let _ = window.draw(cx); view.read(cx).input.entity_id() });
    // The pinned test API requires static selectors, even for entity-derived IDs.
    let outline_selector = Box::leak(format!("field-outline-{field_id}").into_boxed_str());
    let notch_selector = Box::leak(format!("field-label-notch-{field_id}").into_boxed_str());
    let outline = cx.debug_bounds(outline_selector).unwrap();
    let notch = cx.debug_bounds(notch_selector).unwrap();
    assert_eq!(notch.top(), outline.top(), "label mask must cover the border, not the first content pixel");
    assert_eq!(notch.size.height, px(1.0));
    assert!(notch.size.width > px(50.0), "label mask collapsed to {:?}", notch.size.width);
}
