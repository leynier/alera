use std::collections::BTreeMap;

use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};
use gpui_component::scroll::ScrollableElement as _;
use gpui_component::tooltip::Tooltip;
use serde_json::Value;

use super::status_resource_components::*;
use super::AleraApp;
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

#[derive(Clone)]
pub(super) struct ResourceSession {
    pub(super) session_id: String,
    pub(super) workspace_id: String,
    pub(super) tab_id: String,
    pub(super) label: String,
    pub(super) cpu: Option<f64>,
    pub(super) memory: Option<u64>,
    pub(super) running: bool,
    pub(super) orphan: bool,
    pub(super) history: Vec<u64>,
}

#[derive(Clone)]
pub(super) struct ResourceWorkspace {
    pub(super) name: String,
    pub(super) remote: bool,
    pub(super) sessions: Vec<ResourceSession>,
}

#[derive(Clone)]
pub(super) struct ResourceProject {
    pub(super) id: String,
    pub(super) name: String,
    pub(super) workspaces: Vec<ResourceWorkspace>,
}

#[derive(Clone, Default)]
struct ResourceTree {
    projects: Vec<ResourceProject>,
    orphans: Vec<ResourceSession>,
}

impl AleraApp {
    pub(super) fn render_resource_popover(&self, cx: &mut Context<Self>) -> AnyElement {
        let value = self.status_data.resources.as_ref();
        let warming = value
            .and_then(|item| item.get("warming"))
            .and_then(Value::as_bool)
            .unwrap_or(self.status_data.resource_error.is_none());
        let cores = integer_at(value, &["host", "cpuCoreCount"])
            .unwrap_or(1)
            .max(1);
        let total_cpu = number_at(value, &["totals", "cpuPercent"]).map(|cpu| cpu / cores as f64);
        let total_memory = integer_at(value, &["totals", "memoryBytes"]);
        let host_memory = integer_at(value, &["host", "totalMemoryBytes"]);
        let tree = self.resource_tree(value, cores);
        let orphan_count = tree.orphans.len();
        let has_orphans = orphan_count > 0;
        let orphan_session_ids = tree
            .orphans
            .iter()
            .map(|session| session.session_id.clone())
            .collect::<Vec<_>>();
        let app = value
            .and_then(|item| item.pointer("/processes/app"))
            .cloned();
        let host = value
            .and_then(|item| item.pointer("/processes/host"))
            .cloned();
        // Flutter treats the panel tree as terminal-session data. App and host
        // metrics remain in the totals header, but they do not turn an empty
        // session tree into a populated body.
        let empty = tree.projects.is_empty() && tree.orphans.is_empty();
        let body_row_count = tree
            .projects
            .iter()
            .map(|project| {
                1 + if self.resource_collapsed_project_ids.contains(&project.id) {
                    0
                } else {
                    project
                        .workspaces
                        .iter()
                        .map(|workspace| 1 + workspace.sessions.len())
                        .sum::<usize>()
                }
            })
            .sum::<usize>()
            + if has_orphans { 1 + orphan_count } else { 0 }
            + if !empty && (app.is_some() || host.is_some()) {
                1 + usize::from(app.is_some()) + usize::from(host.is_some())
            } else {
                0
            };
        let panel_height = if empty {
            // Flutter's Flexible empty body keeps the card at 320 px even
            // though the placeholder itself is shorter. Preserve that stable
            // footprint so warming, unavailable, and no-session states do not
            // jump toward the status bar.
            320.0
        } else if body_row_count >= 10 {
            420.0
        } else {
            (36.0
                + 24.0
                + 32.0
                + 8.0
                + body_row_count as f32 * 22.0
                + if has_orphans { 34.0 } else { 0.0 }
                + if self.status_data.resource_error.is_some() {
                    56.0
                } else {
                    0.0
                })
            .min(420.0)
        };
        let body = div()
            .id("resource-body-scroll")
            .flex_1()
            .min_h_0()
            .pb_2()
            .when(empty, |body| {
                body.child(
                    div()
                        .flex_1()
                        .flex_col()
                        .flex()
                        .items_center()
                        .justify_center()
                        .p(px(24.0))
                        .text_sm()
                        .text_color(theme::text_muted())
                        .child(icon(AleraIcon::Activity, 28.0, theme::text_faint()))
                        .child(div().h(px(12.0)))
                        .child(div().text_align(gpui::TextAlign::Center).child(if warming {
                            "Measuring Resource Usage"
                        } else {
                            "No Terminal Sessions Are Running"
                        })),
                )
            })
            .children(
                tree.projects
                    .into_iter()
                    .enumerate()
                    .map(|(index, project)| self.resource_project_section(index, project, cx)),
            )
            .when(has_orphans, |body| {
                body.child(metric_row(
                    "resource-orphans",
                    0,
                    "Unattributed Terminals",
                    None,
                    None,
                    true,
                    None,
                    None,
                ))
                .children(
                    tree.orphans
                        .iter()
                        .cloned()
                        .enumerate()
                        .map(|(index, session)| {
                            self.resource_session_row(usize::MAX, 0, index, session, cx)
                        }),
                )
            })
            .when(!empty && (app.is_some() || host.is_some()), |body| {
                body.child(
                    div()
                        .border_t_1()
                        .border_color(theme::border_subtle())
                        .child(metric_row(
                            "resource-alera",
                            0,
                            "Alera",
                            sum_process_cpu(app.as_ref(), host.as_ref(), cores),
                            sum_process_memory(app.as_ref(), host.as_ref()),
                            true,
                            None,
                            None,
                        ))
                        .when_some(app, |section, app| {
                            section.child(process_row("resource-app", "App", &app, cores))
                        })
                        .when_some(host, |section, host| {
                            section.child(process_row(
                                "resource-host",
                                "Runtime Host",
                                &host,
                                cores,
                            ))
                        }),
                )
            })
            .overflow_y_scrollbar();

        div()
            .id("resource-popover")
            .role(Role::Dialog)
            .aria_label("Resource Manager")
            .absolute()
            .right(px(8.0))
            .bottom(theme::status_bar_height() + px(4.0))
            .w(px(417.0))
            .h(px(panel_height))
            .max_h(px(420.0))
            .flex()
            .flex_col()
            .min_h_0()
            .overflow_hidden()
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                this.set_status_popover_panel_hovered(*hovered, cx);
            }))
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| this.pin_active_status_popover(cx)),
            )
            .child(resource_header())
            .when_some(self.status_data.resource_error.clone(), |panel, _| {
                panel.child(resource_host_unreachable_notice())
            })
            .child(resource_totals(
                (!warming).then_some(total_cpu).flatten(),
                (!warming).then_some(total_memory).flatten(),
                host_memory,
            ))
            .child(self.resource_sort_header(cx))
            .child(body)
            .when(has_orphans, |panel| {
                panel.child(self.resource_orphan_footer(orphan_count, orphan_session_ids, cx))
            })
            .into_any_element()
    }

    fn resource_tree(&self, value: Option<&Value>, cores: u64) -> ResourceTree {
        let mut sessions_by_workspace: BTreeMap<String, Vec<ResourceSession>> = BTreeMap::new();
        let mut orphans = Vec::new();
        for session in value
            .and_then(|item| item.get("sessions"))
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let workspace_id = string_at_value(session, "workspaceId")
                .unwrap_or_default()
                .to_owned();
            let session_id = string_at_value(session, "sessionId")
                .unwrap_or_default()
                .to_owned();
            let tab_id = string_at_value(session, "tabId").unwrap_or_default();
            let tab = self.snapshot.all_tabs.iter().find(|tab| {
                tab.kind == "terminal"
                    && tab
                        .payload
                        .get("terminalSessionId")
                        .and_then(Value::as_str)
                        .filter(|value| !value.trim().is_empty())
                        .unwrap_or(&tab.id)
                        == session_id.as_str()
            });
            let orphan = tab.is_none();
            let remote = self
                .snapshot
                .projects
                .iter()
                .flat_map(|project| &project.workspaces)
                .find(|workspace| workspace.id == workspace_id)
                .is_some_and(|workspace| workspace.host_id != "local");
            let measured = session
                .get("measured")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let row = ResourceSession {
                session_id: session_id.clone(),
                workspace_id: workspace_id.clone(),
                tab_id: tab.map_or_else(|| tab_id.to_owned(), |tab| tab.id.clone()),
                label: tab
                    .map(|tab| tab.title.trim())
                    .filter(|title| !title.is_empty())
                    .unwrap_or(&session_id)
                    .to_owned(),
                cpu: (!remote && measured)
                    .then(|| {
                        session
                            .get("cpuPercent")
                            .and_then(Value::as_f64)
                            .map(|cpu| cpu / cores as f64)
                    })
                    .flatten(),
                memory: (!remote && measured)
                    .then(|| session.get("memoryBytes").and_then(Value::as_u64))
                    .flatten(),
                running: session
                    .get("running")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                orphan,
                history: session
                    .get("history")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_u64)
                    .collect(),
            };
            if orphan {
                orphans.push(row);
            } else {
                sessions_by_workspace
                    .entry(workspace_id)
                    .or_default()
                    .push(row);
            }
        }
        let mut projects = self
            .snapshot
            .projects
            .iter()
            .filter_map(|project| {
                let workspaces = project
                    .workspaces
                    .iter()
                    .filter_map(|workspace| {
                        sessions_by_workspace
                            .remove(&workspace.id)
                            .map(|mut sessions| {
                                sort_sessions(&mut sessions, &self.resource_sort_column);
                                ResourceWorkspace {
                                    name: workspace.name.clone(),
                                    remote: workspace.host_id != "local",
                                    sessions,
                                }
                            })
                    })
                    .collect::<Vec<_>>();
                (!workspaces.is_empty()).then(|| ResourceProject {
                    id: project.id.clone(),
                    name: project.name.clone(),
                    workspaces,
                })
            })
            .collect::<Vec<_>>();
        sort_projects(&mut projects, &self.resource_sort_column);
        sort_sessions(&mut orphans, &self.resource_sort_column);
        ResourceTree { projects, orphans }
    }

    fn resource_sort_header(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .flex()
            .flex_shrink_0()
            .items_center()
            .h(px(32.0))
            .px_3()
            .border_b_1()
            .border_color(theme::border_subtle())
            .text_xs()
            .text_color(theme::text_faint())
            .child(resource_sort_button(
                "resource-sort-name",
                "Name",
                "name",
                self.resource_sort_column.as_str(),
                true,
                cx,
            ))
            .child(resource_sort_button(
                "resource-sort-cpu",
                "CPU",
                "cpu",
                self.resource_sort_column.as_str(),
                false,
                cx,
            ))
            .child(resource_sort_button(
                "resource-sort-memory",
                "Memory",
                "memory",
                self.resource_sort_column.as_str(),
                false,
                cx,
            ))
            .child(div().w(px(17.0)))
            .into_any_element()
    }

    fn resource_project_section(
        &self,
        index: usize,
        project: ResourceProject,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let collapsed = self.resource_collapsed_project_ids.contains(&project.id);
        let toggle_id = project.id.clone();
        let (cpu, memory) = aggregate_workspaces(&project.workspaces);
        let mut child_rows = Vec::new();
        if !collapsed {
            for (workspace_index, workspace) in project.workspaces.into_iter().enumerate() {
                let (workspace_cpu, workspace_memory) = aggregate_sessions(&workspace.sessions);
                child_rows.push(
                    metric_row_with_suffix(
                        gpui::SharedString::from(format!(
                            "resource-workspace-{index}-{workspace_index}"
                        )),
                        1,
                        &workspace.name,
                        workspace_cpu,
                        workspace_memory,
                        false,
                        None,
                        None,
                        workspace.remote.then(|| "remote".to_owned()),
                    )
                    .into_any_element(),
                );
                for (session_index, session) in workspace.sessions.into_iter().enumerate() {
                    child_rows.push(self.resource_session_row(
                        index,
                        workspace_index,
                        session_index,
                        session,
                        cx,
                    ));
                }
            }
        }
        div()
            .id(("resource-project", index))
            .flex()
            .flex_col()
            .child(
                metric_row(
                    ("resource-project-row", index),
                    0,
                    &project.name,
                    cpu,
                    memory,
                    true,
                    Some(if collapsed {
                        AleraIcon::ChevronRight
                    } else {
                        AleraIcon::ChevronDown
                    }),
                    None,
                )
                .focusable()
                .tab_stop(true)
                .role(Role::Button)
                .aria_label(project.name.clone())
                .cursor(CursorStyle::PointingHand)
                .on_click(cx.listener(move |this, _, _, cx| {
                    if !this.resource_collapsed_project_ids.remove(&toggle_id) {
                        this.resource_collapsed_project_ids
                            .insert(toggle_id.clone());
                    }
                    cx.notify();
                })),
            )
            .children(child_rows)
            .into_any_element()
    }

    fn resource_session_row(
        &self,
        project_index: usize,
        workspace_index: usize,
        session_index: usize,
        session: ResourceSession,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let open_tab_id = session.tab_id.clone();
        let open_workspace_id = session.workspace_id.clone();
        let terminate_session_id = session.session_id.clone();
        let close_tab_id = session.tab_id.clone();
        let close_label = session.label.clone();
        let orphan = session.orphan;
        let action_tooltip = if orphan {
            "Kill Orphan Terminal"
        } else {
            "Close Terminal Session"
        };
        metric_row(
            gpui::SharedString::from(format!(
                "resource-session-{project_index}-{workspace_index}-{session_index}"
            )),
            2,
            &session.label,
            session.cpu,
            session.memory,
            false,
            None,
            Some((session.running, session.history)),
        )
        .focusable()
        .tab_stop(true)
        .role(Role::Button)
        .aria_label(session.label.clone())
        .when(!orphan, |row| {
            row.cursor(CursorStyle::PointingHand)
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.dismiss_status_popover(cx);
                    this.open_resource_session(open_workspace_id.clone(), open_tab_id.clone(), cx);
                }))
        })
        .child(
            div()
                .id(gpui::SharedString::from(format!(
                    "resource-terminate-{project_index}-{workspace_index}-{session_index}"
                )))
                .focusable()
                .tab_stop(true)
                .role(Role::Button)
                .aria_label(action_tooltip)
                .absolute()
                .right(px(8.0))
                .flex()
                .items_center()
                .justify_center()
                .w(px(17.0))
                .h(px(22.0))
                .rounded_sm()
                .text_color(theme::text_faint())
                .cursor(CursorStyle::PointingHand)
                .tooltip(move |_, cx| cx.new(|_| Tooltip::new(action_tooltip)).into())
                .hover(|style| style.bg(theme::surface_selected()))
                .on_click(cx.listener(move |this, _, _, cx| {
                    cx.stop_propagation();
                    if orphan {
                        this.terminate_resource_session(terminate_session_id.clone(), cx);
                    } else {
                        this.resource_close_confirmation = Some(super::ResourceCloseConfirmation {
                            tab_id: close_tab_id.clone(),
                            label: close_label.clone(),
                        });
                        this.dismiss_status_popover(cx);
                        cx.notify();
                    }
                }))
                .child(icon(AleraIcon::Close, 11.0, theme::text_faint())),
        )
        .into_any_element()
    }
}
