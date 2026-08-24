use std::{cmp::Ordering, collections::BTreeMap};

use alera_desktop_core::WorkbenchSnapshot;
use serde_json::Value;

use super::{ResourceProject, ResourceSession, ResourceTree, ResourceWorkspace};

pub(super) fn resource_tree(
    value: Option<&Value>,
    workbench: Option<&WorkbenchSnapshot>,
    cores: u64,
    sort_column: &str,
) -> ResourceTree {
    let mut sessions_by_workspace: BTreeMap<String, Vec<ResourceSession>> = BTreeMap::new();
    let mut orphans = Vec::new();
    for session in value
        .and_then(|value| value.get("sessions"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let workspace_id = string_at(session, "workspaceId")
            .unwrap_or_default()
            .to_string();
        let session_id = string_at(session, "sessionId")
            .unwrap_or_default()
            .to_string();
        if session_id.is_empty() {
            continue;
        }
        let fallback_tab_id = string_at(session, "tabId").unwrap_or_default();
        let tab = workbench.and_then(|workbench| {
            workbench.tabs.iter().find(|tab| {
                tab.kind == "terminal"
                    && tab
                        .payload
                        .get("terminalSessionId")
                        .and_then(Value::as_str)
                        .filter(|id| !id.trim().is_empty())
                        .unwrap_or(&tab.id)
                        == session_id
            })
        });
        let orphan = tab.is_none();
        let remote = workbench.is_some_and(|workbench| {
            workbench
                .projects
                .iter()
                .flat_map(|project| &project.workspaces)
                .find(|workspace| workspace.id == workspace_id)
                .is_some_and(|workspace| workspace.host_id != "local")
        });
        let measured = session
            .get("measured")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let row = ResourceSession {
            session_id: session_id.clone(),
            workspace_id: workspace_id.clone(),
            tab_id: tab.map_or(fallback_tab_id, |tab| &tab.id).to_string(),
            label: tab
                .map(|tab| tab.title.trim())
                .filter(|title| !title.is_empty())
                .unwrap_or(&session_id)
                .to_string(),
            cpu: (!remote && measured)
                .then(|| session.get("cpuPercent").and_then(Value::as_f64))
                .flatten()
                .map(|cpu| cpu / cores as f64),
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
    let mut projects = workbench
        .into_iter()
        .flat_map(|workbench| &workbench.projects)
        .filter_map(|project| {
            let workspaces = project
                .workspaces
                .iter()
                .filter_map(|workspace| {
                    sessions_by_workspace
                        .remove(&workspace.id)
                        .map(|mut sessions| {
                            sort_sessions(&mut sessions, sort_column);
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
    sort_projects(&mut projects, sort_column);
    sort_sessions(&mut orphans, sort_column);
    ResourceTree { projects, orphans }
}

fn sort_sessions(sessions: &mut [ResourceSession], column: &str) {
    sessions.sort_by(|left, right| match column {
        "cpu" => compare_optional_descending(left.cpu, right.cpu)
            .then_with(|| compare_name(&left.label, &right.label)),
        "memory" => compare_optional_descending(left.memory, right.memory)
            .then_with(|| compare_name(&left.label, &right.label)),
        _ => compare_name(&left.label, &right.label),
    });
}

fn sort_projects(projects: &mut [ResourceProject], column: &str) {
    for project in projects.iter_mut() {
        project.workspaces.sort_by(|left, right| match column {
            "cpu" => compare_optional_descending(
                aggregate_sessions(&left.sessions).0,
                aggregate_sessions(&right.sessions).0,
            )
            .then_with(|| compare_name(&left.name, &right.name)),
            "memory" => compare_optional_descending(
                aggregate_sessions(&left.sessions).1,
                aggregate_sessions(&right.sessions).1,
            )
            .then_with(|| compare_name(&left.name, &right.name)),
            _ => compare_name(&left.name, &right.name),
        });
    }
    projects.sort_by(|left, right| match column {
        "cpu" => compare_optional_descending(
            aggregate_workspaces(&left.workspaces).0,
            aggregate_workspaces(&right.workspaces).0,
        )
        .then_with(|| compare_name(&left.name, &right.name)),
        "memory" => compare_optional_descending(
            aggregate_workspaces(&left.workspaces).1,
            aggregate_workspaces(&right.workspaces).1,
        )
        .then_with(|| compare_name(&left.name, &right.name)),
        _ => compare_name(&left.name, &right.name),
    });
}

pub(super) fn aggregate_workspaces(workspaces: &[ResourceWorkspace]) -> (Option<f64>, Option<u64>) {
    workspaces.iter().fold((None, None), |total, workspace| {
        let next = aggregate_sessions(&workspace.sessions);
        (sum_optional(total.0, next.0), sum_optional(total.1, next.1))
    })
}

pub(super) fn aggregate_sessions(sessions: &[ResourceSession]) -> (Option<f64>, Option<u64>) {
    sessions.iter().fold((None, None), |total, session| {
        (
            sum_optional(total.0, session.cpu),
            sum_optional(total.1, session.memory),
        )
    })
}

pub(super) fn sum_optional<T>(left: Option<T>, right: Option<T>) -> Option<T>
where
    T: Default + std::ops::Add<Output = T>,
{
    match (left, right) {
        (None, None) => None,
        (left, right) => Some(left.unwrap_or_default() + right.unwrap_or_default()),
    }
}

fn compare_name(left: &str, right: &str) -> Ordering {
    left.to_lowercase().cmp(&right.to_lowercase())
}

fn compare_optional_descending<T: PartialOrd>(left: Option<T>, right: Option<T>) -> Ordering {
    match (left, right) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (Some(left), Some(right)) => right.partial_cmp(&left).unwrap_or(Ordering::Equal),
    }
}

fn string_at<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

#[cfg(test)]
mod tests {
    use alera_desktop_core::{Project, Workspace, WorkspaceTab};
    use serde_json::json;

    use super::*;

    #[test]
    fn resource_tree_projects_sessions_and_orphans_match_flutter() {
        let mut workbench = WorkbenchSnapshot::default();
        workbench.projects.push(Project {
            id: "project".to_string(),
            name: "Project".to_string(),
            repo_path: "/repo".to_string(),
            kind: "local".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
            workspaces: vec![Workspace {
                id: "workspace".to_string(),
                name: "Main".to_string(),
                path: "/repo".to_string(),
                branch: Some("main".to_string()),
                source_branch: None,
                kind: "local".to_string(),
                status: "idle".to_string(),
                updated_at: String::new(),
                host_id: "local".to_string(),
                reuses_existing_branch: true,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
            }],
        });
        workbench.tabs.push(WorkspaceTab {
            id: "tab".to_string(),
            workspace_id: "workspace".to_string(),
            title: "Terminal 1".to_string(),
            kind: "terminal".to_string(),
            payload: json!({"terminalSessionId": "session"}),
        });
        let snapshot = json!({
            "sessions": [
                {"sessionId":"session","workspaceId":"workspace","tabId":"tab","running":true,"measured":true,"cpuPercent":200.0,"memoryBytes":1024},
                {"sessionId":"orphan","workspaceId":"missing","tabId":"missing","running":true,"measured":true,"cpuPercent":100.0,"memoryBytes":2048}
            ]
        });
        let tree = resource_tree(Some(&snapshot), Some(&workbench), 4, "memory");
        assert_eq!(tree.projects.len(), 1);
        assert_eq!(
            tree.projects[0].workspaces[0].sessions[0].label,
            "Terminal 1"
        );
        assert_eq!(tree.projects[0].workspaces[0].sessions[0].cpu, Some(50.0));
        assert_eq!(tree.orphans.len(), 1);
        assert!(tree.orphans[0].orphan);
    }

    #[test]
    fn resource_sort_keeps_unknown_values_last() {
        let mut sessions = vec![
            ResourceSession {
                session_id: "a".to_string(),
                workspace_id: String::new(),
                tab_id: String::new(),
                label: "Unknown".to_string(),
                cpu: None,
                memory: None,
                running: false,
                orphan: true,
                history: Vec::new(),
            },
            ResourceSession {
                session_id: "b".to_string(),
                workspace_id: String::new(),
                tab_id: String::new(),
                label: "Measured".to_string(),
                cpu: Some(12.),
                memory: Some(10),
                running: true,
                orphan: true,
                history: Vec::new(),
            },
        ];
        sort_sessions(&mut sessions, "cpu");
        assert_eq!(sessions[0].label, "Measured");
        assert_eq!(sessions[1].label, "Unknown");
    }

    #[test]
    fn metric_sort_uses_names_to_break_project_and_workspace_ties() {
        let session = |label: &str| ResourceSession {
            session_id: label.to_string(),
            workspace_id: String::new(),
            tab_id: String::new(),
            label: label.to_string(),
            cpu: Some(5.),
            memory: Some(10),
            running: true,
            orphan: false,
            history: Vec::new(),
        };
        let workspace = |name: &str| ResourceWorkspace {
            name: name.to_string(),
            remote: false,
            sessions: vec![session(name)],
        };
        let mut projects = vec![
            ResourceProject {
                id: "zulu".to_string(),
                name: "Zulu".to_string(),
                workspaces: vec![workspace("Zulu Workspace"), workspace("Alpha Workspace")],
            },
            ResourceProject {
                id: "alpha".to_string(),
                name: "Alpha".to_string(),
                workspaces: vec![workspace("Only Workspace"), workspace("Second Workspace")],
            },
        ];

        sort_projects(&mut projects, "memory");

        assert_eq!(projects[0].name, "Alpha");
        assert_eq!(projects[1].name, "Zulu");
        assert_eq!(projects[1].workspaces[0].name, "Alpha Workspace");
        assert_eq!(projects[1].workspaces[1].name, "Zulu Workspace");
    }
}
