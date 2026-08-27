use gpui::{
    canvas, div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Bounds, Context,
    CursorStyle, DragMoveEvent, InteractiveElement as _, IntoElement, MouseButton, MouseDownEvent,
    MouseUpEvent, ParentElement as _, Pixels, Point, Render, Rgba, SharedString,
    StatefulInteractiveElement as _, Styled as _, Timer, Window,
};
use gpui_component::tooltip::Tooltip;
use serde_json::Value;
use std::time::Duration;

use super::{AleraApp, PaneDropTarget, TabDropTarget};
use crate::model::{WorkbenchDropZone, WorkbenchPaneGroup, WorkspaceTab};
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

#[derive(Clone, Debug)]
pub(super) struct TabDragData {
    source_group_id: String,
    tab_id: String,
    title: String,
    kind: String,
}

struct DraggedTabFeedback {
    title: String,
    kind: String,
}

impl Render for DraggedTabFeedback {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .items_center()
            .h(px(32.0))
            .max_w(px(tab_title_max_width(&self.kind) + 48.0))
            .px(px(6.0))
            .gap(px(4.0))
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .text_sm()
            .child(super::workbench::tab_kind_icon(&self.kind, theme::text()))
            .child(
                div()
                    .max_w(px(tab_title_max_width(&self.kind)))
                    .text_ellipsis()
                    .child(self.title.clone()),
            )
    }
}

impl AleraApp {
    pub(super) fn render_pane_group(
        &self,
        group: Option<&WorkbenchPaneGroup>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let tabs = group
            .map(|group| {
                group
                    .tab_ids
                    .iter()
                    .filter_map(|tab_id| self.snapshot.tabs.iter().find(|tab| &tab.id == tab_id))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let active_tab = self.active_tab_for_group(group, &tabs);
        let group_id = group.map(|group| group.id.clone()).unwrap_or_default();
        let tab_bar = self.render_group_tab_bar(&group_id, &tabs, active_tab, cx);
        let active =
            active_tab.is_some_and(|tab| self.selected_tab_id.as_deref() == Some(tab.id.as_str()));
        let content = self.render_group_content(active_tab, active, window, cx);
        let pane_drop_zone = self
            .pane_drop_target
            .as_ref()
            .filter(|target| target.group_id == group_id)
            .map(|target| target.zone);
        let pane_bounds_group_id = group_id.clone();
        let pane_bounds_app = cx.entity();
        let pane_drag_group_id = group_id.clone();

        div()
            .id(SharedString::from(format!("workbench-pane-{group_id}")))
            .relative()
            .flex()
            .flex_col()
            .flex_1()
            .size_full()
            .overflow_hidden()
            .border_1()
            .border_color(if active {
                theme::border()
            } else {
                theme::border_subtle()
            })
            .child(tab_bar)
            .child(content)
            .on_drag_move(
                cx.listener(move |this, event: &DragMoveEvent<TabDragData>, _, cx| {
                    let drag = event.drag(cx).clone();
                    this.set_pane_drop_target(
                        &drag,
                        pane_drag_group_id.clone(),
                        event.event.position,
                        event.bounds,
                        cx,
                    );
                }),
            )
            .on_drop(cx.listener(|this, drag: &TabDragData, _, cx| {
                this.drop_workspace_tab(drag, cx);
            }))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(|this, event: &MouseUpEvent, _, cx| {
                    // The native drag dispatcher can hit a child that does
                    // not own the drop listener (for example the preview
                    // overlay). The remembered drag identity lets the pane
                    // finish the same mutation from its mouse-up fallback.
                    this.drop_pointer_tab_at_position(event.position, cx);
                }),
            )
            .on_mouse_up_out(
                MouseButton::Left,
                cx.listener(|this, event: &MouseUpEvent, _, cx| {
                    this.drop_pointer_tab_at_position(event.position, cx);
                }),
            )
            .when_some(pane_drop_zone, |pane, zone| {
                // The preview is also the final hit-test target. Terminal
                // surfaces intentionally stop mouse propagation, so keeping
                // the drop listeners only on the pane would lose the release
                // when the pointer lands on the preview itself.
                pane.child(
                    pane_drop_overlay(zone)
                        .on_mouse_up(
                            MouseButton::Left,
                            cx.listener(|this, event: &MouseUpEvent, _, cx| {
                                this.drop_pointer_tab_at_position(event.position, cx);
                            }),
                        )
                        .on_drop(cx.listener(|this, drag: &TabDragData, _, cx| {
                            this.drop_workspace_tab(drag, cx);
                        })),
                )
            })
            .child(
                canvas(
                    move |bounds, _, cx| {
                        pane_bounds_app.update(cx, |this, _| {
                            this.pane_bounds
                                .insert(pane_bounds_group_id.clone(), bounds);
                        });
                    },
                    |_, _, _, _| {},
                )
                .absolute()
                .top_0()
                .right_0()
                .bottom_0()
                .left_0(),
            )
            .into_any_element()
    }

    fn active_tab_for_group<'a>(
        &'a self,
        group: Option<&WorkbenchPaneGroup>,
        tabs: &[&'a WorkspaceTab],
    ) -> Option<&'a WorkspaceTab> {
        self.selected_tab_id
            .as_deref()
            .filter(|selected| {
                group.is_some_and(|group| group.tab_ids.iter().any(|tab_id| tab_id == *selected))
            })
            .and_then(|tab_id| self.snapshot.tabs.iter().find(|tab| tab.id == tab_id))
            .or_else(|| {
                group
                    .and_then(|group| group.active_tab_id.as_deref())
                    .and_then(|tab_id| self.snapshot.tabs.iter().find(|tab| tab.id == tab_id))
            })
            .or_else(|| tabs.first().copied())
    }

