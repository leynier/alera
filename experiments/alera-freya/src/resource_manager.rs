use std::time::Duration;

use alera_desktop_core::{RuntimeBridge, WorkbenchSnapshot};
use freya::{icons, prelude::*};
use serde_json::Value;

use crate::alera_scroll_view::AleraScrollView as ScrollView;

mod actions;
mod components;
mod model;

use actions::terminate_sessions;
pub(super) use actions::{close_confirmation_dialog, fetch_snapshot};
use components::{
    alera_process_rows, host_unreachable_notice, integer_at, metric_row, number_at, orphan_footer,
    sort_header, totals_row,
};
use model::{aggregate_sessions, aggregate_workspaces, resource_tree};

const SURFACE: (u8, u8, u8) = (24, 24, 24);
const BORDER: (u8, u8, u8) = (50, 50, 50);
const TEXT: (u8, u8, u8) = (245, 245, 245);
const MUTED: (u8, u8, u8) = (161, 161, 161);
const FAINT: (u8, u8, u8) = (96, 96, 96);
const SUCCESS: (u8, u8, u8) = (34, 197, 94);
const WARNING: (u8, u8, u8) = (245, 158, 11);

// Computer Use measures Freya's 417 logical units at roughly 318 Retina pixels.
// This calibrated width paints at the same roughly 356 pixels as Flutter's panel.
pub(crate) const PANEL_WIDTH: f32 = 420.;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ResourceCloseConfirmation {
    pub tab_id: String,
    pub label: String,
}

#[derive(Clone, Debug, PartialEq)]
struct ResourceSession {
    session_id: String,
    workspace_id: String,
    tab_id: String,
    label: String,
    cpu: Option<f64>,
    memory: Option<u64>,
    running: bool,
    orphan: bool,
    history: Vec<u64>,
}

#[derive(Clone, Debug)]
struct ResourceWorkspace {
    name: String,
    remote: bool,
    sessions: Vec<ResourceSession>,
}

#[derive(Clone, Debug)]
struct ResourceProject {
    id: String,
    name: String,
    workspaces: Vec<ResourceWorkspace>,
}

#[derive(Clone, Debug, Default)]
struct ResourceTree {
    projects: Vec<ResourceProject>,
    orphans: Vec<ResourceSession>,
}

#[derive(Clone)]
struct ResourceUiActions {
    bridge: RuntimeBridge,
    confirmation: State<Option<ResourceCloseConfirmation>>,
    busy: State<bool>,
    message: State<Option<String>>,
    snapshot: State<Option<Result<Value, String>>>,
    selected_workspace: State<String>,
    selected_tab_request: State<Option<String>>,
    popover_open: State<bool>,
}

struct MetricRowConfig {
    indent: usize,
    text: String,
    suffix: Option<String>,
    cpu: Option<f64>,
    memory: Option<u64>,
    bold: bool,
    leading: Option<Bytes>,
    status_dot: Option<bool>,
    history: Vec<u64>,
    trailing: Option<Element>,
}

