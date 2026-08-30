use gpui::{App, CursorStyle, Entity, Focusable as _, FontWeight, InteractiveElement as _, IntoElement, MouseButton, ParentElement as _, RenderOnce, SharedString, Styled as _, Window, div, px};
use gpui_component::input::{Textarea, TextareaState};

use crate::theme;

#[derive(IntoElement)]
pub struct AleraTextArea {
    state: Entity<TextareaState>,
    label: SharedString,
    disabled: bool,
}

impl AleraTextArea {
    pub fn new(state: &Entity<TextareaState>, label: impl Into<SharedString>) -> Self {
        Self { state: state.clone(), label: label.into(), disabled: false }
    }

    pub fn disabled(mut self, disabled: bool) -> Self { self.disabled = disabled; self }
}

impl RenderOnce for AleraTextArea {
    fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement {
        let focused = !self.disabled && self.state.focus_handle(cx).is_focused(window);
        let floating = focused || !self.state.read(cx).value().is_empty();
        let viewport = window.use_keyed_state(("alera-textarea-viewport", self.state.entity_id()), cx, |_, _| TextareaViewport::default());
        let input = self.state.clone();
        let disabled = self.disabled;
        let background = theme::surface_selected();
        let field = div().relative().w_full().rounded(px(6.0)).border_1()
            .border_color(if focused { theme::accent() } else { theme::border() })
            .bg(background).cursor(if self.disabled { CursorStyle::Arrow } else { CursorStyle::IBeam })
            // The maintained textarea already contributes 10/8 px padding.
            // Account for its inset and GPUI's layout border to match Flutter's
            // desktop 16/6 px text inset without changing the editing engine.
            .child(div().overflow_hidden().child(
                Textarea::new(&self.state).appearance(false).disabled(self.disabled)
                    .aria_label(self.label.clone()).w_full().px(px(5.0)).my(px(-3.0))
                    .text_size(px(14.0)).line_height(px(21.0))))
            .child(gpui::canvas(move |frame, window, cx| {
                if disabled || !input.focus_handle(cx).is_focused(window) { return; }
                let key = (input.read(cx).cursor(), frame.size);
                if !viewport.update(cx, |viewport, _| viewport.request(key)) { return; }
                let input = input.clone();
                let viewport = viewport.clone();
                // The component publishes its final caret bounds during paint
                // and clears deferred offsets then. Apply only after that frame.
                window.on_next_frame(move |window, cx| {
                    if !input.focus_handle(cx).is_focused(window)
                        || input.read(cx).cursor() != key.0
                        || viewport.read(cx).last_request != Some(key) { return; }
                    let (caret, line_height, bounds, offset) = {
                        let state = input.read(cx);
                        let Some((caret, line_height)) = state.cursor_layout() else { return; };
                        (caret, line_height, state.input_bounds(), state.scroll_offset())
                    };
                    if let Some(y) = caret_scroll_offset(caret, line_height, bounds, offset.y) {
                        input.update(cx, |state, cx| state.set_scroll_offset(gpui::point(offset.x, y), cx));
                    }
                });
            }, |_, _, _, _| {}).absolute().size_full());
        if floating {
            field.child(div().absolute().top(px(-6.0)).left(px(8.0)).px(px(4.0))
                .text_size(px(8.25)).line_height(px(12.0)).font_weight(FontWeight::MEDIUM)
                .text_color(if focused { theme::accent() } else { theme::text_muted() })
                .child(div().absolute().left_0().right_0().top(px(6.0)).h(px(1.0)).bg(background))
                .child(self.label))
        } else {
            let state = self.state.clone();
            field.child(div().id(("textarea-inline-label", self.state.entity_id()))
                .absolute().top(px(1.0)).bottom(px(1.0)).left(px(12.0)).right(px(12.0))
                .flex().items_center().bg(background)
                .text_size(px(11.0)).font_weight(FontWeight::MEDIUM).text_color(theme::text_muted())
                .on_mouse_down(MouseButton::Left, move |_, window, cx| {
                    if !self.disabled { state.update(cx, |state, cx| state.focus(window, cx)); }
                })
                .child(self.label))
        }
    }
}

