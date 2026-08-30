use std::{
    collections::{BTreeMap, BTreeSet},
    time::Duration,
};

use gpui::{
    div, prelude::FluentBuilder as _, px, Animation, AnimationExt as _, AnyElement,
    AppContext as _, ClickEvent, Context, CursorStyle, InteractiveElement as _, IntoElement as _,
    ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::tooltip::Tooltip;
use serde_json::Value;

use super::{AleraApp, SidebarGroupBy};
use crate::{
    icons::{agent_icon, icon, AgentIcon, AleraIcon},
    model::{Project, Workspace},
    theme,
};

struct SidebarWorkspacePlacement<'a> {
    workspace: &'a Workspace,
    depth: usize,
    visible_child_count: usize,
    children_collapsed: bool,
}

impl AleraApp {
    pub(super) fn render_sidebar_rows(
        &self,
        filter: &str,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let mut projects = self
            .snapshot
            .projects
            .iter()
            .filter(|project| {
                self.sidebar_selected_project_ids.is_empty()
                    || self.sidebar_selected_project_ids.contains(&project.id)
            })
            .collect::<Vec<_>>();
        self.sort_sidebar_projects(&mut projects, filter);

        let mut pinned_rows = Vec::new();
        let mut pinned_count = 0;
        for project in &projects {
            let mut pinned = self.visible_workspaces(project, filter, true, false);
            self.sort_sidebar_workspaces(&mut pinned);
            pinned_count += pinned.len();
            pinned_rows.extend(self.render_sidebar_workspace_tree_rows(
                pinned,
                Some(&project.name),
                Some(&project.kind),
                true,
                cx,
            ));
        }

        let mut rows = Vec::new();
        if pinned_count > 0 {
            rows.push(self.render_sidebar_section_header(
                "sidebar-pinned-section",
                "Pinned",
                pinned_count,
                self.sidebar_pinned_collapsed,
                AleraIcon::Pin,
                false,
                cx,
            ));
            if !self.sidebar_pinned_collapsed {
                rows.extend(pinned_rows);
            }
        }

        match self.sidebar_group_by {
            SidebarGroupBy::Project => {
                for project in projects {
                    let mut workspaces = self.visible_workspaces(
                        project,
                        filter,
                        false,
                        !self.sidebar_repeat_pinned,
                    );
                    self.sort_sidebar_workspaces(&mut workspaces);
                    if workspaces.is_empty()
                        && (!filter.is_empty()
                            || !self.sidebar_view_selected_tag_ids.is_empty()
                            || self.sidebar_workspace_kind != super::SidebarWorkspaceKind::All
                            || self.sidebar_active_only
                            || !self.sidebar_repeat_pinned)
                    {
                        continue;
                    }
                    let collapsed = self.collapsed_project_ids.contains(&project.id);
                    rows.push(self.render_sidebar_project_header(
                        project,
                        workspaces.len(),
                        collapsed,
                        cx,
                    ));
                    if collapsed && filter.is_empty() {
                        continue;
                    }
                    rows.extend(self.render_sidebar_workspace_tree_rows(
                        workspaces,
                        None,
                        Some(&project.kind),
                        false,
                        cx,
                    ));
                }
            }
            SidebarGroupBy::None => {
                let mut workspaces = projects
                    .iter()
                    .flat_map(|project| {
                        self.visible_workspaces(project, filter, false, !self.sidebar_repeat_pinned)
                            .into_iter()
                            .map(|workspace| (*project, workspace))
                    })
                    .collect::<Vec<_>>();
                self.sort_sidebar_workspace_pairs(&mut workspaces);
                let show_all_header = pinned_count > 0 && !workspaces.is_empty();
                if show_all_header {
                    rows.push(self.render_sidebar_section_header(
                        "sidebar-all-section",
                        "All",
                        workspaces.len(),
                        self.sidebar_all_collapsed,
                        AleraIcon::List,
                        true,
                        cx,
                    ));
                }
                if !show_all_header || !self.sidebar_all_collapsed || !filter.is_empty() {
                    let project_by_workspace_id = workspaces
                        .iter()
                        .map(|(project, workspace)| (workspace.id.as_str(), *project))
                        .collect::<BTreeMap<_, _>>();
                    let placements = self.workspace_tree_placements(
                        workspaces.iter().map(|(_, workspace)| *workspace).collect(),
                    );
                    for placement in placements {
                        let Some(project) =
                            project_by_workspace_id.get(placement.workspace.id.as_str())
                        else {
                            continue;
                        };
                        rows.push(self.render_sidebar_workspace_row(
                            placement.workspace,
                            Some(&project.name),
                            Some(&project.kind),
                            false,
                            placement.depth as f32 * 12.0,
                            placement.visible_child_count,
                            placement.children_collapsed,
                            cx,
                        ));
                    }
                }
            }
        }
        rows
    }

    fn render_sidebar_workspace_tree_rows(
        &self,
        workspaces: Vec<&Workspace>,
        project_name: Option<&str>,
        project_kind: Option<&str>,
        pinned_copy: bool,
        cx: &mut Context<Self>,
    ) -> Vec<AnyElement> {
        let placements = self.workspace_tree_placements(workspaces);
        placements
            .into_iter()
            .map(|placement| {
                // Flutter reserves one indentation step for the project
                // header in grouped mode. Flat and pinned lists start at the
                // sidebar content edge, so their first workspace has no
                // extra step.
                let base_indent = if project_name.is_none() && !pinned_copy {
                    12.0
                } else {
                    0.0
                };
                self.render_sidebar_workspace_row(
                    placement.workspace,
                    project_name,
                    project_kind,
                    pinned_copy,
                    base_indent + placement.depth as f32 * 12.0,
                    placement.visible_child_count,
                    placement.children_collapsed,
                    cx,
                )
            })
            .collect()
    }

