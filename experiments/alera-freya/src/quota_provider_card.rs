use std::time::Duration;

use alera_desktop_core::RuntimeBridge;
use chrono::Utc;
use freya::{icons, prelude::*};
use serde_json::{Value, json};

use super::{
    ACCENT, CodexResetOffer, FAINT, MUTED, TEXT, codex_reset_offer, codex_reset_summary_row,
    provider_icon_for_name, quota_percent_color, quota_provider, status_popover,
};

#[derive(Clone)]
pub(crate) struct QuotaAgentChip {
    snapshot: Value,
    bridge: RuntimeBridge,
    refresh_revision: State<u64>,
    reset_confirmation: State<Option<CodexResetOffer>>,
    reset_error: State<Option<String>>,
    active_status_popover: State<Option<String>>,
}

impl QuotaAgentChip {
    pub(crate) fn new(
        snapshot: Value,
        bridge: RuntimeBridge,
        refresh_revision: State<u64>,
        reset_confirmation: State<Option<CodexResetOffer>>,
        reset_error: State<Option<String>>,
        active_status_popover: State<Option<String>>,
    ) -> Self {
        Self {
            snapshot,
            bridge,
            refresh_revision,
            reset_confirmation,
            reset_error,
            active_status_popover,
        }
    }
}

impl PartialEq for QuotaAgentChip {
    fn eq(&self, other: &Self) -> bool {
        self.snapshot == other.snapshot
    }
}

impl Component for QuotaAgentChip {
    fn render(&self) -> impl IntoElement {
        let open = use_state(|| false);
        let panel = quota_provider_panel(
            self.snapshot.clone(),
            self.bridge.clone(),
            self.refresh_revision,
            self.reset_confirmation,
            self.reset_error,
        );
        let provider = quota_provider(&self.snapshot).to_string();
        let display_name = self
            .snapshot
            .get("displayName")
            .and_then(Value::as_str)
            .unwrap_or(&provider)
            .to_string();
        let heading = if provider == "claude" {
            format!("Claude Code {display_name}")
        } else {
            quota_provider_label(&provider)
        };
        status_popover(
            "Quota Provider",
            icons::lucide::gauge(),
            heading,
            Vec::new(),
            Some(panel),
            open,
            quota_provider_trigger(&self.snapshot),
            Some((
                format!("quota-provider:{}", super::quota_pin_key(&self.snapshot)),
                self.active_status_popover,
            )),
        )
    }
}

#[derive(Clone, Debug)]
struct QuotaHoverReading {
    label: String,
    remaining_percent: f64,
    resets_at: Option<i64>,
    reset_description: Option<String>,
    order: u8,
}

fn quota_provider_trigger(snapshot: &Value) -> Element {
    let provider = quota_provider(snapshot).to_string();
    let display_name = snapshot
        .get("displayName")
        .and_then(Value::as_str)
        .unwrap_or(&provider)
        .to_string();
    let readings = super::quota_readings(snapshot)
        .into_iter()
        .map(|(label, percent)| (label, percent, quota_percent_color(snapshot, percent)))
        .collect::<Vec<_>>();
    let has_readings = !readings.is_empty();
    let empty_color = quota_status_color(snapshot, None);
    rect()
        .interactive(false)
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(4.)
        .maybe_child(provider_icon_for_name(&provider))
        .maybe_child((provider == "claude").then(|| {
            label()
                .font_size(8.)
                .font_family("JetBrains Mono")
                .font_weight(FontWeight::SEMI_BOLD)
                .color(MUTED)
                .max_lines(1)
                .text(display_name)
        }))
        .children(readings.into_iter().map(|(label_text, percent, color)| {
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(2.)
                .child(
                    label()
                        .font_size(8.)
                        .font_family("JetBrains Mono")
                        .font_weight(FontWeight::MEDIUM)
                        .color(FAINT)
                        .text(label_text),
                )
                .child(
                    label()
                        .font_size(10.)
                        .font_family("JetBrains Mono")
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(color)
                        .text(format!("{percent:.0}%")),
                )
        }))
        .maybe_child((!has_readings).then(|| {
            label()
                .font_size(10.)
                .font_family("JetBrains Mono")
                .color(empty_color)
                .text("-")
        }))
        .into()
}