    fn render_group_tab_bar(
        &self,
        group_id: &str,
        tabs: &[&WorkspaceTab],
        active_tab: Option<&WorkspaceTab>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let append_group_id = group_id.to_string();
        let bounds_group_id = group_id.to_string();
        let bounds_app = cx.entity();
        let append_index = tabs.len();
        let drag_active = self.tab_pointer_drag.is_some() || cx.has_active_drag();
        div()
            .relative()
            .flex()
            .items_center()
            .h(theme::tab_bar_height())
            .border_b_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface())
            .pl_2()
            .py(px(6.0))
            .child(
                div()
                    .id(SharedString::from(format!("tab-scroll-{group_id}")))
                    .flex()
                    .min_w_0()
                    .flex_shrink()
                    .overflow_x_scroll()
                    .children(tabs.iter().enumerate().map(|(index, tab)| {
                        self.render_tab_chip(group_id, tab, index, active_tab, cx)
                    }))
                    .child(
                        div()
                            .id(SharedString::from(format!("tab-drop-append-{group_id}")))
                            .relative()
                            .flex_shrink_0()
                            .w(px(8.0))
                            .h(px(32.0))
                            .on_drag_move(cx.listener(
                                move |this, event: &DragMoveEvent<TabDragData>, _, cx| {
                                    let drag = event.drag(cx).clone();
                                    this.set_tab_drop_target(
                                        &drag,
                                        append_group_id.clone(),
                                        append_index,
                                        cx,
                                    );
                                },
                            ))
                            .on_drop(cx.listener(|this, drag: &TabDragData, _, cx| {
                                this.drop_workspace_tab(drag, cx);
                            }))
                            .on_mouse_up(
                                MouseButton::Left,
                                cx.listener(|this, event: &MouseUpEvent, _, cx| {
                                    this.drop_pointer_tab_at_position(event.position, cx);
                                }),
                            )
                            .when(
                                drag_active
                                    && self.tab_drop_target.as_ref().is_some_and(|target| {
                                        target.group_id == group_id
                                            && target.gap_index == append_index
                                    }),
                                |target| target.child(tab_insertion_indicator(false)),
                            ),
                    ),
            )
            .child(self.render_new_tab_button(group_id, cx))
            .child(div().flex_1())
            .child(self.render_pane_menu_button(group_id, cx))
            .child(div().w(px(4.0)))
            .child(
                canvas(
                    move |bounds, _, cx| {
                        bounds_app.update(cx, |this, _| {
                            this.tab_bar_bounds.insert(bounds_group_id.clone(), bounds);
                        });
                    },
                    |_, _, _, _| {},
                )
                .absolute()
                .top_0()
                .right_0()
                .bottom_0()
                .left_0(),
            )
            .into_any_element()
    }

    fn render_tab_chip(
        &self,
        group_id: &str,
        tab: &WorkspaceTab,
        index: usize,
        active_tab: Option<&WorkspaceTab>,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let selected = active_tab.is_some_and(|active| active.id == tab.id);
        let tab_id = tab.id.clone();
        let pointer_group_id = group_id.to_string();
        let pointer_tab_id = tab.id.clone();
        let bounds_group_id = group_id.to_string();
        let bounds_tab_id = tab.id.clone();
        let bounds_app = cx.entity();
        let close_tab_id = tab.id.clone();
        let menu_group_id = group_id.to_string();
        let menu_tab_id = tab.id.clone();
        let drop_group_id = group_id.to_string();
        let drag_data = TabDragData {
            source_group_id: group_id.to_string(),
            tab_id: tab.id.clone(),
            title: tab.title.clone(),
            kind: tab.kind.clone(),
        };
        let pointer_dragged = self
            .tab_pointer_drag
            .as_ref()
            .is_some_and(|(source, dragged)| source == group_id && dragged == &tab.id);
        let drag_active = pointer_dragged || cx.has_active_drag();
        let show_leading = self.tab_drop_target.as_ref().is_some_and(|target| {
            drag_active && target.group_id == group_id && target.gap_index == index
        });
        let show_trailing = self.tab_drop_target.as_ref().is_some_and(|target| {
            drag_active && target.group_id == group_id && target.gap_index == index + 1
        });
        // Flutter always reserves this six-pixel slot. It is empty when a
        // tab has no agent run, but keeping it in the layout preserves the
        // same chip rhythm and lets the live state appear without shifting
        // the title when a hook event arrives.
        let tab_status = self.tab_status_visual(tab);
        let status_dot = div()
            .id(SharedString::from(format!(
                "layout-status-{group_id}-{}",
                tab.id
            )))
            .w(px(6.0))
            .h(px(6.0))
            .flex_shrink_0()
            .rounded_full()
            .when_some(tab_status, |dot, status| {
                dot.bg(status.color).tooltip(move |_, cx| {
                    let tooltip = status.tooltip.clone();
                    cx.new(move |_| Tooltip::new(tooltip)).into()
                })
            });
        div()
            .id(SharedString::from(format!(
                "layout-tab-{group_id}-{}",
                tab.id
            )))
            .relative()
            .flex()
            .flex_shrink_0()
            .items_center()
            .h(px(32.0))
            .mr_2()
            .px(px(6.0))
            .gap(px(4.0))
            .rounded_md()
            .border_1()
            .border_color(if selected {
                theme::border()
            } else {
                theme::border_subtle()
            })
            .bg(if selected {
                theme::surface_raised()
            } else {
                theme::surface()
            })
            .cursor(CursorStyle::PointingHand)
            .text_sm()
            .text_color(if selected {
                theme::text()
            } else {
                theme::text_muted()
            })
            .hover(|style| style.bg(theme::surface_raised()))
            .when(pointer_dragged, |style| {
                style.opacity(0.45).border_color(theme::accent())
            })
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.begin_pointer_tab_drag(
                        pointer_group_id.clone(),
                        pointer_tab_id.clone(),
                        cx,
                    );
                    this.activate_workspace_tab(tab_id.clone(), cx);
                }),
            )
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(|this, event: &MouseUpEvent, _, cx| {
                    this.drop_pointer_tab_at_position(event.position, cx);
                }),
            )
            .on_mouse_down(
                MouseButton::Right,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    cx.stop_propagation();
                    this.open_tab_context_menu(
                        menu_group_id.clone(),
                        menu_tab_id.clone(),
                        event.position,
                        cx,
                    );
                }),
            )
            .on_drag(drag_data, |drag, _, _, cx| {
                cx.new(|_| DraggedTabFeedback {
                    title: drag.title.clone(),
                    kind: drag.kind.clone(),
                })
            })
            .drag_over::<TabDragData>(|style, _, _, _| style.bg(theme::surface_selected()))
            .on_drag_move(
                cx.listener(move |this, event: &DragMoveEvent<TabDragData>, _, cx| {
                    let gap = if event.event.position.x < event.bounds.center().x {
                        index
                    } else {
                        index + 1
                    };
                    let drag = event.drag(cx).clone();
                    this.set_tab_drop_target(&drag, drop_group_id.clone(), gap, cx);
                }),
            )
            .on_drop(cx.listener(|this, drag: &TabDragData, _, cx| {
                this.drop_workspace_tab(drag, cx);
            }))
            .when(show_leading, |chip| {
                chip.child(tab_insertion_indicator(false))
            })
            .when(show_trailing, |chip| {
                chip.child(tab_insertion_indicator(true))
            })
            .child(super::workbench::tab_kind_icon(
                &tab.kind,
                if selected {
                    theme::text()
                } else {
                    theme::text_muted()
                },
            ))
            .child(status_dot)
            .child(
                div()
                    .max_w(px(tab_title_max_width(&tab.kind)))
                    .text_ellipsis()
                    .child(tab.title.clone()),
            )
            .child(
                div()
                    .id(SharedString::from(format!(
                        "layout-close-tab-{group_id}-{}",
                        tab.id
                    )))
                    .flex()
                    .items_center()
                    .justify_center()
                    .p(px(2.0))
                    .rounded_sm()
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.clear_pointer_tab_drag_state(cx);
                            this.request_close_tab(close_tab_id.clone(), cx);
                        }),
                    )
                    .child(icon(AleraIcon::Close, 12.0, theme::text_muted())),
            )
            .child(
                canvas(
                    move |bounds, _, cx| {
                        bounds_app.update(cx, |this, _| {
                            this.tab_chip_bounds
                                .insert((bounds_group_id.clone(), bounds_tab_id.clone()), bounds);
                        });
                    },
                    |_, _, _, _| {},
                )
                .absolute()
                .top_0()
                .right_0()
                .bottom_0()
                .left_0(),
            )
            .into_any_element()
    }

    fn tab_status_visual(&self, tab: &WorkspaceTab) -> Option<TabStatusVisual> {
        let entry = self.matching_presence_for_tab(tab)?;
        let state = entry.get("agentState").and_then(Value::as_str)?;
        let session_id = tab
            .payload
            .get("terminalSessionId")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(tab.id.as_str());
        let state_started_at = entry
            .get("stateStartedAt")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let completion_acknowledged = state == "done"
            && self
                .tab_completion_acknowledged
                .get(session_id)
                .is_some_and(|value| value == state_started_at);
        let agent = entry
            .get("agentType")
            .and_then(Value::as_str)
            .map(tab_agent_display_name)
            .unwrap_or("Agent");
        let state_label = tab_agent_state_label_for_entry(
            state,
            entry
                .get("interrupted")
                .and_then(Value::as_bool)
                .unwrap_or(false),
        );
        let mut tooltip = format!("{agent} {state_label}");
        if state == "done" && !completion_acknowledged {
            tooltip.push_str(" (unacked)");
        }
        Some(TabStatusVisual {
            color: if state == "done" && !completion_acknowledged {
                theme::warning()
            } else {
                tab_agent_state_color(state)
            },
            tooltip,
        })
    }

    fn set_tab_drop_target(
        &mut self,
        drag: &TabDragData,
        group_id: String,
        gap_index: usize,
        cx: &mut Context<Self>,
    ) {
        // A native drag can deliver one final move after pointer-up. Once the
        // optimistic layout mutation starts, that late event must not repaint
        // a preview over the newly committed workbench.
        if self.tab_mutation_busy {
            self.clear_pointer_tab_drag_state(cx);
            return;
        }
        let Some(layout) = self.snapshot.layout.as_ref() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let Some(group) = layout.groups.get(&group_id) else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let Some(insert_index) = resolve_tab_drop_index(
            &group.tab_ids,
            &drag.source_group_id,
            &group_id,
            &drag.tab_id,
            gap_index,
        ) else {
            self.pane_drop_target = None;
            if self.tab_drop_target.take().is_some() {
                cx.notify();
            }
            return;
        };
        let next = TabDropTarget {
            group_id,
            gap_index,
            insert_index,
        };
        if self.tab_drop_target.as_ref() != Some(&next) {
            // Native GPUI drags do not necessarily pass through the global
            // mouse observer's initial button-down event. Remember the drag
            // here as well so the observer can complete the drop on platforms
            // where the child drop target is not the final hit-test node.
            self.tab_pointer_drag = Some((drag.source_group_id.clone(), drag.tab_id.clone()));
            self.pane_drop_target = None;
            self.tab_drop_target = Some(next);
            cx.notify();
        }
    }

    fn set_pane_drop_target(
        &mut self,
        drag: &TabDragData,
        group_id: String,
        position: Point<gpui::Pixels>,
        bounds: Bounds<Pixels>,
        cx: &mut Context<Self>,
    ) {
        // See `set_tab_drop_target`: GPUI may report a trailing drag move
        // after the drop callback. Do not allow it to resurrect the overlay
        // while the layout request is in flight.
        if self.tab_mutation_busy {
            self.clear_pointer_tab_drag_state(cx);
            return;
        }
        let Some(layout) = self.snapshot.layout.as_ref() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        // The tab strip has its own insertion targets. GPUI bubbles drag
        // movement through ancestors, so the pane target must not replace a
        // tab-gap preview while the pointer is over that strip.
        if self
            .tab_bar_bounds
            .get(&group_id)
            .is_some_and(|tab_bar| tab_bar.contains(&position))
        {
            if self.pane_drop_target.take().is_some() {
                cx.notify();
            }
            return;
        }
        let Some(group) = layout.groups.get(&group_id) else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let zone = resolve_pane_drop_zone(bounds, position);
        if !is_pane_drop_action_enabled(&drag.source_group_id, &group_id, group.tab_ids.len(), zone)
        {
            let changed =
                self.pane_drop_target.take().is_some() || self.tab_drop_target.take().is_some();
            if changed {
                cx.notify();
            }
            return;
        }
        let next = PaneDropTarget { group_id, zone };
        if self.pane_drop_target.as_ref() != Some(&next) {
            // See the corresponding note in `set_tab_drop_target`: retain
            // enough drag identity for the window-level mouse-up fallback.
            self.tab_pointer_drag = Some((drag.source_group_id.clone(), drag.tab_id.clone()));
            self.tab_drop_target = None;
            self.pane_drop_target = Some(next);
            cx.notify();
        }
    }

    fn drop_workspace_tab(&mut self, drag: &TabDragData, cx: &mut Context<Self>) {
        self.tab_pointer_drag = None;
        if let Some(target) = self.tab_drop_target.take() {
            self.pane_drop_target = None;
            self.move_workspace_tab(
                drag.tab_id.clone(),
                target.group_id,
                target.insert_index,
                cx,
            );
        } else if let Some(target) = self.pane_drop_target.take() {
            self.move_workspace_tab_to_drop(
                drag.tab_id.clone(),
                target.group_id,
                target.zone,
                None,
                cx,
            );
        } else {
            // A native drop can arrive without a preview target when the pointer
            // leaves the workbench between the last drag update and release.
            // Never leave a stale directional overlay behind in that case.
            self.clear_pointer_tab_drag_state(cx);
        }
    }

    fn clear_pointer_tab_drag_state(&mut self, cx: &mut Context<Self>) {
        let changed = self.tab_pointer_drag.take().is_some()
            || self.tab_drop_target.take().is_some()
            || self.pane_drop_target.take().is_some();
        if changed {
            cx.notify();
        }
    }

    fn begin_pointer_tab_drag(
        &mut self,
        source_group_id: String,
        tab_id: String,
        cx: &mut Context<Self>,
    ) {
        if self.tab_mutation_busy {
            return;
        }
        self.tab_pointer_drag = Some((source_group_id, tab_id));
        self.tab_drop_target = None;
        self.pane_drop_target = None;
        self.tab_pointer_drag_generation = self.tab_pointer_drag_generation.wrapping_add(1);
        let generation = self.tab_pointer_drag_generation;
        cx.spawn(async move |this, cx| {
            Timer::after(Duration::from_secs(10)).await;
            let _ = this.update(cx, |this, cx| {
                if this.tab_pointer_drag_generation == generation {
                    this.tab_pointer_drag = None;
                    this.tab_drop_target = None;
                    this.pane_drop_target = None;
                    cx.notify();
                }
            });
        })
        .detach();
    }

    pub(super) fn begin_pointer_tab_drag_at_position(
        &mut self,
        position: Point<gpui::Pixels>,
        cx: &mut Context<Self>,
    ) {
        let Some((group_id, tab_id)) = self
            .tab_chip_bounds
            .iter()
            .find(|((group_id, tab_id), bounds)| {
                self.snapshot.layout.as_ref().is_some_and(|layout| {
                    layout
                        .groups
                        .get(group_id)
                        .is_some_and(|group| group.tab_ids.contains(tab_id))
                }) && bounds.contains(&position)
            })
            .map(|((group_id, tab_id), _)| (group_id.clone(), tab_id.clone()))
        else {
            return;
        };
        self.begin_pointer_tab_drag(group_id, tab_id.clone(), cx);
        self.activate_workspace_tab(tab_id, cx);
    }

    fn drop_pointer_tab_at_gap(
        &mut self,
        target_group_id: String,
        gap_index: usize,
        cx: &mut Context<Self>,
    ) {
        let Some((source_group_id, tab_id)) = self.tab_pointer_drag.take() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        self.pane_drop_target = None;
        let Some(group) = self
            .snapshot
            .layout
            .as_ref()
            .and_then(|layout| layout.groups.get(&target_group_id))
        else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let Some(insert_index) = resolve_tab_drop_index(
            &group.tab_ids,
            &source_group_id,
            &target_group_id,
            &tab_id,
            gap_index,
        ) else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        // Consume the preview before starting the async persistence request.
        // If another tab mutation is already busy, the mutation helper is
        // allowed to reject the request; the visual preview must still end on
        // pointer-up instead of remaining painted indefinitely.
        self.clear_pointer_tab_drag_state(cx);
        self.move_workspace_tab(tab_id, target_group_id, insert_index, cx);
    }

    fn drop_pointer_tab_at_pane(
        &mut self,
        target_group_id: String,
        position: Point<gpui::Pixels>,
        bounds: Bounds<Pixels>,
        cx: &mut Context<Self>,
    ) {
        let Some((source_group_id, tab_id)) = self.tab_pointer_drag.take() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let Some(group) = self
            .snapshot
            .layout
            .as_ref()
            .and_then(|layout| layout.groups.get(&target_group_id))
        else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let zone = resolve_pane_drop_zone(bounds, position);
        if !is_pane_drop_action_enabled(
            &source_group_id,
            &target_group_id,
            group.tab_ids.len(),
            zone,
        ) {
            self.clear_pointer_tab_drag_state(cx);
            return;
        }
        // See the center-drop path above: the preview lifecycle ends with the
        // pointer gesture, independently of whether persistence is accepted.
        self.clear_pointer_tab_drag_state(cx);
        self.move_workspace_tab_to_drop(tab_id, target_group_id, zone, None, cx);
    }

    pub(super) fn update_pointer_tab_drag_at_position(
        &mut self,
        position: Point<gpui::Pixels>,
        cx: &mut Context<Self>,
    ) {
        let Some((source_group_id, tab_id)) = self.tab_pointer_drag.clone() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let Some(tab) = self.snapshot.tabs.iter().find(|tab| tab.id == tab_id) else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        let drag = TabDragData {
            source_group_id,
            tab_id,
            title: tab.title.clone(),
            kind: tab.kind.clone(),
        };
        let Some(layout) = self.snapshot.layout.as_ref() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        if let Some(target_group_id) = self
            .tab_bar_bounds
            .iter()
            .find(|(group_id, bounds)| {
                layout.groups.contains_key(*group_id) && bounds.contains(&position)
            })
            .map(|(group_id, _)| group_id.clone())
        {
            let Some(group) = layout.groups.get(&target_group_id) else {
                self.clear_pointer_tab_drag_state(cx);
                return;
            };
            let gap_index = group
                .tab_ids
                .iter()
                .enumerate()
                .find_map(|(index, tab_id)| {
                    let bounds = self
                        .tab_chip_bounds
                        .get(&(target_group_id.clone(), tab_id.clone()))?;
                    bounds
                        .contains(&position)
                        .then_some(if position.x < bounds.center().x {
                            index
                        } else {
                            index + 1
                        })
                })
                .unwrap_or(group.tab_ids.len());
            self.set_tab_drop_target(&drag, target_group_id, gap_index, cx);
            return;
        }
        if let Some((target_group_id, bounds)) = self
            .pane_bounds
            .iter()
            .find(|(group_id, bounds)| {
                layout.groups.contains_key(*group_id) && bounds.contains(&position)
            })
            .map(|(group_id, bounds)| (group_id.clone(), *bounds))
        {
            self.set_pane_drop_target(&drag, target_group_id, position, bounds, cx);
            return;
        }
        if self.tab_drop_target.take().is_some() || self.pane_drop_target.take().is_some() {
            cx.notify();
        }
    }

    pub(super) fn drop_pointer_tab_at_position(
        &mut self,
        position: Point<gpui::Pixels>,
        cx: &mut Context<Self>,
    ) {
        if self.tab_pointer_drag.is_none() {
            self.clear_pointer_tab_drag_state(cx);
            return;
        }
        let Some(layout) = self.snapshot.layout.as_ref() else {
            self.clear_pointer_tab_drag_state(cx);
            return;
        };
        if let Some(target_group_id) = self
            .tab_bar_bounds
            .iter()
            .find(|(group_id, bounds)| {
                layout.groups.contains_key(*group_id) && bounds.contains(&position)
            })
            .map(|(group_id, _)| group_id.clone())
        {
            let Some(group) = layout.groups.get(&target_group_id) else {
                self.clear_pointer_tab_drag_state(cx);
                return;
            };
            let gap_index = group
                .tab_ids
                .iter()
                .enumerate()
                .find_map(|(index, tab_id)| {
                    let bounds = self
                        .tab_chip_bounds
                        .get(&(target_group_id.clone(), tab_id.clone()))?;
                    bounds
                        .contains(&position)
                        .then_some(if position.x < bounds.center().x {
                            index
                        } else {
                            index + 1
                        })
                })
                .unwrap_or(group.tab_ids.len());
            self.drop_pointer_tab_at_gap(target_group_id, gap_index, cx);
            return;
        }
        if let Some((target_group_id, bounds)) = self
            .pane_bounds
            .iter()
            .find(|(group_id, bounds)| {
                layout.groups.contains_key(*group_id) && bounds.contains(&position)
            })
            .map(|(group_id, bounds)| (group_id.clone(), *bounds))
        {
            self.drop_pointer_tab_at_pane(target_group_id, position, bounds, cx);
        } else {
            self.clear_pointer_tab_drag_state(cx);
        }
    }
}

