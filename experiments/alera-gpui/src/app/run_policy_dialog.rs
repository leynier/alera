use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, InteractiveElement as _,
    IntoElement as _, ParentElement as _, Styled as _,
};
use gpui_component::scroll::ScrollableElement as _;

use super::run_policy::{RunExecutionPolicy, RunPolicyStage};
use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_execution_plans_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
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
                    .w(px(720.0))
                    .h(px(640.0))
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .shadow_lg()
                    .p_4()
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .text_size(px(16.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Execution Plans"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .flex_1()
                            .min_h(px(150.0))
                            .overflow_y_scrollbar()
                            .when(self.run_policies_loading, |content| {
                                content.child(empty_state(
                                    AleraIcon::Loading,
                                    "Loading Execution Plans",
                                    "Reading Proposed Coordinator Plans.",
                                ))
                            })
                            .when(
                                !self.run_policies_loading && self.run_policy_error.is_some(),
                                |content| {
                                    content.child(empty_state(
                                        AleraIcon::Error,
                                        "Plans Unavailable",
                                        self.run_policy_error
                                            .clone()
                                            .unwrap_or_else(|| "Unknown Runtime Error".into()),
                                    ))
                                },
                            )
                            .when(
                                !self.run_policies_loading
                                    && self.run_policy_error.is_none()
                                    && self.run_policies.is_empty(),
                                |content| {
                                    content.child(empty_state(
                                        AleraIcon::Workflow,
                                        "No Execution Plans",
                                        "A Coordinator Proposes A Plan Before It Starts Dispatching.",
                                    ))
                                },
                            )
                            .when(
                                !self.run_policies_loading
                                    && self.run_policy_error.is_none()
                                    && !self.run_policies.is_empty(),
                                |content| {
                                    content.children(self.run_policies.iter().map(|policy| {
                                        self.render_run_policy_panel(policy, cx)
                                    }))
                                },
                            ),
                    )
                    .when_some(self.run_policy_error.clone(), |dialog, error| {
                        if self.run_policies_loading || self.run_policies.is_empty() {
                            dialog
                        } else {
                            dialog.child(
                                div()
                                    .mt_2()
                                    .text_size(px(12.0))
                                    .text_color(theme::danger())
                                    .child(error),
                            )
                        }
                    })
                    .child(
                        div()
                            .mt_3()
                            .flex()
                            .justify_end()
                            .child(
                                design_system::button(
                                    "close-execution-plans",
                                    "Close",
                                    ButtonKind::Text,
                                    self.run_policy_busy_id.is_some(),
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        this.close_execution_plans(cx);
                                    }),
                                ),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn render_run_policy_panel(
        &self,
        policy: &RunExecutionPolicy,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let busy = self.run_policy_busy_id.as_deref() == Some(policy.run_id.as_str());
        let run_id = policy.run_id.clone();
        let approve_run_id = run_id.clone();
        let reject_run_id = run_id.clone();
        div()
            .mb_3()
            .rounded_lg()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_raised())
            .p_3()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(
                        div()
                            .flex_1()
                            .overflow_hidden()
                            .text_ellipsis()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(run_id),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(if policy.blocks_dispatch {
                                theme::warning()
                            } else {
                                theme::text_muted()
                            })
                            .child(policy.status.label()),
                    ),
            )
            .when(policy.blocks_dispatch, |panel| {
                panel.child(
                    div()
                        .mt_1()
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child("Scheduling Is Held Until This Plan Is Resolved."),
                )
            })
            .child(
                div()
                    .mt_2()
                    .children(policy.stages.iter().map(render_policy_stage))
                    .child(
                        div()
                            .mt_1()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child(format!("On Stall: {}", policy.stall_policy)),
                    ),
            )
            .when(policy.status.is_pending(), |panel| {
                panel
                    .child(
                        div().mt_3().child(
                            design_system::text_field(&self.run_policy_reason_input)
                                .label("Rejection Reason")
                                .prefix(icon(AleraIcon::Text, 15.0, theme::text_faint()))
                                .disabled(busy),
                        ),
                    )
                    .child(
                        div()
                            .mt_2()
                            .flex()
                            .gap_2()
                            .child(
                                design_system::button_with_loading(
                                    gpui::SharedString::from(format!(
                                        "approve-run-policy-{approve_run_id}"
                                    )),
                                    if busy { "Working" } else { "Approve" },
                                    ButtonKind::Filled,
                                    busy,
                                    busy,
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(move |this, _, window, cx| {
                                        this.decide_run_policy(
                                            approve_run_id.clone(),
                                            true,
                                            window,
                                            cx,
                                        );
                                    }),
                                ),
                            )
                            .child(
                                design_system::button(
                                    gpui::SharedString::from(format!(
                                        "reject-run-policy-{reject_run_id}"
                                    )),
                                    "Reject",
                                    ButtonKind::Outlined,
                                    busy,
                                )
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(move |this, _, window, cx| {
                                        this.decide_run_policy(
                                            reject_run_id.clone(),
                                            false,
                                            window,
                                            cx,
                                        );
                                    }),
                                ),
                            ),
                    )
            })
            .into_any_element()
    }
}

fn render_policy_stage(stage: &RunPolicyStage) -> gpui::Div {
    let mut text = format!("{}  {}", stage.label(), stage.profile);
    if !stage.fallbacks.is_empty() {
        text.push_str("  fallback: ");
        text.push_str(&stage.fallbacks.join(", "));
    }
    div()
        .mb_1()
        .text_size(px(12.0))
        .text_color(theme::text())
        .child(text)
}

fn empty_state(
    icon_kind: AleraIcon,
    title: impl Into<gpui::SharedString>,
    message: impl Into<gpui::SharedString>,
) -> gpui::Div {
    div()
        .min_h(px(150.0))
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .gap_2()
        .text_center()
        .child(icon(icon_kind, 24.0, theme::text_muted()))
        .child(
            div()
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(title.into()),
        )
        .child(
            div()
                .max_w(px(440.0))
                .text_size(px(12.0))
                .text_color(theme::text_muted())
                .child(message.into()),
        )
}