    fn workspace_tree_placements<'a>(
        &self,
        workspaces: Vec<&'a Workspace>,
    ) -> Vec<SidebarWorkspacePlacement<'a>> {
        let ids = workspaces
            .iter()
            .map(|workspace| workspace.id.as_str())
            .collect::<BTreeSet<_>>();
        let mut children = BTreeMap::<&str, Vec<&Workspace>>::new();
        let mut parent_of = BTreeMap::<&str, &str>::new();
        for relation in &self.snapshot.relations {
            if relation.parent_workspace_id == relation.child_workspace_id {
                continue;
            }
            if ids.contains(relation.parent_workspace_id.as_str())
                && ids.contains(relation.child_workspace_id.as_str())
            {
                parent_of.insert(
                    relation.child_workspace_id.as_str(),
                    relation.parent_workspace_id.as_str(),
                );
            }
        }
        for workspace in &workspaces {
            if let Some(parent_id) = parent_of.get(workspace.id.as_str()) {
                children.entry(parent_id).or_default().push(*workspace);
            }
        }

        let mut placements = Vec::with_capacity(workspaces.len());
        let mut visited = BTreeSet::new();
        for workspace in &workspaces {
            if !parent_of.contains_key(workspace.id.as_str()) {
                append_workspace_tree_row(
                    workspace,
                    0,
                    &children,
                    &self.sidebar_collapsed_parent_workspace_ids,
                    &mut placements,
                    &mut visited,
                );
            }
        }
        // A stale relation cycle must not make a workspace disappear.
        for workspace in workspaces {
            if is_hidden_by_collapsed_parent(
                workspace.id.as_str(),
                &parent_of,
                &self.sidebar_collapsed_parent_workspace_ids,
            ) {
                continue;
            }
            append_workspace_tree_row(
                workspace,
                0,
                &children,
                &self.sidebar_collapsed_parent_workspace_ids,
                &mut placements,
                &mut visited,
            );
        }
        placements
    }

    fn visible_workspaces<'a>(
        &self,
        project: &'a Project,
        filter: &str,
        pinned_only: bool,
        exclude_pinned: bool,
    ) -> Vec<&'a Workspace> {
        let project_matches = filter.is_empty() || project.name.to_lowercase().contains(filter);
        project
            .workspaces
            .iter()
            .filter(|workspace| {
                self.sidebar_workspace_visible(workspace)
                    && (!pinned_only || workspace.is_pinned)
                    && (!exclude_pinned || !workspace.is_pinned)
                    && (project_matches
                        || workspace.name.to_lowercase().contains(filter)
                        || workspace
                            .branch
                            .as_deref()
                            .is_some_and(|branch| branch.to_lowercase().contains(filter))
                        || workspace
                            .source_branch
                            .as_deref()
                            .is_some_and(|branch| branch.to_lowercase().contains(filter)))
            })
            .collect()
    }

    #[allow(clippy::too_many_arguments)]
    fn render_sidebar_section_header(
        &self,
        id: &'static str,
        label: &'static str,
        count: usize,
        collapsed: bool,
        leading: AleraIcon,
        divider: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        div()
            .flex_shrink_0()
            .when(divider, |section| {
                section.border_t_1().border_color(theme::border_subtle())
            })
            .child(
                div()
                    .id(id)
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(label)
                    .aria_expanded(!collapsed)
                    .flex()
                    .items_center()
                    // Flutter wraps the 26 px content tile in 2 px vertical
                    // padding, yielding a 30 px section band.
                    .h(px(30.0))
                    .mx_2()
                    .px_2()
                    .gap_2()
                    .rounded_lg()
                    .cursor(CursorStyle::PointingHand)
                    .text_size(crate::theme::body_size())
                    .text_color(theme::text_muted())
                    .hover(|style| style.bg(theme::surface()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if id == "sidebar-pinned-section" {
                            this.toggle_pinned_section(cx);
                        } else {
                            this.sidebar_all_collapsed = !this.sidebar_all_collapsed;
                            this.persist_sidebar_view_prefs(cx);
                            cx.notify();
                        }
                    }))
                    .child(icon(leading, 14.0, theme::text_muted()))
                    .child(
                        div()
                            .flex_1()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(label),
                    )
                    .child(
                        div()
                            .text_size(crate::theme::caption_size())
                            .text_color(theme::text_faint())
                            .child(count.to_string()),
                    )
                    .child(icon(
                        if collapsed {
                            AleraIcon::ChevronDown
                        } else {
                            AleraIcon::ChevronUp
                        },
                        14.0,
                        theme::text_muted(),
                    )),
            )
            .into_any_element()
    }

    fn render_sidebar_project_header(
        &self,
        project: &Project,
        workspace_count: usize,
        collapsed: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let project_id = project.id.clone();
        let project_menu_id = project.id.clone();
        let new_workspace_project_id = project.id.clone();
        let can_create_workspace = project.kind == "gitRepository";
        div()
            .id(SharedString::from(format!("project-row-{}", project.id)))
            .flex_shrink_0()
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(project.name.clone())
            .aria_expanded(!collapsed)
            .flex()
            .items_center()
            // Keep the project header at Flutter's 26 px tile plus 2 px outer
            // padding on each side.
            .h(px(30.0))
            .mx_2()
            .px_2()
            .gap_2()
            .text_size(crate::theme::body_size())
            .text_color(theme::text_muted())
            .rounded_lg()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface()))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.toggle_project_section(project_id.clone(), cx);
            }))
            .on_aux_click(cx.listener(move |this, event: &ClickEvent, _, cx| {
                this.show_project_menu(project_menu_id.clone(), event.position(), cx);
                cx.stop_propagation();
            }))
            .child(icon(
                if collapsed {
                    AleraIcon::Folder
                } else {
                    AleraIcon::FolderOpen
                },
                16.0,
                theme::text_muted(),
            ))
            .child(
                div()
                    .flex_1()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .text_color(theme::text())
                    .child(project.name.clone()),
            )
            .child(
                div()
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::text_faint())
                    .child(workspace_count.to_string()),
            )
            .child(icon(
                if collapsed {
                    AleraIcon::ChevronDown
                } else {
                    AleraIcon::ChevronUp
                },
                14.0,
                theme::text_muted(),
            ))
            .child(
                div()
                    .id(SharedString::from(format!("project-add-{}", project.id)))
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(24.0))
                    .h(px(24.0))
                    .rounded_md()
                    .cursor(if can_create_workspace {
                        CursorStyle::PointingHand
                    } else {
                        CursorStyle::Arrow
                    })
                    .tooltip(move |_, cx| {
                        cx.new(move |_| {
                            Tooltip::new(if can_create_workspace {
                                "New Workspace in This Project"
                            } else {
                                "Add A Git Project First"
                            })
                        })
                        .into()
                    })
                    .opacity(if can_create_workspace { 1.0 } else { 0.4 })
                    .hover(|style| style.bg(theme::surface_raised()))
                    .when(can_create_workspace, |button| {
                        button
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("New Workspace in This Project")
                            .on_click(cx.listener(move |this, _, window, cx| {
                                cx.stop_propagation();
                                this.open_new_workspace_dialog(window, cx);
                                this.select_workspace_project(new_workspace_project_id.clone(), cx);
                            }))
                    })
                    .child(icon(AleraIcon::Add, 14.0, theme::text_muted())),
            )
            .into_any_element()
    }

    #[allow(clippy::too_many_arguments)]
    fn render_sidebar_workspace_row(
        &self,
        workspace: &Workspace,
        project_name: Option<&str>,
        project_kind: Option<&str>,
        pinned_copy: bool,
        indent: f32,
        visible_child_count: usize,
        children_collapsed: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let workspace_id = workspace.id.clone();
        let workspace_menu_id = workspace.id.clone();
        let selected = self.selected_workspace_id.as_deref() == Some(workspace.id.as_str());
        let indent = indent.min(48.0);
        let toggle_children_id = workspace.id.clone();
        let toggle_agents_id = workspace.id.clone();
        let agent_runs = self.sidebar_agent_runs(workspace);
        let aggregate_state = sidebar_aggregate_state(&agent_runs);
        let agents_expanded = self.sidebar_expanded_workspace_ids.contains(&workspace.id);
        let show_children_toggle = visible_child_count > 0 && !pinned_copy;
        let show_agent_toggle = !agent_runs.is_empty();
        // `tabs` is scoped to the mounted workbench.  Sidebar presence is
        // global, so use the all-workspaces projection here; otherwise every
        // non-selected workspace with a live terminal incorrectly renders an
        // idle gray dot while Flutter keeps it green.
        let has_terminal_tabs = self
            .snapshot
            .all_tabs
            .iter()
            .any(|tab| tab.workspace_id == workspace.id && tab.kind == "terminal");
        let has_workspace_tabs = self
            .snapshot
            .all_tabs
            .iter()
            .any(|tab| tab.workspace_id == workspace.id);
        // Flutter clears the active workspace when its last tab closes; keep
        // the idle dot off during the equivalent GPUI state transition.
        let status_indicator = render_workspace_status_indicator(
            aggregate_state,
            workspace_idle_dot_active(selected, has_workspace_tabs, has_terminal_tabs),
            &workspace.id,
        );
        let branch_label = workspace_branch_label(workspace, project_kind);
        let tag_labels = workspace_tag_labels(workspace);
        let tags_tooltip = tag_labels.join(", ");
        let mut row = div()
            .id(SharedString::from(format!(
                "workspace-row-{}-{}",
                if pinned_copy { "pinned" } else { "regular" },
                workspace.id
            )))
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(workspace.name.clone())
            .aria_selected(selected)
            .flex_shrink_0()
            .ml(px(8.0 + indent))
            .mr_2()
            .my(px(2.0))
            .px_3()
            .py(px(6.0))
            // Flutter's 19 px body line plus its vertical padding resolves
            // to a 31 px logical tile. Keep a floor here so long lists have
            // the same cumulative height and scrollbar range as Flutter.
            .min_h(px(31.0))
            .rounded(px(10.0))
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface()))
            .when(selected, |item| item.bg(theme::surface_raised()))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.select_workspace(workspace_id.clone(), cx);
            }))
            .on_aux_click(cx.listener(move |this, event: &ClickEvent, _, cx| {
                this.show_workspace_menu(workspace_menu_id.clone(), event.position(), cx);
                cx.stop_propagation();
            }))
            .flex()
            .items_center()
            .gap_2()
            .child(status_indicator)
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .overflow_hidden()
                    .flex()
                    .items_center()
                    .gap(px(6.0))
                    .text_size(crate::theme::body_size())
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .overflow_hidden()
                    .text_ellipsis()
                    .child(
                        div()
                            .flex_shrink(1.0)
                            .min_w_0()
                            .overflow_hidden()
                            .text_ellipsis()
                            .child(workspace.name.clone()),
                    )
                    .when_some(project_name.map(str::to_owned), |row, project_label| {
                        row.child(
                            div()
                                .id(SharedString::from(format!(
                                    "workspace-meta-project-{}",
                                    workspace.id
                                )))
                                .tooltip(move |_, cx| {
                                    let label = project_label.clone();
                                    cx.new(move |_| Tooltip::new(label)).into()
                                })
                                .child(icon(AleraIcon::FolderSpecial, 12.0, theme::text_muted())),
                        )
                    })
                    .when(workspace.kind == "main", |row| {
                        row.child(
                            div()
                                .id(SharedString::from(format!(
                                    "workspace-meta-home-{}",
                                    workspace.id
                                )))
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Default Workspace")).into()
                                })
                                .child(icon(AleraIcon::Home, 12.0, theme::text_muted())),
                        )
                    })
                    .when(workspace.is_pinned, |row| {
                        row.child(
                            div()
                                .id(SharedString::from(format!(
                                    "workspace-meta-pin-{}",
                                    workspace.id
                                )))
                                .tooltip(|_, cx| {
                                    cx.new(|_| Tooltip::new("Pinned Workspace")).into()
                                })
                                .child(icon(AleraIcon::Pin, 12.0, theme::text_muted())),
                        )
                    })
                    .child(
                        div()
                            .id(SharedString::from(format!(
                                "workspace-meta-branch-{}",
                                workspace.id
                            )))
                            .tooltip(move |_, cx| {
                                let label = branch_label.clone();
                                cx.new(move |_| Tooltip::new(label)).into()
                            })
                            .child(icon(AleraIcon::GitBranch, 12.0, theme::text_muted())),
                    )
                    .when(!tag_labels.is_empty(), move |row| {
                        row.child(
                            div()
                                .id(SharedString::from(format!(
                                    "workspace-meta-tags-{}",
                                    workspace.id
                                )))
                                .tooltip(move |_, cx| {
                                    let label = tags_tooltip.clone();
                                    cx.new(move |_| Tooltip::new(label)).into()
                                })
                                .flex()
                                .items_center()
                                .gap(px(2.0))
                                .text_size(crate::theme::caption_size())
                                .text_color(theme::text_faint())
                                .child(icon(AleraIcon::Tag, 12.0, theme::text_faint()))
                                .child(tag_labels.len().to_string()),
                        )
                    })
                    .when(workspace.host_id != "local", |row| {
                        let host_label = format!("Host: {}", workspace.host_id);
                        row.child(
                            div()
                                .id(SharedString::from(format!(
                                    "workspace-meta-host-{}",
                                    workspace.id
                                )))
                                .tooltip(move |_, cx| {
                                    let label = host_label.clone();
                                    cx.new(move |_| Tooltip::new(label)).into()
                                })
                                .child(icon(AleraIcon::Server, 12.0, theme::text_muted())),
                        )
                    }),
            );
        if show_agent_toggle {
            row = row.child(self.render_agent_summary(
                &agent_runs,
                agents_expanded,
                toggle_agents_id,
                cx,
            ));
        }
        if show_children_toggle {
            let chevron = if children_collapsed {
                AleraIcon::ChevronRight
            } else {
                AleraIcon::ChevronDown
            };
            row = row.child(
                div()
                    .id(SharedString::from(format!(
                        "workspace-children-toggle-{}",
                        workspace.id
                    )))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(if children_collapsed {
                        "Show Child Workspaces"
                    } else {
                        "Hide Child Workspaces"
                    })
                    .aria_expanded(!children_collapsed)
                    .flex()
                    .items_center()
                    .gap_1()
                    .px_1()
                    .py(px(2.0))
                    .h_auto()
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .tooltip(move |_, cx| {
                        let label = if children_collapsed {
                            "Show Child Workspaces"
                        } else {
                            "Hide Child Workspaces"
                        };
                        cx.new(|_| Tooltip::new(label)).into()
                    })
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        cx.stop_propagation();
                        this.toggle_parent_workspace_section(toggle_children_id.clone(), cx);
                    }))
                    .child(icon(AleraIcon::Workflow, 12.0, theme::text_faint()))
                    .child(
                        div()
                            .text_size(crate::theme::caption_size())
                            .text_color(theme::text_faint())
                            .child(visible_child_count.to_string()),
                    )
                    .child(icon(chevron, 12.0, theme::text_faint())),
            );
        }
        if !agent_runs.is_empty() && agents_expanded {
            return div()
                .flex_shrink_0()
                .flex()
                .flex_col()
                .child(row)
                .child(self.render_agent_run_list(&agent_runs, &workspace.id, indent, cx))
                .into_any_element();
        }
        row.into_any_element()
    }

    fn sidebar_agent_runs(&self, workspace: &Workspace) -> Vec<Value> {
        // Flutter's projection walks the workspace tabs in creation order and
        // joins each terminal with its current presence entry. Iterating the
        // host's presence list directly makes hook updates reshuffle rows as
        // soon as a status changes, which is especially visible when several
        // agents share one workspace.
        self.snapshot
            .all_tabs
            .iter()
            .filter(|tab| tab.workspace_id == workspace.id && tab.kind == "terminal")
            .filter_map(|tab| {
                let session_id = tab
                    .payload
                    .get("terminalSessionId")
                    .and_then(Value::as_str)
                    .filter(|value| !value.trim().is_empty())
                    .unwrap_or(tab.id.as_str());
                self.status_data.presence.iter().find(|entry| {
                    entry.get("workspaceId").and_then(Value::as_str) == Some(workspace.id.as_str())
                        && entry.get("tabId").and_then(Value::as_str) == Some(tab.id.as_str())
                        && entry
                            .get("handle")
                            .and_then(Value::as_str)
                            .is_none_or(|handle| handle == session_id)
                })
            })
            .cloned()
            .collect()
    }

    fn render_agent_summary(
        &self,
        runs: &[Value],
        expanded: bool,
        workspace_id: String,
        cx: &mut Context<Self>,
    ) -> gpui::Stateful<gpui::Div> {
        let groups = ["waiting", "blocked", "interrupted", "working", "done"]
            .into_iter()
            .filter_map(|state| {
                let state_runs = runs
                    .iter()
                    .filter(|run| agent_state_key(run) == state)
                    .collect::<Vec<_>>();
                (!state_runs.is_empty()).then_some((state, state_runs))
            })
            .collect::<Vec<_>>();
        let toggle_id = workspace_id.clone();
        let summary_tooltip = if expanded {
            "Hide Agent Runs".to_owned()
        } else if runs.len() == 1 {
            let run = &runs[0];
            let agent = run
                .get("agentType")
                .and_then(Value::as_str)
                .unwrap_or("codex");
            let raw_state = run
                .get("agentState")
                .and_then(Value::as_str)
                .unwrap_or("working");
            agent_run_description(run, agent, raw_state)
        } else {
            "Show Agent Runs".to_owned()
        };
        let mut summary_aria_label = groups
            .iter()
            .take(3)
            .map(|(state, state_runs)| agent_group_accessibility_label(state, state_runs))
            .collect::<Vec<_>>()
            .join("; ");
        let hidden_group_runs = groups
            .iter()
            .skip(3)
            .map(|(_, runs)| runs.len())
            .sum::<usize>();
        if hidden_group_runs > 0 {
            summary_aria_label.push_str(&format!(" +{hidden_group_runs}"));
        }
        let mut summary = div()
            .id(SharedString::from(format!(
                "workspace-agent-summary-{workspace_id}"
            )))
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(summary_aria_label)
            .aria_expanded(expanded)
            .flex()
            .items_center()
            .px_1()
            .py_1()
            .h_auto()
            .rounded_md()
            .cursor(CursorStyle::PointingHand)
            .tooltip(move |_, cx| {
                let label = summary_tooltip.clone();
                cx.new(move |_| Tooltip::new(label)).into()
            })
            .hover(|style| style.bg(theme::surface_raised()))
            .on_click(cx.listener(move |this, _, _, cx| {
                cx.stop_propagation();
                this.toggle_workspace_agents(toggle_id.clone(), cx);
            }));
        for (index, (state, state_runs)) in groups.iter().take(3).enumerate() {
            let cluster = render_agent_group_cluster(workspace_id.as_str(), state, state_runs)
                .when(index > 0, |cluster| cluster.ml(px(6.0)));
            summary = summary.child(cluster);
        }
        if hidden_group_runs > 0 {
            summary = summary.child(
                div()
                    .ml(px(4.0))
                    .text_size(crate::theme::caption_size())
                    .text_color(theme::text_faint())
                    .child(format!("+{hidden_group_runs}")),
            );
        }
        summary.child(div().ml(px(2.0)).child(icon(
            if expanded {
                AleraIcon::ChevronUp
            } else {
                AleraIcon::ChevronDown
            },
            12.0,
            theme::text_muted(),
        )))
    }

    fn render_agent_run_list(
        &self,
        runs: &[Value],
        workspace_id: &str,
        workspace_indent: f32,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let mut list = div()
            // Flutter nests agent rows inside the workspace's padded content:
            // the 12 px row padding plus the 20 px agent-list indent are in
            // addition to the workspace's outer indentation.
            .ml(px(40.0 + workspace_indent))
            .mr_3()
            .mt(px(4.0))
            .mb(px(2.0))
            .flex()
            .flex_col();
        for run in runs {
            let tab_id = run
                .get("tabId")
                .and_then(Value::as_str)
                .or_else(|| run.get("handle").and_then(Value::as_str))
                .unwrap_or_default()
                .to_owned();
            let select_id = tab_id.clone();
            let select_workspace_id = workspace_id.to_owned();
            let close_id = tab_id.clone();
            let state = agent_state_key(run);
            let indicator_state = agent_indicator_state_key(run);
            let active = self.selected_tab_id.as_deref() == Some(tab_id.as_str());
            let hovered = self.sidebar_hovered_agent_run_id.as_deref() == Some(tab_id.as_str());
            let actions_visible = active || hovered;
            let agent = run
                .get("agentType")
                .and_then(Value::as_str)
                .unwrap_or("codex");
            let raw_state = run
                .get("agentState")
                .and_then(Value::as_str)
                .unwrap_or("working");
            let description = agent_run_description(run, agent, raw_state);
            let row_label = format!(
                "{} {} {}",
                agent_state_label(state),
                agent_display_name(agent),
                description
            );
            // Presence can refresh while a row is being hovered. Keep every
            // interactive identity tied to the terminal tab rather than its
            // current render index so a later status update cannot retarget a
            // different agent.
            let row_key = tab_id.clone();
            list = list.child(
                div()
                    .id(SharedString::from(format!("sidebar-agent-run-{row_key}")))
                    .focusable()
                    .tab_stop(true)
                    .role(Role::Button)
                    .aria_label(row_label)
                    .flex()
                    .items_center()
                    .gap(px(6.0))
                    .min_h(px(22.0))
                    .px(px(6.0))
                    .py(px(4.0))
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .when(active, |row| row.bg(theme::accent_subtle()))
                    .hover(move |style| {
                        if active {
                            style
                        } else {
                            style.bg(theme::surface())
                        }
                    })
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.select_workspace_tab(
                            select_workspace_id.clone(),
                            select_id.clone(),
                            cx,
                        );
                        cx.stop_propagation();
                    }))
                    .on_hover({
                        let hover_id = tab_id.clone();
                        cx.listener(move |this, hovered: &bool, _, cx| {
                            if *hovered {
                                this.sidebar_hovered_agent_run_id = Some(hover_id.clone());
                            } else if this.sidebar_hovered_agent_run_id.as_deref()
                                == Some(hover_id.as_str())
                            {
                                this.sidebar_hovered_agent_run_id = None;
                            }
                            cx.notify();
                        })
                    })
                    .child(
                        div()
                            .id(SharedString::from(format!("sidebar-agent-state-{row_key}")))
                            .tooltip({
                                let label = agent_state_label(state).to_owned();
                                move |_, cx| {
                                    let tooltip = label.clone();
                                    cx.new(move |_| Tooltip::new(tooltip)).into()
                                }
                            })
                            .child(if indicator_state == "working" {
                                crate::icons::agent_loading_indicator(
                                    10.0,
                                    agent_state_color(indicator_state),
                                )
                            } else {
                                icon(agent_state_icon(state), 12.0, agent_state_color(state))
                            }),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!(
                                "sidebar-agent-identity-{row_key}"
                            )))
                            .tooltip({
                                let label = agent_display_name(agent).to_owned();
                                move |_, cx| {
                                    let tooltip = label.clone();
                                    cx.new(move |_| Tooltip::new(tooltip)).into()
                                }
                            })
                            .child(agent_icon(
                                agent_icon_for(agent),
                                13.0,
                                if active {
                                    theme::text()
                                } else {
                                    theme::text_muted()
                                },
                            )),
                    )
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .overflow_hidden()
                            .text_ellipsis()
                            .text_size(crate::theme::caption_size())
                            .text_color(if active {
                                theme::text()
                            } else {
                                theme::text_muted()
                            })
                            .font_weight(if active {
                                gpui::FontWeight::SEMIBOLD
                            } else {
                                gpui::FontWeight::MEDIUM
                            })
                            .child(description),
                    )
                    .child({
                        let close_button = div()
                            .id(SharedString::from(format!(
                                "sidebar-agent-run-close-{row_key}"
                            )))
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(20.0))
                            .h(px(20.0))
                            .ml(px(-2.0))
                            .rounded_sm()
                            .cursor(if actions_visible {
                                CursorStyle::PointingHand
                            } else {
                                CursorStyle::Arrow
                            })
                            .opacity(if actions_visible { 1.0 } else { 0.0 })
                            .when(actions_visible, |button| {
                                button
                                    .focusable()
                                    .tab_stop(true)
                                    .role(Role::Button)
                                    .aria_label("Close Terminal")
                                    .tooltip(|_, cx| {
                                        cx.new(|_| Tooltip::new("Close Terminal")).into()
                                    })
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        cx.stop_propagation();
                                        this.request_close_tab(close_id.clone(), cx);
                                    }))
                            })
                            .hover(|style| style.bg(theme::surface_raised()))
                            .child(icon(AleraIcon::Close, 12.0, theme::text_muted()));
                        close_button.with_animation(
                            SharedString::from(format!(
                                "sidebar-agent-run-close-animation-{row_key}-{actions_visible}"
                            )),
                            Animation::new(Duration::from_millis(100)),
                            move |button, delta| {
                                button.opacity(if actions_visible { delta } else { 1.0 - delta })
                            },
                        )
                    }),
            );
        }
        list
    }
}