#[derive(Clone)]
struct TabStatusVisual {
    color: Rgba,
    tooltip: String,
}

fn tab_agent_state_color(state: &str) -> Rgba {
    match state {
        "waiting" => theme::warning(),
        "blocked" => theme::danger(),
        "done" => theme::success(),
        _ => theme::info(),
    }
}

fn tab_agent_state_label(state: &str) -> &'static str {
    match state {
        "waiting" => "waiting",
        "blocked" => "blocked",
        "done" => "done",
        _ => "working",
    }
}

fn tab_agent_state_label_for_entry(state: &str, interrupted: bool) -> &'static str {
    if interrupted {
        "interrupted"
    } else {
        tab_agent_state_label(state)
    }
}

fn tab_agent_display_name(agent: &str) -> &'static str {
    match agent {
        "claude" => "Claude Code",
        "copilot" => "GitHub Copilot",
        "cursor" => "Cursor",
        "agy" | "antigravity" => "Antigravity",
        "opencode" => "OpenCode",
        "pi" => "Pi",
        "amp" => "Amp",
        "grok" => "Grok Build",
        "kimi" => "Kimi",
        "minimax" | "miniMax" => "MiniMax",
        "zai" => "Z.ai",
        _ => "Codex",
    }
}

fn resolve_pane_drop_zone(bounds: Bounds<Pixels>, position: Point<Pixels>) -> WorkbenchDropZone {
    let width = bounds.size.width / px(1.0);
    let height = bounds.size.height / px(1.0);
    if width <= 0.0 || height <= 0.0 {
        return WorkbenchDropZone::Center;
    }
    let local_x = ((position.x - bounds.origin.x) / px(1.0)).clamp(0.0, width);
    let local_y = ((position.y - bounds.origin.y) / px(1.0)).clamp(0.0, height);
    let center_width = width.min((width * 0.36).max(96.0));
    let center_height = height.min((height * 0.36).max(96.0));
    let center_left = (width - center_width) / 2.0;
    let center_top = (height - center_height) / 2.0;
    let center_right = center_left + center_width;
    let center_bottom = center_top + center_height;
    if local_x >= center_left
        && local_x <= center_right
        && local_y >= center_top
        && local_y <= center_bottom
    {
        return WorkbenchDropZone::Center;
    }
    let horizontal_overflow = if local_x < center_left {
        center_left - local_x
    } else {
        (local_x - center_right).max(0.0)
    };
    let vertical_overflow = if local_y < center_top {
        center_top - local_y
    } else {
        (local_y - center_bottom).max(0.0)
    };
    if horizontal_overflow >= vertical_overflow {
        if local_x < width / 2.0 {
            WorkbenchDropZone::Left
        } else {
            WorkbenchDropZone::Right
        }
    } else if local_y < height / 2.0 {
        WorkbenchDropZone::Up
    } else {
        WorkbenchDropZone::Down
    }
}

