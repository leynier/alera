use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::tooltip::Tooltip;
use serde_json::Value;

use super::status_data::QuotaSnapshot;
use super::status_runtime::{runtime_chip_color, runtime_chip_label, runtime_is_running};
use super::AleraApp;
use crate::activity::StatusPopover;
use crate::{
    icons::{icon, loading_indicator, AleraIcon},
    theme,
};

const STATUS_POPOVER_OPEN_DELAY: Duration = Duration::from_millis(280);
const STATUS_POPOVER_CLOSE_DELAY: Duration = Duration::from_millis(180);

impl AleraApp {
    pub(super) fn toggle_status_popover(&mut self, popover: StatusPopover, cx: &mut Context<Self>) {
        self.cancel_status_popover_transition();
        if self.status_popover == popover && self.status_popover_pinned {
            self.status_popover = StatusPopover::None;
            self.status_popover_pinned = false;
            self.status_popover_panel_hovered = false;
            // A click can arrive before GPUI publishes the trigger's hover
            // transition. Suppress unconditionally until the pointer leaves,
            // otherwise the just-closed pinned popover reopens after the
            // hover delay while the cursor is still over the same chip.
            self.status_popover_hover_suppressed = Some(popover);
            cx.notify();
            return;
        }
        self.status_popover = popover;
        self.status_popover_pinned = true;
        self.status_popover_hover_suppressed = None;
        self.refresh_status_popover(popover, cx);
        cx.notify();
    }

    fn refresh_status_popover(&mut self, popover: StatusPopover, cx: &mut Context<Self>) {
        match popover {
            StatusPopover::Quotas | StatusPopover::QuotaProvider(_) => {
                self.refresh_quota_status(false, cx)
            }
            StatusPopover::Resources => self.refresh_resource_status(cx),
            StatusPopover::Runtime => self.refresh_runtime_status(cx),
            StatusPopover::None => {}
        }
    }

    fn cancel_status_popover_transition(&mut self) {
        self.status_popover_transition_generation =
            self.status_popover_transition_generation.wrapping_add(1);
    }

    pub(super) fn set_status_popover_trigger_hovered(
        &mut self,
        popover: StatusPopover,
        hovered: bool,
        cx: &mut Context<Self>,
    ) {
        if hovered {
            self.status_popover_trigger_hovered = Some(popover);
            if self.status_popover_pinned || self.status_popover_hover_suppressed == Some(popover) {
                return;
            }
            if self.status_popover == popover {
                self.cancel_status_popover_transition();
                return;
            }
            self.schedule_status_popover_open(popover, cx);
            return;
        }
        if self.status_popover_trigger_hovered == Some(popover) {
            self.status_popover_trigger_hovered = None;
        }
        if self.status_popover_hover_suppressed == Some(popover) {
            self.cancel_status_popover_transition();
            let generation = self.status_popover_transition_generation;
            cx.spawn(async move |this, cx| {
                cx.background_executor()
                    .timer(Duration::from_millis(120))
                    .await;
                let Some(this) = this.upgrade() else {
                    return;
                };
                this.update(cx, |this, cx| {
                    if this.status_popover_transition_generation == generation
                        && this.status_popover_trigger_hovered != Some(popover)
                        && this.status_popover_hover_suppressed == Some(popover)
                    {
                        this.status_popover_hover_suppressed = None;
                        cx.notify();
                    }
                });
            })
            .detach();
            return;
        }
        self.schedule_status_popover_close(cx);
    }

    pub(super) fn set_status_popover_panel_hovered(
        &mut self,
        hovered: bool,
        cx: &mut Context<Self>,
    ) {
        self.status_popover_panel_hovered = hovered;
        if hovered {
            self.cancel_status_popover_transition();
        } else {
            self.schedule_status_popover_close(cx);
        }
    }

    pub(super) fn pin_active_status_popover(&mut self, cx: &mut Context<Self>) {
        if self.status_popover == StatusPopover::None {
            return;
        }
        self.status_popover_pinned = true;
        self.status_popover_hover_suppressed = None;
        self.cancel_status_popover_transition();
        cx.notify();
    }