#[derive(Default)]
struct TextareaViewport {
    last_request: Option<(usize, gpui::Size<gpui::Pixels>)>,
}

impl TextareaViewport {
    fn request(&mut self, key: (usize, gpui::Size<gpui::Pixels>)) -> bool {
        if self.last_request == Some(key) { return false; }
        self.last_request = Some(key);
        true
    }
}

fn caret_scroll_offset(caret: gpui::Bounds<gpui::Pixels>, line_height: gpui::Pixels, bounds: gpui::Bounds<gpui::Pixels>, current: gpui::Pixels) -> Option<gpui::Pixels> {
        let top = caret.top() - (line_height - caret.size.height) / 2.0;
        if bounds.size.height <= px(0.0) { return None; }
        // The component advances only one row after a selection change. Use
        // final layout bounds for multi-line pastes, without changing focus,
        // selection or IME, and leave subsequent manual scrolling alone.
        let target = if top + current < bounds.top() {
            bounds.top() - top
        } else if top + line_height + current > bounds.bottom() {
            bounds.bottom() - top - line_height
        } else { current }.min(px(0.0));
        (target != current).then_some(target)
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{AppContext as _, Context, Render, TestAppContext};

    struct TextareaProbe { state: Entity<TextareaState> }

    impl Render for TextareaProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            div().w(px(580.0)).child(div().debug_selector(|| "textarea-frame".into())
                .child(AleraTextArea::new(&self.state, "Initial Prompt")))
        }
    }

    #[gpui::test]
    fn textarea_layout_grows_from_four_to_eight_rows(cx: &mut TestAppContext) {
        cx.update(gpui_component::init);
        cx.update(super::super::configure_component_theme);
        let (view, cx) = cx.add_window_view(|window, cx| TextareaProbe {
            state: cx.new(|cx| TextareaState::new(window, cx).auto_grow(4, 8).soft_wrap(true)),
        });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let before = cx.debug_bounds("textarea-frame").unwrap().size.height;
        cx.update(|window, cx| view.update(cx, |view, cx| {
            view.state.update(cx, |state, cx| state.set_value("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten", window, cx));
            cx.notify();
        }));
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let after = cx.debug_bounds("textarea-frame").unwrap().size.height;
        assert_eq!(before, px(96.0), "match measured Flutter macOS four-row field");
        assert_eq!(after, px(180.0), "match measured Flutter macOS eight-row field");
    }

    #[gpui::test]
    fn textarea_paste_reveals_the_final_line(cx: &mut TestAppContext) {
        cx.update(gpui_component::init);
        cx.update(super::super::configure_component_theme);
        let (view, cx) = cx.add_window_view(|window, cx| TextareaProbe {
            state: cx.new(|cx| TextareaState::new(window, cx).auto_grow(4, 8).soft_wrap(true)),
        });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        cx.update(|window, cx| view.update(cx, |view, cx| {
            view.state.update(cx, |state, cx| {
                state.focus(window, cx);
                state.insert("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten", window, cx);
            });
            cx.notify();
        }));
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        cx.update(|window, cx| { window.simulate_next_frame(cx); });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        cx.update(|_, cx| {
            let state = view.read(cx).state.read(cx);
            assert!(state.scroll_offset().y <= px(-42.0), "offset {:?}, text {:?}, input {:?}, cursor {:?}", state.scroll_offset(), state.text_bounds(), state.input_bounds(), state.cursor_layout());
        });
        cx.update(|_, cx| view.read(cx).state.clone().update(cx, |state, cx| state.set_scroll_offset(gpui::point(px(0.0), px(0.0)), cx)));
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        cx.update(|_, cx| assert_eq!(view.read(cx).state.read(cx).scroll_offset().y, px(0.0), "manual scrolling must not snap back to the caret"));
    }
}
