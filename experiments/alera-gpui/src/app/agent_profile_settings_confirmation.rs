use gpui::{
    div, px, Context, CursorStyle, InteractiveElement as _, MouseButton, ParentElement as _,
    Styled as _,
};

use super::agent_profile_settings::managed_risk_warning;
use super::AleraApp;
use crate::theme;

impl AleraApp {
    pub(super) fn render_agent_profile_risk_confirmation(
        &self,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let warning = managed_risk_warning(
            &self.agent_profile_settings.adapter,
            &self.agent_profile_settings.managed_config,
        );
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
                    .p_5()
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .shadow_lg()
                    .child(
                        div()
                            .text_size(px(14.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child("Confirm Reduced Protections"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_size(px(13.0))
                            .text_color(theme::text_muted())
                            .child(warning),
                    )
                    .child(
                        div()
                            .flex()
                            .mt_5()
                            .gap_2()
                            .child(
                                confirmation_button("cancel-agent-profile-risk", "Cancel", false)
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.cancel_agent_profile_risk(cx);
                                        }),
                                    ),
                            )
                            .child(
                                confirmation_button(
                                    "confirm-agent-profile-risk",
                                    "Save Anyway",
                                    true,
                                )
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _, window, cx| {
                                        this.confirm_agent_profile_risk(window, cx);
                                    }),
                                ),
                            ),
                    ),
            )
    }
}

fn confirmation_button(
    id: &'static str,
    label: &'static str,
    destructive: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex_1()
        .flex()
        .items_center()
        .justify_center()
        .h(px(34.0))
        .rounded_lg()
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
        .cursor(CursorStyle::PointingHand)
        .hover(|style| {
            style.bg(if destructive {
                theme::danger_hover()
            } else {
                theme::surface_raised()
            })
        })
        .child(label)
}
