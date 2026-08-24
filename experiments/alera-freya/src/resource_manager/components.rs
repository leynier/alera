use alera_desktop_core::RuntimeBridge;
use freya::{icons, prelude::*};
use serde_json::Value;

use super::{
    BORDER, FAINT, MetricRowConfig, ResourceSession, SUCCESS, TEXT, WARNING,
    actions::terminate_sessions, model::sum_optional,
};

pub(super) fn metric_row(config: MetricRowConfig) -> Rect {
    let MetricRowConfig {
        indent,
        text,
        suffix,
        cpu,
        memory,
        bold,
        leading,
        status_dot,
        history,
        trailing,
    } = config;
    let name = rect()
        .width(Size::flex(1.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(12.)
                .font_weight(if bold {
                    FontWeight::SEMI_BOLD
                } else {
                    FontWeight::NORMAL
                })
                .color(TEXT)
                .max_lines(1)
                .text(text),
        )
        .maybe_child(suffix.map(|suffix| {
            label()
                .font_size(12.)
                .color(FAINT)
                .max_lines(1)
                .text(suffix)
        }));
    let leading_and_name = rect()
        .width(Size::flex(1.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .spacing(6.)
        .maybe_child(leading.map(|icon| {
            SvgViewer::new(icon)
                .width(Size::px(12.))
                .height(Size::px(12.))
                .color(FAINT)
        }))
        .maybe_child(status_dot.map(|running| {
            rect()
                .width(Size::px(6.))
                .height(Size::px(6.))
                .corner_radius(3.)
                .background(if running { SUCCESS } else { FAINT })
        }))
        .child(name);
    rect()
        .width(Size::fill())
        .min_height(Size::px(26.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new(12. + indent as f32 * 12., 4., 12., 4.))
        .child(leading_and_name)
        .maybe_child((history.len() > 1).then(|| {
            rect()
                .width(Size::px(56.))
                .height(Size::px(14.))
                .horizontal()
                .cross_align(Alignment::Center)
                .child(sparkline(history))
        }))
        .child(metric_cell(format_cpu(cpu)))
        .child(metric_cell(format_memory(memory)))
        .child(
            rect()
                .width(Size::px(17.))
                .height(Size::px(26.))
                .center()
                .maybe_child(trailing),
        )
}

fn metric_cell(value: String) -> Element {
    label()
        .width(Size::px(68.))
        .font_family("JetBrains Mono")
        .font_size(10.)
        .color(TEXT)
        .text_align(TextAlign::Right)
        .text(value)
        .into_element()
}

fn sparkline(history: Vec<u64>) -> Element {
    let points = sparkline_points(&history, 48., 14.);
    let points = points
        .iter()
        .map(|(x, y)| format!("{x:.2},{y:.2}"))
        .collect::<Vec<_>>()
        .join(" ");
    let svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="48" height="14" viewBox="0 0 48 14"><polyline points="{points}" fill="none" stroke="#a1a1a1" stroke-width="1" stroke-linejoin="round" stroke-linecap="round"/></svg>"##
    );
    SvgViewer::new(Bytes::from(svg.into_bytes()))
        .width(Size::px(48.))
        .height(Size::px(14.))
        .into_element()
}

fn sparkline_points(samples: &[u64], width: f32, height: f32) -> Vec<(f32, f32)> {
    if samples.len() < 2 || width <= 0. || height <= 0. {
        return Vec::new();
    }
    let lowest = samples.iter().copied().min().unwrap_or_default();
    let highest = samples.iter().copied().max().unwrap_or(lowest);
    let span = highest.saturating_sub(lowest);
    let step_x = width / (samples.len() - 1) as f32;
    samples
        .iter()
        .enumerate()
        .map(|(index, sample)| {
            let normalized = if span == 0 {
                0.5
            } else {
                sample.saturating_sub(lowest) as f32 / span as f32
            };
            (step_x * index as f32, height - normalized * height)
        })
        .collect()
}

pub(super) fn totals_row(
    cpu: Option<f64>,
    memory: Option<u64>,
    host_memory: Option<u64>,
) -> Element {
    let share = memory
        .zip(host_memory)
        .filter(|(_, host)| *host > 0)
        .map(|(memory, host)| format!("{:.0}% of RAM", memory as f64 * 100. / host as f64))
        .unwrap_or_else(|| "-".to_string());
    rect()
        .height(Size::px(36.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new(12., 0., 12., 0.))
        .spacing(16.)
        .border(Border::new().width(bottom_border()).fill(BORDER))
        .child(totals_value(
            "CPU",
            format_cpu(cpu),
            "Total CPU across Alera and every terminal it spawned, as a share of everything this machine can run at once.",
        ))
        .child(totals_value(
            "Memory",
            format_memory(memory),
            "Resident memory of Alera, the runtime host, and every terminal process.",
        ))
        .child(rect().width(Size::flex(1.)).child(""))
        .child(
            TooltipContainer::new(Tooltip::new_text(
                "Share of the machine memory these processes hold.",
            ))
            .position(AttachedPosition::Bottom)
            .delay(std::time::Duration::from_millis(350))
            .child(
                label()
                    .font_family("JetBrains Mono")
                    .font_size(10.)
                    .color(TEXT)
                    .max_lines(1)
                    .text(share),
            ),
        )
        .into_element()
}

fn totals_value(name: &'static str, value: String, tooltip: &'static str) -> Element {
    TooltipContainer::new(Tooltip::new_text(tooltip))
        .position(AttachedPosition::Bottom)
        .delay(std::time::Duration::from_millis(350))
        .child(
            rect()
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(6.)
                .child(label().font_size(12.).color(FAINT).text(name))
                .child(
                    label()
                        .font_family("JetBrains Mono")
                        .font_size(11.)
                        .color(TEXT)
                        .text(value),
                ),
        )
        .into_element()
}

pub(super) fn sort_header(sort_column: State<String>) -> Element {
    rect()
        .height(Size::px(32.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new(12., 0., 12., 0.))
        .border(Border::new().width(bottom_border()).fill(BORDER))
        .child(sort_button("Name", "name", Size::flex(1.), sort_column))
        .child(sort_button("CPU", "cpu", Size::px(68.), sort_column))
        .child(sort_button("Memory", "memory", Size::px(68.), sort_column))
        .child(rect().width(Size::px(17.)).child(""))
        .into_element()
}

fn sort_button(
    text: &'static str,
    column: &'static str,
    width: Size,
    mut sort_column: State<String>,
) -> Element {
    let selected = sort_column.read().as_str() == column;
    TooltipContainer::new(Tooltip::new_text(format!("Sort By {text}")))
        .position(AttachedPosition::Bottom)
        .delay(std::time::Duration::from_millis(350))
        .child(
            rect()
                .width(width)
                .height(Size::fill())
                .cross_align(Alignment::Center)
                .main_align(if column == "name" {
                    Alignment::Start
                } else {
                    Alignment::End
                })
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(format!("Sort By {text}"))
                .on_pointer_enter(|_| Cursor::set(CursorIcon::Pointer))
                .on_pointer_leave(|_| Cursor::set(CursorIcon::default()))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    sort_column.set(column.to_string());
                })
                .child(
                    label()
                        .font_size(12.)
                        .color(if selected { TEXT } else { FAINT })
                        .text(text),
                ),
        )
        .into_element()
}

pub(super) fn host_unreachable_notice(error: String) -> Element {
    TooltipContainer::new(Tooltip::new_text(error))
        .position(AttachedPosition::Bottom)
        .child(
            rect()
                .width(Size::fill())
                .padding(Gaps::new(12., 8., 12., 8.))
                .horizontal()
                .cross_align(Alignment::Center)
                .spacing(8.)
                .background(Color::from_af32rgb(0.12, 245, 158, 11))
                .child(
                    SvgViewer::new(icons::lucide::triangle_alert())
                        .width(Size::px(13.))
                        .height(Size::px(13.))
                        .color(WARNING),
                )
                .child(
                    label().font_size(12.).color(WARNING).max_lines(3).text(
                        "The Runtime Host Is Not Responding. Use The Host Chip To Restart It.",
                    ),
                ),
        )
        .into_element()
}

pub(super) fn orphan_footer(
    count: usize,
    sessions: Vec<ResourceSession>,
    bridge: RuntimeBridge,
    action_busy: State<bool>,
    action_message: State<Option<String>>,
    resource_snapshot: State<Option<Result<Value, String>>>,
) -> Element {
    let session_ids = sessions
        .into_iter()
        .map(|session| session.session_id)
        .collect::<Vec<_>>();
    rect()
        .height(Size::px(34.))
        .horizontal()
        .content(Content::Flex)
        .cross_align(Alignment::Center)
        .padding(Gaps::new(12., 0., 12., 0.))
        .border(Border::new().width(top_border()).fill(BORDER))
        .child(
            label()
                .width(Size::flex(1.))
                .font_size(12.)
                .color(WARNING)
                .text(format!(
                    "{count} Orphan Terminal{}",
                    if count == 1 { "" } else { "s" }
                )),
        )
        .child(
            Button::new()
                .compact()
                .flat()
                .on_press(move |_| {
                    terminate_sessions(
                        bridge.clone(),
                        session_ids.clone(),
                        action_busy,
                        action_message,
                        resource_snapshot,
                    );
                })
                .child("Kill All"),
        )
        .into_element()
}

pub(super) fn alera_process_rows(value: Option<&Value>, cores: u64) -> Element {
    let app = value.and_then(|value| value.pointer("/processes/app"));
    let host = value.and_then(|value| value.pointer("/processes/host"));
    if app.is_none() && host.is_none() {
        return rect().into_element();
    }
    let process_cpu = |value: Option<&Value>| {
        value
            .and_then(|value| value.get("cpuPercent"))
            .and_then(Value::as_f64)
            .map(|cpu| cpu / cores as f64)
    };
    let process_memory = |value: Option<&Value>| {
        value
            .and_then(|value| value.get("memoryBytes"))
            .and_then(Value::as_u64)
    };
    let histories = |value: Option<&Value>| {
        value
            .and_then(|value| value.get("history"))
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_u64)
            .collect::<Vec<_>>()
    };
    let mut rows = rect()
        .width(Size::fill())
        .vertical()
        .border(Border::new().width(top_border()).fill(BORDER))
        .child(metric_row(MetricRowConfig {
            indent: 0,
            text: "Alera".to_string(),
            suffix: None,
            cpu: sum_optional(process_cpu(app), process_cpu(host)),
            memory: sum_optional(process_memory(app), process_memory(host)),
            bold: true,
            leading: None,
            status_dot: None,
            history: Vec::new(),
            trailing: None,
        }));
    if app.is_some() {
        rows = rows.child(metric_row(MetricRowConfig {
            indent: 1,
            text: "App".to_string(),
            suffix: None,
            cpu: process_cpu(app),
            memory: process_memory(app),
            bold: false,
            leading: None,
            status_dot: None,
            history: histories(app),
            trailing: None,
        }));
    }
    if host.is_some() {
        rows = rows.child(metric_row(MetricRowConfig {
            indent: 1,
            text: "Runtime Host".to_string(),
            suffix: None,
            cpu: process_cpu(host),
            memory: process_memory(host),
            bold: false,
            leading: None,
            status_dot: None,
            history: histories(host),
            trailing: None,
        }));
    }
    rows.into_element()
}

pub(super) fn number_at(value: Option<&Value>, path: &[&str]) -> Option<f64> {
    path.iter()
        .fold(value, |value, key| value.and_then(|value| value.get(*key)))
        .and_then(Value::as_f64)
}

pub(super) fn integer_at(value: Option<&Value>, path: &[&str]) -> Option<u64> {
    path.iter()
        .fold(value, |value, key| value.and_then(|value| value.get(*key)))
        .and_then(Value::as_u64)
}

fn format_cpu(value: Option<f64>) -> String {
    value
        .map(|value| format!("{value:.1}%"))
        .unwrap_or_else(|| "-".to_string())
}

fn format_memory(value: Option<u64>) -> String {
    value.map(format_bytes).unwrap_or_else(|| "-".to_string())
}

fn format_bytes(bytes: u64) -> String {
    const KIB: u64 = 1024;
    const MIB: u64 = KIB * 1024;
    const GIB: u64 = MIB * 1024;
    if bytes >= GIB {
        format!("{:.2} GB", bytes as f64 / GIB as f64)
    } else if bytes >= MIB {
        format!("{:.1} MB", bytes as f64 / MIB as f64)
    } else {
        format!("{} KB", bytes.saturating_add(KIB / 2) / KIB)
    }
}

fn top_border() -> BorderWidth {
    BorderWidth {
        top: 1.,
        right: 0.,
        bottom: 0.,
        left: 0.,
    }
}

fn bottom_border() -> BorderWidth {
    BorderWidth {
        top: 0.,
        right: 0.,
        bottom: 1.,
        left: 0.,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sparkline_normalizes_minimum_and_maximum_to_full_height() {
        let points = sparkline_points(&[20, 40, 30], 48., 14.);

        assert_eq!(points, vec![(0., 14.), (24., 0.), (48., 7.)]);
    }

    #[test]
    fn sparkline_centers_a_flat_series() {
        let points = sparkline_points(&[9, 9, 9], 48., 14.);

        assert_eq!(points, vec![(0., 7.), (24., 7.), (48., 7.)]);
    }

    #[test]
    fn sparkline_needs_two_samples() {
        assert!(sparkline_points(&[9], 48., 14.).is_empty());
    }

    #[test]
    fn resource_memory_format_matches_flutter_precision() {
        assert_eq!(format_bytes(512), "1 KB");
        assert_eq!(format_bytes(1_572_864), "1.5 MB");
        assert_eq!(format_bytes(1_610_612_736), "1.50 GB");
    }
}
