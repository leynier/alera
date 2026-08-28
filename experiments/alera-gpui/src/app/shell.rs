use super::{AleraApp, PanelResizeTarget, ResizeDrag, SidebarGroupBy};
use crate::{
    design_system,
    icons::{alera_logo, icon, AleraIcon},
    theme,
};
use gpui::{
    canvas, div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context,
    CursorStyle, DragMoveEvent, Empty, InteractiveElement as _, IntoElement, IsZero as _,
    KeyDownEvent, MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, ParentElement as _,
    Render, Role, ScrollWheelEvent, StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::{
    scroll::{Scrollbar, ScrollbarMode},
    tooltip::Tooltip,
};
const SIDEBAR_SCROLL_DELTA_FACTOR: f32 = if cfg!(target_os = "macos") { 1.25 } else { 1.0 };

impl AleraApp {
    fn render_sidebar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        if self.sidebar_collapsed {
            return self.render_collapsed_sidebar(cx);
        }
        let filter = self
            .sidebar_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let visible_workspace_count =
            self.snapshot
                .projects
                .iter()
                .filter(|project| {
                    self.sidebar_selected_project_ids.is_empty()
                        || self.sidebar_selected_project_ids.contains(&project.id)
                })
                .map(|project| {
                    let project_matches =
                        filter.is_empty() || project.name.to_lowercase().contains(&filter);
                    project
                        .workspaces
                        .iter()
                        .filter(|workspace| {
                            self.sidebar_workspace_visible(workspace)
                                && (project_matches
                                    || workspace.name.to_lowercase().contains(&filter)
                                    || workspace.branch.as_deref().is_some_and(|branch| {
                                        branch.to_lowercase().contains(&filter)
                                    })
                                    || workspace.source_branch.as_deref().is_some_and(|branch| {
                                        branch.to_lowercase().contains(&filter)
                                    }))
                        })
                        .count()
                })
                .sum::<usize>();
        let rows = self.render_sidebar_rows(&filter, cx);
        let has_git_projects = self
            .snapshot
            .projects
            .iter()
            .any(|project| project.kind == "gitRepository");
        let all_project_sections_collapsed = self.all_project_sections_collapsed();

        div()
            .relative()
            .flex()
            .flex_col()
            .flex_shrink_0()
            .w(px(self.sidebar_width))
            .h_full()
            .border_r_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(theme::header_height())
                    .px_3()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(16.0))
                                    .h(px(16.0))
                                    .child(alera_logo(16.0)),
                            )
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child(crate::app_display_name()),
                            ),
                    )
                    .child(
                        div()
                            .id("collapse-project-sidebar")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Collapse Sidebar")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .tooltip(|_, cx| cx.new(|_| Tooltip::new("Collapse Sidebar")).into())
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.sidebar_collapsed = true;
                                cx.defer_in(window, |this, window, cx| {
                                    this.collapsed_sidebar_focus.focus(window, cx);
                                });
                                cx.notify();
                            }))
                            .child(icon(AleraIcon::SidebarToggle, 18.0, theme::text_muted())),
                    ),
            )
            .child(
                div()
                    .h(px(48.0))
                    .p_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(
                        design_system::search_field(&self.sidebar_filter_input, true)
                            .aria_label("Search workspaces"),
                    ),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    // Flutter's toolbar has 4 px vertical padding around its
                    // 32 px controls, for a 40 px band between search and the
                    // first sidebar section.
                    .h(px(40.0))
                    .px_3()
                    .text_xs()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child(if self.sidebar_group_by == SidebarGroupBy::Project {
                        "Projects"
                    } else {
                        "Workspaces"
                    })
                    .child(
                        div()
                            .ml_1()
                            .text_color(theme::text_faint())
                            .child(visible_workspace_count.to_string()),
                    )
                    .child(div().flex_1())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(2.0))
                            .text_color(theme::text_muted())
                            .child(
                                design_system::icon_button(
                                    "sidebar-navigation-back",
                                    "Go Back",
                                    AleraIcon::Back,
                                    !self.worktree_navigation_back.is_empty(),
                                    28.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.go_back(cx);
                                })),
                            )
                            .child(
                                design_system::icon_button(
                                    "sidebar-navigation-forward",
                                    "Go Forward",
                                    AleraIcon::ChevronsRight,
                                    !self.worktree_navigation_forward.is_empty(),
                                    28.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.go_forward(cx);
                                })),
                            )
                            .child(
                                div()
                                    .id("sidebar-view-options")
                                    .focusable()
                                    .tab_stop(true)
                                    .role(Role::Button)
                                    .aria_label("View Options")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .when(!self.show_sidebar_view_options, |button| {
                                        button.tooltip(|_, cx| {
                                            cx.new(|_| Tooltip::new("View Options")).into()
                                        })
                                    })
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.open_sidebar_view_options(cx);
                                    }))
                                    .child(icon(AleraIcon::Tune, 14.0, theme::text_muted())),
                            )
                            .child(
                                div()
                                    .id("toggle-collapse-all-projects")
                                    .focusable()
                                    .tab_stop(true)
                                    .role(Role::Button)
                                    .aria_label(if all_project_sections_collapsed {
                                        "Expand All"
                                    } else {
                                        "Collapse All"
                                    })
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .tooltip(move |_, cx| {
                                        cx.new(move |_| {
                                            Tooltip::new(if all_project_sections_collapsed {
                                                "Expand All"
                                            } else {
                                                "Collapse All"
                                            })
                                        })
                                        .into()
                                    })
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.toggle_all_project_sections(cx);
                                    }))
                                    .child(icon(
                                        if self.all_project_sections_collapsed() {
                                            AleraIcon::ExpandAll
                                        } else {
                                            AleraIcon::CollapseAll
                                        },
                                        14.0,
                                        theme::text_muted(),
                                    )),
                            )
                            .child(
                                div()
                                    .id("add-project-header")
                                    .focusable()
                                    .tab_stop(has_git_projects)
                                    .role(Role::Button)
                                    .aria_label(if has_git_projects {
                                        "New Workspace"
                                    } else {
                                        "Add A Git Project First"
                                    })
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(if has_git_projects {
                                        CursorStyle::PointingHand
                                    } else {
                                        CursorStyle::Arrow
                                    })
                                    .tooltip(move |_, cx| {
                                        cx.new(move |_| {
                                            Tooltip::new(if has_git_projects {
                                                "New Workspace"
                                            } else {
                                                "Add A Git Project First"
                                            })
                                        })
                                        .into()
                                    })
                                    .opacity(if has_git_projects { 1.0 } else { 0.4 })
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .when(has_git_projects, |button| {
                                        button.on_click(cx.listener(|this, _, window, cx| {
                                            this.open_new_workspace_dialog(window, cx);
                                        }))
                                    })
                                    .child(icon(AleraIcon::Add, 14.0, theme::text_muted())),
                            ),
                    ),
            )
            // Flutter keeps the workspace tree in an independent ListView so
            // a long project/workspace list can scroll without moving the
            // search, toolbar, or footer. Keep a persistent handle here so
            // the thumb and the content share one scroll boundary in GPUI.
            .child(
                div()
                    .relative()
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h_0()
                    .child(
                        div()
                            .id("sidebar-workspaces")
                            .flex_1()
                            .min_h_0()
                            .track_scroll(&self.sidebar_scroll_handle)
                            // Computer Use delivers a smaller wheel delta to
                            // GPUI than Flutter's desktop ListView. Keep the
                            // scrollbar attached to the same handle, but own
                            // the delta here so one synthetic page lands on
                            // the same row in both clients.
                            .overflow_hidden()
                            .on_scroll_wheel(
                                cx.listener(|this, event: &ScrollWheelEvent, window, cx| {
                                    let delta =
                                        event.delta.pixel_delta(window.line_height()).y;
                                    if delta.is_zero() {
                                        return;
                                    }
                                    let current = this.sidebar_scroll_handle.offset();
                                    let max_y = this.sidebar_scroll_handle.max_offset().y;
                                    let next_y = (current.y + delta * SIDEBAR_SCROLL_DELTA_FACTOR)
                                        .clamp(-max_y, px(0.0));
                                    this.sidebar_scroll_handle
                                        .set_offset(gpui::point(current.x, next_y));
                                    cx.stop_propagation();
                                    cx.notify();
                                }),
                            )
                            .py_1()
                            .when(self.snapshot.projects.is_empty(), |list| {
                                list.child(
                                    div()
                                        .size_full()
                                        .flex()
                                        .flex_col()
                                        .items_center()
                                        .justify_center()
                                        .px_6()
                                        .text_center()
                                        .child(icon(AleraIcon::Folder, 28.0, theme::text_muted()))
                                        .child(
                                            div()
                                                .mt_3()
                                                .text_sm()
                                                .font_weight(gpui::FontWeight::SEMIBOLD)
                                                .child("No Projects Yet"),
                                        )
                                        .child(
                                            div()
                                                .mt_2()
                                                .max_w(px(165.0))
                                                .whitespace_normal()
                                                .text_xs()
                                                .text_color(theme::text_muted())
                                                .child(
                                                    "Add a git repository to create workspaces with terminal tabs.",
                                                ),
                                        )
                                        .child(
                                            div().mt(px(20.0)).child(
                                                design_system::button_with_leading_icon(
                                                    "sidebar-empty-add-project",
                                                    "Add Your First Project",
                                                    design_system::ButtonKind::Filled,
                                                    false,
                                                    icon(
                                                        AleraIcon::Add,
                                                        14.0,
                                                        theme::on_accent(),
                                                    )
                                                    .into_any_element(),
                                                )
                                                .h(px(28.0))
                                                .text_size(px(11.0))
                                                .on_click(cx.listener(
                                                    |this, _, window, cx| {
                                                        this.add_project(window, cx);
                                                    },
                                                )),
                                            ),
                                        ),
                                )
                            })
                            .children(rows),
                    )
                    .child(
                        Scrollbar::vertical(&self.sidebar_scroll_handle)
                            .id("sidebar-workspaces-scrollbar")
                            .mode(ScrollbarMode::Scrolling),
                    ),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(theme::header_height())
                    .px_2()
                    .border_t_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .child(
                        div()
                            .id("add-project")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Add Project")
                            .flex()
                            .items_center()
                            .h(px(32.0))
                            .px_3()
                            .rounded_lg()
                            .border_1()
                            .border_color(theme::border())
                            .text_xs()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.add_project(window, cx);
                                cx.stop_propagation();
                            }))
                            .gap_2()
                            .child(icon(AleraIcon::FolderSpecial, 16.0, theme::text()))
                            .child("Add Project"),
                    )
                    .child(
                        div()
                            .id("open-settings")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Settings")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.open_settings_dialog(window, cx);
                                cx.stop_propagation();
                            }))
                            .child(icon(AleraIcon::Settings, 17.0, theme::text_muted())),
                    ),
            )
    }

    fn render_project_sidebar_resize_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        let emphasised = self.panel_resize_hovered == Some(PanelResizeTarget::ProjectSidebar)
            || self
                .panel_resize
                .as_ref()
                .is_some_and(|state| state.target == PanelResizeTarget::ProjectSidebar);
        div()
            .id("project-sidebar-resize")
            .focusable()
            .tab_stop(true)
            .role(Role::Splitter)
            .aria_label("Resize Project Sidebar")
            .aria_numeric_value(f64::from(self.sidebar_width))
            .aria_min_numeric_value(220.0)
            .aria_max_numeric_value(460.0)
            .absolute()
            .top_0()
            .left(px(self.sidebar_width - 6.0))
            .bottom(theme::status_bar_height())
            .w(px(12.0))
            .cursor(CursorStyle::ResizeLeftRight)
            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                this.panel_resize_hovered = if *hovered {
                    Some(PanelResizeTarget::ProjectSidebar)
                } else {
                    None
                };
                cx.notify();
            }))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, event: &MouseDownEvent, window, cx| {
                    this.begin_panel_resize(event, window);
                    cx.notify();
                }),
            )
            .on_drag(ResizeDrag, |_, _, _, cx| cx.new(|_| Empty))
            .on_drag_move(
                cx.listener(|this, event: &DragMoveEvent<ResizeDrag>, window, cx| {
                    this.update_panel_resize(&event.event, window, cx);
                    this.schedule_resize_persistence(cx);
                }),
            )
            .on_mouse_up(MouseButton::Left, cx.listener(Self::finish_panel_resize))
            .on_mouse_up_out(MouseButton::Left, cx.listener(Self::finish_panel_resize))
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, _, cx| {
                this.resize_panel_with_keyboard(PanelResizeTarget::ProjectSidebar, event, cx);
            }))
            .child(
                div()
                    .absolute()
                    .top_0()
                    .bottom_0()
                    .left(px(if emphasised { 5.0 } else { 5.5 }))
                    .w(px(if emphasised { 2.0 } else { 1.0 }))
                    .bg(if emphasised {
                        theme::border()
                    } else {
                        theme::border_subtle()
                    }),
            )
            .into_any_element()
    }

    fn render_context_sidebar_resize_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        let emphasised = self.panel_resize_hovered == Some(PanelResizeTarget::ContextSidebar)
            || self
                .panel_resize
                .as_ref()
                .is_some_and(|state| state.target == PanelResizeTarget::ContextSidebar);
        div()
            .id("context-sidebar-resize")
            .focusable()
            .tab_stop(true)
            .role(Role::Splitter)
            .aria_label("Resize Context Sidebar")
            .aria_numeric_value(f64::from(self.context_sidebar_width))
            .aria_min_numeric_value(220.0)
            .aria_max_numeric_value(460.0)
            .absolute()
            .top_0()
            .right(px(self.context_sidebar_width - 6.0))
            .bottom(theme::status_bar_height())
            .w(px(12.0))
            .cursor(CursorStyle::ResizeLeftRight)
            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                this.panel_resize_hovered = if *hovered {
                    Some(PanelResizeTarget::ContextSidebar)
                } else {
                    None
                };
                cx.notify();
            }))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, event: &MouseDownEvent, window, cx| {
                    this.begin_panel_resize(event, window);
                    cx.notify();
                }),
            )
            .on_drag(ResizeDrag, |_, _, _, cx| cx.new(|_| Empty))
            .on_drag_move(
                cx.listener(|this, event: &DragMoveEvent<ResizeDrag>, window, cx| {
                    this.update_panel_resize(&event.event, window, cx);
                    this.schedule_resize_persistence(cx);
                }),
            )
            .on_mouse_up(MouseButton::Left, cx.listener(Self::finish_panel_resize))
            .on_mouse_up_out(MouseButton::Left, cx.listener(Self::finish_panel_resize))
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, _, cx| {
                this.resize_panel_with_keyboard(PanelResizeTarget::ContextSidebar, event, cx);
            }))
            .child(
                div()
                    .absolute()
                    .top_0()
                    .bottom_0()
                    .left(px(if emphasised { 5.0 } else { 5.5 }))
                    .w(px(if emphasised { 2.0 } else { 1.0 }))
                    .bg(if emphasised {
                        theme::border()
                    } else {
                        theme::border_subtle()
                    }),
            )
            .into_any_element()
    }

    fn resize_panel_with_keyboard(
        &mut self,
        target: PanelResizeTarget,
        event: &KeyDownEvent,
        cx: &mut Context<Self>,
    ) {
        let delta = match event.keystroke.key.as_str() {
            "left" | "down" => -8.0,
            "right" | "up" => 8.0,
            _ => return,
        };
        match target {
            PanelResizeTarget::ProjectSidebar => {
                self.sidebar_width = (self.sidebar_width + delta).clamp(220.0, 460.0);
            }
            PanelResizeTarget::ContextSidebar => {
                self.context_sidebar_width =
                    (self.context_sidebar_width + delta).clamp(220.0, 460.0);
            }
        }
        self.persist_sidebar_view_prefs(cx);
        cx.notify();
        cx.stop_propagation();
    }

    fn render_resize_event_observer(&self, cx: &mut Context<Self>) -> AnyElement {
        let app = cx.entity();
        let workbench_left = if self.sidebar_collapsed {
            px(52.0)
        } else {
            px(self.sidebar_width)
        };
        let context_sidebar_width = if self.context_sidebar_collapsed {
            px(52.0)
        } else {
            px(self.context_sidebar_width)
        };
        div()
            .absolute()
            .top_0()
            .left_0()
            .w(px(1.0))
            .h(px(1.0))
            .child(canvas(
                |_, _, _| (),
                move |_, _, window, _| {
                    let app_on_down = app.clone();
                    window.on_mouse_event(move |event: &MouseDownEvent, _, window, cx| {
                        if event.button != MouseButton::Left {
                            return;
                        }
                        // This observer is installed at the window level so a
                        // pointer-up can finish tab drags even when a child
                        // surface consumes the event. It must still ignore
                        // clicks outside the workbench itself: otherwise a
                        // Context Sidebar button can be mistaken for a stale
                        // tab chip and activate a terminal while switching
                        // panels.
                        let viewport_width = window.viewport_size().width;
                        let workbench_right = viewport_width - context_sidebar_width;
                        if event.position.x < workbench_left || event.position.x >= workbench_right
                        {
                            return;
                        }
                        app_on_down.update(cx, |this, cx| {
                            this.begin_pointer_tab_drag_at_position(event.position, cx);
                        });
                    });
                    let app_on_move = app.clone();
                    window.on_mouse_event(move |event: &MouseMoveEvent, _, window, cx| {
                        if !event.dragging() {
                            return;
                        }
                        app_on_move.update(cx, |this, cx| {
                            if this.explorer_pointer_down.is_some() && cx.has_active_drag() {
                                this.explorer_pointer_dragged = true;
                            }
                            let resizing_panel = this.panel_resize.is_some();
                            let resizing_split = this.split_resize.is_some();
                            if resizing_panel {
                                this.update_panel_resize(event, window, cx);
                            }
                            if resizing_split {
                                this.update_split_resize(event, window, cx);
                            }
                            if this.tab_pointer_drag.is_some() {
                                this.update_pointer_tab_drag_at_position(event.position, cx);
                            }
                            if resizing_panel || resizing_split {
                                this.schedule_resize_persistence(cx);
                            }
                        });
                    });
                    let app_on_up = app.clone();
                    window.on_mouse_event(move |event: &MouseUpEvent, _, window, cx| {
                        if event.button != MouseButton::Left {
                            return;
                        }
                        app_on_up.update(cx, |this, cx| {
                            this.finish_panel_resize(event, window, cx);
                            this.finish_split_resize(event, window, cx);
                            this.drop_pointer_tab_at_position(event.position, cx);
                            this.clear_explorer_drop_target(cx);
                            this.explorer_pointer_down = None;
                            this.explorer_pointer_dragged = false;
                        });
                    });
                },
            ))
            .into_any_element()
    }

    fn render_collapsed_sidebar(&self, cx: &mut Context<Self>) -> gpui::Div {
        let project_buttons = self
            .snapshot
            .projects
            .iter()
            .enumerate()
            .map(|(index, project)| {
                let workspace_id = project
                    .workspaces
                    .first()
                    .map(|workspace| workspace.id.clone());
                let label = project
                    .name
                    .chars()
                    .next()
                    .map(|character| character.to_uppercase().to_string())
                    .unwrap_or_else(|| "?".to_string());
                let project_tooltip = project.name.clone();
                let selected = self
                    .selected_workspace_id
                    .as_deref()
                    .is_some_and(|selected| {
                        project
                            .workspaces
                            .iter()
                            .any(|workspace| workspace.id == selected)
                    });
                div()
                    .id(("collapsed-project", index))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(project.name.clone())
                    .relative()
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(32.0))
                    .h(px(32.0))
                    .my(px(3.0))
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
                    .text_xs()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(move |_, cx| {
                        let label = project_tooltip.clone();
                        cx.new(move |_| Tooltip::new(label)).into()
                    })
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.sidebar_collapsed = false;
                        if let Some(workspace_id) = workspace_id.clone() {
                            this.select_workspace(workspace_id, cx);
                        } else {
                            cx.notify();
                        }
                    }))
                    .child(label)
            });
        div()
            .flex()
            .flex_col()
            .items_center()
            .flex_shrink_0()
            .w(px(52.0))
            .h_full()
            .border_r_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .child(
                div()
                    .id("expand-project-sidebar")
                    .track_focus(&self.collapsed_sidebar_focus)
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Expand Sidebar")
                    .flex()
                    .items_center()
                    .justify_end()
                    .w_full()
                    .h(theme::header_height())
                    .pr_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Expand Sidebar")).into())
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.sidebar_collapsed = false;
                        cx.notify();
                    }))
                    .child(icon(AleraIcon::SidebarToggle, 18.0, theme::text_muted())),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .items_center()
                    .flex_1()
                    .w_full()
                    .pt(px(12.0))
                    .pb_2()
                    .children(project_buttons),
            )
            .child(
                div()
                    .id("collapsed-add-project")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Add Project")
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(34.0))
                    .h(px(34.0))
                    .mb_2()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Add Project")).into())
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(cx.listener(|this, _, window, cx| {
                        this.add_project(window, cx);
                    }))
                    .child(icon(AleraIcon::FolderSpecial, 16.0, theme::text_muted())),
            )
            .child(
                div()
                    .id("collapsed-settings")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label("Settings")
                    .flex()
                    .items_center()
                    .justify_center()
                    .w_full()
                    .h(theme::header_height())
                    .border_t_1()
                    .border_color(theme::border_subtle())
                    .text_color(theme::text_muted())
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(|_, cx| cx.new(|_| Tooltip::new("Settings")).into())
                    .on_click(cx.listener(|this, _, window, cx| {
                        this.open_settings_dialog(window, cx);
                    }))
                    .child(icon(AleraIcon::Settings, 18.0, theme::text_muted())),
            )
    }

    fn handle_shell_key_down(
        &mut self,
        event: &KeyDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !event.keystroke.key.eq_ignore_ascii_case("escape") {
            return;
        }
        if self.dismiss_top_overlay_on_escape(window, cx) {
            cx.stop_propagation();
        }
    }

    pub(super) fn dismiss_top_overlay_on_escape(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> bool {
        let handled = if self.tab_pointer_drag.is_some()
            || self.tab_drop_target.is_some()
            || self.pane_drop_target.is_some()
        {
            self.clear_pointer_tab_drag_state(cx);
            true
        } else if self.text_action_operation_id.is_some() {
            self.cancel_text_action(cx);
            true
        } else if self.terminal_search.is_some() {
            self.close_terminal_search(window, cx);
            true
        } else if self.quick_open_open {
            self.close_quick_open(cx);
            true
        } else if self.command_palette_open {
            self.close_command_palette(cx);
            true
        } else if self.command_terminal.is_some() {
            self.close_command_terminal(cx);
            true
        } else if self.workbench_menu.is_some() {
            self.dismiss_workbench_menu(window, cx);
            true
        } else if self.sidebar_menu.take().is_some() || self.sidebar_sort_dropdown.take().is_some()
        {
            true
        } else if self.show_sidebar_view_options {
            self.close_sidebar_view_options(cx);
            true
        } else if self.status_popover != crate::activity::StatusPopover::None {
            self.dismiss_status_popover(cx);
            true
        } else if self.show_tab_rename_dialog && !self.tab_mutation_busy {
            self.close_tab_rename_dialog(cx);
            true
        } else if self.sidebar_dialog.is_some() && !self.sidebar_action_busy {
            self.close_sidebar_dialog(cx);
            true
        } else if self.show_settings_dialog {
            self.close_settings_dialog(window, cx);
            true
        } else if self.show_add_project_dialog && !self.add_project_busy {
            self.close_add_project_dialog(cx);
            true
        } else if self.show_new_workspace_dialog && !self.workspace_creation_busy {
            self.close_new_workspace_dialog(cx);
            true
        } else if !self.explorer_action_busy
            && (self.explorer_create_directory.is_some()
                || self.explorer_rename_path.is_some()
                || self.explorer_delete_path.is_some())
        {
            self.close_explorer_dialog(cx);
            true
        } else if self.show_execution_plans {
            self.close_execution_plans(cx);
            true
        } else if self.mobile_access.overlay.is_some() {
            self.close_mobile_overlay(cx);
            true
        } else if self.source_control_dialog.take().is_some() {
            true
        } else if self.forge_review_action_menu_open {
            self.forge_review_action_menu_open = false;
            true
        } else if self.forge_review_base_menu_open {
            self.forge_review_base_menu_open = false;
            true
        } else if self.forge_create_menu_open {
            self.forge_create_menu_open = false;
            true
        } else if self.forge_base_menu_open {
            self.forge_base_menu_open = false;
            true
        } else {
            self.forge_review_confirmation.take().is_some()
                || self.resource_close_confirmation.take().is_some()
                || (!self.runtime_action_busy && self.runtime_action_armed.take().is_some())
                || (!self.codex_reset_busy && self.codex_reset_offer_revision.take().is_some())
        };

        if handled {
            cx.notify();
        }
        handled
    }
}