fn quota_provider_panel(
    snapshot: Value,
    bridge: RuntimeBridge,
    refresh_revision: State<u64>,
    reset_confirmation: State<Option<CodexResetOffer>>,
    reset_error: State<Option<String>>,
) -> Element {
    let provider = quota_provider(&snapshot).to_string();
    let display_name = snapshot
        .get("displayName")
        .and_then(Value::as_str)
        .unwrap_or(&provider)
        .to_string();
    let status = snapshot
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("unavailable")
        .to_string();
    let error_message = snapshot
        .get("error")
        .and_then(Value::as_str)
        .map(str::to_string);
    let readings = quota_hover_readings(&snapshot);
    let status_color = quota_status_color(
        &snapshot,
        readings
            .iter()
            .map(|reading| reading.remaining_percent)
            .reduce(f64::min),
    );
    let reset_offer = codex_reset_offer(&snapshot);
    let show_tui = provider == "claude" && status != "ok";
    let profile_label = (provider == "claude").then_some(display_name.clone());
    let provider_label = quota_provider_label(&provider);
    let header_height = if profile_label.is_some() { 30. } else { 22. };
    let reading_height = if readings.is_empty() {
        20.
    } else {
        readings.len() as f32 * 42. + readings.len().saturating_sub(1) as f32 * 12.
    };
    let panel_height = (24.
        + header_height
        + 12.
        + reading_height
        + if reset_offer.is_some() { 40. } else { 0. }
        + if show_tui { 34. } else { 0. })
    .min(480.);

    let tui_busy = use_state(|| false);
    let tui_error = use_state(|| None::<String>);
    let busy_now = *tui_busy.read();
    let tui_error_now = tui_error.read().clone();
    let mut busy_for_tui = tui_busy;
    let mut error_for_tui = tui_error;
    let mut refresh_for_tui = refresh_revision;
    let account_id = snapshot
        .get("accountId")
        .and_then(Value::as_str)
        .unwrap_or("default")
        .to_string();
    let display_name_for_tui = display_name.clone();
    let bridge_for_tui = bridge;

    let mut content = rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(12.)
        .padding(Gaps::new_all(12.))
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .spacing(8.)
                .maybe_child(super::provider_icon_for_name_size(&provider, 18.))
                .child(
                    rect()
                        .vertical()
                        .content(Content::Flex)
                        .child(
                            label()
                                .font_size(13.)
                                .font_weight(FontWeight::SEMI_BOLD)
                                .color(TEXT)
                                .text(provider_label),
                        )
                        .maybe_child(profile_label.map(|profile| {
                            label()
                                .font_size(10.)
                                .font_family("JetBrains Mono")
                                .color(MUTED)
                                .text(profile)
                        })),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    rect()
                        .padding(Gaps::new(8., 2., 8., 2.))
                        .corner_radius(20.)
                        .background(Color::from_af32rgb(
                            0.12,
                            status_color.0,
                            status_color.1,
                            status_color.2,
                        ))
                        .child(
                            label()
                                .font_size(10.)
                                .color(status_color)
                                .text(quota_status_label(&status)),
                        ),
                ),
        );

    if readings.is_empty() {
        content = content.child(
            label()
                .font_size(12.)
                .color(MUTED)
                .max_lines(3)
                .text(error_message.unwrap_or_else(|| "Quota Data Unavailable".to_string())),
        );
    } else {
        for reading in readings {
            content = content.child(quota_hover_reading(&snapshot, reading));
        }
    }

    if let Some(offer) = reset_offer {
        content = content.child(codex_reset_summary_row(
            offer,
            reset_confirmation,
            reset_error,
        ));
    }

    if show_tui {
        content = content
            .maybe_child(tui_error_now.map(|message| {
                label()
                    .font_size(10.)
                    .color((248, 113, 113))
                    .max_lines(2)
                    .text(message)
            }))
            .child(
                rect()
                    .height(Size::px(24.))
                    .horizontal()
                    .main_align(Alignment::End)
                    .cross_align(Alignment::Center)
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(if busy_now {
                        "Trying With TUI"
                    } else {
                        "Try With TUI"
                    })
                    .on_pointer_enter(move |_| {
                        Cursor::set(if busy_now {
                            CursorIcon::default()
                        } else {
                            CursorIcon::Pointer
                        })
                    })
                    .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        if busy_now {
                            return;
                        }
                        busy_for_tui.set(true);
                        error_for_tui.set(None);
                        let bridge = bridge_for_tui.clone();
                        let account_id = account_id.clone();
                        let display_name = display_name_for_tui.clone();
                        spawn(async move {
                            match bridge
                                .request_with_timeout(
                                    "agentQuota.fetchClaudeTui",
                                    json!({
                                        "accountId": account_id,
                                        "displayName": display_name,
                                    }),
                                    Duration::from_secs(60),
                                )
                                .await
                            {
                                Ok(_) => {
                                    let next = refresh_for_tui.read().saturating_add(1);
                                    refresh_for_tui.set(next);
                                }
                                Err(message) => error_for_tui.set(Some(message)),
                            }
                            busy_for_tui.set(false);
                        });
                    })
                    .child(if busy_now {
                        rect()
                            .horizontal()
                            .cross_align(Alignment::Center)
                            .spacing(6.)
                            .child(CircularLoader::new().size(13.))
                            .child(
                                label()
                                    .font_size(11.)
                                    .color(FAINT)
                                    .text("Trying With TUI..."),
                            )
                            .into_element()
                    } else {
                        label()
                            .font_size(11.)
                            .font_weight(FontWeight::SEMI_BOLD)
                            .color(ACCENT)
                            .text("Try With TUI")
                            .into_element()
                    }),
            );
    }

    ScrollView::new()
        .width(Size::fill())
        .height(Size::px(panel_height))
        .child(content)
        .into()
}

