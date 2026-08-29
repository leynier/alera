use std::collections::BTreeMap;

use chrono::{Duration as ChronoDuration, Local, NaiveDate};
use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _,
};
use serde_json::{json, Value};
use gpui_component::scroll::ScrollableElement;
use gpui_component::tooltip::Tooltip;

use super::status_data::QuotaSnapshot;
use super::status_quota::provider_agent_icon;
use super::AleraApp;
use crate::icons::{agent_icon, icon, loading_indicator, AleraIcon};
use crate::theme;

const USAGE_DIALOG_WIDTH: f32 = 1_040.0;
const USAGE_DIALOG_HEIGHT: f32 = 720.0;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum UsageBreakdownMode {
    Account,
    Model,
}

#[derive(Clone, Debug, Default)]
struct UsageSnapshotView {
    since_day: String,
    until_day: String,
    buckets: Vec<UsageBucketView>,
    sources: Vec<UsageSourceView>,
    pricing_status: String,
    days: Vec<UsageDayView>,
}

#[derive(Clone, Debug, Default)]
struct UsageBucketView {
    day: String,
    provider: String,
    account_id: String,
    display_name: String,
    model: String,
    tokens: u64,
    cached_input_tokens: u64,
    total_input_tokens: u64,
    cost_usd: f64,
    cache_savings_usd: f64,
    records: u64,
    unpriced_records: u64,
    sessions: u64,
}

#[derive(Clone, Debug, Default)]
struct UsageSourceView {
    provider: String,
    display_name: String,
    status: String,
    scanned_files: u64,
    distinct_sessions: u64,
}

#[derive(Clone, Debug, Default)]
struct UsageDayView {
    day: String,
    claude_tokens: u64,
    codex_tokens: u64,
    cost_usd: f64,
}

#[derive(Clone, Debug, Default)]
struct UsageBreakdownView {
    provider: String,
    label: String,
    tokens: u64,
    cost_usd: f64,
    records: u64,
}

impl UsageSnapshotView {
    fn from_value(value: &Value) -> Self {
        let buckets = value
            .get("buckets")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(UsageBucketView::from_value)
            .collect::<Vec<_>>();
        let sources = value
            .get("sources")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(UsageSourceView::from_value)
            .collect::<Vec<_>>();
        let since_day = string(value, "sinceDay", "");
        let until_day = string(value, "untilDay", "");
        let mut days = BTreeMap::<String, UsageDayView>::new();
        for bucket in &buckets {
            let day = days.entry(bucket.day.clone()).or_insert_with(|| UsageDayView {
                day: bucket.day.clone(),
                ..UsageDayView::default()
            });
            if bucket.provider == "claude" {
                day.claude_tokens = day.claude_tokens.saturating_add(bucket.tokens);
            } else if bucket.provider == "codex" {
                day.codex_tokens = day.codex_tokens.saturating_add(bucket.tokens);
            }
            day.cost_usd += bucket.cost_usd;
        }
        if let (Some(mut date), Some(last)) = (parse_day(&since_day), parse_day(&until_day)) {
            let mut filled = Vec::new();
            while date <= last {
                let key = date.format("%Y-%m-%d").to_string();
                filled.push(days.remove(&key).unwrap_or_else(|| UsageDayView {
                    day: key,
                    ..UsageDayView::default()
                }));
                date += ChronoDuration::days(1);
            }
            days = filled.into_iter().map(|day| (day.day.clone(), day)).collect();
        }
        Self {
            since_day,
            until_day,
            buckets,
            sources,
            pricing_status: value
                .pointer("/pricing/status")
                .and_then(Value::as_str)
                .unwrap_or("unavailable")
                .to_owned(),
            days: days.into_values().collect(),
        }
    }

    fn totals(&self) -> (u64, u64, u64, f64, f64, u64, u64) {
        self.buckets.iter().fold(
            (0, 0, 0, 0.0, 0.0, 0, 0),
            |(tokens, cached, input, cost, savings, records, unpriced), bucket| {
                (
                    tokens.saturating_add(bucket.tokens),
                    cached.saturating_add(bucket.cached_input_tokens),
                    input.saturating_add(bucket.total_input_tokens),
                    cost + bucket.cost_usd,
                    savings + bucket.cache_savings_usd,
                    records.saturating_add(bucket.records),
                    unpriced.saturating_add(bucket.unpriced_records),
                )
            },
        )
    }

