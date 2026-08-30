use gpui::{CursorStyle, Div, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, div, px, prelude::FluentBuilder as _};
use serde_json::{Value, json};

use super::{agent_canvas_cards::{card, notice, passive_card}, agent_canvas_document::{decision_action, display, text, typed_action}, agent_canvas_ui_actions::CanvasActionHandler};
use crate::{design_system::{self, ButtonKind}, icons::{AleraIcon, icon}, theme};

pub(super) fn document_view(canvas: &Value, busy: bool, handler: CanvasActionHandler) -> Div {
    let id = canvas["id"].as_str().unwrap_or_default();
    let mut children = Vec::new();
    for (index, component) in canvas.pointer("/document/components").and_then(Value::as_array).into_iter().flatten().enumerate() {
        let Some(kind) = component.get("type").or_else(|| component.get("component")).and_then(Value::as_str) else { continue; };
        let props = component.get("props").filter(|props| props.is_object()).unwrap_or(component);
        let body = passive_card(kind, props).or_else(|| match kind {
            "DecisionRequest" => Some(decision_card(canvas, index, props, busy, handler.clone())),
            "FileReferenceList" => Some(files_card(index, props, busy, handler.clone())),
            "ArtifactCard" => Some(artifact_card(index, props, busy, handler.clone())),
            "ActionGroup" => Some(actions_card(index, props, busy, handler.clone())),
            _ => None,
        });
        if let Some(body) = body {
            children.push(body.id(SharedString::from(format!("canvas-{id}-component-{index}")))
                .debug_selector(move || format!("canvas-component-{index}").into())
                .role(Role::Group).aria_label(component_label(kind, props)).into_any_element());
        }
    }
    if children.is_empty() {
        children.push(notice("info", "This Agent Canvas has no visible components yet.".into()).into_any_element());
    }
    div().w_full().min_w_0().flex().flex_col().flex_shrink_0().p(px(12.0)).gap(px(8.0)).children(children)
}

fn decision_card(canvas: &Value, index: usize, props: &Value, busy: bool, handler: CanvasActionHandler) -> Div {
    let options = props["options"].as_array();
    card(div().flex().flex_col()
        .child(div().font_weight(FontWeight::MEDIUM).child("Decision Request"))
        .child(div().mt(px(6.0)).child(text(props, "question", "Choose an option.")))
        .when(options.is_some_and(|options| !options.is_empty()), |body| body.child(div().mt(px(8.0)).flex().flex_col().children(
            options.into_iter().flatten().enumerate().map(|(option_index, option)| {
                let action = decision_action(canvas, props, option);
                let callback = handler.clone();
                div().pb(px(4.0)).child(design_system::button(SharedString::from(format!("canvas-decision-{index}-{option_index}")), display(option), ButtonKind::Outlined, busy || action.is_none())
                    .debug_selector(move || format!("canvas-decision-{index}-{option_index}").into())
                    .w_full().on_click(move |_, window, cx| { if !busy { if let Some(action) = &action { callback(action, window, cx); } } }))
            })
        ))), true)
}

fn files_card(index: usize, props: &Value, busy: bool, handler: CanvasActionHandler) -> Div {
    card(div().flex().flex_col().child("Files").child(div().mt(px(6.0)).children(
        props["files"].as_array().into_iter().flatten().enumerate().map(|(file_index, file)| {
            let path = file.as_str().map(str::to_owned);
            let callback = handler.clone();
            let label = display(file);
            div().id(SharedString::from(format!("canvas-file-{index}-{file_index}")))
                .role(if path.is_some() { Role::Button } else { Role::ListItem }).aria_label(label.clone())
                .flex().items_center().min_h(px(40.0))
                .when(path.is_some() && !busy, |row| row.cursor(CursorStyle::PointingHand).hover(|style| style.bg(theme::surface_raised())))
                .on_click(move |_, window, cx| { if !busy { if let Some(path) = &path { callback(&json!({"kind":"openFile","relativePath":path}), window, cx); } } })
                .child(div().w(px(24.0)).flex_shrink_0().child(icon(AleraIcon::File, 16.0, theme::text_muted())))
                .child(div().ml(px(12.0)).flex_1().min_w_0().child(label))
        })
    )), false)
}

fn artifact_card(index: usize, props: &Value, busy: bool, handler: CanvasActionHandler) -> Div {
    let artifact = text(props, "artifactId", "");
    card(div().flex().items_center().gap(px(8.0)).child(icon(AleraIcon::File, 18.0, theme::text()))
        .child(div().flex_1().min_w_0().child(text(props, "title", "Artifact")))
        .when(!artifact.is_empty(), |row| row.child(design_system::button(("canvas-artifact", index), "Open", ButtonKind::Text, busy)
            .on_click(move |_, window, cx| { if !busy { handler(&json!({"kind":"openArtifact","artifactId":artifact}), window, cx); } }))), false)
}