fn render_agent_group_cluster(workspace_id: &str, state: &str, state_runs: &[&Value]) -> gpui::Div {
    let color = agent_state_color(state);
    let mut agents = state_runs
        .iter()
        .filter_map(|run| run.get("agentType").and_then(Value::as_str))
        .collect::<Vec<_>>();
    agents.sort_by_key(|agent| (agent_sort_key(agent), *agent));
    agents.dedup();
    let visible_agents = agents.into_iter().take(3).collect::<Vec<_>>();
    let hidden_count = state_runs.len().saturating_sub(visible_agents.len());
    let icon_width = 14.0 + visible_agents.len().saturating_sub(1) as f32 * 10.0;
    let state_tooltip = agent_state_label(state).to_owned();
    let is_working = state_runs
        .first()
        .is_some_and(|run| run.get("agentState").and_then(Value::as_str) == Some("working"));
    let indicator_color = if is_working { theme::warning() } else { color };
    let mut cluster = div().flex().items_center().gap(px(2.0)).child(
        div()
            .id(SharedString::from(format!(
                "workspace-agent-state-{workspace_id}-{state}"
            )))
            .flex()
            .items_center()
            .justify_center()
            .w(px(11.0))
            .h(px(11.0))
            .tooltip(move |_, cx| {
                let tooltip = state_tooltip.clone();
                cx.new(move |_| Tooltip::new(tooltip)).into()
            })
            .child(if is_working {
                crate::icons::agent_loading_indicator(9.0, indicator_color)
            } else {
                icon(agent_state_icon(state), 11.0, indicator_color)
            }),
    );
    if !visible_agents.is_empty() {
        let mut icons = div().relative().w(px(icon_width)).h(px(14.0));
        for (index, agent) in visible_agents.into_iter().enumerate() {
            let agent_label = agent_display_name(agent).to_owned();
            icons = icons.child(
                div()
                    .id(SharedString::from(format!(
                        "workspace-agent-icon-{workspace_id}-{state}-{agent}"
                    )))
                    .absolute()
                    .left(px(index as f32 * 10.0))
                    .top_0()
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(14.0))
                    .h(px(14.0))
                    .rounded_full()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface_selected())
                    .tooltip(move |_, cx| {
                        let label = agent_label.clone();
                        cx.new(move |_| Tooltip::new(label)).into()
                    })
                    .child(agent_icon(agent_icon_for(agent), 9.0, theme::text_muted())),
            );
        }
        cluster = cluster.child(icons);
    }
    if hidden_count > 0 {
        cluster = cluster.child(
            div()
                .text_size(crate::theme::caption_size())
                .text_color(theme::text_faint())
                .child(format!("+{hidden_count}")),
        );
    }
    cluster
}