fn is_pane_drop_action_enabled(
    source_group_id: &str,
    target_group_id: &str,
    target_tab_count: usize,
    zone: WorkbenchDropZone,
) -> bool {
    source_group_id != target_group_id
        || (target_tab_count > 1 && zone != WorkbenchDropZone::Center)
}

fn pane_drop_overlay(zone: WorkbenchDropZone) -> gpui::Div {
    let mut overlay = div()
        .absolute()
        .rounded_lg()
        .border_1()
        .border_color(theme::accent())
        .bg(theme::accent_subtle());
    match zone {
        WorkbenchDropZone::Center => {
            overlay = overlay
                .left(gpui::relative(0.32))
                .right(gpui::relative(0.32))
                .top(gpui::relative(0.32))
                .bottom(gpui::relative(0.32));
        }
        WorkbenchDropZone::Left => {
            overlay = overlay.left_0().top_0().bottom_0().w(gpui::relative(0.5));
        }
        WorkbenchDropZone::Right => {
            overlay = overlay.right_0().top_0().bottom_0().w(gpui::relative(0.5));
        }
        WorkbenchDropZone::Up => {
            overlay = overlay.left_0().right_0().top_0().h(gpui::relative(0.5));
        }
        WorkbenchDropZone::Down => {
            overlay = overlay.left_0().right_0().bottom_0().h(gpui::relative(0.5));
        }
    }
    overlay
}

