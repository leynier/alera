use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Styled as _,
};

use super::AleraApp;
use crate::icons::loading_indicator;
use crate::theme;

impl AleraApp {
    pub(super) fn render_resource_close_confirmation(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(confirmation) = self.resource_close_confirmation.as_ref() else {
            return div().into_any_element();
        };
        let label = confirmation.label.clone();
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                div()
                    .w(px(420.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p(px(20.0))
                    .child(
                        div()
                            .text_size(px(14.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child("Close Terminal Session"),
                    )
                    .child(
                        div()
                            .mt(px(12.0))
                            .text_size(px(13.0))
                            .text_color(theme::text_muted())
                            .child(format!(
                                "Force-quits {label}. Anything running in that terminal is lost."
                            )),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt(px(20.0))
                            .child(
                                resource_dialog_button("cancel-resource-close", "Cancel", false)
                                    .flex_1()
                                    .on_mouse_down(
                                        gpui::MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            if !this.tab_mutation_busy {
                                                this.resource_close_confirmation = None;
                                                cx.notify();
                                            }
                                        }),
                                    ),
                            )
                            .child(
                                resource_dialog_button_with_loading(
                                    "confirm-resource-close",
                                    "Close",
                                    true,
                                    self.tab_mutation_busy,
                                )
                                .flex_1()
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        if this.tab_mutation_busy {
                                            return;
                                        }
                                        let Some(confirmation) =
                                            this.resource_close_confirmation.take()
                                        else {
                                            return;
                                        };
                                        this.request_close_tab(confirmation.tab_id, cx);
                                    }),
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn resource_dialog_button(
    id: &'static str,
    label: &'static str,
    destructive: bool,
) -> gpui::Stateful<gpui::Div> {
    resource_dialog_button_with_loading(id, label, destructive, false)
}

fn resource_dialog_button_with_loading(
    id: &'static str,
    label: &'static str,
    destructive: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .h(px(32.0))
        .px_3()
        .flex()
        .items_center()
        .justify_center()
        .rounded_md()
        .bg(if destructive {
            theme::danger()
        } else {
            theme::transparent()
        })
        .text_color(if destructive {
            theme::on_danger()
        } else {
            theme::text()
        })
        .font_weight(gpui::FontWeight::SEMIBOLD)
        .cursor(CursorStyle::PointingHand)
        .hover(|style| {
            style.bg(if destructive {
                theme::danger_hover()
            } else {
                theme::surface_selected()
            })
        })
        .when(loading, |button| {
            button.child(loading_indicator(13.0, theme::text_faint()))
        })
        .child(label)
}
