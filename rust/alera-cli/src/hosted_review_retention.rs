use std::path::{Component, Path};

use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord};

const GIT_DIFF_ROOT_KEY: &str = "gitDiffRoot";
const RETENTION_ID_KEY: &str = "gitDiffHostedReviewRetentionId";

pub(crate) struct HostedReviewRetention {
    repo_path: String,
    fallback_repo_path: Option<String>,
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
        let released = alera_core::git::hosted_review::release_hosted_review_range(
            &retention.repo_path,
            &retention.retention_id,
        );
        if released.is_err() {
            if let Some(fallback_repo_path) = retention.fallback_repo_path {
                let _ = alera_core::git::hosted_review::release_hosted_review_range(
                    &fallback_repo_path,
                    &retention.retention_id,
                );
            }
        }
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
        let relative_root = tab
            .payload
            .get(GIT_DIFF_ROOT_KEY)
            .and_then(|value| value.as_str());
        let Some(repo_path) = repo_path_for_root(&workspace.path, relative_root) else {
            continue;
        };
        let fallback_repo_path = match store.find_project(&workspace.project_id).await {
            Ok(Some(project)) => repo_path_for_root(&project.repo_path, relative_root)
                .filter(|fallback| fallback != &repo_path),
            _ => None,
        };
        retentions.push(HostedReviewRetention {
            repo_path,
            fallback_repo_path,
            retention_id: retention_id.to_string(),
        });
    }
    retentions
}

fn repo_path_for_root(root_path: &str, relative_root: Option<&str>) -> Option<String> {
    let Some(relative_root) = relative_root else {
        return Some(root_path.to_string());
    };
    if relative_root.trim().is_empty() {
        return Some(root_path.to_string());
    }
    let relative_root = Path::new(relative_root);
    if relative_root
        .components()
        .any(|component| !matches!(component, Component::Normal(_) | Component::CurDir))
    {
        return None;
    }
    Some(
        Path::new(root_path)
            .join(relative_root)
            .to_string_lossy()
            .into_owned(),
    )
}

#[cfg(test)]
mod tests {
    use alera_core::runtime::{
        Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
    };
    use chrono::Utc;
    use serde_json::json;

    use super::*;

    #[tokio::test]
    async fn release_falls_back_to_the_project_repo_after_worktree_removal() {
        let directory = tempfile::tempdir().unwrap();
        let project_repo_path = directory.path().join("project");
        let removed_worktree_path = directory.path().join("removed-worktree");
        let repository = git2::Repository::init(&project_repo_path).unwrap();
        let object = repository.blob(b"review object").unwrap();
        let retention_id = "abcdef0123456789abcdef0123456789";
        for role in ["base", "head"] {
            repository
                .reference(
                    &format!("refs/alera/hosted-reviews/tabs/{retention_id}/{role}"),
                    object,
                    true,
                    "test",
                )
                .unwrap();
        }
        let store = RuntimeStore::open(&directory.path().join("runtime"))
            .await
            .unwrap();
        let now = Utc::now();
        store
            .upsert_project(Project {
                id: "project".into(),
                name: "Project".into(),
                repo_path: project_repo_path.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: ProjectKind::GitRepository,
            })
            .await
            .unwrap();
        store
            .upsert_workspace(Workspace {
                id: "workspace".into(),
                instance_id: "instance".into(),
                host_id: LOCAL_HOST_ID.into(),
                project_id: "project".into(),
                name: "Workspace".into(),
                branch: None,
                path: removed_worktree_path.to_string_lossy().into_owned(),
                created_at: now,
                updated_at: now,
                kind: WorkspaceKind::Linked,
                status: WorkspaceStatus::Active,
                source_branch: None,
                reuses_existing_branch: false,
                is_pinned: false,
                tag_ids: Vec::new(),
                tag_names: Vec::new(),
                parent_workspace_id: None,
                child_count: 0,
            })
            .await
            .unwrap();
        store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: "diff-tab".into(),
                workspace_id: "workspace".into(),
                kind: "gitDiff".into(),
                title: "Pull Request Diff".into(),
                payload: json!({RETENTION_ID_KEY: retention_id}),
                created_at: now,
                updated_at: now,
            })
            .await
            .unwrap();

        let retentions = for_tab(&store, "diff-tab").await;
        release(retentions);

        for role in ["base", "head"] {
            assert!(repository
                .find_reference(&format!(
                    "refs/alera/hosted-reviews/tabs/{retention_id}/{role}"
                ))
                .is_err());
        }
    }
}
