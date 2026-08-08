use gpui::{div, px, AnyElement, IntoElement as _, ParentElement as _, SharedString, Styled as _};

use crate::icons::{icon, AleraIcon};
use crate::theme;

pub(super) fn render_toast(message: SharedString) -> AnyElement {
    let normalized = message.to_ascii_lowercase();
    let (kind, color) = if normalized.contains("error")
        || normalized.contains("failed")
        || normalized.contains("could not")
        || normalized.contains("required")
    {
        (AleraIcon::Error, theme::danger())
    } else if normalized.contains("created")
        || normalized.contains("saved")
        || normalized.contains("completed")
        || normalized.contains("generated")
        || normalized.contains("updated")
        || normalized.contains("copied")
        || normalized.contains("linked")
    {
        (AleraIcon::Success, theme::success())
    } else {
        (AleraIcon::Info, theme::accent())
    };
    div()
        .absolute()
        .right(px(16.0))
        .bottom(px(40.0))
        .max_w(px(380.0))
        .flex()
        .items_start()
        .gap_2()
        .px_3()
        .py_2()
        .rounded_md()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_raised())
        .shadow_lg()
        .text_sm()
        .child(icon(kind, 16.0, color))
        .child(div().flex_1().child(message))
        .into_any_element()
}
