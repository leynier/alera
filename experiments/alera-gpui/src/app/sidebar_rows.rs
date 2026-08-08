use std::collections::{BTreeMap, BTreeSet};

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, MouseButton, MouseDownEvent, ParentElement as _,
    SharedString, StatefulInteractiveElement as _, Styled as _,
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
        self.sort_sidebar_projects(&mut projects);

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
                workspaces.sort_by(|(left_project, left), (right_project, right)| {
                    self.compare_sidebar_workspaces(left, right)
                        .then_with(|| left_project.name.cmp(&right_project.name))
                });
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
            .when(divider, |section| {
                section.border_t_1().border_color(theme::border_subtle())
            })
            .child(
                div()
                    .id(id)
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .mx_2()
                    .px_2()
                    .gap_2()
                    .rounded_lg()
                    .cursor(CursorStyle::PointingHand)
                    .text_sm()
                    .text_color(theme::text_muted())
                    .hover(|style| style.bg(theme::surface()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            if id == "sidebar-pinned-section" {
                                this.toggle_pinned_section(cx);
                            } else {
                                this.sidebar_all_collapsed = !this.sidebar_all_collapsed;
                                this.persist_sidebar_view_prefs(cx);
                                cx.notify();
                            }
                        }),
                    )
                    .child(icon(leading, 14.0, theme::text_muted()))
                    .child(
                        div()
                            .flex_1()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(label),
                    )
                    .child(
                        div()
                            .text_xs()
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
        div()
            .id(SharedString::from(format!("project-row-{}", project.id)))
            .flex()
            .items_center()
            .h(px(34.0))
            .mx_2()
            .px_2()
            .gap_2()
            .text_sm()
            .text_color(theme::text_muted())
            .rounded_lg()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.toggle_project_section(project_id.clone(), cx);
                }),
            )
            .on_mouse_down(
                MouseButton::Right,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    this.show_project_menu(project_menu_id.clone(), event.position, cx);
                    cx.stop_propagation();
                }),
            )
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
                    .text_xs()
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
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.open_new_workspace_dialog(cx);
                            this.select_workspace_project(new_workspace_project_id.clone(), cx);
                        }),
                    )
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
        let has_terminal_tabs = self
            .snapshot
            .tabs
            .iter()
            .any(|tab| tab.workspace_id == workspace.id && tab.kind == "terminal");
        let has_workspace_tabs = self
            .snapshot
            .tabs
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
            .ml(px(8.0 + indent))
            .mr_2()
            .my(px(2.0))
            .px_3()
            .py(px(6.0))
            .rounded_lg()
            .cursor(CursorStyle::PointingHand)
            .hover(|style| style.bg(theme::surface()))
            .when(selected, |item| item.bg(theme::surface_raised()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.select_workspace(workspace_id.clone(), cx);
                }),
            )
            .on_mouse_down(
                MouseButton::Right,
                cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                    this.show_workspace_menu(workspace_menu_id.clone(), event.position, cx);
                    cx.stop_propagation();
                }),
            )
            .flex()
            .items_center()
            .gap_2()
            .child(status_indicator)
            .child(
                div()
                    .min_w_0()
                    .overflow_hidden()
                    .flex()
                    .items_center()
                    .gap_1()
                    .text_sm()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .overflow_hidden()
                    .text_ellipsis()
                    .child(workspace.name.clone())
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
                                .gap_1()
                                .text_xs()
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
            )
            .child(div().flex_1());
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
                    .flex()
                    .items_center()
                    .gap_1()
                    .px_1()
                    .h(px(24.0))
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
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.toggle_parent_workspace_section(toggle_children_id.clone(), cx);
                        }),
                    )
                    .child(icon(AleraIcon::Workflow, 12.0, theme::text_faint()))
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme::text_faint())
                            .child(visible_child_count.to_string()),
                    )
                    .child(icon(chevron, 12.0, theme::text_faint())),
            );
        }
        if !agent_runs.is_empty() && agents_expanded {
            return div()
                .flex()
                .flex_col()
                .child(row)
                .child(self.render_agent_run_list(&agent_runs, indent, cx))
                .into_any_element();
        }
        row.into_any_element()
    }

    fn sidebar_agent_runs(&self, workspace: &Workspace) -> Vec<Value> {
        self.status_data
            .presence
            .iter()
            .filter(|entry| {
                entry.get("workspaceId").and_then(Value::as_str) == Some(workspace.id.as_str())
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
            agent_run_description(run, agent, agent_state_key(run))
        } else {
            "Show Agent Runs".to_owned()
        };
        let mut summary = div()
            .id(SharedString::from(format!(
                "workspace-agent-summary-{workspace_id}"
            )))
            .flex()
            .items_center()
            .gap_2()
            .px_1()
            .h(px(24.0))
            .rounded_md()
            .cursor(CursorStyle::PointingHand)
            .tooltip(move |_, cx| {
                let label = summary_tooltip.clone();
                cx.new(move |_| Tooltip::new(label)).into()
            })
            .hover(|style| style.bg(theme::surface_raised()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.toggle_workspace_agents(toggle_id.clone(), cx);
                }),
            );
        for (state, state_runs) in groups.iter().take(3) {
            let color = agent_state_color(state);
            let state_icon = agent_state_icon(state);
            let mut cluster = div().flex().items_center().gap_1().child(
                div()
                    .id(SharedString::from(format!(
                        "workspace-agent-state-{workspace_id}-{state}"
                    )))
                    .tooltip({
                        let label = agent_state_label(state).to_owned();
                        move |_, cx| {
                            let tooltip = label.clone();
                            cx.new(move |_| Tooltip::new(tooltip)).into()
                        }
                    })
                    .child(if state == &"working" {
                        crate::icons::agent_loading_indicator(11.0, color)
                    } else {
                        icon(state_icon, 11.0, color)
                    }),
            );
            let mut seen_agents = BTreeSet::new();
            for run in state_runs {
                let agent = run
                    .get("agentType")
                    .and_then(Value::as_str)
                    .unwrap_or("codex");
                if seen_agents.contains(agent) || seen_agents.len() >= 3 {
                    continue;
                }
                seen_agents.insert(agent);
                let agent_label = agent_display_name(agent).to_owned();
                let agent_chip = div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(14.0))
                    .h(px(14.0))
                    .rounded_full()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface_selected())
                    .id(SharedString::from(format!(
                        "workspace-agent-icon-{workspace_id}-{state}-{agent}"
                    )))
                    .tooltip(move |_, cx| {
                        let label = agent_label.clone();
                        cx.new(move |_| Tooltip::new(label)).into()
                    })
                    .child(agent_icon(agent_icon_for(agent), 9.0, theme::text_muted()));
                cluster = cluster.child(agent_chip);
            }
            if state_runs.len() > seen_agents.len() {
                cluster = cluster.child(
                    div()
                        .text_xs()
                        .text_color(theme::text_faint())
                        .child(format!("+{}", state_runs.len() - seen_agents.len())),
                );
            }
            summary = summary.child(cluster);
        }
        summary.child(icon(
            if expanded {
                AleraIcon::ChevronUp
            } else {
                AleraIcon::ChevronDown
            },
            12.0,
            theme::text_muted(),
        ))
    }

    fn render_agent_run_list(
        &self,
        runs: &[Value],
        workspace_indent: f32,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let mut list = div()
            .ml(px(40.0 + workspace_indent))
            .mr_3()
            .mb(px(2.0))
            .flex()
            .flex_col()
            .gap_1();
        for (index, run) in runs.iter().enumerate() {
            let tab_id = run
                .get("tabId")
                .and_then(Value::as_str)
                .or_else(|| run.get("handle").and_then(Value::as_str))
                .unwrap_or_default()
                .to_owned();
            let select_id = tab_id.clone();
            let close_id = tab_id.clone();
            let state = agent_state_key(run);
            let agent = run
                .get("agentType")
                .and_then(Value::as_str)
                .unwrap_or("codex");
            let description = agent_run_description(run, agent, state);
            let tab_index = self
                .snapshot
                .tabs
                .iter()
                .position(|tab| tab.id == tab_id)
                .unwrap_or(index);
            list = list.child(
                div()
                    .id(SharedString::from(format!("sidebar-agent-run-{tab_index}")))
                    .flex()
                    .items_center()
                    .gap_2()
                    .min_h(px(26.0))
                    .px_2()
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            this.activate_workspace_tab(select_id.clone(), cx);
                            cx.stop_propagation();
                        }),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!(
                                "sidebar-agent-state-{tab_index}"
                            )))
                            .tooltip({
                                let label = agent_state_label(state).to_owned();
                                move |_, cx| {
                                    let tooltip = label.clone();
                                    cx.new(move |_| Tooltip::new(tooltip)).into()
                                }
                            })
                            .child(if state == "working" {
                                crate::icons::agent_loading_indicator(
                                    12.0,
                                    agent_state_color(state),
                                )
                            } else {
                                icon(agent_state_icon(state), 12.0, agent_state_color(state))
                            }),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!(
                                "sidebar-agent-identity-{tab_index}"
                            )))
                            .tooltip({
                                let label = agent_display_name(agent).to_owned();
                                move |_, cx| {
                                    let tooltip = label.clone();
                                    cx.new(move |_| Tooltip::new(tooltip)).into()
                                }
                            })
                            .child(agent_icon(agent_icon_for(agent), 13.0, theme::text_muted())),
                    )
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .overflow_hidden()
                            .text_ellipsis()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child(description),
                    )
                    .child(
                        div()
                            .id(SharedString::from(format!(
                                "sidebar-agent-run-close-{tab_index}"
                            )))
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(20.0))
                            .h(px(20.0))
                            .rounded_sm()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.request_close_tab(close_id.clone(), cx);
                                }),
                            )
                            .child(icon(AleraIcon::Close, 12.0, theme::text_muted())),
                    ),
            );
        }
        list
    }
}