#[allow(clippy::too_many_arguments)]
pub fn panel(
    bridge: RuntimeBridge,
    snapshot_result: Option<Result<Value, String>>,
    workbench: Option<WorkbenchSnapshot>,
    sort_column: State<String>,
    collapsed_projects: State<Vec<String>>,
    confirmation: State<Option<ResourceCloseConfirmation>>,
    action_busy: State<bool>,
    action_message: State<Option<String>>,
    resource_snapshot: State<Option<Result<Value, String>>>,
    selected_workspace: State<String>,
    selected_tab_request: State<Option<String>>,
    popover_open: State<bool>,
) -> Element {
    let actions = ResourceUiActions {
        bridge: bridge.clone(),
        confirmation,
        busy: action_busy,
        message: action_message,
        snapshot: resource_snapshot,
        selected_workspace,
        selected_tab_request,
        popover_open,
    };
    let value = snapshot_result
        .as_ref()
        .and_then(|result| result.as_ref().ok());
    let error = snapshot_result
        .as_ref()
        .and_then(|result| result.as_ref().err())
        .cloned();
    let warming = value
        .and_then(|value| value.get("warming"))
        .and_then(Value::as_bool)
        .unwrap_or(true)
        || error.is_some();
    let cores = integer_at(value, &["host", "cpuCoreCount"])
        .unwrap_or(1)
        .max(1);
    let total_cpu = (!warming)
        .then(|| number_at(value, &["totals", "cpuPercent"]).map(|cpu| cpu / cores as f64))
        .flatten();
    let total_memory = (!warming)
        .then(|| integer_at(value, &["totals", "memoryBytes"]))
        .flatten();
    let host_memory = integer_at(value, &["host", "totalMemoryBytes"]);
    let tree = resource_tree(
        value,
        workbench.as_ref(),
        cores,
        sort_column.read().as_str(),
    );
    let orphans = tree.orphans.clone();
    let orphan_count = orphans.len();
    let empty = resource_tree_is_empty(&tree);
    let empty_message = empty_state_message(error.as_deref(), warming);

    let mut rows = rect().width(Size::fill()).vertical();
    rows = rows.padding(Gaps::new(0., 0., 0., 8.));
    if empty {
        rows = rows.height(Size::fill()).child(
            rect()
                .height(Size::fill())
                .vertical()
                .center()
                .spacing(10.)
                .child(
                    SvgViewer::new(icons::lucide::activity())
                        .width(Size::px(28.))
                        .height(Size::px(28.))
                        .color(FAINT),
                )
                .child(
                    label()
                        .font_size(12.)
                        .color(MUTED)
                        .max_lines(4)
                        .text_align(TextAlign::Center)
                        .text(empty_message),
                ),
        );
    } else {
        for project in tree.projects {
            rows = rows.child(project_rows(project, collapsed_projects, actions.clone()));
        }
        if !orphans.is_empty() {
            rows = rows.child(metric_row(MetricRowConfig {
                indent: 0,
                text: "Unattributed Terminals".to_string(),
                suffix: None,
                cpu: None,
                memory: None,
                bold: true,
                leading: None,
                status_dot: None,
                history: Vec::new(),
                trailing: None,
            }));
            for session in &orphans {
                rows = rows.child(session_row(session.clone(), actions.clone()));
            }
        }
        rows = rows.child(alera_process_rows(value, cores));
    }

    let mut body = rect()
        .width(Size::fill())
        .max_width(Size::px(PANEL_WIDTH))
        .height(Size::flex(1.))
        .vertical()
        .content(Content::Flex)
        .maybe_child(error.map(host_unreachable_notice))
        .child(totals_row(total_cpu, total_memory, host_memory))
        .child(sort_header(sort_column))
        .child(
            ScrollView::new()
                .width(Size::fill())
                .height(Size::flex(1.))
                .child(rows),
        );
    if orphan_count > 0 {
        body = body.child(orphan_footer(
            orphan_count,
            orphans,
            bridge,
            action_busy,
            action_message,
            resource_snapshot,
        ));
    }
    body.maybe_child(action_message.read().clone().map(|message| {
        label()
            .font_size(10.)
            .color(MUTED)
            .max_lines(3)
            .text(message)
    }))
    .into_element()
}

fn empty_state_message(error: Option<&str>, warming: bool) -> String {
    error.map(str::to_string).unwrap_or_else(|| {
        if warming {
            "Measuring Resource Usage".to_string()
        } else {
            "No Terminal Sessions Are Running".to_string()
        }
    })
}

fn resource_tree_is_empty(tree: &ResourceTree) -> bool {
    tree.projects.is_empty() && tree.orphans.is_empty()
}