fn agent_group_accessibility_label(state: &str, state_runs: &[&Value]) -> String {
    let mut agents = state_runs
        .iter()
        .filter_map(|run| run.get("agentType").and_then(Value::as_str))
        .collect::<Vec<_>>();
    agents.sort_by_key(|agent| (agent_sort_key(agent), *agent));
    agents.dedup();
    let visible_agents = agents.into_iter().take(3).collect::<Vec<_>>();
    let hidden_count = state_runs.len().saturating_sub(visible_agents.len());
    let mut label = format!(
        "{} {}",
        agent_state_label(state),
        visible_agents
            .into_iter()
            .map(agent_display_name)
            .collect::<Vec<_>>()
            .join(", ")
    );
    if hidden_count > 0 {
        label.push_str(&format!(" +{hidden_count}"));
    }
    label
}

fn agent_sort_key(agent: &str) -> usize {
    match agent {
        // Keep the same stable order as Flutter's AgentType enum. The compact
        // tray is rebuilt on every hook event, so this order must not depend on
        // the arrival order of presence updates.
        "codex" => 0,
        "claude" => 1,
        "copilot" => 2,
        "cursor" => 3,
        "antigravity" | "agy" => 4,
        "opencode" => 5,
        "opencode2" => 6,
        "pi" => 7,
        "amp" => 8,
        "grok" => 9,
        "fx" => 10,
        // These providers are quota-only in Flutter's AgentType enum but can
        // still arrive in persisted GPUI presence data. Keep them deterministic
        // after the shared agent types.
        "kimi" => 11,
        "minimax" | "miniMax" => 12,
        "zai" => 13,
        _ => 100,
    }
}

