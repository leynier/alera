use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};

use chrono::{DateTime, Duration, Utc};
use serde_json::Value;

use super::{AleraApp, SidebarSortBy};
use crate::model::{Project, Workspace};

impl AleraApp {
    pub(super) fn sort_sidebar_projects(&self, projects: &mut Vec<&Project>, filter: &str) {
        projects.sort_by(|left, right| match self.sidebar_project_sort {
            SidebarSortBy::Name => compare_names(&left.name, &right.name),
            SidebarSortBy::Recent => project_recency(right)
                .cmp(project_recency(left))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Activity => compare_agent_activity(
                self.project_activity(left, filter),
                &left.name,
                self.project_activity(right, filter),
                &right.name,
            ),
        });
    }

    pub(super) fn sort_sidebar_workspaces(&self, workspaces: &mut Vec<&Workspace>) {
        match self.sidebar_workspace_sort {
            SidebarSortBy::Name => workspaces.sort_by(|left, right| {
                main_rank(left)
                    .cmp(&main_rank(right))
                    .then_with(|| compare_names(&left.name, &right.name))
            }),
            SidebarSortBy::Recent => workspaces.sort_by(|left, right| {
                main_rank(left)
                    .cmp(&main_rank(right))
                    .then_with(|| right.updated_at.cmp(&left.updated_at))
                    .then_with(|| compare_names(&left.name, &right.name))
            }),
            SidebarSortBy::Activity => {
                let activity = self.subtree_activity_ranks(workspaces.iter().copied());
                workspaces.sort_by(|left, right| {
                    compare_agent_activity(
                        activity.get(left.id.as_str()).copied().flatten(),
                        &left.name,
                        activity.get(right.id.as_str()).copied().flatten(),
                        &right.name,
                    )
                });
            }
        }
    }

