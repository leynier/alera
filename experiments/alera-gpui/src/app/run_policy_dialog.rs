use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, InteractiveElement as _,
    IntoElement as _, ParentElement as _, Role, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::scroll::ScrollableElement as _;

use super::run_policy::{RunExecutionPolicy, RunPolicyStage};
use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_execution_plans_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let compact = !self.run_policies_loading && !self.run_policies.is_empty();
        let content: AnyElement = if self.run_policies_loading {
            div()
                .id("execution-plans-loading")
                .role(Role::ProgressIndicator)
                .aria_label("Loading Execution Plans")
                .mt_3()
                .flex_1()
                .min_h(px(150.0))
                .flex()
                .items_center()
                .justify_center()
                .child(loading_indicator(24.0, theme::text_muted()))
                .into_any_element()
        } else if !self.run_policies.is_empty() {
            let content = div().mt_4().flex_shrink_0().children(
                self.run_policies
                    .iter()
                    .map(|policy| self.render_run_policy_panel(policy, cx)),
            );
            if self.run_policies.len() > 2 {
                content
                    .max_h(px(480.0))
                    .overflow_y_scrollbar()
                    .into_any_element()
            } else {
                content.into_any_element()
            }
        } else if let Some(error) = self.run_policy_error.clone() {
            div()
                .mt_3()
                .flex_1()
                .min_h(px(150.0))
                .flex()
                .flex_col()
                .items_center()
                .justify_center()
                .child(empty_state(AleraIcon::Workflow, "Plans Unavailable", error))
                .into_any_element()
        } else if self.run_policies.is_empty() {
            div()
                .mt_3()
                .flex_1()
                .min_h(px(150.0))
                .flex()
                .flex_col()
                .items_center()
                .justify_center()
                .child(empty_state(
                    AleraIcon::Workflow,
                    "No Execution Plans",
                    "A Coordinator Proposes A Plan Before It Starts Dispatching.",
                ))
                .into_any_element()
        } else {
            unreachable!("empty policies are handled above")
        };

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
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.close_execution_plans(cx)),
            )
            .child(
                div()
                    .id("execution-plans-dialog")
                    .role(Role::Dialog)
                    .aria_label("Execution Plans")
                    // Flutter's dialog is max-constrained, not fixed-size:
                    // a loaded plan hugs its content while loading/error and
                    // the empty state retain the roomy review surface.
                    .when(compact, |dialog| {
                        // GPUI pixels are rendered at the native window scale;
                        // this maps the Flutter 720 logical-pixel cap to the
                        // same on-screen width on the desktop client.
                        dialog.w(px(740.0)).h_auto().max_h(px(640.0))
                    })
                    .when(!compact, |dialog| dialog.w(px(720.0)).h(px(640.0)))
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .shadow_lg()
                    .p_4()
                    // Flutter's Dialog keeps a larger bottom inset below
                    // the trailing Close action than GPUI's default padding.
                    .pb(px(18.0))
                    .flex()
                    .flex_col()
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| cx.stop_propagation())
                    .child(
                        div()
                            .text_size(px(16.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Execution Plans"),
                    )
                    .child(content)
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
                        div().mt_3().flex().justify_end().child(
                            design_system::button(
                                "close-execution-plans",
                                "Close",
                                ButtonKind::Text,
                                false,
                            )
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.close_execution_plans(cx);
                            })),
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
            .id(gpui::SharedString::from(format!("run-policy-{run_id}")))
            .role(Role::Group)
            .aria_label(run_id.clone())
            .mb_3()
            .rounded_lg()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_raised())
            .p_3()
            .pb(px(16.0))
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
                            .text_size(crate::theme::caption_size())
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
                        .text_size(crate::theme::caption_size())
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
                            .text_size(crate::theme::caption_size())
                            .text_color(theme::text_muted())
                            .child(format!("On Stall: {}", policy.stall_policy)),
                    ),
            )
            .when(policy.status.is_pending(), |panel| {
                panel
                    .child(
                        div().mt_4().child(
                            design_system::text_field(&self.run_policy_reason_input)
                                .label("Rejection Reason")
                                .prefix(icon(AleraIcon::Text, 15.0, theme::text_faint()))
                                .disabled(busy),
                        ),
                    )
                    .child(
                        div()
                            .mt_3()
                            .flex()
                            .gap_2()
                            .child(
                                design_system::button_with_loading_and_leading_icon(
                                    gpui::SharedString::from(format!(
                                        "approve-run-policy-{approve_run_id}"
                                    )),
                                    "Approve",
                                    ButtonKind::Elevated,
                                    busy,
                                    busy,
                                    Some(icon(AleraIcon::Check, 14.0, theme::text())),
                                )
                                .on_click(cx.listener(
                                    move |this, _, window, cx| {
                                        this.decide_run_policy(
                                            approve_run_id.clone(),
                                            true,
                                            window,
                                            cx,
                                        );
                                    },
                                )),
                            )
                            .child(
                                design_system::button_with_leading_icon(
                                    gpui::SharedString::from(format!(
                                        "reject-run-policy-{reject_run_id}"
                                    )),
                                    "Reject",
                                    ButtonKind::Outlined,
                                    busy,
                                    icon(AleraIcon::Cancel, 14.0, theme::text()),
                                )
                                .on_click(cx.listener(
                                    move |this, _, window, cx| {
                                        this.decide_run_policy(
                                            reject_run_id.clone(),
                                            false,
                                            window,
                                            cx,
                                        );
                                    },
                                )),
                            ),
                    )
            })
            .into_any_element()
    }
}

fn render_policy_stage(stage: &RunPolicyStage) -> gpui::Div {
    div()
        .mb_1()
        .flex()
        .text_size(px(12.0))
        .child(
            div()
                .text_color(theme::text())
                .child(stage.label().to_owned()),
        )
        .child(
            div()
                .text_color(theme::text_muted())
                .child(format!("  {}", stage.profile)),
        )
        .when(!stage.fallbacks.is_empty(), |row| {
            row.child(
                div()
                    .text_color(theme::text_muted())
                    .child(format!("  fallback: {}", stage.fallbacks.join(", "))),
            )
        })
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
