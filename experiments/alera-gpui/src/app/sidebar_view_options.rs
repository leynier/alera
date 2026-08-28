use std::cmp::Ordering;

use gpui::{
    div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    IntoElement, MouseButton, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::scroll::ScrollableElement as _;

use super::sidebar_view_options_components::{
    available_filter_row, check_row, clear_button, empty_filter_message, filter_header,
    section_label, segment_button, selected_filter_chip, sidebar_sort_label, sort_row,
};
use super::{AleraApp, SidebarGroupBy, SidebarSortTarget, SidebarWorkspaceKind};
use crate::{
    design_system,
    icons::{icon, AleraIcon},
    model::{Project, Workspace},
    theme,
};

impl AleraApp {
    pub(super) fn sidebar_workspace_visible(&self, workspace: &Workspace) -> bool {
        let kind_visible = match self.sidebar_workspace_kind {
            SidebarWorkspaceKind::All => true,
            SidebarWorkspaceKind::DefaultOnly => workspace.kind == "main",
            SidebarWorkspaceKind::NonDefaultOnly => workspace.kind != "main",
        };
        kind_visible
            && (self.sidebar_view_selected_tag_ids.is_empty()
                || workspace
                    .tag_ids
                    .iter()
                    .any(|tag| self.sidebar_view_selected_tag_ids.contains(tag))
                || workspace.tag_names.iter().any(|name| {
                    self.sidebar_view_selected_tag_ids
                        .contains(&format!("tag-name:{name}"))
                }))
    }

    pub(super) fn render_sidebar_view_options(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let project_sort_label = sidebar_sort_label(self.sidebar_project_sort);
        let workspace_sort_label = sidebar_sort_label(self.sidebar_workspace_sort);
        let selected_project_count = self.sidebar_selected_project_ids.len();
        let selected_tag_count = self.sidebar_view_selected_tag_ids.len();
        let project_query = self
            .sidebar_project_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let tag_query = self
            .sidebar_view_tag_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let mut selected_projects = self
            .snapshot
            .projects
            .iter()
            .filter(|project| self.sidebar_selected_project_ids.contains(&project.id))
            .collect::<Vec<_>>();
        let mut available_projects = self
            .snapshot
            .projects
            .iter()
            .filter(|project| !self.sidebar_selected_project_ids.contains(&project.id))
            .filter(|project| {
                project_query.is_empty() || project.name.to_lowercase().contains(&project_query)
            })
            .collect::<Vec<_>>();
        // Flutter keeps project selection deterministic and alphabetic even
        // when the sidebar itself is sorted by recency or activity.
        selected_projects.sort_by(compare_project_selection);
        available_projects.sort_by(compare_project_selection);
        let selected_tags = self
            .snapshot
            .tags
            .iter()
            .filter(|tag| self.sidebar_view_selected_tag_ids.contains(&tag.id))
            .collect::<Vec<_>>();
        let available_tags = self
            .snapshot
            .tags
            .iter()
            .filter(|tag| !self.sidebar_view_selected_tag_ids.contains(&tag.id))
            .filter(|tag| tag_query.is_empty() || tag.name.to_lowercase().contains(&tag_query))
            .collect::<Vec<_>>();
        // Flutter's intrinsic panel replaces selected rows with one chip
        // wrap (chip + spacing) and removes those entries from the available
        // list. Mirror that net height change instead of adding space for a
        // selection, which would make the dialog visibly too tall.
        // The Project grouping has one additional sort row. Flutter's
        // intrinsic dialog grows by about 34 logical pixels for that row;
        // keeping the same height here preserves the centered bounds instead
        // of forcing the extra content into a shorter scroll viewport.
        let dialog_height = 562.0
            + if self.sidebar_group_by == SidebarGroupBy::Project {
                34.0
            } else {
                0.0
            }
            + selected_filter_height_delta(selected_project_count, available_projects.len())
            + selected_filter_height_delta(selected_tag_count, available_tags.len());

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
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.close_sidebar_view_options(cx);
                }),
            )
            .child(
                div()
                    .id("sidebar-view-options-dialog")
                    .role(Role::Dialog)
                    .aria_label("View Options")
                    .w(px(460.0))
                    .h(px(dialog_height))
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border())
                    .bg(theme::surface_raised())
                    .shadow_lg()
                    .p_4()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .h(px(32.0))
                            .child(
                                div()
                                    .flex_1()
                                    .text_lg()
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child("View Options"),
                            )
                            .child(
                                div()
                                    .id("close-sidebar-view-options")
                                    .focusable()
                                    .tab_stop(true)
                                    .role(Role::Button)
                                    .aria_label("Close")
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(28.0))
                                    .h(px(28.0))
                                    .rounded_md()
                                    .cursor(CursorStyle::PointingHand)
                                    .hover(|style| style.bg(theme::surface()))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.close_sidebar_view_options(cx);
                                    }))
                                    .child(icon(AleraIcon::Close, 16.0, theme::text_muted())),
                            ),
                    )
                    .child(
                        div()
                            .mt_2()
                            .max_h(px(dialog_height - 12.0))
                            .overflow_y_scrollbar()
                            .child(section_label("Group By"))
                            .child(
                                div()
                                    .flex()
                                    .mt_2()
                                    .h(px(32.0))
                                    .rounded_md()
                                    .border_1()
                                    .border_color(theme::border_subtle())
                                    .bg(theme::surface())
                                    .child(
                                        segment_button(
                                            "sidebar-group-none",
                                            "None",
                                            self.sidebar_group_by == SidebarGroupBy::None,
                                        )
                                        .on_click(
                                            cx.listener(|this, _, _, cx| {
                                                this.set_sidebar_group_by(SidebarGroupBy::None, cx);
                                            }),
                                        ),
                                    )
                                    .child(
                                        segment_button(
                                            "sidebar-group-project",
                                            "Project",
                                            self.sidebar_group_by == SidebarGroupBy::Project,
                                        )
                                        .on_click(
                                            cx.listener(|this, _, _, cx| {
                                                this.set_sidebar_group_by(
                                                    SidebarGroupBy::Project,
                                                    cx,
                                                );
                                            }),
                                        ),
                                    ),
                            )
                            .when(self.sidebar_group_by == SidebarGroupBy::Project, |panel| {
                                panel
                                    .child(
                                        div()
                                            .relative()
                                            .mt_2()
                                            .child(
                                                sort_row(
                                                    "Sort Projects By",
                                                    project_sort_label,
                                                    "project-sort-trigger",
                                                )
                                                .on_click(cx.listener(|this, _, _, cx| {
                                                    this.toggle_sidebar_sort_dropdown(
                                                        SidebarSortTarget::Project,
                                                        cx,
                                                    );
                                                })),
                                            )
                                            .when(
                                                self.sidebar_sort_dropdown
                                                    == Some(SidebarSortTarget::Project),
                                                |row| {
                                                    row.child(self.render_sort_options(
                                                        SidebarSortTarget::Project,
                                                        cx,
                                                    ))
                                                },
                                            ),
                                    )
                                    .child(
                                        div()
                                            .relative()
                                            .mt_2()
                                            .child(
                                                sort_row(
                                                    "Then Workspaces By",
                                                    workspace_sort_label,
                                                    "workspace-sort-trigger",
                                                )
                                                .on_click(cx.listener(|this, _, _, cx| {
                                                    this.toggle_sidebar_sort_dropdown(
                                                        SidebarSortTarget::Workspace,
                                                        cx,
                                                    );
                                                })),
                                            )
                                            .when(
                                                self.sidebar_sort_dropdown
                                                    == Some(SidebarSortTarget::Workspace),
                                                |row| {
                                                    row.child(self.render_sort_options(
                                                        SidebarSortTarget::Workspace,
                                                        cx,
                                                    ))
                                                },
                                            ),
                                    )
                            })
                            .when(self.sidebar_group_by == SidebarGroupBy::None, |panel| {
                                panel.child(
                                    div()
                                        .relative()
                                        .mt_2()
                                        .child(
                                            sort_row(
                                                "Sort Workspaces By",
                                                workspace_sort_label,
                                                "workspace-sort-trigger",
                                            )
                                            .on_click(
                                                cx.listener(|this, _, _, cx| {
                                                    this.toggle_sidebar_sort_dropdown(
                                                        SidebarSortTarget::Workspace,
                                                        cx,
                                                    );
                                                }),
                                            ),
                                        )
                                        .when(
                                            self.sidebar_sort_dropdown
                                                == Some(SidebarSortTarget::Workspace),
                                            |row| {
                                                row.child(self.render_sort_options(
                                                    SidebarSortTarget::Workspace,
                                                    cx,
                                                ))
                                            },
                                        ),
                                )
                            })
                            .child(section_label("Show Workspaces").mt_3())
                            .child(
                                div()
                                    .flex()
                                    .mt_2()
                                    .h(px(32.0))
                                    .rounded_md()
                                    .border_1()
                                    .border_color(theme::border_subtle())
                                    .bg(theme::surface())
                                    .child(
                                        segment_button(
                                            "sidebar-kind-all",
                                            "All",
                                            self.sidebar_workspace_kind
                                                == SidebarWorkspaceKind::All,
                                        )
                                        .on_click(
                                            cx.listener(|this, _, _, cx| {
                                                this.set_sidebar_workspace_kind(
                                                    SidebarWorkspaceKind::All,
                                                    cx,
                                                );
                                            }),
                                        ),
                                    )
                                    .child(
                                        segment_button(
                                            "sidebar-kind-default",
                                            "Default",
                                            self.sidebar_workspace_kind
                                                == SidebarWorkspaceKind::DefaultOnly,
                                        )
                                        .on_click(
                                            cx.listener(|this, _, _, cx| {
                                                this.set_sidebar_workspace_kind(
                                                    SidebarWorkspaceKind::DefaultOnly,
                                                    cx,
                                                );
                                            }),
                                        ),
                                    )
                                    .child(
                                        segment_button(
                                            "sidebar-kind-non-default",
                                            "Non-Default",
                                            self.sidebar_workspace_kind
                                                == SidebarWorkspaceKind::NonDefaultOnly,
                                        )
                                        .on_click(
                                            cx.listener(|this, _, _, cx| {
                                                this.set_sidebar_workspace_kind(
                                                    SidebarWorkspaceKind::NonDefaultOnly,
                                                    cx,
                                                );
                                            }),
                                        ),
                                    ),
                            )
                            .child(
                                check_row(
                                    "sidebar-repeat-pinned",
                                    "Repeat Pinned Workspaces",
                                    self.sidebar_repeat_pinned,
                                )
                                .mt_2()
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.toggle_sidebar_repeat_pinned(cx);
                                    },
                                )),
                            )
                            .child(div().h(px(1.0)).my_2().bg(theme::border_subtle()))
                            .child(
                                filter_header("Projects", selected_project_count).child(
                                    clear_button(
                                        "clear-sidebar-project-filters",
                                        selected_project_count > 0,
                                    )
                                    .on_click(cx.listener(
                                        |this, _, _, cx| {
                                            this.clear_sidebar_project_filters(cx);
                                        },
                                    )),
                                ),
                            )
                            .when(!selected_projects.is_empty(), |panel| {
                                panel.child(div().flex().flex_wrap().gap_1().mt_2().children(
                                    selected_projects.iter().map(|project| {
                                        let project_id = project.id.clone();
                                        selected_filter_chip(
                                            SharedString::from(format!(
                                                "selected-project-filter-{}",
                                                project.id
                                            )),
                                            project.name.clone(),
                                        )
                                        .on_click(
                                            cx.listener(move |this, _, _, cx| {
                                                this.toggle_sidebar_project_filter(
                                                    project_id.clone(),
                                                    cx,
                                                );
                                            }),
                                        )
                                    }),
                                ))
                            })
                            .child(
                                div().mt_1().mb_2().child(design_system::dense_text_field(
                                    &self.sidebar_project_filter_input,
                                    Some(
                                        icon(AleraIcon::Add, 14.0, theme::text_faint())
                                            .into_any_element(),
                                    ),
                                )),
                            )
                            .when(available_projects.is_empty(), |panel| {
                                panel.child(empty_filter_message(if !project_query.is_empty() {
                                    format!("No Projects Match \"{project_query}\"")
                                } else if selected_project_count > 0 {
                                    "All Projects Selected".to_string()
                                } else {
                                    "No Projects Yet".to_string()
                                }))
                            })
                            .children(available_projects.iter().map(|project| {
                                let project_id = project.id.clone();
                                available_filter_row(
                                    SharedString::from(format!(
                                        "available-project-filter-{}",
                                        project.id
                                    )),
                                    project.name.clone(),
                                    None,
                                )
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.toggle_sidebar_project_filter(project_id.clone(), cx);
                                    },
                                ))
                            }))
                            .child(div().h(px(1.0)).my_3().bg(theme::border_subtle()))
                            .child(
                                filter_header("Tags", selected_tag_count).child(
                                    clear_button(
                                        "clear-sidebar-tag-filters",
                                        selected_tag_count > 0,
                                    )
                                    .on_click(cx.listener(
                                        |this, _, _, cx| {
                                            this.clear_sidebar_view_tag_filters(cx);
                                        },
                                    )),
                                ),
                            )
                            .when(!selected_tags.is_empty(), |panel| {
                                panel.child(div().flex().flex_wrap().gap_1().mt_2().children(
                                    selected_tags.iter().map(|tag| {
                                        let tag_id = tag.id.clone();
                                        selected_filter_chip(
                                            SharedString::from(format!(
                                                "selected-tag-filter-{}",
                                                tag.id
                                            )),
                                            tag.name.clone(),
                                        )
                                        .on_click(
                                            cx.listener(move |this, _, _, cx| {
                                                this.toggle_sidebar_view_tag_filter(
                                                    tag_id.clone(),
                                                    cx,
                                                );
                                            }),
                                        )
                                    }),
                                ))
                            })
                            .child(
                                div().mt_1().mb_2().child(design_system::dense_text_field(
                                    &self.sidebar_view_tag_filter_input,
                                    Some(
                                        icon(AleraIcon::Add, 14.0, theme::text_faint())
                                            .into_any_element(),
                                    ),
                                )),
                            )
                            .when(available_tags.is_empty(), |panel| {
                                panel.child(empty_filter_message(if !tag_query.is_empty() {
                                    format!("No Tags Match \"{tag_query}\"")
                                } else if selected_tag_count > 0 {
                                    "All Tags Selected".to_string()
                                } else {
                                    "No Tags Yet".to_string()
                                }))
                            })
                            .children(available_tags.iter().map(|tag| {
                                let tag_id = tag.id.clone();
                                available_filter_row(
                                    SharedString::from(format!("available-tag-filter-{}", tag.id)),
                                    tag.name.clone(),
                                    Some(AleraIcon::Tag),
                                )
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.toggle_sidebar_view_tag_filter(tag_id.clone(), cx);
                                    },
                                ))
                            })),
                    ),
            )
    }
}

pub(super) fn compare_project_selection(left: &&Project, right: &&Project) -> Ordering {
    left.name
        .to_lowercase()
        .cmp(&right.name.to_lowercase())
        .then_with(|| left.name.cmp(&right.name))
        .then_with(|| left.id.cmp(&right.id))
}

fn selected_filter_height_delta(selected_count: usize, available_count: usize) -> f32 {
    if selected_count == 0 {
        0.0
    } else {
        // One 26px chip row plus the 8px gap replaces one 30px available row
        // for each selected item.
        34.0 - selected_count as f32 * 30.0 + if available_count == 0 { 34.0 } else { 0.0 }
    }
}
