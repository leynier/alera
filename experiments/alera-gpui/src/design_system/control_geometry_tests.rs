use super::*;
use gpui::{Context, Render, TestAppContext};

struct ButtonsProbe;

impl Render for ButtonsProbe {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div().w(px(400.0)).h(px(300.0)).flex().flex_col().children([
            ("filled", ButtonKind::Filled), ("outlined", ButtonKind::Outlined),
            ("text", ButtonKind::Text), ("elevated", ButtonKind::Elevated),
        ].map(|(id, kind)| button(id, "Action", kind, false).debug_selector(move || id.into())))
    }
}

#[gpui::test]
fn material_buttons_match_measured_desktop_density(cx: &mut TestAppContext) {
    cx.update(gpui_component::init);
    cx.update(configure_component_theme);
    let (_, cx) = cx.add_window_view(|_, _| ButtonsProbe);
    cx.run_until_parked();
    cx.update(|window, cx| { let _ = window.draw(cx); });
    for (id, height) in [("filled", 26.0), ("outlined", 26.0), ("text", 32.0), ("elevated", 32.0)] {
        assert_eq!(cx.debug_bounds(id).unwrap().size.height, px(height));
    }
}