fn agent_icon_for(agent: &str) -> AgentIcon {
    match agent {
        "claude" => AgentIcon::Claude,
        "copilot" => AgentIcon::Copilot,
        "cursor" => AgentIcon::Cursor,
        "agy" | "antigravity" => AgentIcon::Agy,
        "opencode" | "opencode2" => AgentIcon::OpenCode,
        "pi" => AgentIcon::Pi,
        "amp" => AgentIcon::Amp,
        "grok" => AgentIcon::Grok,
        "fx" => AgentIcon::Fx,
        "kimi" => AgentIcon::Kimi,
        "minimax" | "miniMax" => AgentIcon::MiniMax,
        "zai" => AgentIcon::Zai,
        _ => AgentIcon::Codex,
    }
}

fn agent_state_key(run: &Value) -> &str {
    if run
        .get("interrupted")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        "interrupted"
    } else {
        run.get("agentState")
            .and_then(Value::as_str)
            .unwrap_or("working")
    }
}

fn agent_indicator_state_key(run: &Value) -> &str {
    let state = run
        .get("agentState")
        .and_then(Value::as_str)
        .unwrap_or("working");
    // Flutter keeps the spinner for a working run even when its attention
    // flag is interrupted.  The interruption still affects the label and
    // grouping, but it must not replace the running glyph.
    if state == "working" {
        "working"
    } else if run
        .get("interrupted")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        "interrupted"
    } else {
        state
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SidebarAggregateState {
    state: &'static str,
    interrupted: bool,
}

fn sidebar_aggregate_state(runs: &[Value]) -> Option<SidebarAggregateState> {
    // Flutter keeps row order stable but chooses the workspace glyph by
    // urgency: blocked > waiting > interrupted > working > done.
    let mut best: Option<(&Value, u8, &str)> = None;
    for run in runs {
        let state = run
            .get("agentState")
            .and_then(Value::as_str)
            .unwrap_or("working");
        let interrupted = run
            .get("interrupted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let priority = if interrupted {
            3
        } else {
            match state {
                "blocked" => 5,
                "waiting" => 4,
                "working" => 2,
                "done" => 1,
                _ => 2,
            }
        };
        let updated_at = run
            .get("updatedAt")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let is_better = best.is_none_or(|(_, current_priority, current_updated_at)| {
            priority > current_priority
                || (priority == current_priority && updated_at > current_updated_at)
        });
        if is_better {
            best = Some((run, priority, updated_at));
        }
    }
    let (run, _, _) = best?;
    let state = run
        .get("agentState")
        .and_then(Value::as_str)
        .unwrap_or("working");
    Some(SidebarAggregateState {
        state: match state {
            "blocked" => "blocked",
            "waiting" => "waiting",
            "done" => "done",
            _ => "working",
        },
        // Flutter applies interruption to the selected aggregate status after
        // choosing the most urgent base state. A cancelled working run still
        // renders the working spinner, while cancelled waiting/done runs use
        // the red cancel glyph.
        interrupted: run
            .get("interrupted")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

fn render_workspace_status_indicator(
    state: Option<SidebarAggregateState>,
    active: bool,
    workspace_id: &str,
) -> AnyElement {
    let mut indicator = div()
        .id(SharedString::from(format!(
            "workspace-status-indicator-{workspace_id}"
        )))
        .flex()
        .items_center()
        .justify_center()
        .w(px(14.0))
        .h(px(14.0));
    if let Some(aggregate) = state {
        let display_state = if aggregate.interrupted {
            "interrupted"
        } else {
            aggregate.state
        };
        let label = agent_state_label(display_state).to_owned();
        indicator = indicator.tooltip(move |_, cx| {
            let tooltip = label.clone();
            cx.new(move |_| Tooltip::new(tooltip)).into()
        });
        let content = if aggregate.state == "working" {
            crate::icons::agent_loading_indicator(11.0, agent_state_color(aggregate.state))
        } else {
            icon(
                agent_state_icon(display_state),
                12.0,
                if aggregate.interrupted {
                    theme::danger()
                } else {
                    agent_state_color(aggregate.state)
                },
            )
        };
        indicator.child(content).into_any_element()
    } else {
        indicator
            .child(div().w(px(8.0)).h(px(8.0)).rounded_full().bg(if active {
                theme::success()
            } else {
                theme::text_faint()
            }))
            .into_any_element()
    }
}

fn workspace_idle_dot_active(
    selected_workspace: bool,
    has_workspace_tabs: bool,
    has_terminal_tabs: bool,
) -> bool {
    (selected_workspace && has_workspace_tabs) || has_terminal_tabs
}

fn workspace_branch_label(workspace: &Workspace, project_kind: Option<&str>) -> String {
    if let Some(branch) = workspace
        .branch
        .as_deref()
        .filter(|branch| !branch.is_empty())
    {
        return branch.to_owned();
    }
    if project_kind.is_some_and(|kind| kind.contains("folder")) {
        "Local Folder".to_owned()
    } else {
        "Git Repository".to_owned()
    }
}

fn workspace_tag_labels(workspace: &Workspace) -> Vec<String> {
    let source = if workspace.tag_names.is_empty() {
        &workspace.tag_ids
    } else {
        &workspace.tag_names
    };
    source
        .iter()
        .map(|tag| tag.trim())
        .filter(|tag| !tag.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn agent_state_icon(state: &str) -> AleraIcon {
    match state {
        "interrupted" => AleraIcon::Cancel,
        "done" => AleraIcon::Success,
        "blocked" | "waiting" => AleraIcon::Notifications,
        _ => AleraIcon::Loading,
    }
}

fn agent_state_color(state: &str) -> gpui::Rgba {
    match state {
        "interrupted" => theme::danger(),
        "done" => theme::success(),
        "blocked" => theme::danger(),
        "waiting" => theme::warning(),
        _ => theme::warning(),
    }
}

fn agent_run_description(run: &Value, agent: &str, state: &str) -> String {
    let tool = run
        .get("toolName")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let input = run
        .get("toolInput")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    if state == "working" && !tool.is_empty() {
        return if input.is_empty() {
            tool.to_owned()
        } else {
            format!("{tool}: {input}")
        };
    }
    if let Some(message) = run
        .get("lastAssistantMessage")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|message| !message.is_empty())
    {
        return message.to_owned();
    }
    let display_state = if run
        .get("interrupted")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        "interrupted"
    } else {
        state
    };
    format!(
        "{} · {}",
        agent_display_name(agent),
        agent_state_label(display_state)
    )
}

fn agent_display_name(agent: &str) -> &'static str {
    match agent {
        "claude" => "Claude Code",
        "copilot" => "GitHub Copilot",
        "cursor" => "Cursor",
        "agy" | "antigravity" => "Antigravity",
        "opencode" => "OpenCode",
        "opencode2" => "OpenCode 2",
        "pi" => "Pi",
        "amp" => "Amp",
        "grok" => "Grok Build",
        "fx" => "fx",
        "kimi" => "Kimi",
        "minimax" | "miniMax" => "MiniMax",
        "zai" => "Z.ai",
        _ => "Codex",
    }
}

fn agent_state_label(state: &str) -> &'static str {
    match state {
        "interrupted" => "Interrupted",
        "done" => "Done",
        "blocked" => "Blocked",
        "waiting" => "Waiting for input",
        _ => "Working",
    }
}

#[cfg(test)]
mod aggregate_tests {
    use serde_json::json;

    use super::{agent_display_name, agent_sort_key, sidebar_aggregate_state};

    #[test]
    fn compact_agent_icon_order_matches_flutter_agent_type_enum() {
        let ordered = [
            "codex",
            "claude",
            "copilot",
            "cursor",
            "agy",
            "opencode",
            "opencode2",
            "pi",
            "amp",
            "grok",
            "fx",
        ];
        let keys = ordered.map(agent_sort_key);
        assert_eq!(keys, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    }

    #[test]
    fn aggregate_state_matches_flutter_priority_before_interruption() {
        let runs = vec![
            json!({
                "agentState": "working",
                "interrupted": true,
                "updatedAt": "2026-08-24T15:00:00Z"
            }),
            json!({
                "agentState": "blocked",
                "interrupted": false,
                "updatedAt": "2026-08-24T14:00:00Z"
            }),
        ];

        assert_eq!(
            sidebar_aggregate_state(&runs),
            Some(super::SidebarAggregateState {
                state: "blocked",
                interrupted: false,
            })
        );
    }

    #[test]
    fn aggregate_state_keeps_flutter_base_state_for_interrupted_run() {
        let runs = vec![json!({
            "agentState": "blocked",
            "interrupted": true,
            "updatedAt": "2026-08-24T15:00:00Z"
        })];

        assert_eq!(
            sidebar_aggregate_state(&runs),
            Some(super::SidebarAggregateState {
                state: "blocked",
                interrupted: true,
            })
        );
    }

    #[test]
    fn interrupted_working_run_keeps_flutter_spinner_state() {
        let run = json!({
            "agentState": "working",
            "interrupted": true,
        });

        assert_eq!(super::agent_indicator_state_key(&run), "working");
    }

    #[test]
    fn aggregate_state_ranks_interruption_above_newer_working_run() {
        let runs = vec![
            json!({
                "agentState": "working",
                "interrupted": false,
                "updatedAt": "2026-08-24T15:00:00Z"
            }),
            json!({
                "agentState": "working",
                "interrupted": true,
                "updatedAt": "2026-08-24T14:00:00Z"
            }),
        ];

        assert_eq!(
            sidebar_aggregate_state(&runs),
            Some(super::SidebarAggregateState {
                state: "working",
                interrupted: true,
            })
        );
    }

    #[test]
    fn agent_display_name_matches_flutter_for_copilot() {
        assert_eq!(agent_display_name("copilot"), "GitHub Copilot");
    }
}

fn append_workspace_tree_row<'a>(
    workspace: &'a Workspace,
    depth: usize,
    children: &BTreeMap<&str, Vec<&'a Workspace>>,
    collapsed_ids: &BTreeSet<String>,
    placements: &mut Vec<SidebarWorkspacePlacement<'a>>,
    visited: &mut BTreeSet<String>,
) {
    if !visited.insert(workspace.id.clone()) {
        return;
    }
    let child_rows = children
        .get(workspace.id.as_str())
        .cloned()
        .unwrap_or_default();
    let collapsed = collapsed_ids.contains(&workspace.id);
    placements.push(SidebarWorkspacePlacement {
        workspace,
        depth: depth.min(4),
        visible_child_count: child_rows.len(),
        children_collapsed: collapsed,
    });
    if collapsed {
        return;
    }
    for child in child_rows {
        append_workspace_tree_row(
            child,
            depth.saturating_add(1),
            children,
            collapsed_ids,
            placements,
            visited,
        );
    }
}

fn is_hidden_by_collapsed_parent(
    workspace_id: &str,
    parent_of: &BTreeMap<&str, &str>,
    collapsed_ids: &BTreeSet<String>,
) -> bool {
    let mut current = workspace_id;
    let mut visited = BTreeSet::new();
    while let Some(parent_id) = parent_of.get(current).copied() {
        if !visited.insert(current) {
            return false;
        }
        if collapsed_ids.contains(parent_id) {
            return true;
        }
        current = parent_id;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::workspace_idle_dot_active;

    #[test]
    fn selected_workspace_without_tabs_is_not_active() {
        assert!(!workspace_idle_dot_active(true, false, false));
    }

    #[test]
    fn selected_workspace_with_editor_tab_is_active() {
        assert!(workspace_idle_dot_active(true, true, false));
    }

    #[test]
    fn terminal_tab_keeps_unselected_workspace_active() {
        assert!(workspace_idle_dot_active(false, true, true));
    }
}
