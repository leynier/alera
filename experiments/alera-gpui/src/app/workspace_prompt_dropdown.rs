use gpui::{
    deferred, div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};

use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, AleraIcon};
use crate::theme;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum WorkspacePromptDropdown {
    Project,
    SourceBranch,
    ParentWorkspace,
    AgentProfile,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AgentProfileOption {
    pub id: String,
    pub name: String,
}

impl AleraApp {
    pub(super) fn workspace_prompt_select_field(
        &self,
        id: &'static str,
        value: String,
        dropdown: WorkspacePromptDropdown,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let expanded = self.workspace_prompt_dropdown == Some(dropdown);
        let container_id = match dropdown {
            WorkspacePromptDropdown::Project => "workspace-project-select-container",
            WorkspacePromptDropdown::SourceBranch => "workspace-branch-select-container",
            WorkspacePromptDropdown::ParentWorkspace => "workspace-parent-select-container",
            WorkspacePromptDropdown::AgentProfile => "workspace-profile-select-container",
        };
        div()
            .id(container_id)
            .relative()
            .h(px(34.0))
            .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                this.workspace_prompt_dropdown = None;
                cx.notify();
            }))
            .child(self.workspace_prompt_select(id, value, dropdown, cx))
            .when(expanded, |field| {
                field.child(deferred(
                    self.render_workspace_prompt_dropdown(dropdown, cx),
                ))
            })
            .into_any_element()
    }

    pub(super) fn workspace_prompt_select(
        &self,
        id: &'static str,
        value: String,
        dropdown: WorkspacePromptDropdown,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let expanded = self.workspace_prompt_dropdown == Some(dropdown);
        let enabled = !self.workspace_creation_busy
            && self.workspace_prompt_created.is_none()
            && (dropdown != WorkspacePromptDropdown::SourceBranch
                || !self.workspace_branches_loading);
        let loading = match dropdown {
            WorkspacePromptDropdown::SourceBranch => self.workspace_branches_loading,
            WorkspacePromptDropdown::AgentProfile => self.workspace_profiles_loading,
            WorkspacePromptDropdown::Project | WorkspacePromptDropdown::ParentWorkspace => false,
        };
        design_system::dropdown_trigger_with_loading(id, value, expanded, enabled, loading)
            .when(enabled, |trigger| {
                trigger.on_click(cx.listener(move |this, _, window, cx| {
                    let opening = !expanded;
                    this.workspace_prompt_dropdown = opening.then_some(dropdown);
                    if opening {
                        this.workspace_dropdown_search_input
                            .update(cx, |input, cx| {
                                input.set_placeholder(
                                    match dropdown {
                                        WorkspacePromptDropdown::ParentWorkspace => {
                                            "Search Workspaces"
                                        }
                                        _ => "Search",
                                    },
                                    window,
                                    cx,
                                );
                                input.set_value("", window, cx);
                                input.focus(window, cx);
                            });
                    }
                    cx.notify();
                }))
            })
            .into_any_element()
    }

    pub(super) fn render_workspace_prompt_dropdown(
        &self,
        dropdown: WorkspacePromptDropdown,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let query = self
            .workspace_dropdown_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let menu_id = match dropdown {
            WorkspacePromptDropdown::Project => "workspace-project-dropdown",
            WorkspacePromptDropdown::SourceBranch => "workspace-source-branch-dropdown",
            WorkspacePromptDropdown::ParentWorkspace => "workspace-parent-dropdown",
            WorkspacePromptDropdown::AgentProfile => "workspace-agent-profile-dropdown",
        };
        let rows = match dropdown {
            WorkspacePromptDropdown::Project => self
                .workspace_prompt_projects()
                .into_iter()
                .filter(|project| query.is_empty() || project.name.to_lowercase().contains(&query))
                .enumerate()
                .map(|(index, project)| {
                    let project_id = project.id.clone();
                    self.workspace_prompt_option(
                        index,
                        project.name.clone(),
                        self.selected_workspace_project_id.as_deref() == Some(project.id.as_str()),
                        move |this, cx| {
                            this.select_workspace_project(project_id.clone(), cx);
                        },
                        cx,
                    )
                })
                .collect::<Vec<_>>(),
            WorkspacePromptDropdown::SourceBranch => self
                .workspace_prompt_branches()
                .into_iter()
                .filter(|branch| query.is_empty() || branch.to_lowercase().contains(&query))
                .enumerate()
                .map(|(index, branch)| {
                    let branch_value = branch.clone();
                    self.workspace_prompt_option(
                        index,
                        branch.clone(),
                        self.selected_workspace_source_branch.as_deref() == Some(branch.as_str()),
                        move |this, cx| {
                            this.select_workspace_source_branch(branch_value.clone(), cx);
                        },
                        cx,
                    )
                })
                .collect::<Vec<_>>(),
            WorkspacePromptDropdown::ParentWorkspace => {
                let no_parent = std::iter::once((None, "No Parent".to_owned()));
                let workspaces = self.workspace_parent_options().into_iter();
                no_parent
                    .chain(workspaces)
                    .filter(|(_, label)| query.is_empty() || label.to_lowercase().contains(&query))
                    .enumerate()
                    .map(|(index, (workspace_id, label))| {
                        let selected = self.workspace_selected_parent_id == workspace_id;
                        self.workspace_prompt_option(
                            index,
                            label,
                            selected,
                            move |this, cx| {
                                this.workspace_selected_parent_id = workspace_id.clone();
                                cx.notify();
                            },
                            cx,
                        )
                    })
                    .collect::<Vec<_>>()
            }
            WorkspacePromptDropdown::AgentProfile => self
                .workspace_agent_profiles
                .iter()
                .filter(|profile| query.is_empty() || profile.name.to_lowercase().contains(&query))
                .enumerate()
                .map(|(index, profile)| {
                    let profile_id = profile.id.clone();
                    self.workspace_prompt_option(
                        index,
                        profile.name.clone(),
                        self.workspace_selected_agent_profile_id.as_deref()
                            == Some(profile.id.as_str()),
                        move |this, cx| {
                            this.workspace_selected_agent_profile_id = Some(profile_id.clone());
                            cx.notify();
                        },
                        cx,
                    )
                })
                .collect::<Vec<_>>(),
        };
        div()
            .id(menu_id)
            .absolute()
            .top(px(38.0))
            .left_0()
            .right_0()
            .occlude()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface())
            .shadow_lg()
            .p_1()
            .child(design_system::search_field(
                &self.workspace_dropdown_search_input,
                true,
            ))
            .child(
                div()
                    .id("workspace-prompt-options")
                    .max_h(px(180.0))
                    .overflow_y_scroll()
                    .when(rows.is_empty(), |list| {
                        list.child(
                            div()
                                .h(px(32.0))
                                .flex()
                                .items_center()
                                .px_2()
                                .text_size(crate::theme::caption_size())
                                .text_color(theme::text_muted())
                                .child(if dropdown == WorkspacePromptDropdown::AgentProfile {
                                    "Create An Agent Profile In Settings"
                                } else {
                                    "No Matching Options"
                                }),
                        )
                    })
                    .children(rows),
            )
            .into_any_element()
    }

    fn workspace_prompt_option(
        &self,
        index: usize,
        label: String,
        selected: bool,
        on_select: impl Fn(&mut AleraApp, &mut Context<AleraApp>) + 'static,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .id(("workspace-prompt-option", index))
            .focusable()
            .tab_stop(true)
            .role(Role::ListBoxOption)
            .aria_label(label.clone())
            .aria_selected(selected)
            .flex()
            .items_center()
            .h(px(30.0))
            .px_2()
            .gap_2()
            .rounded_sm()
            .text_size(crate::theme::body_size())
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface_selected()))
            .on_click(cx.listener(move |this, _, _, cx| {
                on_select(this, cx);
                this.workspace_prompt_dropdown = None;
                cx.notify();
            }))
            .child(div().w(px(14.0)).when(selected, |slot| {
                slot.child(icon(AleraIcon::Check, 13.0, theme::text()))
            }))
            .child(label)
            .into_any_element()
    }

    pub(super) fn workspace_prompt_branches(&self) -> Vec<String> {
        self.workspace_source_branches.clone()
    }

    pub(super) fn confirm_workspace_prompt_search(&mut self, cx: &mut Context<Self>) {
        let Some(dropdown) = self.workspace_prompt_dropdown else {
            return;
        };
        let query = self
            .workspace_dropdown_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        match dropdown {
            WorkspacePromptDropdown::Project => {
                if let Some(project_id) = self
                    .workspace_prompt_projects()
                    .into_iter()
                    .find(|project| {
                        query.is_empty() || project.name.to_lowercase().contains(&query)
                    })
                    .map(|project| project.id.clone())
                {
                    self.select_workspace_project(project_id, cx);
                }
            }
            WorkspacePromptDropdown::SourceBranch => {
                if let Some(branch) = self
                    .workspace_prompt_branches()
                    .into_iter()
                    .find(|branch| query.is_empty() || branch.to_lowercase().contains(&query))
                {
                    self.select_workspace_source_branch(branch, cx);
                }
            }
            WorkspacePromptDropdown::ParentWorkspace => {
                self.workspace_selected_parent_id = if query.is_empty() {
                    None
                } else {
                    self.workspace_parent_options()
                        .into_iter()
                        .find(|(_, label)| label.to_lowercase().contains(&query))
                        .and_then(|(workspace_id, _)| workspace_id)
                };
            }
            WorkspacePromptDropdown::AgentProfile => {
                self.workspace_selected_agent_profile_id = self
                    .workspace_agent_profiles
                    .iter()
                    .find(|profile| {
                        query.is_empty() || profile.name.to_lowercase().contains(&query)
                    })
                    .map(|profile| profile.id.clone());
            }
        }
        self.workspace_prompt_dropdown = None;
        cx.notify();
    }

    pub(super) fn workspace_parent_label(&self) -> String {
        let Some(parent_id) = self.workspace_selected_parent_id.as_deref() else {
            return "No Parent".to_owned();
        };
        self.snapshot
            .projects
            .iter()
            .find_map(|project| {
                project
                    .workspaces
                    .iter()
                    .find(|workspace| workspace.id == parent_id)
                    .map(|workspace| {
                        let suffix = workspace
                            .branch
                            .as_deref()
                            .filter(|branch| !branch.is_empty())
                            .map(|branch| format!(" - {branch}"))
                            .unwrap_or_default();
                        format!("{} / {}{}", project.name, workspace.name, suffix)
                    })
            })
            .unwrap_or_else(|| "No Parent".to_owned())
    }

    pub(super) fn workspace_prompt_projects(&self) -> Vec<&crate::model::Project> {
        let mut projects = self
            .snapshot
            .projects
            .iter()
            .filter(|project| project.kind == "gitRepository")
            .collect::<Vec<_>>();
        projects.sort_by(|left, right| {
            left.name
                .to_lowercase()
                .cmp(&right.name.to_lowercase())
                .then_with(|| left.name.cmp(&right.name))
                .then_with(|| left.id.cmp(&right.id))
        });
        projects
    }

    pub(super) fn workspace_parent_options(&self) -> Vec<(Option<String>, String)> {
        let preferred_project_id = self.selected_workspace_project_id.as_deref();
        let mut workspaces = self
            .snapshot
            .projects
            .iter()
            .flat_map(|project| {
                project
                    .workspaces
                    .iter()
                    .filter(|workspace| workspace.status == "active")
                    .map(move |workspace| (project, workspace))
            })
            .collect::<Vec<_>>();
        workspaces.sort_by(|(left_project, left), (right_project, right)| {
            let left_preferred = Some(left_project.id.as_str()) == preferred_project_id;
            let right_preferred = Some(right_project.id.as_str()) == preferred_project_id;
            right_preferred
                .cmp(&left_preferred)
                .then_with(|| {
                    left_project
                        .name
                        .to_lowercase()
                        .cmp(&right_project.name.to_lowercase())
                })
                .then_with(|| left_project.name.cmp(&right_project.name))
                .then_with(|| left_project.id.cmp(&right_project.id))
                .then_with(|| (right.kind == "main").cmp(&(left.kind == "main")))
                .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
                .then_with(|| left.name.cmp(&right.name))
                .then_with(|| left.id.cmp(&right.id))
        });
        workspaces
            .into_iter()
            .map(|(project, workspace)| {
                let suffix = workspace
                    .branch
                    .as_deref()
                    .filter(|branch| !branch.is_empty())
                    .map(|branch| format!(" - {branch}"))
                    .unwrap_or_default();
                (
                    Some(workspace.id.clone()),
                    format!("{} / {}{}", project.name, workspace.name, suffix),
                )
            })
            .collect()
    }

    pub(super) fn workspace_agent_profile_label(&self) -> String {
        self.workspace_selected_agent_profile_id
            .as_deref()
            .and_then(|selected| {
                self.workspace_agent_profiles
                    .iter()
                    .find(|profile| profile.id == selected)
            })
            .map(|profile| profile.name.clone())
            .unwrap_or_else(|| {
                if self.workspace_profiles_loading {
                    "Loading Agent Profiles".to_owned()
                } else {
                    "Create An Agent Profile In Settings".to_owned()
                }
            })
    }
}
