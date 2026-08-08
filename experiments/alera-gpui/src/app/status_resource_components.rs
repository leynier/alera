use std::cmp::Ordering;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Styled as _,
};
use serde_json::Value;

use super::status_bar::format_resource_memory;
use super::status_resource::{ResourceProject, ResourceSession, ResourceWorkspace};
use super::AleraApp;
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

pub(super) fn resource_header() -> gpui::Div {
    div()
        .flex()
        .flex_shrink_0()
        .items_center()
        .h(px(36.0))
        .px_3()
        .gap_2()
        .border_b_1()
        .border_color(theme::border_subtle())
        .child(icon(AleraIcon::Activity, 13.0, theme::text_muted()))
        .child(
            div()
                .text_sm()
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child("Resource Manager"),
        )
}

pub(super) fn resource_host_unreachable_notice() -> gpui::Div {
    div()
        .flex()
        .flex_shrink_0()
        .items_center()
        .px_3()
        .py_2()
        .gap_2()
        .bg(gpui::Rgba {
            a: 0.12,
            ..theme::warning()
        })
        .text_sm()
        .text_color(theme::warning())
        .child(icon(AleraIcon::Error, 13.0, theme::warning()))
        .child(
            div()
                .flex_1()
                .child("The Runtime Host Is Not Responding. Use The Host Chip To Restart It."),
        )
}

pub(super) fn resource_totals(
    cpu: Option<f64>,
    memory: Option<u64>,
    host_memory: Option<u64>,
) -> gpui::Div {
    let share = memory
        .zip(host_memory)
        .filter(|(_, host)| *host > 0)
        .map(|(memory, host)| format!("{:.0}% of RAM", memory as f64 * 100.0 / host as f64))
        .unwrap_or_else(|| "-".to_owned());
    div()
        .flex()
        .flex_shrink_0()
        .items_center()
        .h(px(36.0))
        .px_3()
        .gap_4()
        .border_b_1()
        .border_color(theme::border_subtle())
        .child(totals_value("CPU", format_cpu(cpu)))
        .child(totals_value("Memory", format_memory(memory)))
        .child(div().flex_1())
        .child(
            div()
                .font_family("JetBrains Mono")
                .text_size(px(10.0))
                .child(share),
        )
}

fn totals_value(label: &'static str, value: String) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .gap(px(6.0))
        .child(div().text_sm().text_color(theme::text_faint()).child(label))
        .child(
            div()
                .font_family("JetBrains Mono")
                .text_size(px(11.0))
                .child(value),
        )
}

pub(super) fn resource_sort_button(
    id: &'static str,
    label: &'static str,
    column: &'static str,
    selected: &str,
    flex: bool,
    cx: &mut Context<AleraApp>,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .when(flex, |button| button.flex_1())
        .when(!flex, |button| button.w(px(68.0)).justify_end())
        .flex()
        .items_center()
        .h_full()
        .cursor(CursorStyle::PointingHand)
        .text_color(if column == selected {
            theme::text()
        } else {
            theme::text_faint()
        })
        .on_mouse_down(
            gpui::MouseButton::Left,
            cx.listener(move |this, _, _, cx| {
                this.resource_sort_column = column.to_owned();
                cx.notify();
            }),
        )
        .child(label)
}

#[allow(clippy::too_many_arguments)]
pub(super) fn metric_row(
    id: impl Into<gpui::ElementId>,
    indent: usize,
    label: &str,
    cpu: Option<f64>,
    memory: Option<u64>,
    bold: bool,
    leading: Option<AleraIcon>,
    session: Option<(bool, Vec<u64>)>,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .relative()
        .flex()
        .items_center()
        .min_h(px(26.0))
        .pl(px(12.0 + indent as f32 * 12.0))
        .pr(px(12.0))
        .text_sm()
        .when_some(leading, |row, leading| {
            row.child(icon(leading, 12.0, theme::text_faint()))
                .gap(px(6.0))
        })
        .when_some(session.clone(), |row, (running, _)| {
            row.child(div().w(px(6.0)).h(px(6.0)).rounded_full().bg(if running {
                theme::success()
            } else {
                theme::text_faint()
            }))
            .gap(px(6.0))
        })
        .child(
            div()
                .flex_1()
                .overflow_hidden()
                .text_ellipsis()
                .when(bold, |text| text.font_weight(gpui::FontWeight::SEMIBOLD))
                .child(label.to_owned()),
        )
        .when_some(session, |row, (_, history)| {
            row.child(sparkline(history)).child(div().w(px(8.0)))
        })
        .child(metric_cell(format_cpu(cpu)))
        .child(metric_cell(format_memory(memory)))
        .child(div().w(px(17.0)))
}

fn metric_cell(value: String) -> gpui::Div {
    div()
        .w(px(68.0))
        .text_right()
        .font_family("JetBrains Mono")
        .text_size(px(10.0))
        .child(value)
}

fn sparkline(history: Vec<u64>) -> gpui::Div {
    let samples = history.into_iter().rev().take(16).collect::<Vec<_>>();
    let max = samples.iter().copied().max().unwrap_or(1).max(1);
    div()
        .flex()
        .items_end()
        .gap(px(1.0))
        .w(px(38.0))
        .h(px(14.0))
        .children(samples.into_iter().rev().map(|sample| {
            div()
                .w(px(1.0))
                .h(px(2.0 + sample as f32 / max as f32 * 10.0))
                .bg(theme::text_faint())
        }))
}