fn tab_insertion_indicator(trailing: bool) -> gpui::Div {
    div()
        .absolute()
        .top_0()
        .bottom_0()
        .w(px(2.0))
        .rounded_full()
        .bg(theme::accent())
        .when(trailing, |indicator| indicator.right(px(-5.0)))
        .when(!trailing, |indicator| indicator.left(px(-5.0)))
}

fn tab_title_max_width(kind: &str) -> f32 {
    match kind {
        "editor" | "markdownViewer" | "pdf" | "gitDiff" => 180.0,
        "mobileEmulator" => 132.0,
        _ => 92.0,
    }
}

fn resolve_tab_drop_index(
    tab_ids: &[String],
    source_group_id: &str,
    target_group_id: &str,
    dragged_tab_id: &str,
    gap_index: usize,
) -> Option<usize> {
    let clamped = gap_index.min(tab_ids.len());
    if source_group_id != target_group_id {
        return Some(clamped);
    }
    let Some(source_index) = tab_ids.iter().position(|tab_id| tab_id == dragged_tab_id) else {
        return Some(clamped);
    };
    let adjusted = if clamped > source_index {
        clamped - 1
    } else {
        clamped
    };
    (adjusted != source_index).then_some(adjusted)
}

#[cfg(test)]
mod tests {
    use gpui::{px, Bounds, Point, Size};

