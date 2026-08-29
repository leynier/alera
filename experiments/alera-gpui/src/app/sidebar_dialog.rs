use chrono::{DateTime, Local};
use gpui::{
    anchored, deferred, div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement, MouseButton, ParentElement as _, Pixels, Point, Role,
    SharedString, Size, StatefulInteractiveElement as _, Styled as _, Toggled, Window,
};
use gpui_component::scroll::ScrollableElement as _;

use super::{AleraApp, SidebarDialogKind, SidebarMenu};
use crate::{
    design_system::{self, ButtonKind},
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_sidebar_menu(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let menu = match self.sidebar_menu.as_ref() {
            Some(SidebarMenu::Project(project_id)) => {
                self.render_project_menu(project_id.clone(), window, cx)
            }
            Some(SidebarMenu::Workspace(workspace_id)) => {
                self.render_workspace_menu(workspace_id.clone(), window, cx)
            }
            None => div().into_any_element(),
        };
        div()
            .id("sidebar-menu-overlay")
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.dismiss_sidebar_menu(cx);
                }),
            )
            .child(menu)
    }

    fn render_project_menu(
        &self,
        project_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let rename_id = project_id.clone();
        let workspace_id = project_id.clone();
        let settings_id = project_id.clone();
        let remove_id = project_id;
        let can_create_workspace = self
            .snapshot
            .projects
            .iter()
            .find(|project| project.id == workspace_id)
            .is_some_and(|project| project.kind == "gitRepository");
        sidebar_menu_shell(
            "project-context-menu",
            "Project actions",
            self.sidebar_menu_position,
            window.viewport_size(),
            px(150.0),
        )
        .child(
            sidebar_menu_button(
                "project-menu-settings",
                AleraIcon::Settings,
                "Open Project Settings",
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                cx.stop_propagation();
                this.open_project_settings_dialog(settings_id.clone(), window, cx);
            })),
        )
        .child(sidebar_menu_divider())
        .child(
            sidebar_menu_button("project-menu-rename", AleraIcon::Edit, "Rename").on_click(
                cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.open_sidebar_dialog(
                        SidebarDialogKind::RenameProject,
                        rename_id.clone(),
                        window,
                        cx,
                    );
                }),
            ),
        )
        .child(
            sidebar_menu_button("project-menu-workspace", AleraIcon::Add, "New Workspace")
                .when(can_create_workspace, |button| {
                    button.on_click(cx.listener(move |this, _, window, cx| {
                        cx.stop_propagation();
                        this.selected_workspace_project_id = Some(workspace_id.clone());
                        this.open_new_workspace_dialog(window, cx);
                        this.sidebar_menu = None;
                    }))
                })
                .when(!can_create_workspace, |button| {
                    button
                        .text_color(theme::text_faint())
                        .cursor(CursorStyle::Arrow)
                }),
        )
        .child(sidebar_menu_divider())
        .child(
            sidebar_menu_button("project-menu-remove", AleraIcon::Delete, "Remove Project")
                .text_color(theme::danger())
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.open_sidebar_dialog(
                        SidebarDialogKind::RemoveProject,
                        remove_id.clone(),
                        window,
                        cx,
                    );
                })),
        )
        .into_any_element()
    }

    fn render_workspace_menu(
        &self,
        workspace_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let Some(workspace) = self.snapshot.workspace(&workspace_id) else {
            return div().into_any_element();
        };
        let is_main = workspace.kind == "main";
        let is_pinned = workspace.is_pinned;
        let has_parent = self
            .snapshot
            .relations
            .iter()
            .any(|relation| relation.child_workspace_id == workspace_id);
        let next_pinned = !is_pinned;
        let rename_id = workspace_id.clone();
        let pin_id = workspace_id.clone();
        let tags_id = workspace_id.clone();
        let parent_id = workspace_id.clone();
        let clear_parent_id = workspace_id.clone();
        let repository_id = workspace_id.clone();
        let folder_id = workspace_id.clone();
        let copy_id = workspace_id.clone();
        let sleep_id = workspace_id.clone();
        let project_settings_id = self
            .snapshot
            .project_for_workspace(&workspace_id)
            .map(|project| project.id.clone());
        let remove_id = workspace_id;
        sidebar_menu_shell(
            "workspace-context-menu",
            "Workspace actions",
            self.sidebar_menu_position,
            window.viewport_size(),
            px(342.0),
        )
        .child(
            sidebar_menu_button("workspace-menu-rename", AleraIcon::Edit, "Rename").on_click(
                cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.open_sidebar_dialog(
                        SidebarDialogKind::RenameWorkspace,
                        rename_id.clone(),
                        window,
                        cx,
                    );
                }),
            ),
        )
        .child(
            sidebar_menu_button(
                "workspace-menu-pin",
                if is_pinned {
                    AleraIcon::PinOff
                } else {
                    AleraIcon::Pin
                },
                if is_pinned {
                    "Unpin Workspace"
                } else {
                    "Pin Workspace"
                },
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.toggle_workspace_pinned(pin_id.clone(), next_pinned, cx);
            })),
        )
        .child(
            sidebar_menu_button("workspace-menu-tags", AleraIcon::Tag, "Manage Tags").on_click(
                cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.open_sidebar_dialog(
                        SidebarDialogKind::ManageWorkspaceTags,
                        tags_id.clone(),
                        window,
                        cx,
                    );
                }),
            ),
        )
        .child(
            sidebar_menu_button(
                "workspace-menu-parent",
                AleraIcon::Link,
                "Set Parent Workspace",
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                cx.stop_propagation();
                this.open_sidebar_dialog(
                    SidebarDialogKind::SetWorkspaceParent,
                    parent_id.clone(),
                    window,
                    cx,
                );
            })),
        )
        .when(has_parent, |menu| {
            menu.child(
                sidebar_menu_button(
                    "workspace-menu-clear-parent",
                    AleraIcon::Close,
                    "Clear Parent Workspace",
                )
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.clear_workspace_parent(clear_parent_id.clone(), cx);
                })),
            )
        })
        .child(sidebar_menu_divider())
        .child(
            sidebar_menu_button(
                "workspace-menu-browser",
                AleraIcon::External,
                "Open in Browser",
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.open_workspace_repository(repository_id.clone(), cx);
            })),
        )
        .child(
            sidebar_menu_button(
                "workspace-menu-folder",
                AleraIcon::FolderOpen,
                "Open in Finder",
            )
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.open_workspace_folder(folder_id.clone(), cx);
            })),
        )
        .when_some(project_settings_id, |menu, project_id| {
            menu.child(
                sidebar_menu_button(
                    "workspace-menu-project-settings",
                    AleraIcon::Settings,
                    "Open in Project Settings",
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.open_project_settings_dialog(project_id.clone(), window, cx);
                })),
            )
        })
        .child(
            sidebar_menu_button("workspace-menu-copy", AleraIcon::Copy, "Copy Path").on_click(
                cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.copy_workspace_path(copy_id.clone(), cx);
                }),
            ),
        )
        .child(sidebar_menu_divider())
        .child(
            sidebar_menu_button("workspace-menu-sleep", AleraIcon::Theme, "Sleep").on_click(
                cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    this.open_sidebar_dialog(
                        SidebarDialogKind::SleepWorkspace,
                        sleep_id.clone(),
                        window,
                        cx,
                    );
                }),
            ),
        )
        .child(
            sidebar_menu_button("workspace-menu-remove", AleraIcon::Delete, "Remove")
                .when(is_main, |button| {
                    button
                        .text_color(theme::text_faint())
                        .cursor(CursorStyle::Arrow)
                })
                .when(!is_main, |button| {
                    button.text_color(theme::danger()).on_click(cx.listener(
                        move |this, _, window, cx| {
                            cx.stop_propagation();
                            this.open_sidebar_dialog(
                                SidebarDialogKind::RemoveWorkspace,
                                remove_id.clone(),
                                window,
                                cx,
                            );
                        },
                    ))
                }),
        )
        .into_any_element()
    }

    fn render_workspace_tags_dialog(&self, cx: &mut Context<Self>) -> AnyElement {
        let mut tags = self.snapshot.tags.iter().collect::<Vec<_>>();
        tags.sort_by_key(|tag| tag.name.to_lowercase());
        let mut list = div().mt_4().max_h(px(260.0)).overflow_y_scrollbar();
        if tags.is_empty() {
            list = list.child(
                div()
                    .pb_3()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child("No Tags Created"),
            );
        }
        for tag in tags {
            let selected = self.sidebar_selected_tag_ids.contains(&tag.id);
            let toggle_id = tag.id.clone();
            let delete_id = tag.id.clone();
            let tag_label = format!("#{}", tag.name);
            let delete_label = format!("Delete Tag #{}", tag.name);
            list = list.child(
                div()
                    .id(SharedString::from(format!("sidebar-tag-row-{}", tag.id)))
                    .flex()
                    .items_center()
                    .h(px(36.0))
                    .gap_2()
                    .child(
                        div()
                            .id(SharedString::from(format!("sidebar-tag-toggle-{}", tag.id)))
                            .focusable()
                            .tab_stop(true)
                            .role(Role::CheckBox)
                            .aria_label(tag_label.clone())
                            .aria_toggled(if selected {
                                Toggled::True
                            } else {
                                Toggled::False
                            })
                            .flex()
                            .items_center()
                            .flex_1()
                            .gap_2()
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.toggle_sidebar_tag(toggle_id.clone(), cx);
                            }))
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(16.0))
                                    .h(px(16.0))
                                    .rounded_sm()
                                    .border_1()
                                    .border_color(if selected {
                                        theme::accent()
                                    } else {
                                        theme::border()
                                    })
                                    .bg(if selected {
                                        theme::accent()
                                    } else {
                                        theme::surface_raised()
                                    })
                                    .when(selected, |check| {
                                        check.child(icon(AleraIcon::Check, 12.0, theme::surface()))
                                    }),
                            )
                            .child(tag_label),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!("sidebar-tag-delete-{}", tag.id)))
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label(delete_label)
                            .cursor(CursorStyle::PointingHand)
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.arm_sidebar_tag_delete(delete_id.clone(), cx);
                            }))
                            .child(icon(AleraIcon::Delete, 16.0, theme::text_muted())),
                    ),
            );
        }

        div()
            .child(list)
            .child(
                div()
                    .mt_3()
                    .flex()
                    .items_start()
                    .gap_2()
                    .child(
                        div()
                            .flex_1()
                            .child(design_system::text_field(&self.sidebar_tag_input)),
                    )
                    .child(
                        design_system::button_with_loading(
                            "sidebar-create-tag",
                            if self.sidebar_action_busy {
                                "Creating"
                            } else {
                                "Create Tag"
                            },
                            ButtonKind::Filled,
                            self.sidebar_action_busy,
                            self.sidebar_action_busy,
                        )
                        .mt_2()
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.create_sidebar_tag(cx);
                        })),
                    ),
            )
            .into_any_element()
    }

    fn render_workspace_parent_dialog(
        &self,
        dialog: &super::SidebarDialog,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let descendants = workspace_descendant_ids(&dialog.target_id, &self.snapshot.relations);
        let filter = self
            .sidebar_parent_filter_input
            .read(cx)
            .value()
            .to_lowercase();
        let selected_label = self
            .sidebar_selected_parent_id
            .as_deref()
            .and_then(|id| workspace_parent_label(&self.snapshot, id))
            .unwrap_or_else(|| "No Parent".to_string());
        let mut options = div()
            .id("sidebar-parent-options")
            .occlude()
            .w(px(420.0))
            .max_h(px(230.0))
            .overflow_y_scrollbar()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .p_1()
            .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                this.sidebar_parent_dropdown_open = false;
                cx.notify();
            }))
            .child(div().p_1().child(design_system::dense_text_field(
                &self.sidebar_parent_filter_input,
                Some(icon(AleraIcon::Search, 14.0, theme::text_faint()).into_any_element()),
            )));
        if filter.is_empty() || "no parent".contains(&filter) {
            options = options.child(
                parent_option(
                    "sidebar-parent-none",
                    "No Parent",
                    self.sidebar_selected_parent_id.is_none(),
                    false,
                )
                .on_click(cx.listener(|this, _, _, cx| {
                    this.select_sidebar_parent(None, cx);
                })),
            );
        }
        for project in &self.snapshot.projects {
            for workspace in &project.workspaces {
                if workspace.id == dialog.target_id {
                    continue;
                }
                let label = workspace_parent_label(&self.snapshot, &workspace.id)
                    .unwrap_or_else(|| workspace.name.clone());
                if !filter.is_empty() && !label.to_lowercase().contains(&filter) {
                    continue;
                }
                let disabled = descendants.contains(&workspace.id);
                let selected =
                    self.sidebar_selected_parent_id.as_deref() == Some(workspace.id.as_str());
                let parent_id = workspace.id.clone();
                let option = parent_option(
                    SharedString::from(format!("sidebar-parent-{}", workspace.id)),
                    label,
                    selected,
                    disabled,
                );
                options = options.child(if disabled {
                    option
                } else {
                    option.on_click(cx.listener(move |this, _, _, cx| {
                        this.select_sidebar_parent(Some(parent_id.clone()), cx);
                    }))
                });
            }
        }

        div()
            .relative()
            .mt_4()
            .child(
                div()
                    .mb_1()
                    .text_size(px(10.0))
                    .font_weight(gpui::FontWeight::MEDIUM)
                    .text_color(theme::text_muted())
                    .child("Parent Workspace"),
            )
            .child(
                div()
                    .id("sidebar-parent-trigger")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::ComboBox)
                    .aria_label("Parent Workspace")
                    .aria_expanded(self.sidebar_parent_dropdown_open)
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .px_3()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_selected())
                    .cursor(CursorStyle::PointingHand)
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.toggle_sidebar_parent_dropdown(cx);
                    }))
                    .child(div().flex_1().child(selected_label))
                    .child(icon(
                        if self.sidebar_parent_dropdown_open {
                            AleraIcon::ChevronUp
                        } else {
                            AleraIcon::ChevronDown
                        },
                        16.0,
                        theme::text_muted(),
                    ))
                    .when(self.sidebar_parent_dropdown_open, |trigger| {
                        trigger.child(
                            deferred(
                                anchored()
                                    .snap_to_window_with_margin(px(8.0))
                                    .offset(gpui::point(px(-10.0), px(100.0)))
                                    .child(options),
                            )
                            .with_priority(1),
                        )
                    }),
            )
            .into_any_element()
    }

    pub(super) fn render_sidebar_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let Some(dialog) = self.sidebar_dialog.as_ref() else {
            return div().into_any_element();
        };
        let target_workspace = self.snapshot.workspace(&dialog.target_id);
        let (title, message, confirm, destructive, show_input) = match dialog.kind {
            SidebarDialogKind::RenameProject => {
                ("Rename Project", String::new(), "Rename", false, true)
            }
            SidebarDialogKind::RemoveProject => (
                "Remove Project?",
                "This Unregisters The Project And Deletes Its Workspace Metadata. Repository Files On Disk Are Not Deleted.".to_string(),
                "Remove",
                true,
                false,
            ),
            SidebarDialogKind::RenameWorkspace => {
                ("Rename Workspace", String::new(), "Rename", false, true)
            }
            SidebarDialogKind::ManageWorkspaceTags => {
                ("Manage Tags", String::new(), "Save", false, false)
            }
            SidebarDialogKind::SetWorkspaceParent => {
                ("Set Parent Workspace", String::new(), "Save", false, false)
            }
            SidebarDialogKind::SleepWorkspace => (
                "Sleep Workspace?",
                target_workspace
                    .map(|workspace| {
                        let dirty_warning = if self.editor_dirty
                            && self.selected_workspace_id.as_deref() == Some(workspace.id.as_str())
                        {
                            " One Editor Has Unsaved Changes That Will Be Discarded."
                        } else {
                            ""
                        };
                        format!(
                            "This Closes All Tabs And Terminal Sessions For \"{}\". The Workspace, Branch, And Files Will Be Preserved.{dirty_warning}",
                            workspace.name
                        )
                    })
                    .unwrap_or_else(|| {
                        "This Closes All Tabs And Terminal Sessions. The Workspace, Branch, And Files Will Be Preserved.".to_string()
                    }),
                "Sleep",
                true,
                false,
            ),
            SidebarDialogKind::RemoveWorkspace => {
                let impact = self.sidebar_storage_impact.as_ref();
                if self.sidebar_action_busy && impact.is_none() {
                    (
                        "Inspecting Workspace Storage",
                        "Measuring allocated entries and verifying runtime ownership, active work, path containment, and Git worktree identity.".to_string(),
                        "Inspecting",
                        false,
                        false,
                    )
                } else if let Some(impact) = impact.filter(|impact| !impact.safe_to_clean) {
                    (
                        "Cleanup Unavailable",
                        format!(
                            "Alera measured {} across {} entries for workspace {}. Cleanup is blocked:\n\n{}",
                            format_workspace_storage_bytes(impact.size_bytes),
                            impact.entry_count,
                            impact.workspace_id,
                            impact
                                .blockers
                                .iter()
                                .map(|blocker| format!("• {blocker}"))
                                .collect::<Vec<_>>()
                                .join("\n"),
                        ),
                        "Close",
                        false,
                        false,
                    )
                } else if let Some(impact) = impact {
                    let removal = target_workspace
                        .map(|workspace| {
                            if workspace.reuses_existing_branch {
                                format!("This removes the worktree for \"{}\".", workspace.name)
                            } else if let Some(branch) = workspace
                                .branch
                                .as_deref()
                                .filter(|branch| !branch.is_empty())
                            {
                                format!(
                                    "This removes the worktree for \"{}\" and deletes branch \"{branch}\".",
                                    workspace.name
                                )
                            } else {
                                format!("This removes the worktree for \"{}\".", workspace.name)
                            }
                        })
                        .unwrap_or_else(|| "This removes the worktree.".to_string());
                    (
                        "Clean Up Workspace?",
                        format!(
                            "Measured size: {} across {} entries.\nLast activity: {}.\nMeasured: {}.\nPath: {}.\n\n{removal}",
                            format_workspace_storage_bytes(impact.size_bytes),
                            impact.entry_count,
                            format_workspace_storage_timestamp(&impact.last_activity_at),
                            format_workspace_storage_timestamp(&impact.measured_at),
                            impact.path,
                        ),
                        "Clean Up",
                        true,
                        false,
                    )
                } else {
                    (
                        "Cleanup Unavailable",
                        "Alera could not verify workspace storage safety. Close this dialog and try again.".to_string(),
                        "Close",
                        false,
                        false,
                    )
                }
            }
        };
        let dialog_width = if matches!(
            dialog.kind,
            SidebarDialogKind::ManageWorkspaceTags | SidebarDialogKind::SetWorkspaceParent
        ) {
            460.0
        } else {
            420.0
        };
        let tag_to_delete = self.sidebar_tag_delete_armed.as_ref().and_then(|id| {
            self.snapshot
                .tags
                .iter()
                .find(|tag| &tag.id == id)
                .map(|tag| tag.name.clone())
        });
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .flex()
            .items_center()
            .justify_center()
            .bg(theme::overlay_scrim())
            .child(
                design_system::dialog_shell("sidebar-action-dialog", title, dialog_width)
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .child(match dialog.kind {
                                SidebarDialogKind::ManageWorkspaceTags => {
                                    icon(AleraIcon::Tag, 24.0, theme::accent()).into_any_element()
                                }
                                SidebarDialogKind::SetWorkspaceParent => {
                                    icon(AleraIcon::Link, 24.0, theme::accent()).into_any_element()
                                }
                                _ => div().into_any_element(),
                            })
                            .child(
                                div()
                                    .flex_1()
                                    .ml_2()
                                    .text_size(px(14.0))
                                    .font_weight(gpui::FontWeight::BOLD)
                                    .child(title),
                            ),
                    )
                    .when(!message.is_empty(), |body| {
                        body.child(
                            div()
                                .mt_3()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child(message),
                        )
                    })
                    .when(show_input, |body| {
                        body.child(
                            div()
                                .mt_4()
                                .child(design_system::text_field(&self.sidebar_action_input)),
                        )
                    })
                    .when(
                        dialog.kind == SidebarDialogKind::ManageWorkspaceTags,
                        |body| body.child(self.render_workspace_tags_dialog(cx)),
                    )
                    .when(
                        dialog.kind == SidebarDialogKind::SetWorkspaceParent,
                        |body| body.child(self.render_workspace_parent_dialog(dialog, cx)),
                    )
                    .when_some(self.error.clone(), |body, error| {
                        body.child(
                            div()
                                .mt_3()
                                .text_sm()
                                .text_color(theme::danger())
                                .child(error),
                        )
                    })
                    .child(
                        div()
                            .flex()
                            .justify_end()
                            .gap_2()
                            .mt(px(20.0))
                            .child(
                                design_system::button(
                                    "sidebar-dialog-cancel",
                                    "Cancel",
                                    ButtonKind::Text,
                                    self.sidebar_action_busy,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.close_sidebar_dialog(cx);
                                })),
                            )
                            .child(
                                design_system::button_with_loading(
                                    "sidebar-dialog-confirm",
                                    if self.sidebar_action_busy {
                                        "Working"
                                    } else {
                                        confirm
                                    },
                                    if destructive {
                                        ButtonKind::Destructive
                                    } else {
                                        ButtonKind::Filled
                                    },
                                    self.sidebar_action_busy,
                                    self.sidebar_action_busy,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.submit_sidebar_dialog(cx);
                                })),
                            ),
                    ),
            )
            .when_some(tag_to_delete, |overlay, name| {
                overlay.child(
                    div()
                        .absolute()
                        .top_0()
                        .right_0()
                        .bottom_0()
                        .left_0()
                        .occlude()
                        .flex()
                        .items_center()
                        .justify_center()
                        .bg(theme::overlay_scrim())
                        .child(
                            design_system::dialog_shell(
                                "delete-tag-dialog",
                                "Delete Tag",
                                420.0,
                            )
                                .child(
                                    div()
                                        .text_size(px(14.0))
                                        .font_weight(gpui::FontWeight::MEDIUM)
                                        .child("Delete Tag"),
                                )
                                .child(
                                    div()
                                        .mt_3()
                                        .text_size(px(13.0))
                                        .text_color(theme::text_muted())
                                        .child(format!(
                                            "Delete The Tag \"#{name}\"? It Will Be Removed From Every Workspace That Uses It."
                                        )),
                                )
                                .child(
                                    div()
                                        .mt(px(20.0))
                                        .flex()
                                        .gap_2()
                                        .child(
                                            design_system::button(
                                                "sidebar-cancel-delete-tag",
                                                "Cancel",
                                                ButtonKind::Text,
                                                self.sidebar_action_busy,
                                            )
                                            .flex_1()
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.cancel_sidebar_tag_delete(cx);
                                            })),
                                        )
                                        .child(
                                            design_system::button(
                                                "sidebar-confirm-delete-tag",
                                                "Delete",
                                                ButtonKind::Destructive,
                                                self.sidebar_action_busy,
                                            )
                                            .flex_1()
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.delete_sidebar_tag(cx);
                                            })),
                                        ),
                                ),
                        ),
                )
            })
            .into_any_element()
    }
}

