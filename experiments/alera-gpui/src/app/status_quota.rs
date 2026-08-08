use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, StatefulInteractiveElement as _,
    Styled as _,
};
use serde_json::json;

use super::status_bar::quota_pin_key;
use super::status_data::QuotaSnapshot;
use super::AleraApp;
use crate::{
    icons::{agent_icon, icon, loading_indicator, AgentIcon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_quota_popover(&self, cx: &mut Context<Self>) -> AnyElement {
        let snapshots = self.ordered_quota_snapshots(false);
        let empty_message = self
            .status_data
            .quota_error
            .as_deref()
            .unwrap_or("No Quota Data");
        div()
            .id("quota-popover")
            .absolute()
            .left(px(8.0))
            .bottom(theme::status_bar_height())
            .w(px(380.0))
            .max_h(px(480.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .py_1()
            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                this.set_status_popover_panel_hovered(*hovered, cx);
            }))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.pin_active_status_popover(cx)),
            )
            .when(snapshots.is_empty(), |panel| {
                panel.child(
                    div()
                        .p_3()
                        .text_sm()
                        .text_color(theme::text_muted())
                        .child(empty_message.to_owned()),
                )
            })
            .children(
                snapshots
                    .into_iter()
                    .enumerate()
                    .map(|(index, snapshot)| self.quota_overview_row(index, snapshot, cx)),
            )
            // Keep the popover itself absolute. `overflow_y_scrollbar()` wraps
            // the element in a relative container, which would put this
            // overlay back into the status bar's flex flow.
            .overflow_y_scroll()
            .into_any_element()
    }

    fn quota_overview_row(
        &self,
        index: usize,
        snapshot: &QuotaSnapshot,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let pin_key = quota_pin_key(snapshot);
        let pinned = !self.settings_state.quota_unpinned_keys.contains(&pin_key);
        let toggle_key = pin_key.clone();
        let name = provider_label(snapshot);
        let status_color = quota_name_color(&snapshot.status);
        let credits = snapshot.reset_credits.clone();
        let offer_revision = credits
            .as_ref()
            .and_then(|credits| credits.offer_revision.clone());
        let can_consume = credits
            .as_ref()
            .is_some_and(|credits| credits.available_count > 0 && credits.can_consume);

        div()
            .id(("quota-overview-row", index))
            .flex()
            .flex_col()
            .px_2()
            .py(px(2.0))
            .child(
                div()
                    .flex()
                    .items_center()
                    .min_h(px(22.0))
                    .gap(px(6.0))
                    .child(agent_icon(
                        provider_agent_icon(&snapshot.provider),
                        14.0,
                        theme::text_muted(),
                    ))
                    .child(
                        div()
                            .flex_1()
                            .overflow_hidden()
                            .text_ellipsis()
                            .font_family("JetBrains Mono")
                            .text_size(px(10.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .text_color(status_color)
                            .child(name),
                    )
                    .when(snapshot.readings.is_empty(), |row| {
                        row.child(
                            div()
                                .font_family("JetBrains Mono")
                                .text_size(px(10.0))
                                .text_color(quota_color(&snapshot.status, None))
                                .child("-"),
                        )
                    })
                    .children(snapshot.readings.iter().map(|reading| {
                        div()
                            .flex()
                            .items_center()
                            .gap(px(2.0))
                            .font_family("JetBrains Mono")
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
                    .child(
                        div()
                            .id(("quota-pin", index))
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(22.0))
                            .h(px(22.0))
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_selected()))
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    let key = toggle_key.clone();
                                    this.update_quota_settings(
                                        move |settings| {
                                            if pinned {
                                                settings.quota_unpinned_keys.insert(key);
                                            } else {
                                                settings.quota_unpinned_keys.remove(&key);
                                            }
                                        },
                                        cx,
                                    );
                                }),
                            )
                            .child(icon(
                                if pinned {
                                    AleraIcon::Pin
                                } else {
                                    AleraIcon::PinOff
                                },
                                12.0,
                                if pinned {
                                    theme::text_muted()
                                } else {
                                    theme::text_faint()
                                },
                            )),
                    ),
            )
            .when_some(credits, |row, credits| {
                let expiry = codex_reset_expiry(credits.next_expires_at);
                row.child(
                    div()
                        .flex()
                        .items_center()
                        .ml(px(20.0))
                        .min_h(px(24.0))
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
                        .when(credits.available_count > 0, |credit_row| {
                            credit_row.child(
                                div()
                                    .id("quota-use-reset")
                                    .px(px(6.0))
                                    .h(px(24.0))
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
                                                cx.notify();
                                            }),
                                        )
                                    })
                                    .child("Use Reset"),
                            )
                        }),
                )
            })
            .into_any_element()
    }

    pub(super) fn render_codex_reset_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
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
                    .w(px(430.0))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p_4()
                    .child(
                        div()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Use Codex Reset"),
                    )
                    .child(
                        div()
                            .mt_3()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(
                                "Use One Codex Rate-Limit Reset Credit? Alera Will Re-Check The Active Account And Offer Before Applying It.",
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt_4()
                            .child(
                                quota_dialog_button("cancel-codex-reset", "Cancel", false).on_mouse_down(gpui::MouseButton::Left,
                                    cx.listener(|this, _, _, cx| {
                                        if !this.codex_reset_busy {
                                            this.codex_reset_offer_revision = None;
                                            cx.notify();
                                        }
                                    }),
                                ),
                            )
                            .child(
                                quota_dialog_button_with_loading(
                                    "confirm-codex-reset",
                                    if self.codex_reset_busy {
                                        "Applying..."
                                    } else {
                                        "Use Reset"
                                    },
                                    true,
                                    self.codex_reset_busy,
                                )
                                .on_mouse_down(gpui::MouseButton::Left, cx.listener(|this, _, _, cx| {
                                    this.consume_codex_reset(cx);
                                })),
                            ),
                    ),
            )
            .into_any_element()
    }

    fn consume_codex_reset(&mut self, cx: &mut Context<Self>) {
        if self.codex_reset_busy {
            return;
        }
        let Some(offer_revision) = self.codex_reset_offer_revision.clone() else {
            return;
        };
        self.codex_reset_busy = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentQuota.consumeCodexResetCredit",
                    json!({"offerRevision": offer_revision}),
                    Duration::from_secs(45),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.codex_reset_busy = false;
                this.codex_reset_offer_revision = None;
                match result {
                    Ok(value) => {
                        this.local_message = Some(codex_reset_result_message(&value).into());
                        this.refresh_quota_status(false, cx);
                    }
                    Err(error) => {
                        this.local_message = Some(format!("Codex Reset Failed: {error}").into())
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }
}

pub(super) fn provider_agent_icon(provider: &str) -> AgentIcon {
    match provider {
        "antigravity" => AgentIcon::Agy,
        "claude" => AgentIcon::Claude,
        "codex" => AgentIcon::Codex,
        "cursor" => AgentIcon::Cursor,
        "grok" => AgentIcon::Grok,
        "kimi" => AgentIcon::Kimi,
        "minimax" => AgentIcon::MiniMax,
        "zai" => AgentIcon::Zai,
        _ => AgentIcon::Codex,
    }
}

pub(super) fn provider_label(snapshot: &QuotaSnapshot) -> String {
    let provider = match snapshot.provider.as_str() {
        "antigravity" => "Antigravity",
        "claude" => "Claude Code",
        "codex" => "Codex",
        "cursor" => "Cursor",
        "grok" => "Grok Build",
        "kimi" => "Kimi",
        "minimax" => "MiniMax",
        "zai" => "Z.ai",
        _ => snapshot.provider.as_str(),
    };
    if snapshot.provider == "claude" {
        format!("{provider} {}", snapshot.display_name)
    } else {
        provider.to_owned()
    }
}

fn quota_name_color(status: &str) -> gpui::Rgba {
    match status {
        "ok" => theme::text(),
        "stale" => theme::text_faint(),
        _ => theme::danger(),
    }
}

pub(super) fn quota_color(status: &str, remaining: Option<f64>) -> gpui::Rgba {
    if matches!(status, "error" | "unavailable") {
        return theme::danger();
    }
    if status == "stale" {
        return theme::text_faint();
    }
    match remaining {
        Some(value) if value < 20.0 => theme::danger(),
        Some(value) if value < 50.0 => theme::warning(),
        Some(_) => theme::success(),
        None => theme::text_faint(),
    }
}

pub(super) fn codex_reset_expiry(next_expires_at: Option<i64>) -> Option<String> {
    let remaining_ms = next_expires_at? - chrono::Utc::now().timestamp_millis();
    if remaining_ms <= 0 {
        return Some("Next Reset Expired".to_owned());
    }
    let minutes = remaining_ms / 60_000;
    let days = minutes / (24 * 60);
    let hours = (minutes % (24 * 60)) / 60;
    let minutes = minutes % 60;
    if days > 0 {
        Some(format!("Next Reset Expires In {days}d {hours}h"))
    } else if hours > 0 {
        Some(format!("Next Reset Expires In {hours}h {minutes}m"))
    } else {
        Some(format!("Next Reset Expires In {}m", minutes.clamp(1, 59)))
    }
}

fn codex_reset_result_message(value: &serde_json::Value) -> &'static str {
    if value.get("status").and_then(serde_json::Value::as_str) == Some("rejected") {
        return match value.get("reason").and_then(serde_json::Value::as_str) {
            Some("offerChanged") => "Codex Reset Offer Changed. Review The Updated Credits.",
            _ => "No Codex Reset Credit Is Available.",
        };
    }
    match value.get("outcome").and_then(serde_json::Value::as_str) {
        Some("reset") => "Codex Rate Limit Reset Applied.",
        Some("nothingToReset") => "Codex Has No Active Rate Limit To Reset.",
        Some("noCredit") => "No Codex Reset Credit Is Available.",
        Some("alreadyRedeemed") => "This Codex Reset Was Already Applied.",
        _ => "Codex Reset Result Was Unavailable.",
    }
}

fn quota_dialog_button(
    id: &'static str,
    label: &'static str,
    filled: bool,
) -> gpui::Stateful<gpui::Div> {
    quota_dialog_button_with_loading(id, label, filled, false)
}

fn quota_dialog_button_with_loading(
    id: &'static str,
    label: &'static str,
    filled: bool,
    loading: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .h(px(30.0))
        .px_3()
        .flex()
        .items_center()
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .when(filled, |button| {
            button.bg(theme::accent()).text_color(theme::on_accent())
        })
        .when(!filled, |button| button.bg(theme::surface_selected()))
        .when(loading, |button| {
            button.child(loading_indicator(13.0, theme::text_faint()))
        })
        .child(label)
}
