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

fn picker_label(label: &'static str) -> gpui::Div {
    div().mb(px(8.0)).text_size(px(11.0)).line_height(px(16.0)).font_weight(gpui::FontWeight::MEDIUM).text_color(theme::text_muted()).child(label)
}

fn picker_list(id: &'static str, height: f32) -> gpui::Stateful<gpui::Div> {
    div().id(id).w_full().min_w_0().mt(px(8.0)).max_h(px(height)).overflow_y_scroll().rounded(px(6.0))
        .border_1().border_color(theme::border_subtle()).bg(theme::surface_selected())
}

fn picker_empty(message: String) -> gpui::Div {
    div().p(px(24.0)).text_size(px(12.0)).text_color(theme::text_muted()).child(message)
}

impl AleraApp {
    pub(super) fn render_workspace_selection(&self, window: &gpui::Window, cx: &mut Context<Self>) -> AnyElement {
        let project_query = self.workspace_project_search_input.read(cx).value().trim().to_lowercase();
        let projects = self.manual_workspace_project_rows(&project_query, cx);
        let branch_query = self.workspace_branch_search_input.read(cx).value().trim().to_lowercase();
        let branch_rows = self.manual_workspace_branch_rows(&branch_query, cx);
        let manual_source = self.manual_workspace_source_required();
        let branch_label = if self.workspace_reuse_existing_branch { "Existing Branch" } else { "Source Branch" };
        let empty_branch = format!("No {} branches match \"{branch_query}\"", if self.workspace_reuse_existing_branch { "existing" } else { "source" });
        let body = div().w_full().min_w_0()
            .child(picker_label("Project"))
            .child(design_system::search_field(&self.workspace_project_search_input, false))
            .child(picker_list("workspace-project-list", 200.0)
                .when(projects.is_empty(), |list| list.child(picker_empty(format!("No projects match \"{project_query}\""))))
                .children(projects))
            .child(self.manual_workspace_branch_mode(cx))
            .when(self.workspace_branches_loading, |body| body.child(div().mt(px(16.0)).h(px(72.0)).flex().items_center().justify_center().gap(px(8.0))
                .child(loading_indicator(14.0, theme::text_muted())).child("Loading source branches")))
            .when(manual_source, |body| body.child(div().mt(px(16.0))
                .child(design_system::text_field(&self.workspace_manual_source_input).label(branch_label)))
                .when(self.error.is_some(),|body|body.child(secondary_button("retry-workspace-branches","Retry")
                    .on_click(cx.listener(|this,_,_,cx|{
                        if let Some(project_id)=this.selected_workspace_project_id.clone() {this.load_workspace_branches(project_id,cx);}
                    })))))
            .when(!self.workspace_branches_loading && !manual_source, |body| body
                .child(picker_label(branch_label).mt(px(16.0)))
                .child(design_system::search_field(&self.workspace_branch_search_input, false))
                .child(picker_list("source-branch-list", 240.0)
                    .when(branch_rows.is_empty(), |list| list.child(picker_empty(empty_branch)))
                    .children(branch_rows)))
            .when_some(self.error.clone(), |body, error| body.child(div().mt(px(8.0)).text_size(px(12.0)).text_color(theme::danger()).child(error)));
        div().id("new-workspace-selection-dialog").role(Role::Dialog).aria_label("New Workspace - Selection")
            .w(px(680.0).min((window.viewport_size().width-px(64.0)).max(px(100.0))))
            .max_h(px(740.0).min((window.viewport_size().height-px(64.0)).max(px(100.0))))
            .flex().flex_col().rounded(px(12.0)).border_1().border_color(theme::border_subtle())
            .bg(theme::surface()).shadow_lg().p(px(19.0))
            .child(self.workspace_dialog_header("New Workspace - Selection", Some("Step 1 of 2"), false, cx))
            .child(div().id("workspace-selection-scroll").mt(px(16.0)).min_h_0().overflow_y_scroll().child(body))
            .child(div().flex().items_center().justify_end().flex_shrink_0().gap(px(8.0)).mt(px(16.0))
                .child(secondary_button("cancel-workspace-selection", "Cancel")
                    .on_click(cx.listener(|this, _, _, cx| this.close_new_workspace_dialog(cx))))
                .child(primary_button("continue-workspace-settings", "Continue",
                    self.workspace_branches_loading || self.selected_workspace_source_branch.is_none())
                    .on_click(cx.listener(|this, _, window, cx| this.continue_manual_workspace_settings(window, cx)))))
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
                        .disabled(self.workspace_reuse_existing_branch || self.workspace_creation_busy),
                ),
            )
            .when(branch_exists, |dialog| {
                dialog.child(
                    div()
                        .mt_1()
                        .text_size(crate::theme::body_size())
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
                                .label("Workspace Name (Optional)").disabled(self.workspace_creation_busy),
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
                                .text_size(crate::theme::caption_size())
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
                    .text_size(crate::theme::caption_size())
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
                        .text_size(crate::theme::body_size())
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
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.create_workspace(window,cx);
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
        .text_size(crate::theme::body_size())
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
