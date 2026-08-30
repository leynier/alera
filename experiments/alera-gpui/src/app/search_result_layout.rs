use gpui::{AnyElement, Div, ParentElement as _, Styled as _, StyledText, div, px};

use crate::theme;

pub(super) fn match_row(line: u32, preview: StyledText, action: AnyElement, depth: usize) -> Div {
    div()
        .w_full()
        .min_w_0()
        .flex()
        .items_start()
        .pt(px(4.0))
        .pb(px(6.0))
        .pr_2()
        .pl(px(8.0 + depth as f32 * 16.0))
        .child(div().w(px(32.0)).flex_shrink_0().text_align(gpui::TextAlign::Right)
            .font_family("JetBrains Mono").text_size(px(12.0))
            .text_color(theme::text_faint()).child(line.to_string()))
        .child(div().w(px(6.0)).flex_shrink_0())
        .child(div().flex_1().min_w_0().line_clamp(2)
            .font_family("JetBrains Mono").text_size(px(12.0)).line_height(px(16.0))
            .text_color(theme::text_muted()).child(preview))
        .child(div().w(px(4.0)).flex_shrink_0())
        .child(action)
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Context, InteractiveElement as _, IntoElement as _, ListAlignment, ListState, Render, TestAppContext, Window, list};

    struct SearchRowsProbe { list: ListState }

    impl Render for SearchRowsProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            div().w(px(280.0)).h(px(180.0)).child(
                list(self.list.clone(), |_, _, _| {
                    match_row(1, StyledText::new("base withreplacement_probe an unstaged review edit"),
                        div().w(px(24.0)).h(px(24.0)).flex_shrink_0()
                            .debug_selector(|| "replace-button".into()).into_any_element(), 1)
                        .debug_selector(|| "search-match-row".into()).into_any_element()
                }).size_full()
            )
        }
    }

    #[gpui::test]
    fn search_result_layout_keeps_replace_action_inside_narrow_virtual_row(cx: &mut TestAppContext) {
        cx.update(gpui_component::init);
        let (_, cx) = cx.add_window_view(|_, _| SearchRowsProbe { list: ListState::new(1, ListAlignment::Top, px(0.0)) });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let row = cx.debug_bounds("search-match-row").unwrap();
        let action = cx.debug_bounds("replace-button").unwrap();
        assert_eq!(row.size.width, px(280.0));
        assert_eq!(action.size.width, px(24.0));
        assert!(action.right() <= row.right() - px(8.0));
        assert!(row.size.height <= px(42.0), "preview must occupy at most two lines");
        assert!(row.size.height >= px(34.0));
    }
}