fn format_workspace_storage_bytes(bytes: u64) -> String {
    if bytes >= 1024 * 1024 * 1024 {
        format!("{:.1} GB", bytes as f64 / (1024.0 * 1024.0 * 1024.0))
    } else if bytes >= 1024 * 1024 {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    } else if bytes >= 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{bytes} B")
    }
}

fn format_workspace_storage_timestamp(value: &str) -> String {
    DateTime::parse_from_rfc3339(value)
        .map(|value| {
            value
                .with_timezone(&Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
        .unwrap_or_else(|_| value.to_string())
}

fn workspace_parent_label(
    snapshot: &crate::model::WorkbenchSnapshot,
    workspace_id: &str,
) -> Option<String> {
    let project = snapshot.project_for_workspace(workspace_id)?;
    let workspace = snapshot.workspace(workspace_id)?;
    let branch = workspace
        .branch
        .as_deref()
        .filter(|branch| !branch.is_empty())
        .map(|branch| format!(" - {branch}"))
        .unwrap_or_default();
    Some(format!("{} / {}{}", project.name, workspace.name, branch))
}

fn workspace_descendant_ids(
    workspace_id: &str,
    relations: &[crate::model::WorkspaceRelation],
) -> std::collections::BTreeSet<String> {
    let mut descendants = std::collections::BTreeSet::new();
    let mut pending = vec![workspace_id.to_string()];
    while let Some(parent_id) = pending.pop() {
        for relation in relations {
            if relation.parent_workspace_id == parent_id
                && descendants.insert(relation.child_workspace_id.clone())
            {
                pending.push(relation.child_workspace_id.clone());
            }
        }
    }
    descendants
}

fn parent_option(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
    selected: bool,
    disabled: bool,
) -> gpui::Stateful<gpui::Div> {
    let label = label.into();
    div()
        .id(id)
        .focusable()
        .tab_stop(!disabled)
        .role(Role::ListBoxOption)
        .aria_label(label.clone())
        .aria_selected(selected)
        .flex()
        .items_center()
        .h(px(32.0))
        .px_2()
        .gap_2()
        .rounded_md()
        .text_color(if disabled {
            theme::text_faint()
        } else {
            theme::text()
        })
        .when(!disabled, |row| {
            row.cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface()))
        })
        .child(div().w(px(16.0)).when(selected, |marker| {
            marker.child(icon(AleraIcon::Check, 14.0, theme::accent()))
        }))
        .child(label)
}

fn sidebar_menu_shell(
    id: &'static str,
    label: &'static str,
    position: Point<Pixels>,
    viewport: Size<Pixels>,
    height: Pixels,
) -> gpui::Stateful<gpui::Div> {
    let width = px(220.0);
    let left = position.x.clamp(px(8.0), viewport.width - width - px(8.0));
    let top = position
        .y
        .clamp(px(8.0), viewport.height - height - px(8.0));
    div()
        .id(id)
        .role(Role::Menu)
        .aria_label(label)
        .absolute()
        .top(top)
        .left(left)
        .w(width)
        .rounded_lg()
        .border_1()
        .border_color(theme::border())
        .bg(theme::surface_raised())
        .shadow_lg()
        .p_1()
}

fn sidebar_menu_button(
    id: &'static str,
    icon_kind: AleraIcon,
    label: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::MenuItem)
        .aria_label(label)
        .flex()
        .items_center()
        .h(px(30.0))
        .px_2()
        .gap_2()
        .rounded_md()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface()))
        .child(icon(icon_kind, 16.0, theme::text_muted()))
        .child(label)
}

fn sidebar_menu_divider() -> gpui::Div {
    div().h(px(1.0)).my_1().bg(theme::border_subtle())
}
