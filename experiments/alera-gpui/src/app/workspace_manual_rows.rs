use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Toggled,
};

use super::dialogs::radio;
use super::AleraApp;
use crate::theme;

impl AleraApp {
    pub(super) fn manual_workspace_project_rows(
        &self,
        query: &str,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        self.snapshot
            .projects
            .iter()
            .filter(|project| project.kind == "gitRepository")
            .filter(|project| query.is_empty() || project.name.to_lowercase().contains(query))
            .map(|project| {
                let project_id = project.id.clone();
                let selected =
                    self.selected_workspace_project_id.as_deref() == Some(project.id.as_str());
                let branch = project
                    .workspaces
                    .iter()
                    .find_map(|workspace| workspace.branch.as_deref())
                    .unwrap_or("HEAD");
                div()
                    .id(SharedString::from(format!(
                        "workspace-project-choice-{}",
                        project.id
                    )))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::RadioButton)
                    .aria_label(project.name.clone())
                    .aria_selected(selected)
                    .aria_toggled(if selected {
                        Toggled::True
                    } else {
                        Toggled::False
                    })
                    .flex()
                    .items_center()
                    .h(px(48.0))
                    .px_2()
                    .gap_2()
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .when(selected, |row| row.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.select_workspace_project(project_id.clone(), cx);
                    }))
                    .child(radio(selected))
                    .child(
                        div()
                            .child(
                                div()
                                    .text_size(crate::theme::body_size())
                                    .font_weight(gpui::FontWeight::SEMIBOLD)
                                    .child(project.name.clone()),
                            )
                            .child(
                                div()
                                    .text_size(crate::theme::caption_size())
                                    .text_color(theme::text_faint())
                                    .child(format!("{}  •  ({branch})", project.repo_path)),
                            ),
                    )
                    .into_any_element()
            })
            .collect()
    }

    pub(super) fn manual_workspace_branch_rows(
        &self,
        query: &str,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let branches = if self.workspace_reuse_existing_branch {
            self.available_local_workspace_branches()
        } else {
            self.workspace_source_branches.clone()
        };
        branches
            .into_iter()
            .filter(|branch| query.is_empty() || branch.to_lowercase().contains(query))
            .map(|branch| {
                let selected = self.selected_workspace_source_branch.as_deref() == Some(&branch);
                let branch_value = branch.clone();
                let default = matches!(
                    branch.as_str(),
                    "main" | "origin/main" | "master" | "origin/master"
                );
                div()
                    .id(SharedString::from(format!(
                        "workspace-source-branch-{branch}"
                    )))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::RadioButton)
                    .aria_label(branch.clone())
                    .aria_selected(selected)
                    .aria_toggled(if selected {
                        Toggled::True
                    } else {
                        Toggled::False
                    })
                    .flex()
                    .items_center()
                    .h(px(30.0))
                    .px_2()
                    .gap_2()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_selected()))
                    .when(selected, |row| row.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.select_manual_workspace_source_branch(
                            branch_value.clone(),
                            window,
                            cx,
                        );
                    }))
                    .child(radio(selected))
                    .child(if default {
                        format!("{branch} (default)")
                    } else {
                        branch
                    })
                    .into_any_element()
            })
            .collect()
    }
}