    pub(super) fn sort_sidebar_workspace_pairs<'a>(
        &self,
        workspaces: &mut Vec<(&'a Project, &'a Workspace)>,
    ) {
        if self.sidebar_workspace_sort != SidebarSortBy::Activity {
            workspaces
                .sort_by(|(_, left), (_, right)| self.compare_non_activity_workspaces(left, right));
            return;
        }
        let activity =
            self.subtree_activity_ranks(workspaces.iter().map(|(_, workspace)| *workspace));
        workspaces.sort_by(|(_, left), (_, right)| {
            compare_agent_activity(
                activity.get(left.id.as_str()).copied().flatten(),
                &left.name,
                activity.get(right.id.as_str()).copied().flatten(),
                &right.name,
            )
        });
    }

    fn compare_non_activity_workspaces(&self, left: &Workspace, right: &Workspace) -> Ordering {
        match self.sidebar_workspace_sort {
            SidebarSortBy::Name => main_rank(left)
                .cmp(&main_rank(right))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Recent => main_rank(left)
                .cmp(&main_rank(right))
                .then_with(|| right.updated_at.cmp(&left.updated_at))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Activity => unreachable!("activity is handled by subtree ranks"),
        }
    }

    fn project_activity(&self, project: &Project, filter: &str) -> Option<AgentActivityRank> {
        project
            .workspaces
            .iter()
            .filter(|workspace| {
                self.sidebar_workspace_visible(workspace)
                    && workspace_matches_filter(project, workspace, filter)
            })
            .filter_map(|workspace| self.direct_activity_rank(workspace))
            .reduce(best_agent_activity)
    }

    fn subtree_activity_ranks<'a, I>(
        &self,
        workspaces: I,
    ) -> BTreeMap<String, Option<AgentActivityRank>>
    where
        I: IntoIterator<Item = &'a Workspace>,
    {
        let workspaces = workspaces.into_iter().collect::<Vec<_>>();
        let ids = workspaces
            .iter()
            .map(|workspace| workspace.id.clone())
            .collect::<BTreeSet<_>>();
        let mut children = BTreeMap::<String, Vec<String>>::new();
        for relation in &self.snapshot.relations {
            if ids.contains(&relation.parent_workspace_id)
                && ids.contains(&relation.child_workspace_id)
                && relation.parent_workspace_id != relation.child_workspace_id
            {
                children
                    .entry(relation.parent_workspace_id.clone())
                    .or_default()
                    .push(relation.child_workspace_id.clone());
            }
        }
        let direct = workspaces
            .iter()
            .map(|workspace| (workspace.id.clone(), self.direct_activity_rank(workspace)))
            .collect::<BTreeMap<_, _>>();
        let mut aggregate = BTreeMap::new();
        let mut visiting = BTreeSet::new();
        for workspace in &workspaces {
            aggregate_activity(
                &workspace.id,
                &children,
                &direct,
                &mut aggregate,
                &mut visiting,
            );
        }
        aggregate
    }

    fn direct_activity_rank(&self, workspace: &Workspace) -> Option<AgentActivityRank> {
        let terminal_tabs = self
            .snapshot
            .all_tabs
            .iter()
            .filter(|tab| tab.workspace_id == workspace.id && tab.kind == "terminal")
            .collect::<Vec<_>>();
        if terminal_tabs.is_empty() {
            return None;
        }

        let now = Utc::now();
        let mut best = None;
        for tab in terminal_tabs {
            let Some(entry) = self.matching_presence_for_tab(tab) else {
                continue;
            };
            let Some(updated_at) = json_timestamp(entry, "updatedAt") else {
                continue;
            };
            if now.signed_duration_since(updated_at) > Duration::minutes(30) {
                continue;
            }
            let state = if entry
                .get("interrupted")
                .and_then(Value::as_bool)
                .unwrap_or(false)
            {
                AgentAttentionClass::NeedsYou
            } else {
                match entry.get("agentState").and_then(Value::as_str) {
                    Some("waiting") | Some("blocked") => AgentAttentionClass::NeedsYou,
                    Some("done") => AgentAttentionClass::Done,
                    _ => AgentAttentionClass::Working,
                }
            };
            let activity_at = json_timestamp(entry, "stateStartedAt").unwrap_or(updated_at);
            let candidate = AgentActivityRank {
                class: state,
                activity_at,
            };
            best = Some(best.map_or(candidate, |current| best_agent_activity(current, candidate)));
        }
        Some(best.unwrap_or_else(|| {
            AgentActivityRank {
                class: AgentAttentionClass::Idle,
                activity_at: self
                    .snapshot
                    .activity
                    .get(&workspace.id)
                    .and_then(|timestamp| json_timestamp_string(timestamp))
                    .or_else(|| json_timestamp_string(&workspace.updated_at))
                    .unwrap_or(DateTime::<Utc>::UNIX_EPOCH),
            }
        }))
    }

    pub(super) fn matching_presence_for_tab<'a>(
        &'a self,
        tab: &crate::model::WorkspaceTab,
    ) -> Option<&'a Value> {
        let session_id = tab
            .payload
            .get("terminalSessionId")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(tab.id.as_str());
        self.status_data.presence.iter().find(|entry| {
            entry.get("workspaceId").and_then(Value::as_str) == Some(tab.workspace_id.as_str())
                && entry.get("tabId").and_then(Value::as_str) == Some(tab.id.as_str())
                && entry
                    .get("handle")
                    .and_then(Value::as_str)
                    .is_none_or(|handle| handle == session_id)
                && entry.get("agentState").and_then(Value::as_str).is_some()
        })
    }
}

fn compare_names(left: &str, right: &str) -> Ordering {
    left.to_lowercase().cmp(&right.to_lowercase())
}

fn workspace_matches_filter(project: &Project, workspace: &Workspace, filter: &str) -> bool {
    filter.is_empty()
        || project.name.to_lowercase().contains(filter)
        || workspace.name.to_lowercase().contains(filter)
        || workspace
            .branch
            .as_deref()
            .is_some_and(|branch| branch.to_lowercase().contains(filter))
        || workspace
            .source_branch
            .as_deref()
            .is_some_and(|branch| branch.to_lowercase().contains(filter))
}

fn project_recency(project: &Project) -> &str {
    // The Flutter listing uses the project record's updatedAt for project
    // ordering. Deriving recency from the newest child workspace can reorder
    // projects differently after a workspace-only update.
    project.updated_at.as_str()
}

