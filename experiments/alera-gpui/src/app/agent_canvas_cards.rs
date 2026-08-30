use gpui::{Div, FontWeight, ParentElement as _, Styled as _, div, px};
use serde_json::Value;

use super::agent_canvas_document::{display, text};
use crate::{icons::{AleraIcon, icon}, theme};

pub(super) fn card(content: Div, emphasized: bool) -> Div {
    div().w_full().min_w_0().p(px(11.0)).rounded(px(6.0)).border_1()
        .border_color(if emphasized { theme::info() } else { theme::border_subtle() })
        .bg(if emphasized { theme::surface_raised() } else { theme::surface() })
        .text_size(px(13.0)).text_color(theme::text()).child(content.w_full().min_w_0())
}

pub(super) fn badge(label: String) -> Div {
    div().flex_shrink_0().px(px(6.0)).py(px(2.0)).rounded_full().bg(theme::accent_subtle())
        .text_size(px(10.0)).font_weight(FontWeight::MEDIUM).text_color(theme::text_muted()).child(label)
}

fn status_pill(label: String) -> Div {
    div().flex_shrink_0().px(px(8.0)).py(px(4.0)).rounded_full().bg(theme::accent_subtle()).child(label)
}

pub(super) fn notice(tone: &str, message: String) -> Div {
    let color = match tone { "error" => theme::danger(), "warning" => theme::warning(), "success" => theme::success(), _ => theme::info() };
    card(div().flex().items_start().gap(px(8.0)).child(icon(AleraIcon::Info, 17.0, color))
        .child(div().flex_1().min_w_0().child(message)), false)
}

pub(super) fn passive_card(kind: &str, props: &Value) -> Option<Div> {
    let content = match kind {
        "AgentRunHeader" => div().flex().items_center().gap(px(8.0))
            .child(icon(AleraIcon::Agent, 18.0, theme::info()))
            .child(div().flex_1().min_w_0().font_weight(FontWeight::MEDIUM).child(text(props, "title", "Agent Run")))
            .child(status_pill(text(props, "status", "live"))),
        "TaskProgress" => {
            let completed = props["completed"].as_f64().unwrap_or(0.0).trunc();
            let total = props["total"].as_f64().unwrap_or(0.0).trunc().clamp(1.0, 100000.0);
            let fraction = (completed / total).clamp(0.0, 1.0);
            div().flex().flex_col()
                .child(text(props, "label", "Task Progress"))
                .child(div().mt(px(8.0)).h(px(4.0)).bg(theme::surface_raised())
                    .child(div().h_full().w(gpui::relative(fraction as f32)).bg(theme::accent())))
                .child(div().mt(px(6.0)).text_size(px(12.0)).text_color(theme::text_muted()).child(format!("{completed} of {total} complete")))
        }
        "ChangeSummary" => div().flex().flex_col().child("Change Summary")
            .child(div().mt(px(6.0)).children([("added","Added"), ("modified","Modified"), ("deleted","Deleted"), ("summary","Summary")].into_iter()
                .filter(|(key, _)| !props[*key].is_null()).map(|(key, label)| div().pb(px(4.0)).child(format!("{label}: {}", display(&props[key])))))),
        "ValidationResults" => div().flex().flex_col().child("Validation Results")
            .child(div().mt(px(6.0)).children(props["results"].as_array().into_iter().flatten().map(|result| div().pb(px(4.0)).child(display(result))))),
        "RiskSummary" => div().flex().items_center().gap(px(8.0))
            .child(icon(AleraIcon::ShieldCheck, 17.0, theme::warning()))
            .child(div().flex_1().min_w_0().child(text(props, "summary", "Risk Summary")))
            .child(status_pill(text(props, "level", "unknown"))),
        "Notice" => return Some(notice(&text(props, "tone", "info"), text(props, "text", ""))),
        _ => return None,
    };
    Some(card(content, false))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn agent_canvas_passive_cards_accept_missing_and_malformed_optional_fields() {
        for kind in ["AgentRunHeader", "TaskProgress", "ChangeSummary", "ValidationResults", "RiskSummary", "Notice"] {
            assert!(passive_card(kind, &json!({})).is_some());
            assert!(passive_card(kind, &json!({"completed":"bad","total":0,"results":false})).is_some());
        }
        assert!(passive_card("Unsupported", &json!({})).is_none());
        assert_eq!(display(&json!({"result":["passed", 2, null]})), "{result: [passed, 2, null]}");
    }
}