fn actions_card(index: usize, props: &Value, busy: bool, handler: CanvasActionHandler) -> Div {
    card(div().flex().flex_wrap().gap(px(6.0)).children(
        props["actions"].as_array().into_iter().flatten().enumerate().filter(|(_, action)| action.is_object()).map(|(action_index, raw)| {
            let action = typed_action(raw);
            let callback = handler.clone();
            design_system::button(SharedString::from(format!("canvas-action-{index}-{action_index}")), text(raw, "label", "Action"), ButtonKind::Outlined, busy || action.is_none())
                .debug_selector(move || format!("canvas-action-{index}-{action_index}").into())
                .on_click(move |_, window, cx| { if !busy { if let Some(action) = &action { callback(action, window, cx); } } })
        })
    ), false)
}

fn component_label(kind: &str, props: &Value) -> String {
    match kind {
        "AgentRunHeader" => format!("{}. {}", text(props,"title","Agent Run"),text(props,"status","live")),
        "TaskProgress" => format!("{}. {} of {} complete", text(props,"label","Task Progress"),display(&props["completed"]),display(&props["total"])),
        "DecisionRequest" => format!("Decision Request. {}", text(props,"question","Choose an option.")),
        "ChangeSummary" => format!("Change Summary. {}", display(props)),
        "FileReferenceList" => "Files".into(),
        "ValidationResults" => format!("Validation Results. {}", display(&props["results"])),
        "RiskSummary" => format!("{}. {}", text(props,"summary","Risk Summary"),text(props,"level","unknown")),
        "ArtifactCard" => text(props,"title","Artifact"),
        "Notice" => text(props,"text",""),
        "ActionGroup" => "Actions".into(),
        _ => String::new(),
    }
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Context, Modifiers, Render, TestAppContext, Window};
    use std::cell::RefCell;
    use std::rc::Rc;

    struct DocumentProbe { canvas: Value, actions: Rc<RefCell<Vec<Value>>> }
    impl Render for DocumentProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            let actions = self.actions.clone();
            div().w(px(320.0)).child(document_view(&self.canvas, false, Rc::new(move |action, _, _| actions.borrow_mut().push(action.clone()))))
        }
    }

    #[gpui::test]
    fn agent_canvas_document_renders_all_ten_fixture_components(cx: &mut TestAppContext) {
        let document: Value = serde_json::from_str(include_str!("../../tests/fixtures/canvas-review.json")).unwrap();
        assert_eq!(document["components"].as_array().unwrap().len(), 10);
        let (_, cx) = cx.add_window_view(|_, _| DocumentProbe { canvas: json!({"id":"fixture","document":document,"revision":1,"decisions":[]}), actions: Default::default() });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        for selector in ["canvas-component-0", "canvas-component-1", "canvas-component-2", "canvas-component-3", "canvas-component-4", "canvas-component-5", "canvas-component-6", "canvas-component-7", "canvas-component-8", "canvas-component-9"] {
            let bounds = cx.debug_bounds(selector).unwrap();
            assert!(bounds.size.width <= px(320.0));
        }
    }

    #[gpui::test]
    fn agent_canvas_action_group_click_emits_the_unwrapped_typed_action(cx: &mut TestAppContext) {
        let actions = Rc::new(RefCell::new(Vec::new()));
        let (_, cx) = cx.add_window_view(|_, _| DocumentProbe { actions: actions.clone(), canvas: json!({"id":"fixture","document":{"components":[
            {"type":"ActionGroup","props":{"actions":[{"label":"Search","action":{"kind":"openSearch","confirmed":true}}]}}
        ]}}) });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let position = cx.debug_bounds("canvas-action-0-0").unwrap().center();
        cx.simulate_click(position, Modifiers::default());
        cx.run_until_parked();
        assert_eq!(*actions.borrow(), vec![json!({"kind":"openSearch"})]);
    }

    #[gpui::test]
    fn agent_canvas_decision_click_keeps_the_original_json_option(cx: &mut TestAppContext) {
        let actions = Rc::new(RefCell::new(Vec::new()));
        let option = json!({"label":"Review","value":"editor"});
        let (_, cx) = cx.add_window_view(|_, _| DocumentProbe { actions: actions.clone(), canvas: json!({"id":"fixture","revision":2,
            "decisions":[{"id":"decision","revision":2,"state":"pending","question":"Pick"}],
            "document":{"components":[{"type":"DecisionRequest","props":{"question":"Pick","options":[option]}}]}
        }) });
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let position = cx.debug_bounds("canvas-decision-0-0").unwrap().center();
        cx.simulate_click(position, Modifiers::default());
        cx.run_until_parked();
        assert_eq!(actions.borrow()[0]["decisionId"], "decision");
        assert_eq!(actions.borrow()[0]["resolution"], option);
    }
}
