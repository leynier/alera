use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::scroll::ScrollableElement as _;
use serde_json::{json, Value};

use super::AleraApp;
use crate::design_system::{self, ButtonKind};
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn refresh_agent_canvas(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            self.agent_canvas_generation = self.agent_canvas_generation.wrapping_add(1);
            self.agent_canvas_loading = false;
            self.agent_canvas_busy = false;
            self.agent_canvas_values.clear();
            self.agent_canvas_selected_id = None;
            self.agent_canvas_error = None;
            cx.notify();
            return;
        };
        if self.agent_canvas_loading {
            return;
        }
        self.agent_canvas_generation = self.agent_canvas_generation.wrapping_add(1);
        let generation = self.agent_canvas_generation;
        self.agent_canvas_loading = true;
        self.agent_canvas_error = None;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let capabilities = bridge.request("agentCanvas.capabilities", json!({})).await;
            let catalog = bridge
                .request(
                    "agentCanvas.catalog",
                    json!({"workspaceId": workspace_id.clone(), "includeHistory": true}),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                if generation != this.agent_canvas_generation
                    || this.selected_workspace_id.as_deref() != Some(workspace_id.as_str())
                {
                    return;
                }
                this.agent_canvas_loading = false;
                match capabilities {
                    Ok(value) => this.agent_canvas_capabilities = Some(value),
                    Err(error) => this.agent_canvas_error = Some(error.into()),
                }
                match catalog {
                    Ok(value) => {
                        this.agent_canvas_values = value
                            .get("canvases")
                            .and_then(Value::as_array)
                            .cloned()
                            .unwrap_or_default();
                        if this.agent_canvas_selected_id.as_ref().is_some_and(|id| {
                            !this
                                .agent_canvas_values
                                .iter()
                                .any(|canvas| value_string(canvas, "id").as_deref() == Some(id))
                        }) {
                            this.agent_canvas_selected_id = None;
                        }
                    }
                    Err(error) => this.agent_canvas_error = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn render_agent_canvas_panel(
        &self,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let supported = self
            .agent_canvas_capabilities
            .as_ref()
            .and_then(|value| value.get("supported"))
            .and_then(Value::as_bool)
            .unwrap_or(true);
        if self.agent_canvas_loading && self.agent_canvas_values.is_empty() {
            return div()
                .flex()
                .flex_1()
                .items_center()
                .justify_center()
                .child(loading_indicator(18.0, theme::text_muted()))
                .into_any_element();
        }
        if !supported {
            return self.agent_canvas_empty(
                "Agent Canvas Unavailable",
                "Restart Alera to use Agent Canvas with this runtime host.",
            );
        }
        if let Some(error) = self.agent_canvas_error.clone() {
            return self.agent_canvas_empty("Agent Canvas Unavailable", &error);
        }
        let values = self.visible_agent_canvases();
        let selected = self.selected_agent_canvas(&values);
        let list = self.render_agent_canvas_list(&values, selected.as_ref(), cx);
        let details = selected
            .map(|canvas| self.render_agent_canvas_details(&canvas, cx))
            .unwrap_or_else(|| {
                self.agent_canvas_empty(
                    "Select an Agent Canvas",
                    "Publish a run from an agent terminal to inspect its progress here.",
                )
            });
        div()
            .id("agent-canvas-panel")
            .flex()
            .flex_col()
            .size_full()
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(px(38.0))
                    .px_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(icon(AleraIcon::Agent, 16.0, theme::info()))
                    .child(
                        div()
                            .ml_2()
                            .flex_1()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Agent Canvas"),
                    )
                    .child(
                        design_system::button(
                            "agent-canvas-history",
                            if self.agent_canvas_show_history {
                                "Hide History"
                            } else {
                                "Show History"
                            },
                            ButtonKind::Text,
                            false,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.agent_canvas_show_history = !this.agent_canvas_show_history;
                            cx.notify();
                        })),
                    )
                    .child(
                        design_system::icon_button(
                            "agent-canvas-refresh",
                            "Refresh Agent Canvas",
                            AleraIcon::Refresh,
                            self.agent_canvas_loading,
                            28.0,
                            None,
                            None,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.refresh_agent_canvas(cx);
                        })),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_1()
                    .min_h_0()
                    .child(list)
                    .child(div().w(px(1.0)).h_full().bg(theme::border_subtle()))
                    .child(div().flex_1().min_w_0().child(details)),
            )
            .into_any_element()
    }

    fn visible_agent_canvases(&self) -> Vec<Value> {
        self.agent_canvas_values
            .iter()
            .filter(|canvas| {
                self.agent_canvas_show_history
                    || !matches!(
                        value_string(canvas, "state").as_deref(),
                        Some("completed" | "orphaned" | "closed")
                    )
                    || value_bool(canvas, "pinned")
            })
            .cloned()
            .collect()
    }

    fn selected_agent_canvas(&self, values: &[Value]) -> Option<Value> {
        if let Some(id) = self.agent_canvas_selected_id.as_deref() {
            if let Some(canvas) = values
                .iter()
                .find(|canvas| value_string(canvas, "id").as_deref() == Some(id))
            {
                return Some(canvas.clone());
            }
        }
        values.first().cloned()
    }

    fn render_agent_canvas_list(
        &self,
        values: &[Value],
        selected: Option<&Value>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let mut list = div()
            .id("agent-canvas-list")
            .w(px(148.0))
            .flex_shrink_0()
            .min_h_0()
            .overflow_y_scrollbar()
            .p_1();
        for (index, canvas) in values.iter().enumerate() {
            let id = value_string(canvas, "id").unwrap_or_else(|| format!("canvas-{index}"));
            let title = value_string(canvas, "title").unwrap_or_else(|| "Agent Run".to_owned());
            let state = value_string(canvas, "state").unwrap_or_else(|| "waiting".to_owned());
            let is_selected =
                selected.is_some_and(|value| value_string(value, "id") == Some(id.clone()));
            let id_for_click = id.clone();
            list = list.child(
                div()
                    .id(SharedString::from(format!("agent-canvas-row-{id}")))
                    .flex()
                    .flex_col()
                    .gap_1()
                    .p_2()
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .when(is_selected, |row| row.bg(theme::accent_subtle()))
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.agent_canvas_selected_id = Some(id_for_click.clone());
                        cx.notify();
                    }))
                    .child(div().text_size(px(12.0)).text_ellipsis().child(title))
                    .child(
                        div()
                            .text_size(px(10.0))
                            .text_color(agent_canvas_state_color(&state))
                            .child(state),
                    ),
            );
        }
        list.into_any_element()
    }

    fn render_agent_canvas_details(&self, canvas: &Value, cx: &mut Context<Self>) -> AnyElement {
        let canvas_id = value_string(canvas, "id").unwrap_or_default();
        let title = value_string(canvas, "title").unwrap_or_else(|| "Agent Run".to_owned());
        let state = value_string(canvas, "state").unwrap_or_else(|| "waiting".to_owned());
        let pinned = value_bool(canvas, "pinned");
        let components = canvas
            .pointer("/document/components")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let mut body = div()
            .id("agent-canvas-details")
            .flex()
            .flex_col()
            .min_h_0()
            .flex_1()
            .overflow_y_scrollbar()
            .p_3()
            .child(
                div()
                    .flex()
                    .items_center()
                    .child(icon(AleraIcon::Agent, 18.0, theme::info()))
                    .child(
                        div()
                            .ml_2()
                            .flex_1()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(title),
                    )
                    .child(
                        div()
                            .text_color(agent_canvas_state_color(&state))
                            .child(state.clone()),
                    ),
            )
            .child(
                div()
                    .flex()
                    .gap_1()
                    .mt_2()
                    .child(
                        design_system::button(
                            "agent-canvas-pin",
                            if pinned { "Unpin" } else { "Pin" },
                            ButtonKind::Outlined,
                            self.agent_canvas_busy,
                        )
                        .on_click(cx.listener({
                            let canvas_id = canvas_id.clone();
                            move |this, _, _, cx| {
                                this.agent_canvas_action(
                                    "agentCanvas.pin",
                                    json!({"canvasId": canvas_id, "pinned": !pinned}),
                                    cx,
                                );
                            }
                        })),
                    )
                    .when(matches!(state.as_str(), "waiting" | "live"), |row| {
                        row.child(
                            design_system::button(
                                "agent-canvas-complete",
                                "Complete",
                                ButtonKind::Text,
                                self.agent_canvas_busy,
                            )
                            .on_click(cx.listener({
                                let canvas_id = canvas_id.clone();
                                move |this, _, _, cx| {
                                    this.agent_canvas_action(
                                        "agentCanvas.complete",
                                        json!({"canvasId": canvas_id}),
                                        cx,
                                    );
                                }
                            })),
                        )
                    })
                    .when(matches!(state.as_str(), "waiting" | "live"), |row| {
                        row.child(
                            design_system::button(
                                "agent-canvas-close",
                                "Close",
                                ButtonKind::Outlined,
                                self.agent_canvas_busy,
                            )
                            .on_click(cx.listener({
                                let canvas_id = canvas_id.clone();
                                move |this, _, _, cx| {
                                    this.agent_canvas_action(
                                        "agentCanvas.close",
                                        json!({"canvasId": canvas_id}),
                                        cx,
                                    );
                                }
                            })),
                        )
                    })
                    .when(!matches!(state.as_str(), "waiting" | "live"), |row| {
                        row.child(
                            design_system::button(
                                "agent-canvas-remove",
                                "Remove",
                                ButtonKind::Destructive,
                                self.agent_canvas_busy,
                            )
                            .on_click(cx.listener({
                                let canvas_id = canvas_id.clone();
                                move |this, _, _, cx| {
                                    this.agent_canvas_action(
                                        "agentCanvas.remove",
                                        json!({"canvasId": canvas_id}),
                                        cx,
                                    );
                                }
                            })),
                        )
                    }),
            );
        if components.is_empty() {
            body = body.child(self.agent_canvas_empty(
                "No Canvas Components",
                "This run has not published a visible document yet.",
            ));
        } else {
            for (index, component) in components.iter().enumerate() {
                body = body
                    .child(self.render_agent_canvas_component(&canvas_id, index, component, cx));
            }
        }
        body.into_any_element()
    }

    fn render_agent_canvas_component(
        &self,
        canvas_id: &str,
        index: usize,
        component: &Value,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let kind = value_string(component, "type")
            .or_else(|| value_string(component, "component"))
            .unwrap_or_else(|| "Notice".to_owned());
        let props = component.get("props").unwrap_or(component);
        let title = value_string(props, "title")
            .or_else(|| value_string(props, "label"))
            .unwrap_or_else(|| kind.clone());
        let text = value_string(props, "text")
            .or_else(|| value_string(props, "summary"))
            .or_else(|| value_string(props, "message"));
        let mut card = div()
            .id(SharedString::from(format!(
                "agent-canvas-component-{index}"
            )))
            .mt_2()
            .rounded_lg()
            .border_1()
            .border_color(if kind == "DecisionRequest" {
                theme::warning()
            } else {
                theme::border_subtle()
            })
            .bg(theme::surface_raised())
            .p_3()
            .child(div().font_weight(gpui::FontWeight::SEMIBOLD).child(title));
        if let Some(text) = text {
            card = card.child(div().mt_1().text_color(theme::text_muted()).child(text));
        }
        if kind == "TaskProgress" {
            let completed = value_number(props, "completed");
            let total = value_number(props, "total").max(1.0);
            let fraction = (completed / total).clamp(0.0, 1.0);
            card = card.child(
                div()
                    .mt_2()
                    .h(px(5.0))
                    .rounded_full()
                    .bg(theme::surface())
                    .child(
                        div()
                            .h_full()
                            .w(gpui::relative(fraction as f32))
                            .bg(theme::accent()),
                    ),
            );
        }
        if kind == "DecisionRequest" {
            let options = props
                .get("options")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let decision_id = value_string(props, "id");
            for (option_index, option) in options.into_iter().enumerate() {
                let label = option
                    .as_str()
                    .map(str::to_owned)
                    .or_else(|| value_string(&option, "label"))
                    .unwrap_or_else(|| format!("Option {}", option_index + 1));
                let decision_id = decision_id.clone();
                let canvas_id = canvas_id.to_owned();
                card = card.child(
                    design_system::button(
                        SharedString::from(format!("agent-canvas-decision-{index}-{option_index}")),
                        label.clone(),
                        ButtonKind::Outlined,
                        self.agent_canvas_busy,
                    )
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if let Some(decision_id) = decision_id.clone() {
                            this.agent_canvas_action(
                                "agentCanvas.decision.resolve",
                                json!({"decisionId": decision_id, "resolution": label}),
                                cx,
                            );
                        } else {
                            this.agent_canvas_action(
                                "agentCanvas.action",
                                json!({"canvasId": canvas_id, "action": {"kind": "resolveDecision", "resolution": label}}),
                                cx,
                            );
                        }
                    })),
                );
            }
        }
        if kind == "ActionGroup" {
            if let Some(actions) = props.get("actions").and_then(Value::as_array) {
                for (action_index, action) in actions.iter().enumerate() {
                    let action = action.clone();
                    let canvas_id = canvas_id.to_owned();
                    let label =
                        value_string(&action, "label").unwrap_or_else(|| "Action".to_owned());
                    card = card.child(
                        design_system::button(
                            SharedString::from(format!(
                                "agent-canvas-action-{index}-{action_index}"
                            )),
                            label,
                            ButtonKind::Outlined,
                            self.agent_canvas_busy,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.agent_canvas_action(
                                "agentCanvas.action",
                                json!({"canvasId": canvas_id, "action": action}),
                                cx,
                            );
                        })),
                    );
                }
            }
        }
        card.into_any_element()
    }

    fn agent_canvas_empty(&self, title: &str, message: &str) -> AnyElement {
        div()
            .flex()
            .flex_col()
            .flex_1()
            .items_center()
            .justify_center()
            .p_4()
            .text_center()
            .child(icon(AleraIcon::Agent, 24.0, theme::text_faint()))
            .child(
                div()
                    .mt_2()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(title.to_owned()),
            )
            .child(
                div()
                    .mt_1()
                    .text_size(crate::theme::body_size())
                    .text_color(theme::text_muted())
                    .child(message.to_owned()),
            )
            .into_any_element()
    }

    fn agent_canvas_action(&mut self, request_type: &str, payload: Value, cx: &mut Context<Self>) {
        if self.agent_canvas_busy {
            return;
        }
        self.agent_canvas_busy = true;
        let generation = self.agent_canvas_generation;
        let bridge = self.bridge.clone();
        let request_type = request_type.to_owned();
        cx.spawn(async move |this, cx| {
            let result = bridge.request(request_type, payload).await;
            let _ = this.update(cx, |this, cx| {
                if generation != this.agent_canvas_generation {
                    return;
                }
                this.agent_canvas_busy = false;
                if let Err(error) = result {
                    this.agent_canvas_error = Some(error.into());
                } else {
                    this.agent_canvas_error = None;
                    this.refresh_agent_canvas(cx);
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn value_bool(value: &Value, key: &str) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn value_number(value: &Value, key: &str) -> f64 {
    value.get(key).and_then(Value::as_f64).unwrap_or(0.0)
}

fn agent_canvas_state_color(state: &str) -> gpui::Rgba {
    match state {
        "live" => theme::success(),
        "waiting" => theme::warning(),
        "completed" => theme::info(),
        "orphaned" | "closed" => theme::text_faint(),
        _ => theme::text_muted(),
    }
}