fn agent_icon_for(agent: &str) -> AgentIcon {
    match agent {
        "claude" => AgentIcon::Claude,
        "copilot" => AgentIcon::Copilot,
        "cursor" => AgentIcon::Cursor,
        "agy" | "antigravity" => AgentIcon::Agy,
        "opencode" => AgentIcon::OpenCode,
        "pi" => AgentIcon::Pi,
        "amp" => AgentIcon::Amp,
        "grok" => AgentIcon::Grok,
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

fn sidebar_aggregate_state(runs: &[Value]) -> Option<&'static str> {
    ["interrupted", "blocked", "waiting", "working", "done"]
        .into_iter()
        .find(|state| runs.iter().any(|run| agent_state_key(run) == *state))
}

fn render_workspace_status_indicator(
    state: Option<&str>,
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
    if let Some(state) = state {
        let label = agent_state_label(state).to_owned();
        indicator = indicator.tooltip(move |_, cx| {
            let tooltip = label.clone();
            cx.new(move |_| Tooltip::new(tooltip)).into()
        });
        let content = if state == "working" {
            crate::icons::agent_loading_indicator(12.0, agent_state_color(state))
        } else {
            icon(agent_state_icon(state), 12.0, agent_state_color(state))
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
    format!(
        "{} · {}",
        agent_display_name(agent),
        agent_state_label(state)
    )
}

fn agent_display_name(agent: &str) -> &'static str {
    match agent {
        "claude" => "Claude Code",
        "copilot" => "Copilot",
        "cursor" => "Cursor",
        "agy" | "antigravity" => "Antigravity",
        "opencode" => "OpenCode",
        "pi" => "Pi",
        "amp" => "Amp",
        "grok" => "Grok Build",
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