fn project_rows(
    project: ResourceProject,
    collapsed_projects: State<Vec<String>>,
    actions: ResourceUiActions,
) -> Element {
    let collapsed = collapsed_projects.read().contains(&project.id);
    let (cpu, memory) = aggregate_workspaces(&project.workspaces);
    let project_header = ResourceProjectHeaderRow {
        project_id: project.id.clone(),
        name: project.name,
        cpu,
        memory,
        collapsed,
        collapsed_projects,
    };
    let mut rows = rect().width(Size::fill()).vertical().child(project_header);
    if !collapsed {
        for workspace in project.workspaces {
            let (workspace_cpu, workspace_memory) = aggregate_sessions(&workspace.sessions);
            rows = rows.child(metric_row(MetricRowConfig {
                indent: 1,
                text: workspace.name,
                suffix: workspace.remote.then(|| "remote".to_string()),
                cpu: workspace_cpu,
                memory: workspace_memory,
                bold: false,
                leading: None,
                status_dot: None,
                history: Vec::new(),
                trailing: None,
            }));
            for session in workspace.sessions {
                rows = rows.child(session_row(session, actions.clone()));
            }
        }
    }
    rows.into_element()
}

#[derive(Clone)]
struct ResourceProjectHeaderRow {
    project_id: String,
    name: String,
    cpu: Option<f64>,
    memory: Option<u64>,
    collapsed: bool,
    collapsed_projects: State<Vec<String>>,
}

impl PartialEq for ResourceProjectHeaderRow {
    fn eq(&self, other: &Self) -> bool {
        self.project_id == other.project_id
            && self.name == other.name
            && self.cpu == other.cpu
            && self.memory == other.memory
            && self.collapsed == other.collapsed
    }
}

impl Component for ResourceProjectHeaderRow {
    fn render(&self) -> impl IntoElement {
        let mut hovered = use_state(|| false);
        let project_id = self.project_id.clone();
        let mut collapsed_projects = self.collapsed_projects;
        metric_row(MetricRowConfig {
            indent: 0,
            text: self.name.clone(),
            suffix: None,
            cpu: self.cpu,
            memory: self.memory,
            bold: true,
            leading: Some(if self.collapsed {
                icons::lucide::chevron_right()
            } else {
                icons::lucide::chevron_down()
            }),
            status_dot: None,
            history: Vec::new(),
            trailing: None,
        })
        .background(if hovered() {
            Color::from_af32rgb(0.04, 245, 245, 245)
        } else {
            Color::TRANSPARENT
        })
        .a11y_role(AccessibilityRole::Button)
        .a11y_alt(if self.collapsed {
            format!("Expand {}", self.name)
        } else {
            format!("Collapse {}", self.name)
        })
        .on_pointer_enter(move |_| {
            hovered.set(true);
            Cursor::set(CursorIcon::Pointer);
        })
        .on_pointer_leave(move |_| {
            hovered.set(false);
            Cursor::set(CursorIcon::default());
        })
        .on_pointer_down(move |event: Event<PointerEventData>| {
            event.stop_propagation();
            let mut ids = collapsed_projects.write();
            if let Some(index) = ids.iter().position(|id| id == &project_id) {
                ids.remove(index);
            } else {
                ids.push(project_id.clone());
            }
        })
    }

    fn render_key(&self) -> DiffKey {
        DiffKey::from(&self.project_id)
    }
}

fn session_row(session: ResourceSession, actions: ResourceUiActions) -> Element {
    ResourceSessionRowComponent { session, actions }.into_element()
}

#[derive(Clone)]
struct ResourceSessionRowComponent {
    session: ResourceSession,
    actions: ResourceUiActions,
}

impl PartialEq for ResourceSessionRowComponent {
    fn eq(&self, other: &Self) -> bool {
        self.session == other.session
    }
}