fn main_rank(workspace: &Workspace) -> u8 {
    u8::from(workspace.kind != "main")
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
enum AgentAttentionClass {
    NeedsYou,
    Done,
    Working,
    Idle,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct AgentActivityRank {
    class: AgentAttentionClass,
    activity_at: DateTime<Utc>,
}

fn best_agent_activity(left: AgentActivityRank, right: AgentActivityRank) -> AgentActivityRank {
    match left.class.cmp(&right.class) {
        Ordering::Less => left,
        Ordering::Greater => right,
        Ordering::Equal => {
            if left.activity_at >= right.activity_at {
                left
            } else {
                right
            }
        }
    }
}

fn compare_agent_activity(
    left: Option<AgentActivityRank>,
    left_name: &str,
    right: Option<AgentActivityRank>,
    right_name: &str,
) -> Ordering {
    match (left, right) {
        (Some(left), Some(right)) => left
            .class
            .cmp(&right.class)
            .then_with(|| right.activity_at.cmp(&left.activity_at))
            .then_with(|| compare_names(left_name, right_name)),
        (Some(_), None) => Ordering::Less,
        (None, Some(_)) => Ordering::Greater,
        (None, None) => compare_names(left_name, right_name),
    }
}

fn aggregate_activity(
    workspace_id: &str,
    children: &BTreeMap<String, Vec<String>>,
    direct: &BTreeMap<String, Option<AgentActivityRank>>,
    aggregate: &mut BTreeMap<String, Option<AgentActivityRank>>,
    visiting: &mut BTreeSet<String>,
) -> Option<AgentActivityRank> {
    if let Some(value) = aggregate.get(workspace_id) {
        return *value;
    }
    if !visiting.insert(workspace_id.to_owned()) {
        return direct.get(workspace_id).copied().flatten();
    }
    let mut best = direct.get(workspace_id).copied().flatten();
    if let Some(child_ids) = children.get(workspace_id) {
        for child_id in child_ids {
            if let Some(child) = aggregate_activity(child_id, children, direct, aggregate, visiting)
            {
                best = Some(best.map_or(child, |current| best_agent_activity(current, child)));
            }
        }
    }
    visiting.remove(workspace_id);
    aggregate.insert(workspace_id.to_owned(), best);
    best
}

fn json_timestamp(value: &Value, key: &str) -> Option<DateTime<Utc>> {
    value
        .get(key)
        .and_then(Value::as_str)
        .and_then(json_timestamp_string)
}

fn json_timestamp_string(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|value| value.with_timezone(&Utc))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rank(class: AgentAttentionClass, timestamp: &str) -> AgentActivityRank {
        AgentActivityRank {
            class,
            activity_at: json_timestamp_string(timestamp).unwrap(),
        }
    }

    #[test]
    fn agent_activity_urgency_matches_flutter_order() {
        let done = rank(AgentAttentionClass::Done, "2026-08-24T12:00:00Z");
        let working = rank(AgentAttentionClass::Working, "2026-08-24T13:00:00Z");
        let waiting = rank(AgentAttentionClass::NeedsYou, "2026-08-24T11:00:00Z");

        assert_eq!(
            compare_agent_activity(Some(waiting), "Waiting", Some(done), "Done"),
            Ordering::Less
        );
        assert_eq!(
            compare_agent_activity(Some(done), "Done", Some(working), "Working"),
            Ordering::Less
        );
        assert_eq!(
            compare_agent_activity(Some(working), "Working", None, "Idle"),
            Ordering::Less
        );
    }

    #[test]
    fn subtree_activity_promotes_the_most_urgent_descendant() {
        let children = BTreeMap::from([("root".to_string(), vec!["child".to_string()])]);
        let direct = BTreeMap::from([
            (
                "root".to_string(),
                Some(rank(AgentAttentionClass::Idle, "2026-08-24T10:00:00Z")),
            ),
            (
                "child".to_string(),
                Some(rank(AgentAttentionClass::NeedsYou, "2026-08-24T09:00:00Z")),
            ),
        ]);
        let mut aggregate = BTreeMap::new();
        let mut visiting = BTreeSet::new();
        let result =
            aggregate_activity("root", &children, &direct, &mut aggregate, &mut visiting).unwrap();

        assert_eq!(result.class, AgentAttentionClass::NeedsYou);
    }
}