    fn breakdowns(&self, mode: UsageBreakdownMode) -> Vec<UsageBreakdownView> {
        let mut values = BTreeMap::<String, UsageBreakdownView>::new();
        for bucket in &self.buckets {
            let (key, label) = match mode {
                UsageBreakdownMode::Account => (
                    format!("{}:{}", bucket.provider, bucket.account_id),
                    bucket.display_name.clone(),
                ),
                UsageBreakdownMode::Model => (
                    format!("{}:{}", bucket.provider, bucket.model),
                    bucket.model.clone(),
                ),
            };
            let entry = values.entry(key).or_insert_with(|| UsageBreakdownView {
                provider: bucket.provider.clone(),
                label,
                ..UsageBreakdownView::default()
            });
            entry.tokens = entry.tokens.saturating_add(bucket.tokens);
            entry.cost_usd += bucket.cost_usd;
            entry.records = entry.records.saturating_add(bucket.records);
        }
        let mut result = values.into_values().collect::<Vec<_>>();
        result.sort_by(|left, right| right.tokens.cmp(&left.tokens));
        result
    }
}

impl UsageBucketView {
    fn from_value(value: &Value) -> Self {
        let totals = value.get("totals");
        let uncached = number(totals, "uncachedInputTokens");
        let cached = number(totals, "cachedInputTokens");
        let created = number(totals, "cacheCreationTokens");
        Self {
            day: string(value, "day", ""),
            provider: string(value, "provider", "codex"),
            account_id: string(value, "accountId", "default"),
            display_name: string(value, "displayName", "Default"),
            model: string(value, "model", "Unknown"),
            tokens: uncached
                .saturating_add(cached)
                .saturating_add(created)
                .saturating_add(number(totals, "outputTokens")),
            cached_input_tokens: cached,
            total_input_tokens: uncached.saturating_add(cached).saturating_add(created),
            cost_usd: number_f64(value, "costUsd"),
            cache_savings_usd: number_f64(value, "cacheSavingsUsd"),
            records: number(Some(value), "records"),
            unpriced_records: number(Some(value), "unpricedRecords"),
            sessions: number(Some(value), "sessions"),
        }
    }
}

impl UsageSourceView {
    fn from_value(value: &Value) -> Self {
        Self {
            provider: string(value, "provider", "codex"),
            display_name: string(value, "displayName", "Default"),
            status: string(value, "status", "failed"),
            scanned_files: number(Some(value), "scannedFiles"),
            distinct_sessions: number(Some(value), "distinctSessions"),
        }
    }
}

impl AleraApp {
    fn current_status_host_id(&self) -> String {
        self.selected_workspace_id
            .as_deref()
            .and_then(|workspace_id| {
                self.snapshot
                    .projects
                    .iter()
                    .flat_map(|project| project.workspaces.iter())
                    .find(|workspace| workspace.id == workspace_id)
            })
            .map(|workspace| workspace.host_id.clone())
            .filter(|host| !host.trim().is_empty())
            .unwrap_or_else(|| "local".to_owned())
    }

    fn current_status_host_label(&self) -> String {
        let host = self.current_status_host_id();
        if host == "local" {
            "Local Host".to_owned()
        } else {
            host
        }
    }

    pub(super) fn open_agent_usage_dialog(&mut self, cx: &mut Context<Self>) {
        self.status_popover = crate::activity::StatusPopover::None;
        self.status_popover_pinned = false;
        self.status_popover_panel_hovered = false;
        self.show_agent_usage_dialog = true;
        self.agent_usage_days = 30;
        self.agent_usage_breakdown_mode = UsageBreakdownMode::Account;
        self.refresh_agent_usage(cx);
        cx.notify();
    }

    pub(super) fn close_agent_usage_dialog(&mut self, cx: &mut Context<Self>) {
        self.show_agent_usage_dialog = false;
        self.agent_usage_generation = self.agent_usage_generation.wrapping_add(1);
        cx.notify();
    }

