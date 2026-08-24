use freya::prelude::*;

use crate::{MUTED, settings_switch};

pub(super) fn toggle_control(enabled: bool, mut action: impl FnMut() + 'static) -> Element {
    settings_switch::control(enabled, true, move |event| {
        event.stop_propagation();
        action();
    })
}

pub(super) fn loading_row(text: impl Into<String>) -> Element {
    rect()
        .height(Size::px(100.))
        .center()
        .horizontal()
        .spacing(8.)
        .child(label().font_size(11.).color(MUTED).text(text.into()))
        .into_element()
}