pub(super) fn process_row(
    id: &'static str,
    label: &'static str,
    value: &Value,
    cores: u64,
) -> AnyElement {
    metric_row(
        id,
        1,
        label,
        value
            .get("cpuPercent")
            .and_then(Value::as_f64)
            .map(|cpu| cpu / cores as f64),
        value.get("memoryBytes").and_then(Value::as_u64),
        false,
        None,
        Some((
            true,
            value
                .get("history")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(Value::as_u64)
                .collect(),
        )),
    )
    .into_any_element()
}

pub(super) fn sort_sessions(sessions: &mut [ResourceSession], column: &str) {
    sessions.sort_by(|left, right| match column {
        "cpu" => compare_optional_descending(left.cpu, right.cpu)
            .then_with(|| compare_name(&left.label, &right.label)),
        "memory" => compare_optional_descending(left.memory, right.memory)
            .then_with(|| compare_name(&left.label, &right.label)),
        _ => compare_name(&left.label, &right.label),
    });
}

pub(super) fn sort_projects(projects: &mut [ResourceProject], column: &str) {
    for project in projects.iter_mut() {
        project.workspaces.sort_by(|left, right| match column {
            "cpu" => compare_optional_descending(
                aggregate_sessions(&left.sessions).0,
                aggregate_sessions(&right.sessions).0,
            )
            .then_with(|| compare_name(&left.name, &right.name)),
            "memory" => compare_optional_descending(
                aggregate_sessions(&left.sessions).1,
                aggregate_sessions(&right.sessions).1,
            )
            .then_with(|| compare_name(&left.name, &right.name)),
            _ => compare_name(&left.name, &right.name),
        });
    }
    projects.sort_by(|left, right| match column {
        "cpu" => compare_optional_descending(
            aggregate_workspaces(&left.workspaces).0,
            aggregate_workspaces(&right.workspaces).0,
        )
        .then_with(|| compare_name(&left.name, &right.name)),
        "memory" => compare_optional_descending(
            aggregate_workspaces(&left.workspaces).1,
            aggregate_workspaces(&right.workspaces).1,
        )
        .then_with(|| compare_name(&left.name, &right.name)),
        _ => compare_name(&left.name, &right.name),
    });
}

fn compare_name(left: &str, right: &str) -> Ordering {
    left.to_lowercase().cmp(&right.to_lowercase())
}

fn compare_optional_descending<T>(left: Option<T>, right: Option<T>) -> Ordering
where
    T: PartialOrd,
{
    match (left, right) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (Some(left), Some(right)) => right.partial_cmp(&left).unwrap_or(Ordering::Equal),
    }
}

pub(super) fn aggregate_workspaces(workspaces: &[ResourceWorkspace]) -> (Option<f64>, Option<u64>) {
    workspaces
        .iter()
        .fold((None, None), |(cpu, memory), workspace| {
            let (next_cpu, next_memory) = aggregate_sessions(&workspace.sessions);
            (
                sum_optional(cpu, next_cpu),
                sum_optional_u64(memory, next_memory),
            )
        })
}

pub(super) fn aggregate_sessions(sessions: &[ResourceSession]) -> (Option<f64>, Option<u64>) {
    sessions
        .iter()
        .fold((None, None), |(cpu, memory), session| {
            (
                sum_optional(cpu, session.cpu),
                sum_optional_u64(memory, session.memory),
            )
        })
}

fn sum_optional(left: Option<f64>, right: Option<f64>) -> Option<f64> {
    match (left, right) {
        (None, None) => None,
        (left, right) => Some(left.unwrap_or(0.0) + right.unwrap_or(0.0)),
    }
}

fn sum_optional_u64(left: Option<u64>, right: Option<u64>) -> Option<u64> {
    match (left, right) {
        (None, None) => None,
        (left, right) => Some(left.unwrap_or(0) + right.unwrap_or(0)),
    }
}

pub(super) fn sum_process_cpu(
    app: Option<&Value>,
    host: Option<&Value>,
    cores: u64,
) -> Option<f64> {
    let raw = [app, host]
        .into_iter()
        .flatten()
        .filter_map(|value| value.get("cpuPercent").and_then(Value::as_f64))
        .sum::<f64>();
    Some(raw / cores as f64)
}

pub(super) fn sum_process_memory(app: Option<&Value>, host: Option<&Value>) -> Option<u64> {
    Some(
        [app, host]
            .into_iter()
            .flatten()
            .filter_map(|value| value.get("memoryBytes").and_then(Value::as_u64))
            .sum(),
    )
}

pub(super) fn number_at(value: Option<&Value>, path: &[&str]) -> Option<f64> {
    path.iter()
        .fold(value, |value, key| value.and_then(|item| item.get(*key)))
        .and_then(Value::as_f64)
}

pub(super) fn integer_at(value: Option<&Value>, path: &[&str]) -> Option<u64> {
    path.iter()
        .fold(value, |value, key| value.and_then(|item| item.get(*key)))
        .and_then(Value::as_u64)
}

pub(super) fn string_at_value<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn format_cpu(value: Option<f64>) -> String {
    value
        .map(|value| format!("{value:.1}%"))
        .unwrap_or_else(|| "-".to_owned())
}

fn format_memory(value: Option<u64>) -> String {
    value
        .map(format_resource_memory)
        .unwrap_or_else(|| "-".to_owned())
}
