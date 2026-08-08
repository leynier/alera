use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, MouseDownEvent, MouseMoveEvent, ParentElement as _,
    StatefulInteractiveElement as _, Styled as _,
};
use serde_json::json;

use super::status_bar::quota_pin_key;
use super::status_data::{QuotaReading, QuotaSnapshot};
use super::status_quota::{codex_reset_expiry, provider_agent_icon, provider_label, quota_color};
use super::AleraApp;
use crate::activity::StatusPopover;
use crate::icons::{agent_icon, loading_indicator};
use crate::theme;

impl AleraApp {
    pub(super) fn quota_summary(
        &self,
        index: usize,
        snapshot: &QuotaSnapshot,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let popover = StatusPopover::QuotaProvider(index);
        let mut row = div()
            .id(("quota-summary", index))
            .flex()
            .items_center()
            .h_full()
            .px(px(6.0))
            .gap(px(6.0))
            .border_r_1()
            .border_color(theme::border_subtle())
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_raised()))
            .on_mouse_move(cx.listener(|this, event: &MouseMoveEvent, _, _| {
                this.status_popover_anchor_x = event.position.x / px(1.0);
            }))
            .on_hover(cx.listener(move |this, hovered: &bool, _, cx| {
                this.set_status_popover_trigger_hovered(popover, *hovered, cx);
            }))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    this.status_popover_anchor_x = event.position.x / px(1.0);
                    this.toggle_status_popover(popover, cx);
                    cx.stop_propagation();
                }),
            )
            .child(agent_icon(
                provider_agent_icon(&snapshot.provider),
                14.0,
                theme::text_muted(),
            ));
        if snapshot.provider == "claude" {
            row = row.child(
                div()
                    .text_size(px(8.0))
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .text_color(theme::text_muted())
                    .child(snapshot.display_name.clone()),
            );
        }
        if snapshot.readings.is_empty() {
            return row
                .child(
                    div()
                        .text_size(px(10.0))
                        .text_color(quota_color(&snapshot.status, None))
                        .child("-"),
                )
                .into_any_element();
        }
        row.children(snapshot.readings.iter().map(|reading| {
            div()
                .flex()
                .items_center()
                .gap(px(2.0))
                .child(
                    div()
                        .text_size(px(8.0))
                        .font_weight(gpui::FontWeight::MEDIUM)
                        .text_color(theme::text_faint())
                        .child(reading.label.clone()),
                )
                .child(
                    div()
                        .text_size(px(10.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .text_color(quota_color(
                            &snapshot.status,
                            Some(reading.remaining_percent),
                        ))
                        .child(format!("{:.0}%", reading.remaining_percent)),
                )
        }))
        .into_any_element()
    }

    pub(super) fn render_quota_provider_popover(
        &self,
        index: usize,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let snapshots = self.visible_quota_snapshots();
        let Some(snapshot) = snapshots.get(index).copied() else {
            return div().into_any_element();
        };
        let left = (self.status_popover_anchor_x - 180.0).max(8.0);
        let status_color = quota_color(&snapshot.status, None);
        let profile_label = (snapshot.provider == "claude").then(|| snapshot.display_name.clone());
        let snapshot_key = quota_pin_key(snapshot);
        let tui_busy = self.quota_tui_busy_key.as_deref() == Some(snapshot_key.as_str());
        div()
            .id(("quota-provider-popover", index))
            .absolute()
            .left(px(left))
            .bottom(theme::status_bar_height())
            .w(px(360.0))
            .max_h(px(480.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_3()
            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                this.set_status_popover_panel_hovered(*hovered, cx);
            }))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.pin_active_status_popover(cx)),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(agent_icon(
                        provider_agent_icon(&snapshot.provider),
                        18.0,
                        theme::text(),
                    ))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .flex_1()
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .text_color(theme::text())
                                    .child(provider_label(snapshot)),
                            )
                            .when_some(profile_label, |header, label| {
                                header.child(
                                    div()
                                        .font_family("JetBrains Mono")
                                        .text_size(px(10.0))
                                        .text_color(theme::text_muted())
                                        .child(label),
                                )
                            }),
                    )
                    .child(
                        div()
                            .rounded_full()
                            .px_2()
                            .py(px(2.0))
                            .bg(gpui::Rgba {
                                a: 0.11,
                                ..status_color
                            })
                            .text_xs()
                            .text_color(status_color)
                            .child(quota_status_label(&snapshot.status)),
                    ),
            )
            .when(snapshot.readings.is_empty(), |panel| {
                panel.child(
                    div()
                        .mt_3()
                        .text_sm()
                        .text_color(theme::text_muted())
                        .child(
                            snapshot
                                .error
                                .clone()
                                .unwrap_or_else(|| "Quota Data Unavailable".to_owned()),
                        ),
                )
            })
            .children(snapshot.readings.iter().map(|reading| {
                let color = quota_color(&snapshot.status, Some(reading.remaining_percent));
                div()
                    .mt_3()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .child(
                                div()
                                    .flex_1()
                                    .text_sm()
                                    .font_weight(gpui::FontWeight::MEDIUM)
                                    .text_color(theme::text_muted())
                                    .child(reading.full_label.clone()),
                            )
                            .child(
                                div()
                                    .font_family("JetBrains Mono")
                                    .text_size(px(11.0))
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .text_color(color)
                                    .child(format!("{:.0}% Left", reading.remaining_percent)),
                            ),
                    )
                    .child(
                        div()
                            .mt(px(6.0))
                            .h(px(4.0))
                            .w_full()
                            .rounded_full()
                            .bg(theme::surface_selected())
                            .child(
                                div()
                                    .h_full()
                                    .w(gpui::relative(
                                        (reading.remaining_percent / 100.0).clamp(0.0, 1.0) as f32,
                                    ))
                                    .rounded_full()
                                    .bg(color),
                            ),
                    )
                    .child(
                        div()
                            .mt(px(6.0))
                            .font_family("JetBrains Mono")
                            .text_size(px(9.0))
                            .text_color(theme::text_faint())
                            .child(quota_reset_text(reading)),
                    )
            }))
            .when_some(snapshot.reset_credits.clone(), |panel, credits| {
                let expiry = codex_reset_expiry(credits.next_expires_at);
                let offer_revision = credits.offer_revision.clone();
                let can_consume = credits.available_count > 0 && credits.can_consume;
                panel.child(
                    div()
                        .mt_2()
                        .flex()
                        .items_center()
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .flex_1()
                                .font_family("JetBrains Mono")
                                .child(
                                    div()
                                        .text_size(px(10.0))
                                        .font_weight(gpui::FontWeight::SEMIBOLD)
                                        .text_color(theme::text_muted())
                                        .child(format!(
                                            "{} Rate-Limit {} Available",
                                            credits.available_count,
                                            if credits.available_count == 1 {
                                                "Reset"
                                            } else {
                                                "Resets"
                                            }
                                        )),
                                )
                                .when_some(expiry, |summary, expiry| {
                                    summary.child(
                                        div()
                                            .text_size(px(9.0))
                                            .text_color(theme::text_faint())
                                            .child(expiry),
                                    )
                                }),
                        )
                        .when(credits.available_count > 0, |row| {
                            row.child(
                                div()
                                    .id(("quota-provider-use-reset", index))
                                    .h(px(24.0))
                                    .px(px(6.0))
                                    .flex()
                                    .items_center()
                                    .text_sm()
                                    .text_color(if can_consume {
                                        theme::accent()
                                    } else {
                                        theme::text_faint()
                                    })
                                    .when(can_consume, |button| {
                                        button.cursor(CursorStyle::PointingHand).on_mouse_down(
                                            gpui::MouseButton::Left,
                                            cx.listener(move |this, _, _, cx| {
                                                this.codex_reset_offer_revision =
                                                    offer_revision.clone();
                                                this.pin_active_status_popover(cx);
                                                cx.stop_propagation();
                                                cx.notify();
                                            }),
                                        )
                                    })
                                    .child("Use Reset"),
                            )
                        }),
                )
            })
            .when(
                snapshot.provider == "claude" && snapshot.status != "ok",
                |panel| {
                    let account_id = snapshot.account_id.clone();
                    let display_name = snapshot.display_name.clone();
                    panel.child(
                        div()
                            .id(("quota-try-tui", index))
                            .mt_3()
                            .flex()
                            .justify_end()
                            .text_sm()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .text_color(if tui_busy {
                                theme::text_faint()
                            } else {
                                theme::accent()
                            })
                            .when(!tui_busy, |button| {
                                button.cursor(CursorStyle::PointingHand).on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(move |this, _, _, cx| {
                                        this.try_claude_quota_tui(
                                            snapshot_key.clone(),
                                            account_id.clone(),
                                            display_name.clone(),
                                            cx,
                                        );
                                        cx.stop_propagation();
                                    }),
                                )
                            })
                            .when(tui_busy, |button| {
                                button.child(loading_indicator(13.0, theme::text_faint()))
                            })
                            .child(if tui_busy {
                                "Trying With TUI..."
                            } else {
                                "Try With TUI"
                            }),
                    )
                },
            )
            // See the overview popover: the scrollbar wrapper is relative and
            // would make this absolute overlay participate in the root flex.
            .overflow_y_scroll()
            .into_any_element()
    }

    fn try_claude_quota_tui(
        &mut self,
        snapshot_key: String,
        account_id: String,
        display_name: String,
        cx: &mut Context<Self>,
    ) {
        if self.quota_tui_busy_key.is_some() {
            return;
        }
        self.quota_tui_busy_key = Some(snapshot_key);
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentQuota.fetchClaudeTui",
                    json!({
                        "accountId": account_id,
                        "displayName": display_name,
                    }),
                    Duration::from_secs(60),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.quota_tui_busy_key = None;
                match result {
                    Ok(_) => this.refresh_quota_status(false, cx),
                    Err(error) => {
                        this.local_message =
                            Some(format!("Claude TUI Quota Failed: {error}").into())
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }
}

fn quota_status_label(status: &str) -> &'static str {
    match status {
        "ok" => "Live",
        "stale" => "Stale",
        "error" => "Error",
        _ => "Unavailable",
    }
}

fn quota_reset_text(reading: &QuotaReading) -> String {
    if let Some(description) = reading
        .reset_description
        .as_deref()
        .map(str::trim)
        .filter(|description| !description.is_empty())
    {
        return description.to_owned();
    }
    let Some(resets_at) = reading.resets_at else {
        return "Reset Time Unavailable".to_owned();
    };
    let remaining_ms = resets_at - chrono::Utc::now().timestamp_millis();
    if remaining_ms <= 0 {
        return "Reset Available".to_owned();
    }
    let minutes = remaining_ms / 60_000;
    let days = minutes / (24 * 60);
    let hours = (minutes % (24 * 60)) / 60;
    let minutes = minutes % 60;
    if days > 0 {
        format!("Resets In {days}d {hours}h")
    } else if hours > 0 {
        format!("Resets In {hours}h {minutes}m")
    } else {
        format!("Resets In {}m", minutes.clamp(1, 59))
    }
}