    pub(super) fn dismiss_status_popover(&mut self, cx: &mut Context<Self>) {
        let dismissed = self.status_popover;
        if dismissed == StatusPopover::None {
            return;
        }
        self.cancel_status_popover_transition();
        self.status_popover = StatusPopover::None;
        self.status_popover_pinned = false;
        self.status_popover_panel_hovered = false;
        self.status_popover_hover_suppressed =
            (self.status_popover_trigger_hovered == Some(dismissed)).then_some(dismissed);
        cx.notify();
    }

    fn schedule_status_popover_open(&mut self, popover: StatusPopover, cx: &mut Context<Self>) {
        self.cancel_status_popover_transition();
        let generation = self.status_popover_transition_generation;
        cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(STATUS_POPOVER_OPEN_DELAY)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.status_popover_transition_generation != generation
                    || this.status_popover_pinned
                    || this.status_popover_trigger_hovered != Some(popover)
                    || this.status_popover_hover_suppressed == Some(popover)
                {
                    return;
                }
                this.status_popover = popover;
                this.status_popover_panel_hovered = false;
                this.refresh_status_popover(popover, cx);
                cx.notify();
            });
        })
        .detach();
    }

    fn schedule_status_popover_close(&mut self, cx: &mut Context<Self>) {
        if self.status_popover == StatusPopover::None || self.status_popover_pinned {
            return;
        }
        self.cancel_status_popover_transition();
        let generation = self.status_popover_transition_generation;
        let popover = self.status_popover;
        cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(STATUS_POPOVER_CLOSE_DELAY)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.status_popover_transition_generation != generation
                    || this.status_popover_pinned
                    || this.status_popover_panel_hovered
                    || this.status_popover_trigger_hovered == Some(popover)
                {
                    return;
                }
                this.status_popover = StatusPopover::None;
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_status_popover_dismiss_layer(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .id("status-popover-dismiss-layer")
            .absolute()
            .top_0()
            .right_0()
            .bottom(theme::status_bar_height())
            .left_0()
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.dismiss_status_popover(cx)),
            )
            .into_any_element()
    }

    pub(super) fn render_status_bar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let quotas = self.visible_quota_snapshots();
        let quota_empty_label = if self.status_data.quota_loading {
            "Refreshing Quotas"
        } else if self.status_data.quota_error.is_some() {
            "Quota Refresh Failed"
        } else {
            "No Quota Data"
        };
        let resource_value = self.status_data.resources.as_ref();
        let memory = resource_value
            .and_then(|value| value.get("totals"))
            .and_then(|totals| totals.get("memoryBytes"))
            .and_then(Value::as_u64)
            .filter(|_| self.status_data.resource_error.is_none())
            .map(format_resource_memory)
            .unwrap_or_else(|| "-".to_owned());
        let session_count = resource_value
            .and_then(|value| value.get("sessions"))
            .and_then(Value::as_array)
            .map_or(0, Vec::len);
        let orphan_count = resource_value
            .and_then(|value| value.get("sessions"))
            .and_then(Value::as_array)
            .map_or(0, |sessions| {
                sessions
                    .iter()
                    .filter(|session| {
                        let session_id = session
                            .get("sessionId")
                            .and_then(Value::as_str)
                            .unwrap_or_default();
                        // Resource snapshots include every workspace, not
                        // just the mounted workbench.  Join against the same
                        // global tab projection so sessions from another
                        // workspace are not falsely reported as orphans.
                        !self.snapshot.all_tabs.iter().any(|tab| {
                            tab.kind == "terminal"
                                && tab
                                    .payload
                                    .get("terminalSessionId")
                                    .and_then(Value::as_str)
                                    .filter(|value| !value.trim().is_empty())
                                    .unwrap_or(&tab.id)
                                    == session_id
                        })
                    })
                    .count()
            });
        let runtime_error = self.status_data.runtime_error.is_some();
        let runtime_value = self.status_data.runtime.as_ref();
        let runtime_running = runtime_is_running(runtime_value, runtime_error);
        let runtime_loading = self.status_data.runtime_loading
            || (matches!(
                self.connection_label.as_ref(),
                "Runtime Connecting" | "Runtime Starting" | "Runtime Reconnecting"
            ) && !runtime_running
                && !runtime_error);
        let runtime_label = runtime_chip_label(runtime_value, runtime_error, runtime_loading);
        let runtime_color = runtime_chip_color(runtime_value, runtime_error, runtime_loading);
        let host_label = self
            .selected_workspace_id
            .as_deref()
            .and_then(|workspace_id| {
                self.snapshot
                    .projects
                    .iter()
                    .flat_map(|project| project.workspaces.iter())
                    .find(|workspace| workspace.id == workspace_id)
            })
            .map(|workspace| workspace.host_id.clone())
            .filter(|host_id| !host_id.trim().is_empty())
            .unwrap_or_else(|| "local".to_owned());
        let host_label = if host_label == "local" {
            "Local".to_owned()
        } else {
            host_label
        };

        div()
            .flex()
            .items_center()
            .h(theme::status_bar_height())
            .border_t_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface())
            .text_xs()
            .font_family("JetBrains Mono")
            .text_color(theme::text_muted())
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.dismiss_status_popover(cx)),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_1()
                    .h_full()
                    .px_2()
                    .border_r_1()
                    .border_color(theme::border_subtle())
                    .child(icon(AleraIcon::Server, 13.0, theme::text_muted()))
                    .child(host_label),
            )
            .child(
                div()
                    .id("quota-overview")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("All Agent Quotas")
                    .flex()
                    .items_center()
                    .justify_center()
                    .h_full()
                    .px(px(6.0))
                    .border_r_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("All Agent Quotas")).into())
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                        this.set_status_popover_trigger_hovered(
                            StatusPopover::Quotas,
                            *hovered,
                            cx,
                        );
                    }))
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.toggle_status_popover(StatusPopover::Quotas, cx);
                        cx.stop_propagation();
                    }))
                    .child(icon(AleraIcon::Quota, 13.0, theme::text_muted())),
            )
            .child(
                div()
                    .id("quota-summary-scroll")
                    .flex()
                    .items_center()
                    .flex_1()
                    .min_w_0()
                    .h_full()
                    .overflow_x_scroll()
                    .when(quotas.is_empty(), |row| {
                        row.child(
                            div()
                                .px_2()
                                .flex()
                                .items_center()
                                .gap_1()
                                .text_size(px(10.0))
                                .when(self.status_data.quota_loading, |row| {
                                    row.child(loading_indicator(11.0, theme::text_faint()))
                                })
                                .child(quota_empty_label),
                        )
                    })
                    .children(
                        quotas
                            .into_iter()
                            .enumerate()
                            .map(|(index, snapshot)| self.quota_summary(index, snapshot, cx)),
                    )
                    .child(
                        div()
                            .id("quota-refresh")
                            .focusable()
                            .tab_stop(!self.status_data.quota_loading)
                            .role(Role::Button)
                            .aria_label(if self.status_data.quota_loading {
                                "Refreshing Quotas"
                            } else {
                                "Refresh Quotas"
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .h_full()
                            .px_2()
                            .cursor(CursorStyle::PointingHand)
                            .tooltip({
                                let label = if self.status_data.quota_loading {
                                    "Refreshing Quotas"
                                } else {
                                    "Refresh Quotas - Automatically Refreshes Every 5 Minutes"
                                };
                                move |_, cx| {
                                    let label = label.to_owned();
                                    cx.new(move |_| Tooltip::new(label)).into()
                                }
                            })
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                                cx.stop_propagation();
                            })
                            .on_click(cx.listener(|this, _, _, cx| {
                                if !this.status_data.quota_loading {
                                    this.refresh_quota_status(true, cx);
                                }
                                cx.stop_propagation();
                            }))
                            .child(if self.status_data.quota_loading {
                                loading_indicator(13.0, theme::text_faint())
                            } else {
                                icon(AleraIcon::Refresh, 13.0, theme::text_muted())
                            }),
                    ),
            )
            .child(
                div()
                    .id("resource-status")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Resource Manager")
                    .flex()
                    .items_center()
                    .gap(px(6.0))
                    .h_full()
                    .px_2()
                    .border_l_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Resource Manager")).into())
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                        this.set_status_popover_trigger_hovered(
                            StatusPopover::Resources,
                            *hovered,
                            cx,
                        );
                    }))
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.toggle_status_popover(StatusPopover::Resources, cx);
                        cx.stop_propagation();
                    }))
                    .child(icon(AleraIcon::Activity, 13.0, theme::text_muted()))
                    .child(div().text_size(px(10.0)).child(memory))
                    .child(icon(AleraIcon::Terminal, 11.0, theme::text_muted()))
                    .child(div().text_size(px(10.0)).child(session_count.to_string()))
                    .when(orphan_count > 0, |chip| {
                        chip.child(
                            div()
                                .text_size(px(10.0))
                                .text_color(theme::warning())
                                .child(format!("({orphan_count})")),
                        )
                    }),
            )
            .child(
                div()
                    .id("runtime-status")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Runtime Host")
                    .flex()
                    .items_center()
                    .gap(px(6.0))
                    .h_full()
                    .px_2()
                    .border_l_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .text_color(runtime_color)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Runtime Host")).into())
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                        this.set_status_popover_trigger_hovered(
                            StatusPopover::Runtime,
                            *hovered,
                            cx,
                        );
                    }))
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.toggle_status_popover(StatusPopover::Runtime, cx);
                        cx.stop_propagation();
                    }))
                    .child(if runtime_loading {
                        loading_indicator(13.0, runtime_color)
                    } else {
                        icon(AleraIcon::Server, 13.0, runtime_color)
                    })
                    .child(gpui::SharedString::from(runtime_label)),
            )
    }

    pub(super) fn ordered_quota_snapshots(&self, pinned_only: bool) -> Vec<&QuotaSnapshot> {
        let mut ordered = Vec::new();
        for provider in &self.settings_state.quota_enabled_providers {
            let candidates = self
                .status_data
                .quotas
                .iter()
                .filter(|snapshot| &snapshot.provider == provider)
                .collect::<Vec<_>>();
            if provider == "claude" {
                if self.settings_state.claude_default_enabled {
                    if let Some(snapshot) = candidates
                        .iter()
                        .find(|snapshot| snapshot.account_id == "default")
                    {
                        ordered.push(*snapshot);
                    }
                }
                for profile in &self.settings_state.claude_profiles {
                    if let Some(snapshot) = candidates
                        .iter()
                        .find(|snapshot| snapshot.account_id == profile.profile)
                    {
                        ordered.push(*snapshot);
                    }
                }
                for snapshot in candidates {
                    if snapshot.account_id != "default"
                        && !self
                            .settings_state
                            .claude_profiles
                            .iter()
                            .any(|profile| profile.profile == snapshot.account_id)
                    {
                        ordered.push(snapshot);
                    }
                }
            } else if let Some(snapshot) = candidates.first() {
                ordered.push(*snapshot);
            }
        }
        ordered
            .into_iter()
            .filter(|snapshot| {
                !pinned_only
                    || !self
                        .settings_state
                        .quota_unpinned_keys
                        .contains(&quota_pin_key(snapshot))
            })
            .collect()
    }

    pub(super) fn visible_quota_snapshots(&self) -> Vec<&QuotaSnapshot> {
        self.ordered_quota_snapshots(true)
    }

    pub(super) fn render_active_status_popover(&self, cx: &mut Context<Self>) -> AnyElement {
        match self.status_popover {
            StatusPopover::None => div().into_any_element(),
            StatusPopover::Quotas => self.render_quota_popover(cx),
            StatusPopover::QuotaProvider(index) => self.render_quota_provider_popover(index, cx),
            StatusPopover::Resources => self.render_resource_popover(cx),
            StatusPopover::Runtime => self.render_runtime_popover(cx),
        }
    }
}

pub(super) fn quota_pin_key(snapshot: &QuotaSnapshot) -> String {
    if snapshot.provider == "claude" {
        format!("claude:{}", snapshot.account_id)
    } else {
        snapshot.provider.clone()
    }
}

pub(super) fn format_resource_memory(bytes: u64) -> String {
    if bytes < 1_048_576 {
        return format!("{} KB", (bytes as f64 / 1024.0).round() as u64);
    }
    if bytes < 1_073_741_824 {
        return format!("{:.1} MB", bytes as f64 / 1_048_576.0);
    }
    format!("{:.2} GB", bytes as f64 / 1_073_741_824.0)
}
