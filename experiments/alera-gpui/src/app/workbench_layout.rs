use std::time::Duration;

use gpui::{
    div, px, AnyElement, AppContext as _, Context, CursorStyle, DragMoveEvent, Empty,
    InteractiveElement as _, IntoElement as _, MouseButton, MouseDownEvent, MouseMoveEvent,
    MouseUpEvent, ParentElement as _, SharedString, StatefulInteractiveElement as _, Styled as _,
    Timer, Window,
};

use super::{AleraApp, PanelResizeState, PanelResizeTarget, ResizeDrag, SplitResizeState};
use crate::model::{WorkbenchLayout, WorkbenchLayoutNode, WorkbenchSplitAxis, WorkspaceTab};
use crate::theme;

impl AleraApp {
    pub(super) fn render_persisted_workbench_layout(
        &self,
        layout: &WorkbenchLayout,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        self.render_layout_node(&layout.root, layout, &[], window, cx)
    }

    fn render_layout_node(
        &self,
        node: &WorkbenchLayoutNode,
        layout: &WorkbenchLayout,
        path: &[usize],
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        match node {
            WorkbenchLayoutNode::Leaf { group_id } => {
                let group = layout.groups.get(group_id);
                self.render_pane_group(group, window, cx)
            }
            WorkbenchLayoutNode::Split {
                axis,
                first,
                second,
                ratio,
            } => {
                let mut first_path = path.to_vec();
                first_path.push(0);
                let mut second_path = path.to_vec();
                second_path.push(1);
                let first_view = self.render_layout_node(first, layout, &first_path, window, cx);
                let second_view = self.render_layout_node(second, layout, &second_path, window, cx);
                let resize_ratio = *ratio;
                let ratio = *ratio as f32;
                let resize_path = path.to_vec();
                let resize_axis = *axis;
                let resize_handle = div()
                    .id(SharedString::from(format!("split-handle-{path:?}")))
                    .bg(theme::border_subtle())
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                            this.split_resize = Some(SplitResizeState {
                                path: resize_path.clone(),
                                axis: resize_axis,
                                start: event.position,
                                initial_ratio: resize_ratio,
                            });
                            cx.notify();
                            cx.stop_propagation();
                        }),
                    )
                    .on_drag(ResizeDrag, |_, _, _, cx| cx.new(|_| Empty))
                    .on_drag_move(cx.listener(
                        |this, event: &DragMoveEvent<ResizeDrag>, window, cx| {
                            this.update_split_resize(&event.event, window, cx);
                            this.schedule_resize_persistence(cx);
                        },
                    ))
                    .on_mouse_up(MouseButton::Left, cx.listener(Self::finish_split_resize))
                    .on_mouse_up_out(MouseButton::Left, cx.listener(Self::finish_split_resize));
                match axis {
                    WorkbenchSplitAxis::Horizontal => div()
                        .flex()
                        .min_w_0()
                        .size_full()
                        .overflow_hidden()
                        .child(
                            div()
                                .flex_basis(gpui::relative(ratio))
                                .flex_shrink()
                                .h_full()
                                .overflow_hidden()
                                .child(first_view),
                        )
                        .child(
                            resize_handle
                                .flex_shrink_0()
                                .w(px(4.0))
                                .h_full()
                                .cursor(CursorStyle::ResizeLeftRight),
                        )
                        .child(
                            div()
                                .flex_basis(gpui::relative(1.0 - ratio))
                                .flex_shrink()
                                .h_full()
                                .overflow_hidden()
                                .child(second_view),
                        )
                        .into_any_element(),
                    WorkbenchSplitAxis::Vertical => div()
                        .flex()
                        .flex_col()
                        .min_h_0()
                        .size_full()
                        .overflow_hidden()
                        .child(
                            div()
                                .flex_basis(gpui::relative(ratio))
                                .flex_shrink()
                                .w_full()
                                .overflow_hidden()
                                .child(first_view),
                        )
                        .child(
                            resize_handle
                                .flex_shrink_0()
                                .h(px(4.0))
                                .w_full()
                                .cursor(CursorStyle::ResizeUpDown),
                        )
                        .child(
                            div()
                                .flex_basis(gpui::relative(1.0 - ratio))
                                .flex_shrink()
                                .w_full()
                                .overflow_hidden()
                                .child(second_view),
                        )
                        .into_any_element(),
                }
            }
        }
    }

    pub(super) fn update_split_resize(
        &mut self,
        event: &MouseMoveEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(state) = self.split_resize.as_ref() else {
            return;
        };
        if !event.dragging() {
            return;
        }
        let viewport = window.viewport_size();
        let delta = match state.axis {
            WorkbenchSplitAxis::Horizontal => (event.position.x - state.start.x) / viewport.width,
            WorkbenchSplitAxis::Vertical => (event.position.y - state.start.y) / viewport.height,
        };
        if let Some(layout) = self.snapshot.layout.as_mut() {
            layout.update_split_ratio(&state.path, state.initial_ratio + f64::from(delta));
            cx.notify();
        }
    }

    pub(super) fn finish_split_resize(
        &mut self,
        _: &MouseUpEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.persist_finished_split_resize(cx);
    }

    fn persist_finished_split_resize(&mut self, cx: &mut Context<Self>) {
        if self.split_resize.take().is_none() {
            return;
        }
        let bridge = self.bridge.clone();
        let layout = self.snapshot.layout.clone();
        cx.spawn(async move |_, _| {
            let _ = super::tab_actions::persist_layout(&bridge, layout).await;
        })
        .detach();
    }

    pub(super) fn update_panel_resize(
        &mut self,
        event: &MouseMoveEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(state) = self.panel_resize.as_ref() else {
            return;
        };
        if !event.dragging() {
            return;
        }
        let delta = (event.position.x - state.start_x) / gpui::px(1.0);
        let width = match state.target {
            PanelResizeTarget::ProjectSidebar => state.initial_width + delta,
            PanelResizeTarget::ContextSidebar => state.initial_width - delta,
        }
        .clamp(220.0, 460.0);
        match state.target {
            PanelResizeTarget::ProjectSidebar => self.sidebar_width = width,
            PanelResizeTarget::ContextSidebar => self.context_sidebar_width = width,
        }
        cx.notify();
    }

    pub(super) fn begin_panel_resize(&mut self, event: &MouseDownEvent, window: &mut Window) {
        self.panel_resize = None;
        let Some(target) = self.panel_resize_target(event, window) else {
            return;
        };
        self.panel_resize = Some(PanelResizeState {
            target,
            start_x: event.position.x,
            initial_width: match target {
                PanelResizeTarget::ProjectSidebar => self.sidebar_width,
                PanelResizeTarget::ContextSidebar => self.context_sidebar_width,
            },
        });
    }

    pub(super) fn panel_resize_target(
        &self,
        event: &MouseDownEvent,
        window: &Window,
    ) -> Option<PanelResizeTarget> {
        if event.button != MouseButton::Left {
            return None;
        }
        let x = event.position.x / gpui::px(1.0);
        let viewport_width = window.viewport_size().width / gpui::px(1.0);
        if !self.sidebar_collapsed && (x - self.sidebar_width).abs() <= 8.0 {
            Some(PanelResizeTarget::ProjectSidebar)
        } else if !self.context_sidebar_collapsed
            && self.selected_workspace_id.is_some()
            && !self.snapshot.tabs.is_empty()
            && (x - (viewport_width - self.context_sidebar_width)).abs() <= 8.0
        {
            Some(PanelResizeTarget::ContextSidebar)
        } else {
            None
        }
    }

    pub(super) fn schedule_resize_persistence(&mut self, cx: &mut Context<Self>) {
        self.resize_persist_generation = self.resize_persist_generation.wrapping_add(1);
        let generation = self.resize_persist_generation;
        cx.spawn(async move |this, cx| {
            Timer::after(Duration::from_millis(180)).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if this.resize_persist_generation != generation {
                    return;
                }
                if this.panel_resize.is_some() {
                    this.persist_sidebar_view_prefs(cx);
                }
                if this.split_resize.is_some() {
                    let bridge = this.bridge.clone();
                    let layout = this.snapshot.layout.clone();
                    cx.spawn(async move |_, _| {
                        let _ = super::tab_actions::persist_layout(&bridge, layout).await;
                    })
                    .detach();
                }
            });
        })
        .detach();
    }

    pub(super) fn finish_panel_resize(
        &mut self,
        _: &MouseUpEvent,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.panel_resize.take().is_some() {
            self.persist_sidebar_view_prefs(cx);
        }
    }

    pub(super) fn render_group_content(
        &self,
        tab: Option<&WorkspaceTab>,
        active: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        match tab.map(|tab| tab.kind.as_str()) {
            Some("terminal") => self.render_terminal_surface_for(tab, active, cx),
            Some("gitDiff") => self.render_git_diff_surface(tab.unwrap(), cx),
            Some("editor") | Some("markdownViewer") => {
                self.render_editor_for_tab(tab.unwrap(), active, window, cx)
            }
            Some(kind) => div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child(format!(
                    "{} Surface",
                    super::workbench::title_case_kind(kind)
                ))
                .into_any_element(),
            None => div()
                .flex_1()
                .flex()
                .items_center()
                .justify_center()
                .text_color(theme::text_muted())
                .child("Open Or Create A Tab To Begin")
                .into_any_element(),
        }
    }
}
