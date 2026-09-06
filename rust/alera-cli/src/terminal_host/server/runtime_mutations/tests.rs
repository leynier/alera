use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
    WorkspaceTabRecord, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::json;

use super::{run_runtime_mutation, RuntimeMutationEffect, RuntimeMutationRequest};

#[tokio::test]
async fn removing_tab_releases_its_hosted_review_refs() {
    let dir = tempfile::tempdir().unwrap();
    let workspace_path = dir.path().join("workspace");
    let repo_path = workspace_path.join("nested/repo");
    std::fs::create_dir_all(&repo_path).unwrap();
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
    let store = RuntimeStore::open(&dir.path().join("runtime"))
        .await
        .unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: repo_path.to_string_lossy().into_owned(),
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
            kind: WorkspaceKind::Main,
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
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "diff-tab".into(),
            workspace_id: "workspace".into(),
            kind: "gitDiff".into(),
            title: "Pull Request Diff".into(),
            payload: json!({
                "gitDiffRoot": "nested/repo",
                "gitDiffHostedReviewRetentionId": retention_id,
            }),
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();

    let outcome = run_runtime_mutation(
        store,
        RuntimeMutationRequest::RemoveTab {
            tab_id: "diff-tab".into(),
        },
    )
    .await;

    assert!(outcome.result.is_ok());
    for role in ["base", "head"] {
        assert!(repository
            .find_reference(&format!(
                "refs/alera/hosted-reviews/tabs/{retention_id}/{role}"
            ))
            .is_err());
    }
}

#[tokio::test]
async fn sleep_reports_committed_effect_when_activity_recording_fails() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "emulator-tab".into(),
            workspace_id: "force-activity-failure".into(),
            kind: "terminal".into(),
            title: "Android".into(),
            payload: json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        })
        .await
        .unwrap();

    let outcome = run_runtime_mutation(
        store.clone(),
        RuntimeMutationRequest::SleepWorkspace {
            workspace_id: "force-activity-failure".into(),
        },
    )
    .await;

    assert!(outcome.result.is_err());
    assert!(outcome.committed_tab_ids.is_empty());
    assert!(matches!(
        outcome.effect_on_error,
        Some(RuntimeMutationEffect::WorkspaceSlept { workspace_id })
            if workspace_id == "force-activity-failure"
    ));
    assert!(store
        .find_workspace_tab("emulator-tab")
        .await
        .unwrap()
        .is_none());
}
