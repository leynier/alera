use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

use alera_desktop_core::{Project, WorkbenchSnapshot, Workspace, WorkspaceRelation};
use chrono::{DateTime, Duration, Utc};
use serde_json::Value;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum SidebarGroupBy {
    None,
    #[default]
    Project,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum SidebarSortBy {
    #[default]
    Name,
    Recent,
    Activity,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum SidebarWorkspaceKind {
    #[default]
    All,
    DefaultOnly,
    NonDefaultOnly,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SidebarViewPrefs {
    pub group_by: SidebarGroupBy,
    pub project_sort: SidebarSortBy,
    pub workspace_sort: SidebarSortBy,
    pub workspace_kind: SidebarWorkspaceKind,
    pub selected_project_ids: HashSet<String>,
    pub selected_tag_ids: HashSet<String>,
    pub collapsed_project_ids: HashSet<String>,
    pub collapsed_parent_workspace_ids: HashSet<String>,
    pub expanded_workspace_ids: HashSet<String>,
    pub pinned_section_collapsed: bool,
    pub all_section_collapsed: bool,
    pub show_pinned_workspaces_below: bool,
}

impl Default for SidebarViewPrefs {
    fn default() -> Self {
        Self {
            group_by: SidebarGroupBy::Project,
            project_sort: SidebarSortBy::Name,
            workspace_sort: SidebarSortBy::Name,
            workspace_kind: SidebarWorkspaceKind::All,
            selected_project_ids: HashSet::new(),
            selected_tag_ids: HashSet::new(),
            collapsed_project_ids: HashSet::new(),
            collapsed_parent_workspace_ids: HashSet::new(),
            expanded_workspace_ids: HashSet::new(),
            pinned_section_collapsed: false,
            all_section_collapsed: false,
            show_pinned_workspaces_below: true,
        }
    }
}

impl SidebarViewPrefs {
    pub fn from_record(record: Option<&Value>) -> Self {
        let prefs = record
            .and_then(|record| record.get("prefs").or(Some(record)))
            .filter(|value| value.is_object());
        let Some(prefs) = prefs else {
            return Self::default();
        };
        Self {
            group_by: match string_field(prefs, "groupBy") {
                "none" => SidebarGroupBy::None,
                _ => SidebarGroupBy::Project,
            },
            project_sort: parse_sort(string_field(prefs, "projectSort")),
            workspace_sort: parse_sort(string_field(prefs, "workspaceSort")),
            workspace_kind: match string_field(prefs, "workspaceKindFilter") {
                "defaultOnly" => SidebarWorkspaceKind::DefaultOnly,
                "nonDefaultOnly" => SidebarWorkspaceKind::NonDefaultOnly,
                _ => SidebarWorkspaceKind::All,
            },
            selected_project_ids: string_set(prefs.get("selectedProjectIds")),
            selected_tag_ids: string_set(prefs.get("selectedTagIds")),
            collapsed_project_ids: string_set(prefs.get("collapsedProjectIds")),
            collapsed_parent_workspace_ids: string_set(prefs.get("collapsedParentWorkspaceIds")),
            expanded_workspace_ids: string_set(prefs.get("expandedWorkspaceIds")),
            pinned_section_collapsed: bool_field(prefs, "pinnedSectionCollapsed", false),
            all_section_collapsed: bool_field(prefs, "allSectionCollapsed", false),
            show_pinned_workspaces_below: bool_field(prefs, "showPinnedWorkspacesBelow", true),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum AgentRunState {
    Waiting,
    Blocked,
    Interrupted,
    Working,
    Done,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SidebarAgentRun {
    pub tab_id: String,
    pub terminal_session_id: String,
    pub agent_type: String,
    pub state: AgentRunState,
    pub description: String,
    pub state_started_at: String,
    pub updated_at: String,
}

impl SidebarAgentRun {
    pub fn from_presence(value: &Value) -> Option<Self> {
        let interrupted = value
            .get("interrupted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let raw_state = value.get("state").and_then(Value::as_str)?;
        let state = if interrupted {
            AgentRunState::Interrupted
        } else {
            match raw_state {
                "waiting" => AgentRunState::Waiting,
                "blocked" => AgentRunState::Blocked,
                "working" => AgentRunState::Working,
                "done" => AgentRunState::Done,
                _ => return None,
            }
        };
        let agent_type = value
            .get("agentType")
            .and_then(Value::as_str)
            .unwrap_or("codex")
            .to_string();
        let tool_name = trimmed_field(value, "toolName");
        let tool_input = trimmed_field(value, "toolInput");
        let assistant = trimmed_field(value, "lastAssistantMessage");
        let description = if state == AgentRunState::Working && !tool_name.is_empty() {
            if tool_input.is_empty() {
                tool_name
            } else {
                format!("{tool_name}: {tool_input}")
            }
        } else if !assistant.is_empty() {
            assistant
        } else {
            format!("{} · {}", agent_display_name(&agent_type), state.label())
        };
        Some(Self {
            tab_id: value.get("tabId")?.as_str()?.to_string(),
            terminal_session_id: value
                .get("terminalSessionId")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            agent_type,
            state,
            description,
            state_started_at: value
                .get("stateStartedAt")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            updated_at: value
                .get("updatedAt")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
        })
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ActivityRank {
    attention_class: u8,
    activity_at: String,
}

impl AgentRunState {
    pub fn label(self) -> &'static str {
        match self {
            Self::Waiting => "Waiting for input",
            Self::Blocked => "Blocked",
            Self::Interrupted => "Interrupted",
            Self::Working => "Working",
            Self::Done => "Done",
        }
    }

    fn priority(self) -> u8 {
        match self {
            Self::Blocked => 5,
            Self::Waiting => 4,
            Self::Interrupted => 3,
            Self::Working => 2,
            Self::Done => 1,
        }
    }
}

#[derive(Clone, Debug)]
pub struct SidebarWorkspaceRow {
    pub id: String,
    pub name: String,
    pub path: String,
    pub project_name: String,
    pub depth: usize,
    pub is_pinned: bool,
    pub is_pinned_copy: bool,
    pub is_default: bool,
    pub branch_label: String,
    pub tag_ids: Vec<String>,
    pub tag_names: Vec<String>,
    pub host_id: Option<String>,
    pub has_terminal_tabs: bool,
    pub agent_runs: Vec<SidebarAgentRun>,
    pub agents_expanded: bool,
    pub visible_child_count: usize,
    pub children_collapsed: bool,
    pub parent_id: Option<String>,
    pub reuses_existing_branch: bool,
    pub show_project_chip: bool,
}

impl SidebarWorkspaceRow {
    pub fn aggregate_state(&self) -> Option<AgentRunState> {
        self.agent_runs
            .iter()
            .max_by_key(|run| (run.state.priority(), run.updated_at.as_str()))
            .map(|run| run.state)
    }
}

#[derive(Clone, Debug)]
pub enum SidebarRow {
    PinnedHeader {
        count: usize,
        collapsed: bool,
    },
    AllHeader {
        count: usize,
        collapsed: bool,
    },
    ProjectHeader {
        id: String,
        name: String,
        count: usize,
        collapsed: bool,
        supports_linked_workspaces: bool,
    },
    Workspace(Box<SidebarWorkspaceRow>),
}

pub struct SidebarProjection<'a> {
    snapshot: &'a WorkbenchSnapshot,
    prefs: &'a SidebarViewPrefs,
    query: String,
    active_workspace_ids: &'a HashSet<String>,
    presence_by_workspace: HashMap<String, Vec<SidebarAgentRun>>,
    now: DateTime<Utc>,
}

impl<'a> SidebarProjection<'a> {
    pub fn new(
        snapshot: &'a WorkbenchSnapshot,
        prefs: &'a SidebarViewPrefs,
        query: &str,
        active_workspace_ids: &'a HashSet<String>,
        presence: &[Value],
    ) -> Self {
        Self::new_at(
            snapshot,
            prefs,
            query,
            active_workspace_ids,
            presence,
            Utc::now(),
        )
    }

    fn new_at(
        snapshot: &'a WorkbenchSnapshot,
        prefs: &'a SidebarViewPrefs,
        query: &str,
        active_workspace_ids: &'a HashSet<String>,
        presence: &[Value],
        now: DateTime<Utc>,
    ) -> Self {
        let mut presence_by_workspace = HashMap::<String, Vec<SidebarAgentRun>>::new();
        for value in presence {
            let Some(workspace_id) = value.get("workspaceId").and_then(Value::as_str) else {
                continue;
            };
            if let Some(run) = SidebarAgentRun::from_presence(value) {
                presence_by_workspace
                    .entry(workspace_id.to_string())
                    .or_default()
                    .push(run);
            }
        }
        Self {
            snapshot,
            prefs,
            query: query.trim().to_lowercase(),
            active_workspace_ids,
            presence_by_workspace,
            now,
        }
    }

    pub fn build(&self) -> Vec<SidebarRow> {
        let mut projects = self
            .snapshot
            .projects
            .iter()
            .filter(|project| {
                self.prefs.selected_project_ids.is_empty()
                    || self.prefs.selected_project_ids.contains(&project.id)
            })
            .collect::<Vec<_>>();
        self.sort_projects(&mut projects);

        let mut pinned = Vec::<(&Project, &Workspace)>::new();
        for project in &projects {
            let mut workspaces = self.visible_workspaces(project, true, false);
            self.sort_workspaces(
                &mut workspaces,
                self.prefs.group_by == SidebarGroupBy::Project,
            );
            pinned.extend(
                workspaces
                    .into_iter()
                    .map(|workspace| (*project, workspace)),
            );
        }
        if self.prefs.group_by == SidebarGroupBy::None
            || self.prefs.workspace_sort == SidebarSortBy::Activity
        {
            self.sort_project_workspace_pairs(&mut pinned, false);
        }

        let mut rows = Vec::new();
        let has_pinned = !pinned.is_empty();
        if has_pinned {
            rows.push(SidebarRow::PinnedHeader {
                count: pinned.len(),
                collapsed: self.prefs.pinned_section_collapsed,
            });
            if !self.prefs.pinned_section_collapsed {
                rows.extend(self.workspace_rows_from_pairs(pinned, 0, true, true, true));
            }
        }

        match self.prefs.group_by {
            SidebarGroupBy::Project => {
                for project in projects {
                    let mut workspaces = self.visible_workspaces(
                        project,
                        false,
                        !self.prefs.show_pinned_workspaces_below,
                    );
                    self.sort_workspaces(&mut workspaces, true);
                    let filters_hide_empty = !self.query.is_empty()
                        || !self.prefs.selected_tag_ids.is_empty()
                        || self.prefs.workspace_kind != SidebarWorkspaceKind::All
                        || !self.prefs.show_pinned_workspaces_below;
                    if filters_hide_empty && workspaces.is_empty() {
                        continue;
                    }
                    let collapsed = self.prefs.collapsed_project_ids.contains(&project.id);
                    rows.push(SidebarRow::ProjectHeader {
                        id: project.id.clone(),
                        name: project.name.clone(),
                        count: workspaces.len(),
                        collapsed,
                        supports_linked_workspaces: project.kind != "folder",
                    });
                    if !collapsed {
                        let pairs = workspaces
                            .into_iter()
                            .map(|workspace| (project, workspace))
                            .collect();
                        rows.extend(self.workspace_rows_from_pairs(pairs, 1, false, false, false));
                    }
                }
            }
            SidebarGroupBy::None => {
                let mut workspaces = Vec::<(&Project, &Workspace)>::new();
                for project in projects {
                    workspaces.extend(
                        self.visible_workspaces(
                            project,
                            false,
                            !self.prefs.show_pinned_workspaces_below,
                        )
                        .into_iter()
                        .map(|workspace| (project, workspace)),
                    );
                }
                self.sort_project_workspace_pairs(&mut workspaces, false);
                let show_all = has_pinned && !workspaces.is_empty();
                if show_all {
                    rows.push(SidebarRow::AllHeader {
                        count: workspaces.len(),
                        collapsed: self.prefs.all_section_collapsed,
                    });
                }
                if !show_all || !self.prefs.all_section_collapsed {
                    rows.extend(self.workspace_rows_from_pairs(workspaces, 0, true, false, false));
                }
            }
        }
        rows
    }

    fn visible_workspaces<'b>(
        &self,
        project: &'b Project,
        pinned_only: bool,
        exclude_pinned: bool,
    ) -> Vec<&'b Workspace> {
        let project_matches =
            self.query.is_empty() || project.name.to_lowercase().contains(self.query.as_str());
        project
            .workspaces
            .iter()
            .filter(|workspace| {
                let kind_visible = match self.prefs.workspace_kind {
                    SidebarWorkspaceKind::All => true,
                    SidebarWorkspaceKind::DefaultOnly => workspace.kind == "main",
                    SidebarWorkspaceKind::NonDefaultOnly => workspace.kind != "main",
                };
                let tags_visible = self.prefs.selected_tag_ids.is_empty()
                    || workspace
                        .tag_ids
                        .iter()
                        .any(|tag| self.prefs.selected_tag_ids.contains(tag));
                let query_visible =
                    project_matches
                        || workspace.name.to_lowercase().contains(self.query.as_str())
                        || workspace.branch.as_deref().is_some_and(|branch| {
                            branch.to_lowercase().contains(self.query.as_str())
                        })
                        || workspace.source_branch.as_deref().is_some_and(|branch| {
                            branch.to_lowercase().contains(self.query.as_str())
                        });
                kind_visible
                    && tags_visible
                    && (!pinned_only || workspace.is_pinned)
                    && (!exclude_pinned || !workspace.is_pinned)
                    && query_visible
            })
            .collect()
    }

    fn sort_projects(&self, projects: &mut Vec<&Project>) {
        projects.sort_by(|left, right| match self.prefs.project_sort {
            SidebarSortBy::Name => compare_names(&left.name, &right.name),
            SidebarSortBy::Recent => right
                .updated_at
                .cmp(&left.updated_at)
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Activity => compare_activity(
                self.project_activity(left).as_ref(),
                &left.name,
                self.project_activity(right).as_ref(),
                &right.name,
            ),
        });
    }

    fn sort_workspaces(&self, workspaces: &mut Vec<&Workspace>, pin_main_on_recent: bool) {
        if self.prefs.workspace_sort == SidebarSortBy::Activity {
            let activity = self.aggregate_activity(workspaces);
            workspaces.sort_by(|left, right| {
                compare_activity(
                    activity.get(&left.id).and_then(Option::as_ref),
                    &left.name,
                    activity.get(&right.id).and_then(Option::as_ref),
                    &right.name,
                )
            });
            return;
        }
        workspaces.sort_by(|left, right| self.compare_workspaces(left, right, pin_main_on_recent));
    }

    fn sort_project_workspace_pairs(
        &self,
        workspaces: &mut Vec<(&Project, &Workspace)>,
        pin_main_on_recent: bool,
    ) {
        if self.prefs.workspace_sort == SidebarSortBy::Activity {
            let entries = workspaces
                .iter()
                .map(|(_, workspace)| *workspace)
                .collect::<Vec<_>>();
            let activity = self.aggregate_activity(&entries);
            workspaces.sort_by(|(left_project, left), (right_project, right)| {
                compare_activity(
                    activity.get(&left.id).and_then(Option::as_ref),
                    &left.name,
                    activity.get(&right.id).and_then(Option::as_ref),
                    &right.name,
                )
                .then_with(|| compare_names(&left_project.name, &right_project.name))
            });
            return;
        }
        workspaces.sort_by(|(left_project, left), (right_project, right)| {
            self.compare_workspaces(left, right, pin_main_on_recent)
                .then_with(|| compare_names(&left_project.name, &right_project.name))
        });
    }

    fn compare_workspaces(
        &self,
        left: &Workspace,
        right: &Workspace,
        pin_main_on_recent: bool,
    ) -> Ordering {
        match self.prefs.workspace_sort {
            SidebarSortBy::Name => main_rank(left)
                .cmp(&main_rank(right))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Recent => {
                let main_order = if pin_main_on_recent {
                    main_rank(left).cmp(&main_rank(right))
                } else {
                    Ordering::Equal
                };
                main_order
                    .then_with(|| right.updated_at.cmp(&left.updated_at))
                    .then_with(|| compare_names(&left.name, &right.name))
            }
            SidebarSortBy::Activity => unreachable!("activity uses the subtree comparator"),
        }
    }

    fn project_activity(&self, project: &Project) -> Option<ActivityRank> {
        self.visible_workspaces(project, false, false)
            .into_iter()
            .filter_map(|workspace| self.direct_activity(workspace))
            .reduce(best_activity)
    }

    fn direct_activity(&self, workspace: &Workspace) -> Option<ActivityRank> {
        if !self.active_workspace_ids.contains(&workspace.id) {
            return None;
        }
        let mut best = None;
        for run in self
            .presence_by_workspace
            .get(&workspace.id)
            .into_iter()
            .flatten()
        {
            if run_is_stale(run, self.now) {
                continue;
            }
            let attention_class = match run.state {
                AgentRunState::Waiting | AgentRunState::Blocked | AgentRunState::Interrupted => 0,
                AgentRunState::Done => 1,
                AgentRunState::Working => 2,
            };
            let activity_at = if run.state_started_at.is_empty() {
                run.updated_at.clone()
            } else {
                run.state_started_at.clone()
            };
            let candidate = ActivityRank {
                attention_class,
                activity_at,
            };
            best = Some(match best {
                Some(current) => best_activity(current, candidate),
                None => candidate,
            });
        }
        best.or_else(|| {
            Some(ActivityRank {
                attention_class: 3,
                activity_at: workspace.updated_at.clone(),
            })
        })
    }

    fn aggregate_activity(
        &self,
        workspaces: &[&Workspace],
    ) -> HashMap<String, Option<ActivityRank>> {
        let ids = workspaces
            .iter()
            .map(|workspace| workspace.id.as_str())
            .collect::<HashSet<_>>();
        let mut children = HashMap::<String, Vec<String>>::new();
        for relation in &self.snapshot.relations {
            if valid_relation(relation, &ids) {
                children
                    .entry(relation.parent_workspace_id.clone())
                    .or_default()
                    .push(relation.child_workspace_id.clone());
            }
        }
        let direct = workspaces
            .iter()
            .map(|workspace| (workspace.id.clone(), self.direct_activity(workspace)))
            .collect::<HashMap<_, _>>();
        let mut aggregate = HashMap::<String, Option<ActivityRank>>::new();
        let mut visiting = HashSet::<String>::new();
        for workspace in workspaces {
            aggregate_activity_for(
                &workspace.id,
                &children,
                &direct,
                &mut aggregate,
                &mut visiting,
            );
        }
        aggregate
    }

    fn workspace_rows_from_pairs(
        &self,
        pairs: Vec<(&Project, &Workspace)>,
        base_depth: usize,
        show_project_chip: bool,
        is_pinned_copy: bool,
        ignore_collapsed_parents: bool,
    ) -> Vec<SidebarRow> {
        let ids = pairs
            .iter()
            .map(|(_, workspace)| workspace.id.as_str())
            .collect::<HashSet<_>>();
        let project_by_workspace = pairs
            .iter()
            .map(|(project, workspace)| (workspace.id.as_str(), *project))
            .collect::<HashMap<_, _>>();
        let workspace_by_id = pairs
            .iter()
            .map(|(_, workspace)| (workspace.id.as_str(), *workspace))
            .collect::<HashMap<_, _>>();
        let mut parent_of = HashMap::<&str, &str>::new();
        let mut children = HashMap::<&str, Vec<&Workspace>>::new();
        for relation in &self.snapshot.relations {
            if valid_relation(relation, &ids) {
                parent_of.insert(
                    relation.child_workspace_id.as_str(),
                    relation.parent_workspace_id.as_str(),
                );
            }
        }
        for (_, workspace) in &pairs {
            if let Some(parent_id) = parent_of.get(workspace.id.as_str()) {
                children.entry(parent_id).or_default().push(*workspace);
            }
        }
        let order = pairs
            .iter()
            .enumerate()
            .map(|(index, (_, workspace))| (workspace.id.as_str(), index))
            .collect::<HashMap<_, _>>();
        for values in children.values_mut() {
            values.sort_by_key(|workspace| order.get(workspace.id.as_str()).copied());
        }

        let mut rows = Vec::new();
        let mut visited = HashSet::new();
        for (_, workspace) in &pairs {
            if !parent_of.contains_key(workspace.id.as_str()) {
                self.append_tree_rows(
                    workspace,
                    base_depth,
                    &project_by_workspace,
                    &children,
                    show_project_chip,
                    is_pinned_copy,
                    ignore_collapsed_parents,
                    &mut visited,
                    &mut rows,
                );
            }
        }
        for (_, workspace) in pairs {
            if visited.contains(workspace.id.as_str()) {
                continue;
            }
            let mut ancestor_id = workspace.id.as_str();
            let mut ancestor_chain = HashSet::new();
            let mut hidden_by_visited_ancestor = false;
            while let Some(parent_id) = parent_of.get(ancestor_id).copied() {
                if visited.contains(parent_id) {
                    hidden_by_visited_ancestor = true;
                    break;
                }
                if !ancestor_chain.insert(parent_id) {
                    break;
                }
                ancestor_id = parent_id;
            }
            if hidden_by_visited_ancestor {
                visited.insert(workspace.id.clone());
                continue;
            }
            self.append_tree_rows(
                workspace,
                base_depth,
                &project_by_workspace,
                &children,
                show_project_chip,
                is_pinned_copy,
                ignore_collapsed_parents,
                &mut visited,
                &mut rows,
            );
        }
        debug_assert_eq!(visited.len(), workspace_by_id.len());
        rows
    }

    #[allow(clippy::too_many_arguments)]
    fn append_tree_rows(
        &self,
        workspace: &Workspace,
        depth: usize,
        project_by_workspace: &HashMap<&str, &Project>,
        children: &HashMap<&str, Vec<&Workspace>>,
        show_project_chip: bool,
        is_pinned_copy: bool,
        ignore_collapsed_parents: bool,
        visited: &mut HashSet<String>,
        rows: &mut Vec<SidebarRow>,
    ) {
        if !visited.insert(workspace.id.clone()) {
            return;
        }
        let Some(project) = project_by_workspace.get(workspace.id.as_str()) else {
            return;
        };
        let child_rows = children
            .get(workspace.id.as_str())
            .cloned()
            .unwrap_or_default();
        let collapsed = !ignore_collapsed_parents
            && self
                .prefs
                .collapsed_parent_workspace_ids
                .contains(&workspace.id);
        let runs = self
            .presence_by_workspace
            .get(&workspace.id)
            .cloned()
            .unwrap_or_default();
        rows.push(SidebarRow::Workspace(Box::new(SidebarWorkspaceRow {
            id: workspace.id.clone(),
            name: workspace.name.clone(),
            path: workspace.path.clone(),
            project_name: project.name.clone(),
            depth,
            is_pinned: workspace.is_pinned,
            is_pinned_copy,
            is_default: workspace.kind == "main",
            branch_label: workspace.branch.clone().unwrap_or_else(|| {
                if project.kind == "folder" {
                    "Local Folder".to_string()
                } else {
                    "Git Repository".to_string()
                }
            }),
            tag_ids: workspace.tag_ids.clone(),
            tag_names: if workspace.tag_names.is_empty() {
                workspace.tag_ids.clone()
            } else {
                workspace.tag_names.clone()
            },
            host_id: (workspace.host_id != "local").then(|| workspace.host_id.clone()),
            has_terminal_tabs: self.active_workspace_ids.contains(&workspace.id),
            agent_runs: runs,
            agents_expanded: self.prefs.expanded_workspace_ids.contains(&workspace.id),
            visible_child_count: child_rows.len(),
            children_collapsed: collapsed,
            parent_id: self
                .snapshot
                .relations
                .iter()
                .find(|relation| relation.child_workspace_id == workspace.id)
                .map(|relation| relation.parent_workspace_id.clone()),
            reuses_existing_branch: workspace.reuses_existing_branch,
            show_project_chip,
        })));
        if !collapsed || is_pinned_copy {
            for child in child_rows {
                self.append_tree_rows(
                    child,
                    depth + 1,
                    project_by_workspace,
                    children,
                    show_project_chip,
                    is_pinned_copy,
                    ignore_collapsed_parents,
                    visited,
                    rows,
                );
            }
        }
    }
}

pub fn agent_display_name(agent_type: &str) -> &'static str {
    match agent_type {
        "claude" => "Claude Code",
        "copilot" => "GitHub Copilot",
        "cursor" => "Cursor",
        "agy" => "Antigravity",
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

fn valid_relation(relation: &WorkspaceRelation, ids: &HashSet<&str>) -> bool {
    relation.parent_workspace_id != relation.child_workspace_id
        && ids.contains(relation.parent_workspace_id.as_str())
        && ids.contains(relation.child_workspace_id.as_str())
}

fn main_rank(workspace: &Workspace) -> u8 {
    u8::from(workspace.kind != "main")
}

fn run_is_stale(run: &SidebarAgentRun, now: DateTime<Utc>) -> bool {
    DateTime::parse_from_rfc3339(&run.updated_at)
        .map(|updated| {
            now.signed_duration_since(updated.with_timezone(&Utc)) > Duration::minutes(30)
        })
        .unwrap_or(false)
}

fn best_activity(left: ActivityRank, right: ActivityRank) -> ActivityRank {
    if left.attention_class < right.attention_class
        || (left.attention_class == right.attention_class && left.activity_at >= right.activity_at)
    {
        left
    } else {
        right
    }
}

fn compare_activity(
    left: Option<&ActivityRank>,
    left_name: &str,
    right: Option<&ActivityRank>,
    right_name: &str,
) -> Ordering {
    match (left, right) {
        (Some(left), Some(right)) => left
            .attention_class
            .cmp(&right.attention_class)
            .then_with(|| right.activity_at.cmp(&left.activity_at))
            .then_with(|| compare_names(left_name, right_name)),
        (Some(_), None) => Ordering::Less,
        (None, Some(_)) => Ordering::Greater,
        (None, None) => compare_names(left_name, right_name),
    }
}

fn aggregate_activity_for(
    workspace_id: &str,
    children: &HashMap<String, Vec<String>>,
    direct: &HashMap<String, Option<ActivityRank>>,
    aggregate: &mut HashMap<String, Option<ActivityRank>>,
    visiting: &mut HashSet<String>,
) -> Option<ActivityRank> {
    if aggregate.contains_key(workspace_id) {
        return aggregate.get(workspace_id).cloned().flatten();
    }
    if !visiting.insert(workspace_id.to_string()) {
        return direct.get(workspace_id).cloned().flatten();
    }
    let mut best = direct.get(workspace_id).cloned().flatten();
    for child_id in children.get(workspace_id).into_iter().flatten() {
        let child = aggregate_activity_for(child_id, children, direct, aggregate, visiting);
        best = match (best, child) {
            (Some(left), Some(right)) => Some(best_activity(left, right)),
            (Some(left), None) => Some(left),
            (None, Some(right)) => Some(right),
            (None, None) => None,
        };
    }
    visiting.remove(workspace_id);
    aggregate.insert(workspace_id.to_string(), best.clone());
    best
}

fn compare_names(left: &str, right: &str) -> Ordering {
    left.to_lowercase().cmp(&right.to_lowercase())
}

fn string_field<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or_default()
}

fn bool_field(value: &Value, key: &str, fallback: bool) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(fallback)
}

fn string_set(value: Option<&Value>) -> HashSet<String> {
    value
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect()
}

fn parse_sort(value: &str) -> SidebarSortBy {
    match value {
        "recent" => SidebarSortBy::Recent,
        "activity" => SidebarSortBy::Activity,
        _ => SidebarSortBy::Name,
    }
}

fn trimmed_field(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn workspace(id: &str, name: &str, kind: &str, pinned: bool, updated_at: &str) -> Workspace {
        Workspace {
            id: id.to_string(),
            name: name.to_string(),
            path: format!("/repo/{id}"),
            branch: Some(name.to_lowercase()),
            source_branch: Some("main".to_string()),
            kind: kind.to_string(),
            status: "active".to_string(),
            updated_at: updated_at.to_string(),
            host_id: "local".to_string(),
            reuses_existing_branch: false,
            is_pinned: pinned,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
        }
    }

    fn project(id: &str, name: &str, updated_at: &str, workspaces: Vec<Workspace>) -> Project {
        Project {
            id: id.to_string(),
            name: name.to_string(),
            repo_path: format!("/repo/{id}"),
            kind: "gitRepository".to_string(),
            updated_at: updated_at.to_string(),
            workspaces,
        }
    }

    fn workspace_rows(rows: &[SidebarRow]) -> Vec<&SidebarWorkspaceRow> {
        rows.iter()
            .filter_map(|row| match row {
                SidebarRow::Workspace(workspace) => Some(workspace.as_ref()),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn prefs_parse_flutter_defaults_and_overrides() {
        let record = serde_json::json!({
            "revision": 2,
            "prefs": {
                "groupBy": "none",
                "workspaceSort": "activity",
                "workspaceKindFilter": "nonDefaultOnly",
                "showPinnedWorkspacesBelow": false,
                "expandedWorkspaceIds": ["workspace-a"]
            }
        });
        let prefs = SidebarViewPrefs::from_record(Some(&record));
        assert_eq!(prefs.group_by, SidebarGroupBy::None);
        assert_eq!(prefs.workspace_sort, SidebarSortBy::Activity);
        assert_eq!(prefs.workspace_kind, SidebarWorkspaceKind::NonDefaultOnly);
        assert!(!prefs.show_pinned_workspaces_below);
        assert!(prefs.expanded_workspace_ids.contains("workspace-a"));
        assert_eq!(prefs.project_sort, SidebarSortBy::Name);
    }

    #[test]
    fn presence_projects_interruption_and_descriptions() {
        let run = SidebarAgentRun::from_presence(&serde_json::json!({
            "tabId": "tab-1",
            "terminalSessionId": "session-1",
            "agentType": "claude",
            "state": "working",
            "interrupted": true,
            "lastAssistantMessage": "Stopped by user"
        }))
        .expect("run");
        assert_eq!(run.state, AgentRunState::Interrupted);
        assert_eq!(run.description, "Stopped by user");
        assert_eq!(agent_display_name(&run.agent_type), "Claude Code");
    }

    #[test]
    fn none_group_sorts_pinned_globally_and_separates_the_all_section() {
        let snapshot = WorkbenchSnapshot {
            projects: vec![
                project(
                    "alpha",
                    "Alpha",
                    "2026-08-01T00:00:00Z",
                    vec![
                        workspace(
                            "alpha-pinned",
                            "Zulu",
                            "linked",
                            true,
                            "2026-08-01T00:00:00Z",
                        ),
                        workspace(
                            "alpha-other",
                            "Alpha Other",
                            "linked",
                            false,
                            "2026-08-01T00:00:00Z",
                        ),
                    ],
                ),
                project(
                    "beta",
                    "Beta",
                    "2026-08-02T00:00:00Z",
                    vec![
                        workspace(
                            "beta-main",
                            "Beta Main",
                            "main",
                            true,
                            "2026-08-02T00:00:00Z",
                        ),
                        workspace(
                            "beta-other",
                            "Beta Other",
                            "linked",
                            false,
                            "2026-08-02T00:00:00Z",
                        ),
                    ],
                ),
            ],
            ..WorkbenchSnapshot::default()
        };
        let prefs = SidebarViewPrefs {
            group_by: SidebarGroupBy::None,
            show_pinned_workspaces_below: false,
            ..SidebarViewPrefs::default()
        };
        let rows = SidebarProjection::new(&snapshot, &prefs, "", &HashSet::new(), &[]).build();
        assert!(matches!(rows[0], SidebarRow::PinnedHeader { count: 2, .. }));
        let workspaces = workspace_rows(&rows);
        assert_eq!(workspaces[0].id, "beta-main");
        assert_eq!(workspaces[1].id, "alpha-pinned");
        assert!(matches!(rows[3], SidebarRow::AllHeader { count: 2, .. }));
        assert!(workspaces[0].is_pinned_copy);
        assert!(workspaces[0].show_project_chip);
    }

    #[test]
    fn project_recent_sort_uses_the_project_timestamp_like_flutter() {
        let snapshot = WorkbenchSnapshot {
            projects: vec![
                project(
                    "old-project",
                    "Alpha",
                    "2026-07-01T00:00:00Z",
                    vec![workspace(
                        "future-workspace",
                        "Main",
                        "main",
                        false,
                        "2026-09-01T00:00:00Z",
                    )],
                ),
                project(
                    "new-project",
                    "Beta",
                    "2026-08-01T00:00:00Z",
                    vec![workspace(
                        "old-workspace",
                        "Main",
                        "main",
                        false,
                        "2026-01-01T00:00:00Z",
                    )],
                ),
            ],
            ..WorkbenchSnapshot::default()
        };
        let prefs = SidebarViewPrefs {
            project_sort: SidebarSortBy::Recent,
            ..SidebarViewPrefs::default()
        };
        let rows = SidebarProjection::new(&snapshot, &prefs, "", &HashSet::new(), &[]).build();
        assert!(matches!(
            &rows[0],
            SidebarRow::ProjectHeader { id, .. } if id == "new-project"
        ));
    }

    #[test]
    fn activity_sort_promotes_a_parent_whose_visible_child_needs_attention() {
        let snapshot = WorkbenchSnapshot {
            projects: vec![project(
                "project",
                "Project",
                "2026-08-09T12:00:00Z",
                vec![
                    workspace("other", "Alpha", "linked", false, "2026-08-09T12:00:00Z"),
                    workspace("parent", "Zulu", "main", false, "2026-08-09T12:00:00Z"),
                    workspace("child", "Child", "linked", false, "2026-08-09T12:00:00Z"),
                ],
            )],
            relations: vec![WorkspaceRelation {
                parent_workspace_id: "parent".to_string(),
                child_workspace_id: "child".to_string(),
            }],
            ..WorkbenchSnapshot::default()
        };
        let prefs = SidebarViewPrefs {
            workspace_sort: SidebarSortBy::Activity,
            ..SidebarViewPrefs::default()
        };
        let active = HashSet::from(["other".to_string(), "child".to_string()]);
        let presence = vec![
            serde_json::json!({
                "workspaceId":"other", "tabId":"other-tab", "terminalSessionId":"other-session",
                "agentType":"codex", "state":"working", "stateStartedAt":"2026-08-09T12:08:00Z",
                "updatedAt":"2026-08-09T12:08:00Z"
            }),
            serde_json::json!({
                "workspaceId":"child", "tabId":"child-tab", "terminalSessionId":"child-session",
                "agentType":"claude", "state":"waiting", "stateStartedAt":"2026-08-09T12:05:00Z",
                "updatedAt":"2026-08-09T12:05:00Z"
            }),
        ];
        let now = DateTime::parse_from_rfc3339("2026-08-09T12:10:00Z")
            .expect("time")
            .with_timezone(&Utc);
        let rows =
            SidebarProjection::new_at(&snapshot, &prefs, "", &active, &presence, now).build();
        let workspaces = workspace_rows(&rows);
        assert_eq!(
            workspaces
                .iter()
                .map(|workspace| workspace.id.as_str())
                .collect::<Vec<_>>(),
            vec!["parent", "child", "other"]
        );
        assert_eq!(workspaces[0].visible_child_count, 1);
        assert_eq!(workspaces[1].depth, 2);
    }

    #[test]
    fn pinned_tree_ignores_the_regular_parent_collapse_state() {
        let snapshot = WorkbenchSnapshot {
            projects: vec![project(
                "project",
                "Project",
                "2026-08-09T12:00:00Z",
                vec![
                    workspace("parent", "Main", "main", true, "2026-08-09T12:00:00Z"),
                    workspace("child", "Child", "linked", true, "2026-08-09T12:00:00Z"),
                ],
            )],
            relations: vec![WorkspaceRelation {
                parent_workspace_id: "parent".to_string(),
                child_workspace_id: "child".to_string(),
            }],
            ..WorkbenchSnapshot::default()
        };
        let prefs = SidebarViewPrefs {
            collapsed_parent_workspace_ids: HashSet::from(["parent".to_string()]),
            show_pinned_workspaces_below: false,
            ..SidebarViewPrefs::default()
        };
        let rows = SidebarProjection::new(&snapshot, &prefs, "", &HashSet::new(), &[]).build();
        let workspaces = workspace_rows(&rows);
        assert_eq!(workspaces.len(), 2);
        assert_eq!(workspaces[0].id, "parent");
        assert!(!workspaces[0].children_collapsed);
        assert_eq!(workspaces[1].depth, 1);
    }

    #[test]
    fn collapsed_parent_does_not_reinsert_descendants_as_roots() {
        let snapshot = WorkbenchSnapshot {
            projects: vec![project(
                "project",
                "Project",
                "2026-08-09T12:00:00Z",
                vec![
                    workspace("parent", "Parent", "main", false, "2026-08-09T12:00:00Z"),
                    workspace("child", "Child", "linked", false, "2026-08-09T12:00:00Z"),
                    workspace(
                        "grandchild",
                        "Grandchild",
                        "linked",
                        false,
                        "2026-08-09T12:00:00Z",
                    ),
                    workspace("other", "Other", "linked", false, "2026-08-09T12:00:00Z"),
                ],
            )],
            relations: vec![
                WorkspaceRelation {
                    parent_workspace_id: "parent".to_string(),
                    child_workspace_id: "child".to_string(),
                },
                WorkspaceRelation {
                    parent_workspace_id: "child".to_string(),
                    child_workspace_id: "grandchild".to_string(),
                },
            ],
            ..WorkbenchSnapshot::default()
        };
        let prefs = SidebarViewPrefs {
            group_by: SidebarGroupBy::None,
            collapsed_parent_workspace_ids: HashSet::from(["parent".to_string()]),
            ..SidebarViewPrefs::default()
        };
        let rows = SidebarProjection::new(&snapshot, &prefs, "", &HashSet::new(), &[]).build();
        let workspaces = workspace_rows(&rows);
        assert_eq!(
            workspaces
                .iter()
                .map(|workspace| workspace.id.as_str())
                .collect::<Vec<_>>(),
            vec!["parent", "other"]
        );
    }
}