    pub(super) fn set_agent_usage_days(&mut self, days: u32, cx: &mut Context<Self>) {
        if !matches!(days, 7 | 30 | 90) || self.agent_usage_days == days {
            return;
        }
        self.agent_usage_days = days;
        self.refresh_agent_usage(cx);
        cx.notify();
    }

    pub(super) fn toggle_agent_usage_breakdown(&mut self, cx: &mut Context<Self>) {
        self.agent_usage_breakdown_mode = match self.agent_usage_breakdown_mode {
            UsageBreakdownMode::Account => UsageBreakdownMode::Model,
            UsageBreakdownMode::Model => UsageBreakdownMode::Account,
        };
        cx.notify();
    }

    pub(super) fn refresh_agent_usage(&mut self, cx: &mut Context<Self>) {
        self.agent_usage_generation = self.agent_usage_generation.wrapping_add(1);
        let generation = self.agent_usage_generation;
        self.agent_usage_loading = true;
        self.agent_usage_error = None;
        let days = self.agent_usage_days.max(1);
        let cache_key = format!("{}:{days}", self.current_status_host_id());
        self.agent_usage_snapshot = self.agent_usage_cache.get(&cache_key).cloned();
        let until = Local::now().date_naive();
        let since = until - ChronoDuration::days(i64::from(days.saturating_sub(1)));
        let payload = json!({
            "sinceDay": since.format("%Y-%m-%d").to_string(),
            "untilDay": until.format("%Y-%m-%d").to_string(),
        });
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentUsage.snapshot",
                    payload,
                    std::time::Duration::from_secs(90),
                )
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.agent_usage_generation {
                    return;
                }
                this.agent_usage_loading = false;
                match result {
                    Ok(value) => {
                        this.agent_usage_cache.insert(cache_key, value.clone());
                        while this.agent_usage_cache.len() > 9 {
                            let Some(key) = this.agent_usage_cache.keys().next().cloned() else {
                                break;
                            };
                            this.agent_usage_cache.remove(&key);
                        }
                        this.agent_usage_snapshot = Some(value);
                        this.agent_usage_error = None;
                    }
                    Err(error) => {
                        this.agent_usage_snapshot = None;
                        this.agent_usage_error = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_agent_usage_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let snapshot = self
            .agent_usage_snapshot
            .as_ref()
            .map(UsageSnapshotView::from_value);
        let quotas = self
            .visible_quota_snapshots()
            .into_iter()
            .filter(|snapshot| matches!(snapshot.provider.as_str(), "claude" | "codex"))
            .cloned()
            .collect::<Vec<_>>();
        let host = self.current_status_host_label();
        div()
            .id("agent-usage-overlay")
            .absolute()
            .inset_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                div()
                    .id("agent-usage-dialog")
                    .role(Role::Dialog)
                    .aria_label("Usage")
                    .w(px(USAGE_DIALOG_WIDTH))
                    .h(px(USAGE_DIALOG_HEIGHT))
                    .max_h(px(USAGE_DIALOG_HEIGHT))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .flex()
                    .flex_col()
                    .child(self.render_usage_header(host, cx))
                    .when(self.agent_usage_loading, |dialog| {
                        dialog.child(div().h(px(2.0)).bg(theme::accent()))
                    })
                    .child(if let Some(snapshot) = snapshot {
                        self.render_usage_content(snapshot, quotas, cx)
                    } else {
                        self.render_usage_unavailable(cx)
                    }),
            )
            .into_any_element()
    }

