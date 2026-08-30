use gpui::{AnyElement, Context, CursorStyle, FontWeight, InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, Window, div, px};
use gpui_component::{Disableable as _, button::{Button, ButtonVariants as _}, menu::{DropdownMenu as _, PopupMenuItem}, scroll::ScrollableElement as _};
use serde_json::Value;

use super::{AleraApp, agent_canvas_catalog as catalog};
use super::agent_canvas_cards::badge;
use crate::{design_system, icons::{AleraIcon, icon, loading_indicator}, theme};

impl AleraApp {
    pub(super) fn render_agent_canvas_panel(&self, _: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        if self.agent_canvas_loading && self.agent_canvas_values.is_empty() {
            return div().flex().flex_1().items_center().justify_center().child(loading_indicator(18.0, theme::text_muted())).into_any_element();
        }
        if self.agent_canvas_capabilities.as_ref().and_then(|value| value["supported"].as_bool()) == Some(false) {
            return design_system::empty_state("canvas-unsupported", AleraIcon::Agent, "Agent Canvas Unavailable",
                "This runtime host does not support Agent Canvas. Restart Alera to use Agent Canvas.").into_any_element();
        }
        if let Some(error) = self.agent_canvas_error.clone() {
            return design_system::empty_state("canvas-load-error", AleraIcon::Error, "Agent Canvas Unavailable",
                format!("Agent Canvas could not load: {error}")).into_any_element();
        }
        let selected = catalog::selected(&self.agent_canvas_values, self.agent_canvas_selected_id.as_deref());
        let body = if self.agent_canvas_values.is_empty() {
            design_system::empty_state("canvas-catalog-empty", AleraIcon::Agent, "No Agent Canvases",
                "Publish a run from an agent terminal to see its progress here.").into_any_element()
        } else {
            let details = selected.map(|canvas| self.render_agent_canvas_details(canvas, cx))
                .unwrap_or_else(|| design_system::empty_state_with_action("canvas-selection-empty", AleraIcon::Agent, None,
                    "Select an Agent Canvas to inspect its run.".into(), None).into_any_element());
            canvas_columns(self.render_agent_canvas_list(selected, cx), details).into_any_element()
        };
        canvas_frame(self.render_agent_canvas_toolbar(cx), body).into_any_element()
    }

    fn render_agent_canvas_toolbar(&self, cx: &mut Context<Self>) -> AnyElement {
        let show_history = self.agent_canvas_show_history;
        let has_history = self.agent_canvas_values.iter().any(|canvas| catalog::is_history(canvas) && !catalog::is_pinned(canvas));
        let app = cx.entity().downgrade();
        let workspace_id = self.selected_workspace_id.clone();
        let trigger = Button::new("canvas-history-filter").ghost().compact().h(px(24.0)).px_0()
            .label(if show_history { "History" } else { "Active" }).text_size(px(14.0))
            .disabled(!has_history)
            .child(icon(AleraIcon::ChevronDown, 16.0, if has_history { theme::text_muted() } else { theme::text_faint() }));
        div().flex().items_center().h(px(36.0)).flex_shrink_0().px(px(8.0)).gap(px(6.0))
            .child(icon(AleraIcon::Agent, 16.0, theme::info()))
            .child(div().flex_1().text_size(px(13.0)).font_weight(FontWeight::MEDIUM).child("Agent Canvas"))
            .child(trigger.dropdown_menu(move |mut menu, _, _| {
                for (label, show) in [("Active", false), ("History", true)] {
                    let app = app.clone();
                    let workspace_id = workspace_id.clone();
                    menu = menu.item(PopupMenuItem::new(label).checked(show == show_history).on_click(move |_, _, cx| {
                        let _ = app.update(cx, |this, cx| {
                            if this.selected_workspace_id == workspace_id && this.agent_canvas_values.iter().any(|canvas| catalog::is_history(canvas) && !catalog::is_pinned(canvas)) {
                                this.agent_canvas_show_history = show;
                                cx.notify();
                            }
                        });
                    }));
                }
                menu
            })).into_any_element()
    }

