use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _, Toggled,
};

use super::dialogs::{
    check_box, form_label, primary_button, primary_button_with_loading, secondary_button,
};
use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_workspace_selection(&self, cx: &mut Context<Self>) -> AnyElement {
        let project_query = self
            .workspace_project_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let projects = self.manual_workspace_project_rows(&project_query, cx);
        let branch_query = self
            .workspace_branch_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let branch_rows = self.manual_workspace_branch_rows(&branch_query, cx);
        let branch_picker_label = if self.workspace_reuse_existing_branch {
            "Existing Branch"
        } else {
            "Source Branch"
        };
        let empty_branch_message = if self.workspace_branches_loading {
            "Loading Branches".to_owned()
        } else if self.workspace_reuse_existing_branch {
            format!("No Existing Branches Match \"{branch_query}\"")
        } else {
            format!("No Source Branches Match \"{branch_query}\"")
        };

        div()
            .id("new-workspace-selection-dialog")
            .role(Role::Dialog)
            .aria_label("New Workspace - Selection")
            .w(px(690.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .px_4()
            .py(px(27.0))
            .child(self.workspace_dialog_header(
                "New Workspace - Selection",
                Some("Step 1 of 2"),
                false,
                cx,
            ))
            .child(form_label("Project").mt_5().mb_2())
            .child(design_system::search_field(
                &self.workspace_project_search_input,
                false,
            ))
            .child(
                div()
                    .mt_2()
                    .when(projects.is_empty(), |list| {
                        list.child(
                            div()
                                .h(px(36.0))
                                .flex()
                                .items_center()
                                .px_2()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child("No Matching Projects"),
                        )
                    })
                    .children(projects),
            )
            .child(
                div()
                    .flex()
                    .mt_4()
                    .w(px(186.0))
                    .h(px(32.0))
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .id("workspace-new-branch-mode")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::RadioButton)
                            .aria_label("New Branch")
                            .aria_selected(!self.workspace_reuse_existing_branch)
                            .aria_toggled(if self.workspace_reuse_existing_branch {
                                Toggled::False
                            } else {
                                Toggled::True
                            })
                            .flex_1()
                            .h_full()
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .when(!self.workspace_reuse_existing_branch, |button| {
                                button.bg(theme::surface_selected())
                            })
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.set_workspace_reuse_existing_branch(false, window, cx);
                            }))
                            .child("New Branch"),
                    )
                    .child(
                        div()
                            .id("workspace-existing-branch-mode")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::RadioButton)
                            .aria_label("Existing Branch")
                            .aria_selected(self.workspace_reuse_existing_branch)
                            .aria_toggled(if self.workspace_reuse_existing_branch {
                                Toggled::True
                            } else {
                                Toggled::False
                            })
                            .flex_1()
                            .h_full()
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .when(self.workspace_reuse_existing_branch, |button| {
                                button.bg(theme::surface_selected())
                            })
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.set_workspace_reuse_existing_branch(true, window, cx);
                            }))
                            .child("Existing Branch"),
                    ),
            )
            .child(form_label(branch_picker_label).mb_2())
            .child(design_system::search_field(
                &self.workspace_branch_search_input,
                false,
            ))
            .child(
                div()
                    .id("source-branch-list")
                    .mt_2()
                    .max_h(px(180.0))
                    .overflow_y_scroll()
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .when(branch_rows.is_empty(), |list| {
                        list.child(
                            div()
                                .h(px(32.0))
                                .flex()
                                .items_center()
                                .px_2()
                                .gap_2()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .when(self.workspace_branches_loading, |row| {
                                    row.child(loading_indicator(14.0, theme::text_muted()))
                                })
                                .child(empty_branch_message),
                        )
                    })
                    .children(branch_rows),
            )
            .when_some(self.error.clone(), |dialog, error| {
                dialog.child(
                    div()
                        .mt_2()
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
                    .mt_4()
                    .child(
                        secondary_button("cancel-workspace-selection", "Cancel").on_click(
                            cx.listener(|this, _, _, cx| this.close_new_workspace_dialog(cx)),
                        ),
                    )
                    .child(
                        primary_button(
                            "continue-workspace-settings",
                            "Continue",
                            self.workspace_branches_loading
                                || self.selected_workspace_source_branch.is_none(),
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.continue_manual_workspace_settings(window, cx);
                        })),
                    ),
            )
            .into_any_element()
    }

    pub(super) fn render_workspace_settings(&self, cx: &mut Context<Self>) -> AnyElement {
        let selected_project = self.selected_workspace_project();
        let project = selected_project
            .map(|project| project.name.clone())
            .unwrap_or_else(|| "Project".to_string());
        let source_branch = self
            .selected_workspace_source_branch
            .clone()
            .unwrap_or_else(|| "main".to_string());
        let branch = self
            .workspace_branch_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        let target_branch = if self.workspace_reuse_existing_branch {
            source_branch.clone()
        } else {
            branch.clone()
        };
        let preview_branch = if target_branch.is_empty() {
            "<new-branch>".to_string()
        } else {
            target_branch.clone()
        };
        let name = self
            .workspace_name_input
            .read(cx)
            .value()
            .trim()
            .to_string();
        let project_slug = slugify(&project);
        let workspace_slug = slugify(if name.is_empty() {
            if target_branch.is_empty() {
                "workspace"
            } else {
                target_branch.as_str()
            }
        } else {
            name.as_str()
        });
        let project_id = selected_project
            .map(|project| project.id.as_str())
            .unwrap_or("project");
        let preview_path =
            format!("~/.alera/workspaces/{project_slug}-{project_id}/{workspace_slug}");
        let branch_exists = !self.workspace_reuse_existing_branch
            && !branch.is_empty()
            && self
                .workspace_source_branches
                .iter()
                .any(|candidate| candidate == &branch);
        let parent_label = self.workspace_parent_label();
        let branch_summary_label = if self.workspace_reuse_existing_branch {
            "Existing Branch:"
        } else {
            "Source Branch:"
        };
        let branch_input_label = if self.workspace_reuse_existing_branch {
            "Existing Branch *"
        } else {
            "New Branch Name *"
        };

        div()
            .id("new-workspace-settings-dialog")
            .role(Role::Dialog)
            .aria_label("New Workspace - Settings")
            .w(px(570.0))
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .px_4()
            .py(px(32.5))
            .child(self.workspace_dialog_header(
                "New Workspace - Settings",
                Some("Step 2 of 2"),
                true,
                cx,
            ))
            .child(
                div()
                    .mt_3()
                    .rounded_md()
                    .bg(theme::surface())
                    .p_3()
                    .child(summary_row("Project:", project.clone()))
                    .child(summary_row(branch_summary_label, source_branch.clone())),
            )
            .child(
                div().mt_4().child(
                    design_system::text_field(&self.workspace_branch_input)
                        .label(branch_input_label)
                        .disabled(self.workspace_reuse_existing_branch),
                ),
            )
            .when(branch_exists, |dialog| {
                dialog.child(
                    div()
                        .mt_1()
                        .text_sm()
                        .text_color(theme::danger())
                        .child(format!("Branch \"{branch}\" Already Exists")),
                )
            })
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .mt_3()
                    .child(
                        div().flex_1().child(
                            design_system::text_field(&self.workspace_name_input)
                                .label("Workspace Name (Optional)"),
                        ),
                    )
                    .when(!name.is_empty() && name == target_branch, |row| {
                        row.child(
                            div()
                                .flex()
                                .items_center()
                                .gap_1()
                                .px_2()
                                .py_1()
                                .rounded_sm()
                                .border_1()
                                .border_color(theme::accent())
                                .text_xs()
                                .text_color(theme::accent())
                                .child(icon(AleraIcon::Link, 10.0, theme::accent()))
                                .child("Sync"),
                        )
                    }),
            )
            .child(form_label("Parent Workspace"))
            .child(self.workspace_prompt_select_field(
                "manual-workspace-parent",
                parent_label.clone(),
                super::workspace_prompt_dropdown::WorkspacePromptDropdown::ParentWorkspace,
                cx,
            ))
            .child(form_label("Preview"))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_2()
                    .min_h(px(90.0))
                    .rounded_md()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .p_3()
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .child(icon(AleraIcon::FolderOpen, 13.0, theme::text_muted()))
                            .child(div().overflow_hidden().text_ellipsis().child(preview_path)),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .child(icon(AleraIcon::GitBranch, 13.0, theme::text_muted()))
                            .child(if self.workspace_reuse_existing_branch {
                                format!("Branch: {preview_branch}")
                            } else {
                                format!("Branch: {preview_branch} From {source_branch}")
                            }),
                    )
                    .when(self.workspace_selected_parent_id.is_some(), |preview| {
                        preview.child(
                            div()
                                .flex()
                                .items_center()
                                .gap_2()
                                .child(icon(AleraIcon::Link, 13.0, theme::text_muted()))
                                .child(format!("Parent: {parent_label}")),
                        )
                    })
                    .child(">_ Initial Terminal Tab Will Be Opened"),
            )
            .child(
                div()
                    .id("create-another-manual-workspace")
                    .focusable()
                    .tab_stop(true)
                    .role(Role::CheckBox)
                    .aria_label("Create Another")
                    .aria_selected(self.create_another_workspace)
                    .aria_toggled(if self.create_another_workspace {
                        Toggled::True
                    } else {
                        Toggled::False
                    })
                    .flex()
                    .items_center()
                    .gap_2()
                    .mt_4()
                    .cursor(CursorStyle::PointingHand)
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.toggle_create_another_workspace(cx);
                    }))
                    .child(check_box(self.create_another_workspace))
                    .child("Create Another"),
            )
            .when_some(self.error.clone(), |dialog, error| {
                dialog.child(
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
                    .mt_4()
                    .child(
                        secondary_button("back-workspace-selection", "Back").on_click(cx.listener(
                            |this, _, _, cx| {
                                this.back_new_workspace(cx);
                            },
                        )),
                    )
                    .child(
                        primary_button_with_loading(
                            "create-workspace",
                            if self.workspace_creation_busy {
                                "Creating"
                            } else {
                                "Create Workspace"
                            },
                            target_branch.is_empty()
                                || branch_exists
                                || self.workspace_creation_busy,
                            self.workspace_creation_busy,
                        )
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.create_workspace(cx);
                        })),
                    ),
            )
            .into_any_element()
    }
}

fn summary_row(label: &'static str, value: String) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .text_sm()
        .child(
            div()
                .w(px(116.0))
                .text_color(theme::text_muted())
                .child(label),
        )
        .child(div().font_weight(gpui::FontWeight::MEDIUM).child(value))
}

fn slugify(value: &str) -> String {
    let mut result = String::new();
    let mut separator = false;
    for character in value.trim().to_lowercase().chars() {
        if character.is_ascii_alphanumeric() {
            result.push(character);
            separator = false;
        } else if !separator && !result.is_empty() {
            result.push('-');
            separator = true;
        }
    }
    while result.ends_with('-') {
        result.pop();
    }
    result
}
