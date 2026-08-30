use std::rc::Rc;
use gpui::{App, AppContext as _, CursorStyle, DragMoveEvent, Empty, InteractiveElement as _, MouseButton, MouseDownEvent, MouseUpEvent, ParentElement as _, Pixels, Point, Role, StatefulInteractiveElement as _, Styled as _, Window, div, px};
use crate::theme;

#[derive(Clone)]
struct MasterResizeDrag;

pub(super) fn handle(
    label: &'static str,
    start: impl Fn(&MouseDownEvent, &mut Window, &mut App) + 'static,
    update: impl Fn(&Point<Pixels>, &mut Window, &mut App) + 'static,
    finish: impl Fn(&MouseUpEvent, &mut Window, &mut App) + 'static,
) -> gpui::Stateful<gpui::Div> {
    let finish = Rc::new(finish);
    let finish_out = finish.clone();
    let update = Rc::new(update);
    let update_up = update.clone();
    let update_out = update.clone();
    div().id("settings-master-detail-resize-handle").debug_selector(|| "master-resize-grip".into())
        .role(Role::Splitter).aria_label(label).w(px(33.0)).h_full().flex_shrink_0().flex().items_center().justify_center()
        .cursor(CursorStyle::ResizeLeftRight)
        .on_mouse_down(MouseButton::Left, start)
        .on_drag(MasterResizeDrag, |_, _, _, cx| cx.new(|_| Empty))
        .on_drag_move(move |event: &DragMoveEvent<MasterResizeDrag>, window, cx| update(&event.event.position, window, cx))
        // The move that arms a drag has no DragMove callback; release is authoritative too.
        .on_mouse_up(MouseButton::Left, move |event, window, cx| { update_up(&event.position, window, cx); finish(event, window, cx); })
        .on_mouse_up_out(MouseButton::Left, move |event, window, cx| { update_out(&event.position, window, cx); finish_out(event, window, cx); })
        .child(div().w(px(1.0)).h_full().bg(theme::border_subtle()))
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Context, IntoElement, Modifiers, Pixels, Point, Render, TestAppContext, point};

    struct Probe { width: f32, start: Option<(Point<Pixels>, f32)> }
    impl Render for Probe {
        fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
            div().w(px(600.0)).h(px(300.0)).flex().on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                .child(div().w(px(self.width)).h_full().flex_shrink_0())
                .child(handle("Resize Test List", cx.listener(|this, event: &MouseDownEvent, _, cx| {
                    this.start = Some((event.position, this.width)); cx.notify();
                }), cx.listener(|this, position: &Point<Pixels>, _, cx| {
                    if let Some((start, width)) = this.start {
                        this.width = (width + f32::from(position.x - start.x)).clamp(180.0, 420.0); cx.notify();
                    }
                }), cx.listener(|this, _, _, cx| { this.start = None; cx.notify(); })))
        }
    }

    #[gpui::test]
    fn master_detail_resize_tracks_drag_outside_grip_and_finishes(cx: &mut TestAppContext) {
        let (view, cx) = cx.add_window_view(|_, _| Probe { width: 240.0, start: None });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let from = cx.debug_bounds("master-resize-grip").unwrap().center();
        cx.simulate_mouse_down(from, MouseButton::Left, Modifiers::default());
        cx.simulate_mouse_move(from + point(px(12.0), px(0.0)), Some(MouseButton::Left), Modifiers::default());
        cx.simulate_mouse_move(from + point(px(60.0), px(0.0)), None, Modifiers::default());
        cx.simulate_mouse_up(from + point(px(60.0), px(0.0)), MouseButton::Left, Modifiers::default());
        cx.run_until_parked();
        cx.update(|_, cx| { let view = view.read(cx); assert_eq!(view.width, 300.0); assert!(view.start.is_none()); });
    }

    #[gpui::test]
    fn master_detail_resize_commits_a_coalesced_single_move_on_release(cx: &mut TestAppContext) {
        let (view, cx) = cx.add_window_view(|_, _| Probe { width: 240.0, start: None });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let from = cx.debug_bounds("master-resize-grip").unwrap().center();
        let to = from + point(px(60.0), px(0.0));
        cx.simulate_mouse_down(from, MouseButton::Left, Modifiers::default());
        cx.simulate_mouse_move(to, Some(MouseButton::Left), Modifiers::default());
        cx.simulate_mouse_up(to, MouseButton::Left, Modifiers::default());
        cx.run_until_parked();
        cx.update(|_, cx| { let view = view.read(cx); assert_eq!(view.width, 300.0); assert!(view.start.is_none()); });
    }
}