    fn render_usage_header(&self, host: String, cx: &mut Context<Self>) -> AnyElement {
        let selected_days = self.agent_usage_days;
        div()
            .flex()
            .items_center()
            .gap_2()
            .px_5()
            .py_3()
            .border_b_1()
            .border_color(theme::border_subtle())
            .child(
                div()
                    .text_lg()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Usage"),
            )
            .child(div().flex_1())
            .child(
                div()
                    .font_family("JetBrains Mono")
                    .text_size(px(10.0))
                    .text_color(theme::text_muted())
                    .child(host),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border())
                    .children([7_u32, 30, 90].into_iter().map(|days| {
                        div()
                            .id(SharedString::from(format!("usage-days-{days}")))
                            .role(Role::Button)
                            .aria_label(format!("{days} Days"))
                            .px_2()
                            .py(px(5.0))
                            .text_size(px(10.0))
                            .cursor(CursorStyle::PointingHand)
                            .when(selected_days == days, |button| {
                                button.bg(theme::accent()).text_color(theme::on_accent())
                            })
                            .when(selected_days != days, |button| {
                                button.text_color(theme::text_muted()).hover(|style| {
                                    style.bg(theme::surface_selected())
                                })
                            })
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.set_agent_usage_days(days, cx);
                            }))
                            .child(format!("{days} Days"))
                    })),
            )
            .child(
                div()
                    .id("usage-refresh")
                    .role(Role::Button)
                    .aria_label("Refresh Usage")
                    .focusable()
                    .tab_stop(!self.agent_usage_loading)
                    .p_2()
                    .cursor(CursorStyle::PointingHand)
                    .when(!self.agent_usage_loading, |button| {
                        button.on_click(cx.listener(|this, _, _, cx| {
                            this.refresh_agent_usage(cx);
                        }))
                    })
                    .child(if self.agent_usage_loading {
                        loading_indicator(14.0, theme::text_faint())
                    } else {
                        icon(AleraIcon::Refresh, 14.0, theme::text_muted())
                    }),
            )
            .child(
                div()
                    .id("usage-close")
                    .role(Role::Button)
                    .aria_label("Close Usage")
                    .focusable()
                    .tab_stop(true)
                    .p_2()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.close_agent_usage_dialog(cx);
                    }))
                    .child(icon(AleraIcon::Close, 14.0, theme::text_muted())),
            )
            .into_any_element()
    }

    fn render_usage_unavailable(&self, cx: &mut Context<Self>) -> AnyElement {
        let loading = self.agent_usage_loading;
        div()
            .flex_1()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .gap_2()
            .text_color(theme::text_muted())
            .child(icon(AleraIcon::Quota, 28.0, theme::text_faint()))
            .child(if loading {
                "Loading Usage"
            } else {
                "Usage Unavailable"
            })
            .when_some(self.agent_usage_error.clone(), |panel, error| {
                panel.child(
                    div()
                        .max_w(px(520.0))
                        .text_size(px(11.0))
                        .text_color(theme::text_faint())
                        .child(error),
                )
            })
            .when(!loading, |panel| {
                panel.child(
                    div()
                        .id("usage-try-again")
                        .role(Role::Button)
                        .aria_label("Try Again")
                        .px_3()
                        .py_2()
                        .rounded_md()
                        .bg(theme::surface_selected())
                        .cursor(CursorStyle::PointingHand)
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.refresh_agent_usage(cx);
                        }))
                        .child("Try Again"),
                )
            })
            .into_any_element()
    }

    fn render_usage_content(
        &self,
        snapshot: UsageSnapshotView,
        quotas: Vec<QuotaSnapshot>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let (tokens, cached, input, cost, savings, records, unpriced) = snapshot.totals();
        let cached_share = if input == 0 {
            0.0
        } else {
            cached as f64 / input as f64
        };
        let mode = self.agent_usage_breakdown_mode;
        let breakdowns = snapshot.breakdowns(mode);
        let maximum = snapshot
            .days
            .iter()
            .map(|day| day.claude_tokens.max(day.codex_tokens))
            .max()
            .unwrap_or(1);
        div()
            .flex_1()
            .min_h_0()
            .overflow_y_scrollbar()
            .p_5()
            .children([self.render_usage_quota_strip(&quotas), self.render_usage_notice(&snapshot)])
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .gap_2()
                    .mt_3()
                    .children([
                        usage_metric("Processed Tokens", format_tokens(tokens), format!("{records} assistant responses")),
                        usage_metric("API-Equivalent Cost", format!("${cost:.2}"), if unpriced > 0 { format!("{unpriced} unpriced responses") } else { match snapshot.pricing_status.as_str() { "fresh" => "Current model rates".to_owned(), "cached" => "Cached model rates".to_owned(), _ => "Pricing unavailable".to_owned() } }),
                        usage_metric("Sessions", format_count(snapshot.sources.iter().map(|source| source.distinct_sessions).sum()), format!("{} transcript sources", snapshot.sources.len())),
                        usage_metric("Cached Input", format_tokens(cached), format!("{:.1}% of input", cached_share * 100.0)),
                        usage_metric("Cache Savings", format!("${savings:.2}"), "Compared with full input rates".to_owned()),
                    ]),
            )
            .child(
                div()
                    .mt_5()
                    .text_size(px(13.0))
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("Daily Activity"),
            )
            .child(
                div()
                    .mt_1()
                    .text_size(px(11.0))
                    .text_color(theme::text_muted())
                    .child("Tokens read from Claude Code and Codex transcripts on this host."),
            )
            .child(self.render_usage_chart(&snapshot.days, maximum))
            .child(
                div()
                    .flex()
                    .items_center()
                    .mt_5()
                    .child(
                        div()
                            .flex_1()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Breakdown"),
                    )
                    .child(
                        div()
                            .id("usage-breakdown-mode")
                            .role(Role::Button)
                            .aria_label(if mode == UsageBreakdownMode::Account {
                                "Switch To Model Breakdown"
                            } else {
                                "Switch To Account Breakdown"
                            })
                            .px_2()
                            .py(px(5.0))
                            .rounded_md()
                            .bg(theme::surface_selected())
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.toggle_agent_usage_breakdown(cx);
                            }))
                            .child(if mode == UsageBreakdownMode::Account {
                                "Account"
                            } else {
                                "Model"
                            }),
                    ),
            )
            .child(self.render_usage_table(&breakdowns))
            .child(
                div()
                    .mt_3()
                    .text_size(px(10.0))
                    .text_color(theme::text_faint())
                    .child(format!(
                        "Scanned {} files in {} ms. Transcript content stays on this host.",
                        snapshot
                            .sources
                            .iter()
                            .map(|source| source.scanned_files)
                            .sum::<u64>(),
                        self.agent_usage_snapshot
                            .as_ref()
                            .and_then(|value| value.get("scanDurationMs"))
                            .and_then(Value::as_u64)
                            .unwrap_or_default()
                    )),
            )
            .into_any_element()
    }

    fn render_usage_quota_strip(&self, quotas: &[QuotaSnapshot]) -> AnyElement {
        let visible = quotas
            .iter()
            .filter(|snapshot| matches!(snapshot.provider.as_str(), "claude" | "codex"));
        div()
            .when(quotas.is_empty(), |panel| panel)
            .when(!quotas.is_empty(), |panel| {
                panel
                    .child(
                        div()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Current Limits"),
                    )
                    .child(
                        div()
                            .mt_2()
                            .rounded_md()
                            .border_1()
                            .border_color(theme::border_subtle())
                            .bg(theme::surface())
                            .children(visible.map(|snapshot| {
                                let used = snapshot
                                    .readings
                                    .first()
                                    .map(|reading| 100.0 - reading.remaining_percent);
                                div()
                                    .flex()
                                    .items_center()
                                    .gap_2()
                                    .px_3()
                                    .py_2()
                                    .child(agent_icon(
                                        provider_agent_icon(&snapshot.provider),
                                        14.0,
                                        theme::text_muted(),
                                    ))
                                    .child(
                                        div()
                                            .flex_1()
                                            .text_size(px(11.0))
                                            .child(format!(
                                                "{} {}",
                                                provider_label(&snapshot.provider),
                                                snapshot.display_name
                                            )),
                                    )
                                    .when_some(used, |row, used| {
                                        row.child(
                                            div()
                                                .w(px(152.0))
                                                .h(px(4.0))
                                                .rounded_full()
                                                .bg(theme::border())
                                                .child(
                                                    div()
                                                        .h_full()
                                                        .w(gpui::relative((used / 100.0).clamp(0.0, 1.0) as f32))
                                                        .rounded_full()
                                                        .bg(theme::text_muted()),
                                                ),
                                        )
                                        .child(
                                            div()
                                                .font_family("JetBrains Mono")
                                                .text_size(px(10.0))
                                                .child(format!("{used:.0}% Used")),
                                        )
                                    })
                            })),
                    )
            })
            .into_any_element()
    }

    fn render_usage_notice(&self, snapshot: &UsageSnapshotView) -> AnyElement {
        let issues = snapshot
            .sources
            .iter()
            .filter(|source| matches!(source.status.as_str(), "partial" | "failed"))
            .map(|source| format!("{} {} is partial.", provider_label(&source.provider), source.display_name))
            .chain((snapshot.pricing_status == "unavailable").then_some(
                "Some model costs may be unavailable because pricing could not be loaded.".to_owned(),
            ))
            .collect::<Vec<_>>();
        if issues.is_empty() {
            return div().into_any_element();
        }
        div()
            .mt_3()
            .p_3()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface())
            .text_size(px(11.0))
            .text_color(theme::text_muted())
            .child(issues.join(" "))
            .into_any_element()
    }

    fn render_usage_chart(&self, days: &[UsageDayView], maximum: u64) -> AnyElement {
        let chart = div()
            .flex()
            .items_end()
            .gap(px(2.0))
            .h(px(160.0))
            .mt_3()
            .border_b_1()
            .border_color(theme::border_subtle())
            .children(days.iter().map(|day| {
                let claude_height = 150.0 * day.claude_tokens as f32 / maximum.max(1) as f32;
                let codex_height = 150.0 * day.codex_tokens as f32 / maximum.max(1) as f32;
                div()
                    .id(SharedString::from(format!("usage-day-{}", day.day)))
                    .flex_1()
                    .flex()
                    .items_end()
                    .gap(px(1.0))
                    .h(px(150.0))
                    .tooltip({
                        let label = format!(
                            "{}\nClaude Code: {}\nCodex: {}",
                            format_usage_day(&day.day),
                            format_tokens(day.claude_tokens),
                            format_tokens(day.codex_tokens),
                        );
                        move |_, cx| {
                            let label = label.clone();
                            cx.new(move |_| Tooltip::new(label)).into()
                        }
                    })
                    .child(
                        div()
                            .flex_1()
                            .h(px(claude_height.max(if day.claude_tokens > 0 { 2.0 } else { 0.0 })))
                            .rounded_t_sm()
                            .bg(theme::text()),
                    )
                    .child(
                        div()
                            .flex_1()
                            .h(px(codex_height.max(if day.codex_tokens > 0 { 2.0 } else { 0.0 })))
                            .rounded_t_sm()
                            .bg(theme::text_faint()),
                    )
            }));
        div()
            .child(chart)
            .child(
                div()
                    .flex()
                    .items_center()
                    .mt_1()
                    .text_size(px(10.0))
                    .text_color(theme::text_faint())
                    .child(
                        days.first()
                            .map(|day| format_usage_day(&day.day))
                            .unwrap_or_default(),
                    )
                    .child(div().flex_1())
                    .child("Claude Code")
                    .child(div().w_3())
                    .child("Codex")
                    .child(div().flex_1())
                    .child(
                        days.last()
                            .map(|day| format_usage_day(&day.day))
                            .unwrap_or_default(),
                    ),
            )
            .into_any_element()
    }

    fn render_usage_table(&self, values: &[UsageBreakdownView]) -> AnyElement {
        let mut table = div()
            .mt_2()
            .rounded_md()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface());
        if values.is_empty() {
            return table
                .p_3()
                .text_size(px(11.0))
                .text_color(theme::text_muted())
                .child("No Claude Code or Codex usage was found in this range.")
                .into_any_element();
        }
        table = table.child(
            usage_table_row("Name", "Tokens", "Cost", "Responses", true, None),
        );
        for value in values {
            table = table.child(usage_table_row(
                &value.label,
                &format_tokens(value.tokens),
                &format!("${:.2}", value.cost_usd),
                &format_count(value.records),
                false,
                Some(&value.provider),
            ));
        }
        table.into_any_element()
    }
}

