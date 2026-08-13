use std::path::{Component, Path};

use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord};

const GIT_DIFF_ROOT_KEY: &str = "gitDiffRoot";
const RETENTION_ID_KEY: &str = "gitDiffHostedReviewRetentionId";

pub(crate) struct HostedReviewRetention {
    repo_path: String,
    retention_id: String,
}

pub(crate) async fn for_tab(store: &RuntimeStore, tab_id: &str) -> Vec<HostedReviewRetention> {
    let Ok(Some(tab)) = store.find_workspace_tab(tab_id).await else {
        return Vec::new();
    };
    for_records(store, [tab]).await
}

pub(crate) async fn for_workspace(
    store: &RuntimeStore,
    workspace_id: &str,
) -> Vec<HostedReviewRetention> {
    let Ok(tabs) = store.list_workspace_tabs(workspace_id).await else {
        return Vec::new();
    };
    for_records(store, tabs).await
}

pub(crate) async fn for_project(
    store: &RuntimeStore,
    project_id: &str,
) -> Vec<HostedReviewRetention> {
    let Ok(workspaces) = store.list_workspaces(project_id).await else {
        return Vec::new();
    };
    let mut retentions = Vec::new();
    for workspace in workspaces {
        retentions.extend(for_workspace(store, &workspace.id).await);
    }
    retentions
}

pub(crate) fn release(retentions: Vec<HostedReviewRetention>) {
    for retention in retentions {
        let _ = alera_core::git::hosted_review::release_hosted_review_range(
            &retention.repo_path,
            &retention.retention_id,
        );
    }
}

async fn for_records(
    store: &RuntimeStore,
    tabs: impl IntoIterator<Item = WorkspaceTabRecord>,
) -> Vec<HostedReviewRetention> {
    let mut retentions = Vec::new();
    for tab in tabs {
        let Some(retention_id) = tab
            .payload
            .get(RETENTION_ID_KEY)
            .and_then(|value| value.as_str())
        else {
            continue;
        };
        let Ok(Some(workspace)) = store.find_workspace(&tab.workspace_id).await else {
            continue;
        };
        let Some(repo_path) = repo_path_for_tab(&workspace.path, &tab) else {
            continue;
        };
        retentions.push(HostedReviewRetention {
            repo_path,
            retention_id: retention_id.to_string(),
        });
    }
    retentions
}

fn repo_path_for_tab(workspace_path: &str, tab: &WorkspaceTabRecord) -> Option<String> {
    let Some(relative_root) = tab
        .payload
        .get(GIT_DIFF_ROOT_KEY)
        .and_then(|value| value.as_str())
    else {
        return Some(workspace_path.to_string());
    };
    if relative_root.trim().is_empty() {
        return Some(workspace_path.to_string());
    }
    let relative_root = Path::new(relative_root);
    if relative_root
        .components()
        .any(|component| !matches!(component, Component::Normal(_) | Component::CurDir))
    {
        return None;
    }
    Some(
        Path::new(workspace_path)
            .join(relative_root)
            .to_string_lossy()
            .into_owned(),
    )
}
