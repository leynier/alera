use gpui::{AnyElement, FontWeight, InteractiveElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, div, px, prelude::FluentBuilder as _};

use crate::{icons::{AleraIcon, icon}, theme};

pub fn empty_state(id: &'static str, symbol: AleraIcon, title: impl Into<SharedString>, message: impl Into<SharedString>) -> gpui::Stateful<gpui::Div> {
    empty_state_with_action(id, symbol, Some(title.into()), message.into(), None)
}

pub fn empty_state_with_action(id: &'static str, symbol: AleraIcon, title: Option<SharedString>, message: SharedString, action: Option<AnyElement>) -> gpui::Stateful<gpui::Div> {
    let description = title.as_ref().map_or_else(|| message.to_string(), |title| format!("{title}. {message}"));
    div().id(id).role(Role::Group).aria_label(description)
        .flex().flex_1().size_full().min_w_0().min_h_0().items_center().justify_center()
        .child(div().w_full().max_w(px(520.0)).p(px(24.0)).flex().flex_col().items_center()
            .text_align(gpui::TextAlign::Center)
            .child(icon(symbol, 28.0, theme::text_faint()))
            .when_some(title, |body, title| body.child(div().mt(px(12.0)).text_size(px(14.0)).line_height(px(21.0))
                .font_weight(FontWeight::MEDIUM).text_color(theme::text()).child(title)))
            .child(div().mt(px(8.0)).text_size(px(13.0)).text_color(theme::text_muted()).child(message))
            .when_some(action, |body, action| body.child(div().mt(px(16.0)).child(action))))
}