    use super::{
        is_pane_drop_action_enabled, resolve_pane_drop_zone, resolve_tab_drop_index,
        tab_agent_display_name, tab_agent_state_label, tab_agent_state_label_for_entry,
    };
    use crate::model::WorkbenchDropZone;

    #[test]
    fn drop_index_matches_flutter_gap_semantics() {
        let tabs = vec!["a".to_string(), "b".to_string(), "c".to_string()];
        assert_eq!(resolve_tab_drop_index(&tabs, "g", "g", "a", 3), Some(2));
        assert_eq!(resolve_tab_drop_index(&tabs, "g", "g", "b", 1), None);
        assert_eq!(resolve_tab_drop_index(&tabs, "g", "other", "b", 1), Some(1));
    }

    #[test]
    fn pane_drop_zones_match_flutter_geometry() {
        let bounds = Bounds::new(
            Point::new(px(10.0), px(20.0)),
            Size::new(px(300.0), px(240.0)),
        );
        assert_eq!(
            resolve_pane_drop_zone(bounds, Point::new(px(160.0), px(140.0))),
            WorkbenchDropZone::Center
        );
        assert_eq!(
            resolve_pane_drop_zone(bounds, Point::new(px(90.0), px(140.0))),
            WorkbenchDropZone::Left
        );
        assert_eq!(
            resolve_pane_drop_zone(bounds, Point::new(px(230.0), px(140.0))),
            WorkbenchDropZone::Right
        );
        assert_eq!(
            resolve_pane_drop_zone(bounds, Point::new(px(160.0), px(84.0))),
            WorkbenchDropZone::Up
        );
        assert_eq!(
            resolve_pane_drop_zone(bounds, Point::new(px(160.0), px(196.0))),
            WorkbenchDropZone::Down
        );
    }