fn usage_metric(label: &str, value: String, detail: String) -> AnyElement {
    div()
        .w(px(180.0))
        .min_h(px(78.0))
        .p_3()
        .rounded_lg()
        .border_1()
        .border_color(theme::border_subtle())
        .bg(theme::surface())
        .child(div().text_size(px(10.0)).text_color(theme::text_muted()).child(label.to_owned()))
        .child(div().mt_1().font_family("JetBrains Mono").text_size(px(16.0)).child(value))
        .child(div().mt_1().text_size(px(10.0)).text_color(theme::text_faint()).child(detail))
        .into_any_element()
}

fn usage_table_row(
    name: &str,
    tokens: &str,
    cost: &str,
    responses: &str,
    header: bool,
    provider: Option<&str>,
) -> AnyElement {
    div()
        .flex()
        .items_center()
        .gap_2()
        .px_3()
        .py_2()
        .border_b_1()
        .border_color(theme::border_subtle())
        .when(!header, |row| {
            row.child(agent_icon(
                provider.map(provider_agent_icon).unwrap_or(crate::icons::AgentIcon::Codex),
                14.0,
                theme::text_muted(),
            ))
        })
        .child(div().flex_1().text_size(px(11.0)).child(name.to_owned()))
        .child(
            div()
                .w(px(120.0))
                .text_align(gpui::TextAlign::Right)
                .font_family("JetBrains Mono")
                .text_size(px(10.0))
                .text_color(theme::text_muted())
                .child(tokens.to_owned()),
        )
        .child(
            div()
                .w(px(100.0))
                .text_align(gpui::TextAlign::Right)
                .font_family("JetBrains Mono")
                .text_size(px(10.0))
                .text_color(theme::text_muted())
                .child(cost.to_owned()),
        )
        .child(
            div()
                .w(px(90.0))
                .text_align(gpui::TextAlign::Right)
                .font_family("JetBrains Mono")
                .text_size(px(10.0))
                .text_color(theme::text_muted())
                .child(responses.to_owned()),
        )
        .into_any_element()
}

