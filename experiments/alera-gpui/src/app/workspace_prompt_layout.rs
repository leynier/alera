use gpui::{Div, InteractiveElement as _, ParentElement as _, ScrollHandle, StatefulInteractiveElement as _, Styled as _, div, px};
use gpui_component::scroll::{Scrollbar, ScrollbarMode};

pub(super) fn prompt_form(content: Div, scroll: &ScrollHandle) -> Div {
    div().relative().flex().flex_col().min_h_0().mt(px(20.0))
        .child(div().id("workspace-prompt-form-scroll")
            .debug_selector(|| "workspace-prompt-form-viewport".into())
            .min_h_0().track_scroll(scroll).overflow_y_scroll()
            .child(content.flex_shrink_0()))
        .child(Scrollbar::vertical(scroll).id("workspace-prompt-form-scrollbar").mode(ScrollbarMode::Scrolling))
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Context, IntoElement, Render, TestAppContext, Window, point};

    struct FormProbe { scroll: ScrollHandle }

    impl Render for FormProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            div().w(px(620.0)).h(px(300.0)).flex().flex_col()
                .child(div().h(px(40.0)).flex_shrink_0())
                .child(div().h(px(30.0)).flex_shrink_0())
                .child(prompt_form(div().h(px(500.0)).child("long form"), &self.scroll))
        }
    }

    #[gpui::test]
    fn workspace_prompt_gap_stays_outside_the_scroll_viewport(cx: &mut TestAppContext) {
        cx.update(gpui_component::init);
        let (view, cx) = cx.add_window_view(|_, _| FormProbe { scroll: ScrollHandle::new() });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let before = cx.debug_bounds("workspace-prompt-form-viewport").unwrap();
        assert_eq!(before.top(), px(90.0));
        cx.update(|_, cx| view.update(cx, |view, cx| {
            view.scroll.set_offset(point(px(0.0), px(-120.0)));
            cx.notify();
        }));
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let after = cx.debug_bounds("workspace-prompt-form-viewport").unwrap();
        assert_eq!(after, before);
        assert!(after.bottom() <= px(300.0));
    }
}
