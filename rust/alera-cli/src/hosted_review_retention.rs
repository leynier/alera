use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord};

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
        retentions.push(HostedReviewRetention {
            repo_path: workspace.path,
            retention_id: retention_id.to_string(),
        });
    }
    retentions
}