impl Component for ResourceSessionRowComponent {
    fn render(&self) -> impl IntoElement {
        let mut hovered = use_state(|| false);
        let mut close_hovered = use_state(|| false);
        let session = self.session.clone();
        let orphan = session.orphan;
        let close_session = session.clone();
        let mut close_actions = self.actions.clone();
        let close_label = if orphan {
            "Kill Orphan Terminal"
        } else {
            "Close Terminal Session"
        };
        let trailing = TooltipContainer::new(Tooltip::new_text(close_label))
            .position(AttachedPosition::Left)
            .delay(Duration::from_millis(350))
            .child(
                rect()
                    .width(Size::px(17.))
                    .height(Size::px(26.))
                    .center()
                    .corner_radius(4.)
                    .background(if close_hovered() {
                        Color::from_rgb(51, 51, 51)
                    } else {
                        Color::TRANSPARENT
                    })
                    .a11y_role(AccessibilityRole::Button)
                    .a11y_alt(close_label)
                    .on_pointer_enter(move |_| {
                        close_hovered.set(true);
                        Cursor::set(CursorIcon::Pointer);
                    })
                    .on_pointer_leave(move |_| {
                        close_hovered.set(false);
                        Cursor::set(CursorIcon::default());
                    })
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        event.stop_propagation();
                        if orphan {
                            terminate_sessions(
                                close_actions.bridge.clone(),
                                vec![close_session.session_id.clone()],
                                close_actions.busy,
                                close_actions.message,
                                close_actions.snapshot,
                            );
                        } else {
                            close_actions
                                .confirmation
                                .set(Some(ResourceCloseConfirmation {
                                    tab_id: close_session.tab_id.clone(),
                                    label: close_session.label.clone(),
                                }));
                            close_actions.popover_open.set(false);
                        }
                    })
                    .child(
                        SvgViewer::new(icons::lucide::x())
                            .width(Size::px(11.))
                            .height(Size::px(11.))
                            .color(FAINT),
                    ),
            )
            .into_element();
        let mut row = metric_row(MetricRowConfig {
            indent: 2,
            text: session.label.clone(),
            suffix: None,
            cpu: session.cpu,
            memory: session.memory,
            bold: false,
            leading: None,
            status_dot: Some(session.running),
            history: session.history.clone(),
            trailing: Some(trailing),
        })
        .background(if hovered() {
            Color::from_af32rgb(0.04, 245, 245, 245)
        } else {
            Color::TRANSPARENT
        })
        .on_pointer_enter(move |_| {
            hovered.set(true);
            if !orphan {
                Cursor::set(CursorIcon::Pointer);
            }
        })
        .on_pointer_leave(move |_| {
            hovered.set(false);
            Cursor::set(CursorIcon::default());
        });
        if !orphan {
            let open_workspace = session.workspace_id;
            let open_tab = session.tab_id;
            let mut open_actions = self.actions.clone();
            row = row
                .a11y_role(AccessibilityRole::Button)
                .a11y_alt(format!("Open {}", session.label))
                .on_pointer_down(move |event: Event<PointerEventData>| {
                    event.stop_propagation();
                    open_actions.popover_open.set(false);
                    open_actions.selected_workspace.set(open_workspace.clone());
                    open_actions
                        .selected_tab_request
                        .set(Some(open_tab.clone()));
                });
        }
        row
    }

    fn render_key(&self) -> DiffKey {
        DiffKey::from(&self.session.session_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_resource_tree_shows_the_actual_host_error() {
        assert_eq!(
            empty_state_message(Some("runtime socket disappeared"), true),
            "runtime socket disappeared"
        );
    }

    #[test]
    fn empty_resource_tree_distinguishes_warming_from_idle() {
        assert_eq!(empty_state_message(None, true), "Measuring Resource Usage");
        assert_eq!(
            empty_state_message(None, false),
            "No Terminal Sessions Are Running"
        );
    }

    #[test]
    fn process_rows_do_not_replace_the_empty_terminal_state() {
        let tree = ResourceTree::default();

        assert!(resource_tree_is_empty(&tree));
    }

    #[test]
    fn resource_panel_width_matches_flutter_contract() {
        assert_eq!(PANEL_WIDTH, 420.);
    }
}