fn quota_hover_reading(snapshot: &Value, reading: QuotaHoverReading) -> Element {
    let color = quota_percent_color(snapshot, reading.remaining_percent);
    let progress = reading.remaining_percent.clamp(0., 100.) as f32;
    rect()
        .width(Size::fill())
        .vertical()
        .content(Content::Flex)
        .spacing(6.)
        .child(
            rect()
                .width(Size::fill())
                .horizontal()
                .content(Content::Flex)
                .cross_align(Alignment::Center)
                .child(
                    label()
                        .font_size(12.)
                        .font_weight(FontWeight::MEDIUM)
                        .color(MUTED)
                        .max_lines(1)
                        .text(reading.label),
                )
                .child(rect().width(Size::flex(1.)).child(""))
                .child(
                    label()
                        .font_size(11.)
                        .font_family("JetBrains Mono")
                        .font_weight(FontWeight::SEMI_BOLD)
                        .color(color)
                        .text(format!("{:.0}% Left", reading.remaining_percent)),
                ),
        )
        .child(
            rect()
                .width(Size::fill())
                .height(Size::px(4.))
                .corner_radius(20.)
                .background((45, 45, 45))
                .child(
                    rect()
                        .width(Size::percent(progress))
                        .height(Size::fill())
                        .corner_radius(20.)
                        .background(color),
                ),
        )
        .child(
            label()
                .font_size(9.)
                .font_family("JetBrains Mono")
                .color(FAINT)
                .text(quota_reset_text(
                    reading.resets_at,
                    reading.reset_description.as_deref(),
                )),
        )
        .into()
}

