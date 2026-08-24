use freya::prelude::*;

use crate::{BACKGROUND, MUTED};

pub(super) fn control(
    value: bool,
    enabled: bool,
    on_toggle: impl FnMut(Event<PointerEventData>) + 'static,
) -> Element {
    rect()
        .width(Size::px(57.))
        .padding(Gaps::new(0., 5., 0., 0.))
        .child(
            rect()
                .width(Size::px(52.))
                .height(Size::px(32.))
                .corner_radius(16.)
                .background(if value { (232, 232, 232) } else { (70, 70, 70) })
                .padding(Gaps::new_all(4.))
                .horizontal()
                .main_align(if value {
                    Alignment::End
                } else {
                    Alignment::Start
                })
                .a11y_role(AccessibilityRole::Button)
                .on_pointer_enter(move |_| {
                    if enabled {
                        Cursor::set(CursorIcon::Pointer);
                    }
                })
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(on_toggle)
                .child(
                    rect()
                        .width(Size::px(24.))
                        .height(Size::px(24.))
                        .corner_radius(12.)
                        .background(if value { BACKGROUND } else { MUTED }),
                ),
        )
        .into_element()
}