fn provider_label(provider: &str) -> &'static str {
    match provider {
        "claude" => "Claude Code",
        "codex" => "Codex",
        _ => "Agent",
    }
}

fn parse_day(value: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()
}

fn string(value: &Value, key: &str, fallback: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .to_owned()
}

fn number(value: Option<&Value>, key: &str) -> u64 {
    value
        .and_then(|value| value.get(key))
        .and_then(Value::as_u64)
        .unwrap_or_default()
}

fn number_f64(value: &Value, key: &str) -> f64 {
    value.get(key).and_then(Value::as_f64).unwrap_or_default()
}

fn format_tokens(value: u64) -> String {
    if value >= 1_000_000_000_000 {
        return trim_number(value as f64 / 1_000_000_000_000.0) + "T";
    }
    if value >= 1_000_000_000 {
        return trim_number(value as f64 / 1_000_000_000.0) + "B";
    }
    if value >= 1_000_000 {
        return trim_number(value as f64 / 1_000_000.0) + "M";
    }
    if value >= 1_000 {
        return trim_number(value as f64 / 1_000.0) + "K";
    }
    value.to_string()
}

fn trim_number(value: f64) -> String {
    let digits = if value >= 100.0 {
        0
    } else if value >= 10.0 {
        1
    } else {
        2
    };
    let text = format!("{value:.digits$}");
    text.trim_end_matches('0').trim_end_matches('.').to_owned()
}

fn format_count(value: u64) -> String {
    let raw = value.to_string();
    let mut result = String::new();
    for (index, character) in raw.chars().enumerate() {
        if index > 0 && (raw.len() - index) % 3 == 0 {
            result.push(',');
        }
        result.push(character);
    }
    result
}

fn format_usage_day(value: &str) -> String {
    let mut parts = value.split('-');
    let _year = parts.next();
    let month = parts.next().and_then(|month| month.parse::<usize>().ok());
    let day = parts.next().and_then(|day| day.parse::<u32>().ok());
    let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
        "Dec",
    ];
    match (month, day) {
        (Some(month), Some(day)) if (1..=12).contains(&month) => {
            format!("{} {day}", months[month - 1])
        }
        _ => value.to_owned(),
    }
}
