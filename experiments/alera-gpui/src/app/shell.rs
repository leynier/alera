use super::{AleraApp, ResizeDrag, SidebarGroupBy};
use crate::{
    design_system,
    icons::{alera_logo, icon, AleraIcon},
    theme,
};
use gpui::{
    canvas, div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context,
    CursorStyle, DragMoveEvent, Empty, InteractiveElement as _, IntoElement, MouseButton,
    MouseDownEvent, MouseMoveEvent, MouseUpEvent, ParentElement as _, Render,
    StatefulInteractiveElement as _, Styled as _, Window,
};

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
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _, _, cx| {
                                    this.sidebar_collapsed = true;
                                    cx.notify();
                                }),
                            )
                            .child(icon(AleraIcon::SidebarToggle, 18.0, theme::text_muted())),
                    ),
            )
            .child(
                div()
                    .h(px(56.0))
                    .p_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .child(design_system::search_field(
                        &self.sidebar_filter_input,
                        true,
                    )),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(px(32.0))
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
                                div()
                                    .id("sidebar-view-options")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.open_sidebar_view_options(cx);
                                        }),
                                    )
                                    .child(icon(AleraIcon::Tune, 14.0, theme::text_muted())),
                            )
                            .child(
                                div()
                                    .id("toggle-collapse-all-projects")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.toggle_all_project_sections(cx);
                                        }),
                                    )
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
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface_raised()))
                                    .on_mouse_down(
                                        MouseButton::Left,
                                        cx.listener(|this, _, _, cx| {
                                            this.open_new_workspace_dialog(cx);
                                        }),
                                    )
                                    .child(icon(AleraIcon::Add, 14.0, theme::text_muted())),
                            ),
                    ),
            )
            .child(div().flex_1().overflow_hidden().py_1().children(rows))
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
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, window, cx| {
                                    this.add_project(window, cx);
                                    cx.stop_propagation();
                                }),
                            )
                            .gap_2()
                            .child(icon(AleraIcon::FolderSpecial, 16.0, theme::text()))
                            .child("Add Project"),
                    )
                    .child(
                        div()
                            .id("open-settings")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _: &MouseDownEvent, window, cx| {
                                    this.open_settings_dialog(window, cx);
                                    cx.stop_propagation();
                                }),
                            )
                            .child(icon(AleraIcon::Settings, 17.0, theme::text_muted())),
                    ),
            )
    }

    fn render_project_sidebar_resize_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .id("project-sidebar-resize")
            .absolute()
            .top_0()
            .left(px(self.sidebar_width - 6.0))
            .bottom(theme::status_bar_height())
            .w(px(12.0))
            .cursor(CursorStyle::ResizeLeftRight)
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, event: &MouseDownEvent, window, _| {
                    this.begin_panel_resize(event, window);
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
            .into_any_element()
    }

    fn render_context_sidebar_resize_overlay(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .id("context-sidebar-resize")
            .absolute()
            .top_0()
            .right(px(self.context_sidebar_width - 6.0))
            .bottom(theme::status_bar_height())
            .w(px(12.0))
            .cursor(CursorStyle::ResizeLeftRight)
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, event: &MouseDownEvent, window, _| {
                    this.begin_panel_resize(event, window);
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
            .into_any_element()
    }

    fn render_resize_event_observer(&self, cx: &mut Context<Self>) -> AnyElement {
        let app = cx.entity();
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
                    window.on_mouse_event(move |event: &MouseDownEvent, _, _, cx| {
                        if event.button != MouseButton::Left {
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
                    .find(|character| character.is_alphanumeric())
                    .map(|character| character.to_uppercase().to_string())
                    .unwrap_or_else(|| "P".to_string());
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
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            this.sidebar_collapsed = false;
                            if let Some(workspace_id) = workspace_id.clone() {
                                this.select_workspace(workspace_id, cx);
                            } else {
                                cx.notify();
                            }
                        }),
                    )
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
                    .flex()
                    .items_center()
                    .justify_end()
                    .w_full()
                    .h(theme::header_height())
                    .pr_2()
                    .border_b_1()
                    .border_color(theme::border_subtle())
                    .cursor(CursorStyle::PointingHand)
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, _, cx| {
                            this.sidebar_collapsed = false;
                            cx.notify();
                        }),
                    )
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
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.add_project(window, cx);
                        }),
                    )
                    .child(icon(AleraIcon::FolderSpecial, 16.0, theme::text_muted())),
            )
            .child(
                div()
                    .id("collapsed-settings")
                    .flex()
                    .items_center()
                    .justify_center()
                    .w_full()
                    .h(theme::header_height())
                    .border_t_1()
                    .border_color(theme::border_subtle())
                    .text_color(theme::text_muted())
                    .cursor(CursorStyle::PointingHand)
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.open_settings_dialog(window, cx);
                        }),
                    )
                    .child(icon(AleraIcon::Settings, 18.0, theme::text_muted())),
            )
    }
}

impl Render for AleraApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.ensure_selected_editor_loaded(window, cx);
        self.sync_terminal_size(window, cx);
        div()
            .relative()
            .on_action(cx.listener(Self::on_open_settings))
            .on_action(cx.listener(Self::on_open_execution_plans))
            .on_action(cx.listener(Self::on_minimize_window))
            .on_action(cx.listener(Self::on_zoom_window))
            .on_action(cx.listener(Self::on_toggle_full_screen))
            .on_action(cx.listener(Self::on_quit_app))
            .on_action(cx.listener(Self::on_add_project))
            .on_action(cx.listener(Self::on_toggle_sidebar))
            .on_action(cx.listener(Self::on_create_workspace))
            .on_action(cx.listener(Self::on_find_in_files))
            .on_action(cx.listener(Self::on_replace_in_files))
            .on_action(cx.listener(Self::on_save_file))
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
            .when(self.show_add_project_dialog, |root| {
                root.child(self.render_add_project_dialog(cx))
            })
            .when(self.show_settings_dialog, |root| {
                root.child(self.render_settings_dialog(cx))
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
            .when(self.forge_review_confirmation.is_some(), |root| {
                root.child(self.render_pull_request_confirmation(cx))
            })
            .when_some(self.local_message.clone(), |root, message| {
                root.child(super::toast::render_toast(message))
            })
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