    #[test]
    fn same_group_pane_drop_guards_match_flutter() {
        assert!(!is_pane_drop_action_enabled(
            "group-a",
            "group-a",
            1,
            WorkbenchDropZone::Right
        ));
        assert!(!is_pane_drop_action_enabled(
            "group-a",
            "group-a",
            2,
            WorkbenchDropZone::Center
        ));
        assert!(is_pane_drop_action_enabled(
            "group-a",
            "group-a",
            2,
            WorkbenchDropZone::Right
        ));
        assert!(is_pane_drop_action_enabled(
            "group-a",
            "group-b",
            1,
            WorkbenchDropZone::Center
        ));
    }

    #[test]
    fn tab_agent_labels_match_flutter_tooltips() {
        assert_eq!(tab_agent_display_name("claude"), "Claude Code");
        assert_eq!(tab_agent_display_name("miniMax"), "MiniMax");
        assert_eq!(tab_agent_display_name("unknown"), "Codex");
        assert_eq!(tab_agent_state_label("waiting"), "waiting");
        assert_eq!(tab_agent_state_label("blocked"), "blocked");
        assert_eq!(tab_agent_state_label("done"), "done");
        assert_eq!(tab_agent_state_label("working"), "working");
        assert_eq!(
            tab_agent_state_label_for_entry("working", true),
            "interrupted"
        );
        assert_eq!(
            tab_agent_state_label_for_entry("waiting", true),
            "interrupted"
        );
    }
}
