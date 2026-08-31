use std::collections::HashSet;
use std::path::{Component, Path};

use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord};

#[path = "hosted_review_operation_liveness.rs"]
mod operation_liveness;

use operation_liveness::active_operation_ids;

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

pub(crate) async fn remove_project(store: RuntimeStore, project_id: &str) -> anyhow::Result<()> {
    let retentions = for_project(&store, project_id).await;
    store.remove_project(project_id).await?;
    release(retentions);
    Ok(())
}

pub(crate) async fn remove_workspace(
    store: RuntimeStore,
    workspace_id: &str,
) -> anyhow::Result<()> {
    let retentions = for_workspace(&store, workspace_id).await;
    store.remove_workspace(workspace_id, true).await?;
    release(retentions);
    Ok(())
}

pub(crate) async fn reconcile(store: &RuntimeStore) {
    let Ok(projects) = store.list_projects().await else {
        return;
    };
    let Ok(workspaces) = store.list_all_workspaces().await else {
        return;
    };
    let mut repo_paths = projects
        .into_iter()
        .map(|project| project.repo_path)
        .chain(workspaces.iter().map(|workspace| workspace.path.clone()))
        .collect::<HashSet<_>>();
    let operations = alera_core::git::hosted_review::hosted_review_operations();
    repo_paths.extend(
        operations
            .iter()
            .map(|operation| operation.repo_path.clone()),
    );
    let mut retentions = Vec::new();
    for workspace in workspaces {
        let Ok(tabs) = store.list_workspace_tabs(&workspace.id).await else {
            continue;
        };
        retentions.extend(for_records(store, tabs).await);
    }
    let active_operation_ids = active_operation_ids(&operations);
    let stale_operation_ids = operations
        .iter()
        .filter(|operation| !active_operation_ids.contains(&operation.retention_id))
        .map(|operation| operation.retention_id.clone())
        .collect::<HashSet<_>>();
    let retained_ids = retentions
        .iter()
        .map(|retention| retention.retention_id.clone())
        .chain(active_operation_ids)
        .collect::<HashSet<_>>();
    for retention in &retentions {
        repo_paths.insert(retention.repo_path.clone());
        let persisted = alera_core::git::hosted_review::persist_hosted_review_range(
            &retention.repo_path,
            &retention.retention_id,
        );
        if persisted.is_err() {
            if let Some(fallback) = &retention.fallback_repo_path {
                repo_paths.insert(fallback.clone());
                let _ = alera_core::git::hosted_review::persist_hosted_review_range(
                    fallback,
                    &retention.retention_id,
                );
            }
        }
    }
    let retained_ids = retained_ids.into_iter().collect::<Vec<_>>();
    let stale_operation_ids = stale_operation_ids.into_iter().collect::<Vec<_>>();
    let mut swept_repo_paths = HashSet::new();
    for repo_path in repo_paths {
        if alera_core::git::hosted_review::sweep_hosted_review_ranges(
            &repo_path,
            &retained_ids,
            &stale_operation_ids,
        )
        .is_ok()
        {
            swept_repo_paths.insert(repo_path);
        }
    }
    for operation in operations {
        if !stale_operation_ids.contains(&operation.retention_id) {
            continue;
        }
        if swept_repo_paths.contains(&operation.repo_path)
            || !Path::new(&operation.repo_path).exists()
        {
            let _ = alera_core::git::hosted_review::clear_hosted_review_operation(
                &operation.retention_id,
            );
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
    async fn direct_store_cascade_removals_release_hosted_review_refs() {
        for remove_project in [false, true] {
            let directory = tempfile::tempdir().unwrap();
            let repo_path = directory.path().join("project");
            let repository = git2::Repository::init(&repo_path).unwrap();
            let object = repository.blob(b"review object").unwrap();
            let retention_id = "0123456789abcdef0123456789abcdef";
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
            insert_records(&store, &repo_path, &repo_path, retention_id).await;

            if remove_project {
                super::remove_project(store.clone(), "project")
                    .await
                    .unwrap();
                assert!(store.find_project("project").await.unwrap().is_none());
            } else {
                super::remove_workspace(store.clone(), "workspace")
                    .await
                    .unwrap();
                assert!(store.find_workspace("workspace").await.unwrap().is_none());
            }
            for role in ["base", "head"] {
                assert!(repository
                    .find_reference(&format!(
                        "refs/alera/hosted-reviews/tabs/{retention_id}/{role}"
                    ))
                    .is_err());
            }
        }
    }

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
                    &format!("refs/alera/hosted-reviews/operations/{retention_id}/{role}"),
                    object,
                    true,
                    "test",
                )
                .unwrap();
        }
        let store = RuntimeStore::open(&directory.path().join("runtime"))
            .await
            .unwrap();
        insert_records(
            &store,
            &project_repo_path,
            &removed_worktree_path,
            retention_id,
        )
        .await;

        reconcile(&store).await;
        for role in ["base", "head"] {
            assert!(repository
                .find_reference(&format!(
                    "refs/alera/hosted-reviews/tabs/{retention_id}/{role}"
                ))
                .is_ok());
            assert!(repository
                .find_reference(&format!(
                    "refs/alera/hosted-reviews/operations/{retention_id}/{role}"
                ))
                .is_err());
        }

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

    #[tokio::test]
    async fn reconcile_sweeps_journaled_operations_in_nested_repositories() {
        let directory = tempfile::tempdir().unwrap();
        let folder_path = directory.path().join("folder");
        let repo_path = folder_path.join("packages/app");
        std::fs::create_dir_all(&repo_path).unwrap();
        let repository = git2::Repository::init(&repo_path).unwrap();
        let object = repository.blob(b"review object").unwrap();
        let retention_id = uuid::Uuid::new_v4().simple().to_string();
        for role in ["base", "head"] {
            repository
                .reference(
                    &format!("refs/alera/hosted-reviews/operations/{retention_id}/{role}"),
                    object,
                    true,
                    "test",
                )
                .unwrap();
        }
        write_operation_marker(
            repo_path.to_string_lossy().as_ref(),
            &retention_id,
            u32::MAX,
        );
        let store = RuntimeStore::open(&directory.path().join("runtime"))
            .await
            .unwrap();
        insert_workspace_records(&store, &folder_path, &folder_path).await;

        reconcile(&store).await;

        for role in ["base", "head"] {
            assert!(repository
                .find_reference(&format!(
                    "refs/alera/hosted-reviews/operations/{retention_id}/{role}"
                ))
                .is_err());
        }
        assert!(!alera_core::git::hosted_review::hosted_review_operations()
            .iter()
            .any(|operation| operation.retention_id == retention_id));
    }

    #[tokio::test]
    async fn reconcile_preserves_an_operation_owned_by_a_live_process() {
        let directory = tempfile::tempdir().unwrap();
        let repo_path = directory.path().join("project");
        let repository = git2::Repository::init(&repo_path).unwrap();
        let object = repository.blob(b"review object").unwrap();
        let retention_id = uuid::Uuid::new_v4().simple().to_string();
        for role in ["base", "head"] {
            repository
                .reference(
                    &format!("refs/alera/hosted-reviews/operations/{retention_id}/{role}"),
                    object,
                    true,
                    "test",
                )
                .unwrap();
        }
        alera_core::git::hosted_review::record_hosted_review_operation(
            repo_path.to_string_lossy().as_ref(),
            &retention_id,
        )
        .unwrap();
        let store = RuntimeStore::open(&directory.path().join("runtime"))
            .await
            .unwrap();
        insert_workspace_records(&store, &repo_path, &repo_path).await;

        reconcile(&store).await;

        for role in ["base", "head"] {
            assert!(repository
                .find_reference(&format!(
                    "refs/alera/hosted-reviews/operations/{retention_id}/{role}"
                ))
                .is_ok());
        }
        assert!(alera_core::git::hosted_review::hosted_review_operations()
            .iter()
            .any(|operation| operation.retention_id == retention_id));
        alera_core::git::hosted_review::release_hosted_review_range(
            repo_path.to_string_lossy().as_ref(),
            &retention_id,
        )
        .unwrap();
    }

    fn write_operation_marker(repo_path: &str, retention_id: &str, owner_pid: u32) {
        let path =
            std::env::temp_dir().join(format!("alera-hosted-review-operation-{retention_id}.json"));
        std::fs::write(
            path,
            serde_json::to_vec(&json!({
                "repoPath": repo_path,
                "retentionId": retention_id,
                "ownerPid": owner_pid,
            }))
            .unwrap(),
        )
        .unwrap();
    }

    async fn insert_records(
        store: &RuntimeStore,
        project_repo_path: &Path,
        workspace_path: &Path,
        retention_id: &str,
    ) {
        insert_workspace_records(store, project_repo_path, workspace_path).await;
        store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: "diff-tab".into(),
                workspace_id: "workspace".into(),
                kind: "gitDiff".into(),
                title: "Pull Request Diff".into(),
                payload: json!({RETENTION_ID_KEY: retention_id}),
                created_at: Utc::now(),
                updated_at: Utc::now(),
            })
            .await
            .unwrap();
    }

    async fn insert_workspace_records(
        store: &RuntimeStore,
        project_repo_path: &Path,
        workspace_path: &Path,
    ) {
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
                path: workspace_path.to_string_lossy().into_owned(),
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
                section_id: None,
                child_count: 0,
            })
            .await
            .unwrap();
    }
}