fn quota_hover_readings(snapshot: &Value) -> Vec<QuotaHoverReading> {
    let provider = quota_provider(snapshot);
    let mut readings = snapshot
        .get("windows")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .chain(
            snapshot
                .get("buckets")
                .and_then(Value::as_array)
                .into_iter()
                .flatten(),
        )
        .filter_map(|reading| {
            let label = reading
                .get("label")
                .or_else(|| reading.get("name"))
                .or_else(|| reading.get("fullLabel"))
                .and_then(Value::as_str)?
                .to_string();
            let remaining_percent = reading
                .get("remainingPercent")
                .or_else(|| reading.get("remaining_percent"))
                .and_then(Value::as_f64)
                .or_else(|| {
                    reading
                        .get("usedPercent")
                        .or_else(|| reading.get("used_percent"))
                        .and_then(Value::as_f64)
                        .map(|used| 100. - used)
                })?
                .clamp(0., 100.);
            Some(QuotaHoverReading {
                order: super::quota_reading_order(provider, &label),
                label,
                remaining_percent,
                resets_at: reading
                    .get("resetsAt")
                    .or_else(|| reading.get("resets_at"))
                    .and_then(Value::as_i64),
                reset_description: reading
                    .get("resetDescription")
                    .or_else(|| reading.get("reset_description"))
                    .and_then(Value::as_str)
                    .map(str::to_string),
            })
        })
        .collect::<Vec<_>>();
    readings.sort_by_key(|reading| reading.order);
    readings
}

fn quota_provider_label(provider: &str) -> String {
    match provider {
        "antigravity" => "Antigravity",
        "claude" => "Claude Code",
        "codex" => "Codex",
        "cursor" => "Cursor",
        "grok" => "Grok Build",
        "kimi" => "Kimi",
        "minimax" => "MiniMax",
        "zai" => "Z.ai",
        other => other,
    }
    .to_string()
}

fn quota_status_label(status: &str) -> &'static str {
    match status {
        "ok" => "Live",
        "stale" => "Stale",
        "error" => "Error",
        _ => "Unavailable",
    }
}

fn quota_status_color(snapshot: &Value, remaining: Option<f64>) -> (u8, u8, u8) {
    let status = snapshot
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("unavailable");
    if matches!(status, "error" | "unavailable") {
        return (248, 113, 113);
    }
    if status == "stale" {
        return FAINT;
    }
    remaining
        .map(|value| quota_percent_color(snapshot, value))
        .unwrap_or(FAINT)
}

fn quota_reset_text(resets_at: Option<i64>, description: Option<&str>) -> String {
    if let Some(resets_at) = resets_at {
        let remaining_ms = resets_at - Utc::now().timestamp_millis();
        if remaining_ms <= 0 {
            return "Reset Available".to_string();
        }
        let minutes = remaining_ms / 60_000;
        let days = minutes / (24 * 60);
        let hours = (minutes % (24 * 60)) / 60;
        let minutes = minutes % 60;
        return if days > 0 {
            format!("Resets In {days}d {hours}h")
        } else if hours > 0 {
            format!("Resets In {hours}h {minutes}m")
        } else {
            format!("Resets In {}m", minutes.clamp(1, 59))
        };
    }
    description
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| "Reset Time Unavailable".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hover_readings_keep_full_labels_and_flutter_order() {
        let snapshot = json!({
            "provider": "claude",
            "status": "ok",
            "windows": [
                {"label": "5 Hour", "usedPercent": 0.0},
                {"label": "Weekly", "usedPercent": 13.0},
                {"label": "Model Weekly", "usedPercent": 100.0}
            ]
        });
        let readings = quota_hover_readings(&snapshot);
        assert_eq!(
            readings
                .iter()
                .map(|reading| reading.label.as_str())
                .collect::<Vec<_>>(),
            vec!["5 Hour", "Weekly", "Model Weekly"]
        );
        assert_eq!(readings[1].remaining_percent, 87.0);
    }

    #[test]
    fn provider_labels_and_statuses_match_flutter_copy() {
        assert_eq!(quota_provider_label("claude"), "Claude Code");
        assert_eq!(quota_provider_label("cursor"), "Cursor");
        assert_eq!(quota_status_label("ok"), "Live");
        assert_eq!(quota_status_label("unavailable"), "Unavailable");
    }
}