impl Render for AleraApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.ensure_selected_editor_loaded(window, cx);
        self.sync_terminal_size(window, cx);
        // Terminal attachment waits for the first measured pane bounds, just
        // like Flutter waits for TerminalView layout before creating its PTY.
        // Re-run the pending attach check on every render after that measure.
        self.ensure_selected_terminal(cx);
        self.ensure_terminal_composer_inputs(window, cx);
        self.ensure_codex_state(window, cx);
        self.refresh_terminal_frame_views(cx);
        let toast_entries = self.visible_toast_entries();
        div()
            .id("alera-app")
            .role(Role::Application)
            .aria_label("Alera Dev")
            .on_key_down(cx.listener(Self::handle_shell_key_down))
            .relative()
            .on_action(cx.listener(Self::on_open_settings))
            .on_action(cx.listener(Self::on_open_quick_open))
            .on_action(cx.listener(Self::on_open_command_palette))
            .on_action(cx.listener(Self::on_open_execution_plans))
            .on_action(cx.listener(Self::on_minimize_window))
            .on_action(cx.listener(Self::on_zoom_window))
            .on_action(cx.listener(Self::on_toggle_full_screen))
            .on_action(cx.listener(Self::on_quit_app))
            .on_action(cx.listener(Self::on_add_project))
            .on_action(cx.listener(Self::on_toggle_sidebar))
            .on_action(cx.listener(Self::on_create_workspace))
            .on_action(cx.listener(Self::on_go_back))
            .on_action(cx.listener(Self::on_go_forward))
            .on_action(cx.listener(Self::on_find_in_files))
            .on_action(cx.listener(Self::on_find_in_terminal))
            .on_action(cx.listener(Self::on_toggle_terminal_composer))
            .on_action(cx.listener(Self::on_replace_in_files))
            .on_action(cx.listener(Self::on_save_file))
            .on_action(cx.listener(Self::on_run_text_action))
            .on_action(cx.listener(Self::on_new_terminal))
            .on_action(cx.listener(Self::on_close_tab))
            .on_action(cx.listener(Self::on_next_tab))
            .on_action(cx.listener(Self::on_previous_tab))
            .on_action(cx.listener(Self::on_go_to_tab_1))
            .on_action(cx.listener(Self::on_go_to_tab_2))
            .on_action(cx.listener(Self::on_go_to_tab_3))
            .on_action(cx.listener(Self::on_go_to_tab_4))
            .on_action(cx.listener(Self::on_go_to_tab_5))
            .on_action(cx.listener(Self::on_go_to_tab_6))
            .on_action(cx.listener(Self::on_go_to_tab_7))
            .on_action(cx.listener(Self::on_go_to_tab_8))
            .on_action(cx.listener(Self::on_go_to_tab_9))
            .on_action(cx.listener(Self::on_split_right))
            .on_action(cx.listener(Self::on_split_down))
            .on_action(cx.listener(Self::on_close_split))
            .on_action(cx.listener(Self::on_terminal_enter))
            .on_action(cx.listener(Self::on_terminal_backspace))
            .on_action(cx.listener(Self::on_terminal_delete))
            .on_action(cx.listener(Self::on_terminal_tab))
            .on_action(cx.listener(Self::on_terminal_back_tab))
            .on_action(cx.listener(Self::on_terminal_escape))
            .on_action(cx.listener(Self::on_terminal_up))
            .on_action(cx.listener(Self::on_terminal_down))
            .on_action(cx.listener(Self::on_terminal_left))
            .on_action(cx.listener(Self::on_terminal_right))
            .on_action(cx.listener(Self::on_terminal_home))
            .on_action(cx.listener(Self::on_terminal_end))
            .on_action(cx.listener(Self::on_terminal_page_up))
            .on_action(cx.listener(Self::on_terminal_page_down))
            .on_action(cx.listener(Self::on_terminal_copy))
            .on_action(cx.listener(Self::on_terminal_paste))
            .on_action(cx.listener(Self::on_terminal_interrupt))
            .flex()
            .flex_col()
            .size_full()
            .bg(theme::app_background())
            .text_color(theme::text())
            .font_family("Inter")
            // A native drag can stop bubbling at the preview overlay or at a
            // terminal surface. Capture the release on the full app hitbox so
            // the remembered pointer drag is committed before GPUI clears its
            // active drag state.
            .capture_any_mouse_up(cx.listener(|this, event: &MouseUpEvent, _, cx| {
                if event.button == MouseButton::Left
                    && (this.tab_pointer_drag.is_some()
                        || this.tab_drop_target.is_some()
                        || this.pane_drop_target.is_some())
                {
                    this.drop_pointer_tab_at_position(event.position, cx);
                }
            }))
            .child(
                div()
                    .flex()
                    .flex_1()
                    .overflow_hidden()
                    .child(self.render_sidebar(cx))
                    .child(self.render_workbench(window, cx)),
            )
            .child(self.render_status_bar(cx))
            .child(self.render_resize_event_observer(cx))
            .when(!self.sidebar_collapsed, |root| {
                root.child(self.render_project_sidebar_resize_overlay(cx))
            })
            .when(
                !self.context_sidebar_collapsed
                    && self.selected_workspace_id.is_some()
                    && !self.snapshot.tabs.is_empty(),
                |root| root.child(self.render_context_sidebar_resize_overlay(cx)),
            )
            .when(
                self.status_popover != crate::activity::StatusPopover::None,
                |root| {
                    root.child(self.render_status_popover_dismiss_layer(cx))
                        .child(self.render_active_status_popover(cx))
                },
            )
            .when(self.show_new_workspace_dialog, |root| {
                root.child(self.render_new_workspace_dialog(cx))
            })
            .when(self.quick_open_open, |root| {
                root.child(self.render_quick_open_overlay(cx))
            })
            .when(self.command_palette_open, |root| {
                root.child(self.render_command_palette_overlay(cx))
            })
            .when(self.show_add_project_dialog, |root| {
                root.child(self.render_add_project_dialog(cx))
            })
            .when(self.show_settings_dialog, |root| {
                root.child(self.render_settings_dialog(cx))
            })
            .when(self.show_about_dialog, |root| {
                root.child(self.render_about_dialog(cx))
            })
            .when(self.show_execution_plans, |root| {
                root.child(self.render_execution_plans_dialog(cx))
            })
            .when(self.mobile_access.overlay.is_some(), |root| {
                root.child(self.render_mobile_access_overlay(cx))
            })
            .when(self.show_sidebar_view_options, |root| {
                root.child(self.render_sidebar_view_options(cx))
            })
            .when(self.show_tab_rename_dialog, |root| {
                root.child(self.render_tab_rename_dialog(cx))
            })
            .when(self.tab_close_armed.is_some(), |root| {
                root.child(self.render_dirty_tab_close_dialog(cx))
            })
            .when(self.editor_conflict, |root| {
                root.child(self.render_editor_conflict_dialog(cx))
            })
            .when(
                self.explorer_create_directory.is_some()
                    || self.explorer_rename_path.is_some()
                    || self.explorer_delete_path.is_some(),
                |root| root.child(self.render_explorer_create_dialog(cx)),
            )
            .when(self.codex_reset_offer_revision.is_some(), |root| {
                root.child(self.render_codex_reset_dialog(cx))
            })
            .when(self.runtime_action_armed.is_some(), |root| {
                root.child(self.render_runtime_force_dialog(cx))
            })
            .when(self.resource_close_confirmation.is_some(), |root| {
                root.child(self.render_resource_close_confirmation(cx))
            })
            .when(self.source_control_dialog.is_some(), |root| {
                root.child(self.render_source_control_dialog(cx))
            })
            .when(self.command_terminal.is_some(), |root| {
                root.child(self.render_command_terminal_dialog(cx))
            })
            .when(self.forge_review_confirmation.is_some(), |root| {
                root.child(self.render_pull_request_confirmation(cx))
            })
            .children(toast_entries.into_iter().rev().enumerate().map(
                |(stack_index, (message, exiting))| {
                    super::toast::render_toast(message, stack_index, exiting)
                },
            ))
            .when(self.explorer_menu.is_some(), |root| {
                root.child(self.render_explorer_menu(window, cx))
            })
            .when(self.sidebar_menu.is_some(), |root| {
                root.child(self.render_sidebar_menu(window, cx))
            })
            .when(self.sidebar_dialog.is_some(), |root| {
                root.child(self.render_sidebar_dialog(cx))
            })
            .when(self.workbench_menu.is_some(), |root| {
                root.child(self.render_workbench_menu(window, cx))
            })
    }
}