    fn render_agent_canvas_list(&self, selected: Option<&Value>, cx: &mut Context<Self>) -> AnyElement {
        div().id("agent-canvas-list").w(px(148.0)).flex_shrink_0().min_h_0().overflow_y_scrollbar().py(px(4.0))
            .children(catalog::groups(&self.agent_canvas_values, self.agent_canvas_show_history).into_iter().map(|(group, rows)| {
                div().child(div().pt(px(6.0)).pb(px(4.0)).pl(px(8.0)).pr(px(4.0)).text_size(px(10.0)).font_weight(FontWeight::SEMIBOLD).text_color(theme::text_muted()).child(group))
                    .children(rows.into_iter().map(|canvas| {
                        let id = canvas["id"].as_str().unwrap_or_default().to_owned();
                        let chosen = selected.is_some_and(|value| value["id"] == id);
                        let pending = canvas["decisions"].as_array().is_some_and(|decisions| decisions.iter().any(|decision| decision["state"] == "pending"));
                        let title = canvas["title"].as_str().unwrap_or("Agent Run").to_owned();
                        div().id(SharedString::from(format!("agent-canvas-row-{id}"))).role(Role::ListBoxOption).aria_label(title.clone()).aria_selected(chosen)
                            .focusable().tab_stop(true).flex().items_center().min_h(px(56.0)).px(px(6.0)).cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(cx.listener(move |this, _, _, cx| { this.agent_canvas_selected_id = Some(id.clone()); cx.notify(); }))
                            .child(div().w(px(24.0)).flex_shrink_0().child(icon(if pending { AleraIcon::Warning } else { AleraIcon::Agent }, 16.0, if pending { theme::warning() } else { theme::text_muted() })))
                            .child(div().ml(px(12.0)).flex_1().min_w_0().child(div().text_size(px(13.0)).text_ellipsis().child(title))
                                .child(div().text_size(px(12.0)).text_ellipsis().text_color(theme::text()).child(canvas["agentType"].as_str().unwrap_or_default().to_owned())))
                            .child(div().ml(px(12.0)).child(badge(format!("r{}", canvas["revision"].as_u64().unwrap_or(0)))))
                    }))
            })).into_any_element()
    }
}

fn canvas_frame(toolbar: AnyElement, body: AnyElement) -> gpui::Div {
    div().flex().flex_col().size_full().min_w_0().min_h_0().child(toolbar)
        .child(div().debug_selector(|| "canvas-catalog-body".into()).w_full().min_w_0().flex().flex_1().min_h_0().child(body))
}

fn canvas_columns(list: AnyElement, details: AnyElement) -> gpui::Div {
    div().w_full().min_w_0().flex().flex_1().min_h_0().child(list)
        .child(div().w(px(1.0)).h_full().flex_shrink_0().bg(theme::border_subtle()))
        .child(div().flex_1().min_w_0().min_h_0().flex().child(details))
}

#[cfg(all(test, feature = "gpui-tests"))]
mod tests {
    use super::*;
    use gpui::{Render, TestAppContext};
    use std::rc::Rc;
    use serde_json::json;
    use crate::app::{agent_canvas_details::{details_frame, details_header}, agent_canvas_document_view::document_view};
    struct EmptyProbe;
    impl Render for EmptyProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            div().w(px(280.0)).h(px(500.0)).child(canvas_frame(div().h(px(36.0)).flex_shrink_0().into_any_element(),
                design_system::empty_state("empty-probe", AleraIcon::Agent, "No Agent Canvases", "Publish a run.").into_any_element()))
        }
    }
    #[gpui::test]
    fn agent_canvas_empty_body_has_full_width_without_a_list_divider(cx: &mut TestAppContext) {
        let (_, cx) = cx.add_window_view(|_, _| EmptyProbe);
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        let body = cx.debug_bounds("canvas-catalog-body").unwrap();
        assert_eq!(body.size.width, px(280.0));
        assert_eq!(body.top(), px(36.0));
        assert_eq!(body.bottom(), px(500.0));
    }

    struct PopulatedProbe;
    impl Render for PopulatedProbe {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl gpui::IntoElement {
            let document: Value = serde_json::from_str(include_str!("../../tests/fixtures/canvas-review.json")).unwrap();
            let canvas = json!({"id":"fixture","revision":1,"decisions":[],"document":document});
            let header = details_header("Review Canvas Alpha".into(), 1, vec![
                div().w(px(22.0)).h(px(22.0)).flex_shrink_0().into_any_element(),
                div().w(px(22.0)).h(px(22.0)).flex_shrink_0().into_any_element(),
                div().debug_selector(|| "canvas-last-header-action".into()).w(px(22.0)).h(px(22.0)).flex_shrink_0().into_any_element(),
            ]);
            div().w(px(460.0)).h(px(700.0)).child(canvas_frame(div().h(px(36.0)).flex_shrink_0().into_any_element(), canvas_columns(
                div().w(px(148.0)).h_full().flex_shrink_0().into_any_element(),
                details_frame(header.into_any_element(), document_view(&canvas, false, Rc::new(|_, _, _| {}))).into_any_element()
            ).into_any_element()))
        }
    }

    #[gpui::test]
    fn agent_canvas_populated_scroll_and_header_stay_inside_the_context_panel(cx: &mut TestAppContext) {
        cx.update(gpui_component::init);
        cx.update(crate::design_system::configure_component_theme);
        let (_, cx) = cx.add_window_view(|_, _| PopulatedProbe);
        cx.run_until_parked();
        cx.update(|window, cx| { let _ = window.draw(cx); });
        assert!(cx.debug_bounds("canvas-last-header-action").unwrap().right() <= px(460.0));
        assert!(cx.debug_bounds("canvas-component-0").unwrap().right() <= px(460.0));
        assert!(cx.debug_bounds("canvas-component-2").unwrap().right() <= px(460.0));
    }
}
