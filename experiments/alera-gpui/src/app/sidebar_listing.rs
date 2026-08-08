use std::cmp::Ordering;

use super::{AleraApp, SidebarSortBy};
use crate::model::{Project, Workspace};

impl AleraApp {
    pub(super) fn sort_sidebar_projects(&self, projects: &mut Vec<&Project>) {
        projects.sort_by(|left, right| match self.sidebar_project_sort {
            SidebarSortBy::Name => compare_names(&left.name, &right.name),
            SidebarSortBy::Recent => project_recency(right)
                .cmp(project_recency(left))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Activity => project_activity(right)
                .cmp(&project_activity(left))
                .then_with(|| project_recency(right).cmp(project_recency(left)))
                .then_with(|| compare_names(&left.name, &right.name)),
        });
    }

    pub(super) fn sort_sidebar_workspaces(&self, workspaces: &mut Vec<&Workspace>) {
        workspaces.sort_by(|left, right| self.compare_sidebar_workspaces(left, right));
    }

    pub(super) fn compare_sidebar_workspaces(
        &self,
        left: &Workspace,
        right: &Workspace,
    ) -> Ordering {
        match self.sidebar_workspace_sort {
            SidebarSortBy::Name => main_rank(left)
                .cmp(&main_rank(right))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Recent => main_rank(left)
                .cmp(&main_rank(right))
                .then_with(|| right.updated_at.cmp(&left.updated_at))
                .then_with(|| compare_names(&left.name, &right.name)),
            SidebarSortBy::Activity => activity_rank(right)
                .cmp(&activity_rank(left))
                .then_with(|| right.updated_at.cmp(&left.updated_at))
                .then_with(|| compare_names(&left.name, &right.name)),
        }
    }
}

fn compare_names(left: &str, right: &str) -> Ordering {
    left.to_lowercase().cmp(&right.to_lowercase())
}

fn project_recency(project: &Project) -> &str {
    project
        .workspaces
        .iter()
        .map(|workspace| workspace.updated_at.as_str())
        .max()
        .unwrap_or("")
}

fn project_activity(project: &Project) -> u8 {
    project
        .workspaces
        .iter()
        .map(activity_rank)
        .max()
        .unwrap_or(0)
}

fn main_rank(workspace: &Workspace) -> u8 {
    u8::from(workspace.kind != "main")
}

fn activity_rank(workspace: &Workspace) -> u8 {
    match workspace.status.as_str() {
        "busy" | "running" => 3,
        "waiting" | "attention" => 2,
        "active" => 1,
        _ => 0,
    }
}
