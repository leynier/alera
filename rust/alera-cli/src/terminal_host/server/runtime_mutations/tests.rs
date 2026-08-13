use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
    WorkspaceTabRecord, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::json;

use crate::terminal_host::protocol::MOBILE_EMULATOR_TAB_KIND;
use crate::terminal_host::server::codex_runtime_cleanup::{
    apply_cleanup_activity, CodexCleanupEntry, CodexCleanupPlan,
};
use crate::terminal_host::server::codex_tab_lifecycle::{active_cwd, set_active_cwd};

use super::{run_runtime_mutation, RuntimeMutationEffect, RuntimeMutationRequest};

#[tokio::test]
async fn removing_tab_releases_its_hosted_review_refs() {
    let dir = tempfile::tempdir().unwrap();
    let repo_path = dir.path().join("repo");
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
            path: repo_path.to_string_lossy().into_owned(),
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
            payload: json!({"gitDiffHostedReviewRetentionId": retention_id}),
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();

    let outcome = run_runtime_mutation(
        None,
        store,
        RuntimeMutationRequest::RemoveTab {
            tab_id: "diff-tab".into(),
        },
        None,
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
            kind: MOBILE_EMULATOR_TAB_KIND.into(),
            title: "Android".into(),
            payload: json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        })
        .await
        .unwrap();

    let outcome = run_runtime_mutation(
        None,
        store.clone(),
        RuntimeMutationRequest::SleepWorkspace {
            workspace_id: "force-activity-failure".into(),
        },
        None,
    )
    .await;

    assert!(outcome.result.is_err());
    assert_eq!(outcome.committed_tab_ids, ["emulator-tab"]);
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

#[tokio::test]
async fn surviving_codex_tab_is_repaired_after_competing_event_persistence() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: dir.path().to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let surviving_path = dir.path().join("surviving");
    let removed_path = dir.path().join("removed");
    for (id, path) in [
        ("surviving", surviving_path.as_path()),
        ("removed", removed_path.as_path()),
    ] {
        store
            .upsert_workspace(Workspace {
                id: id.into(),
                instance_id: format!("instance-{id}"),
                host_id: LOCAL_HOST_ID.into(),
                project_id: "project".into(),
                name: id.into(),
                branch: None,
                path: path.to_string_lossy().into_owned(),
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
                child_count: 0,
            })
            .await
            .unwrap();
    }
    let mut stale_tab = WorkspaceTabRecord {
        id: "codex-tab".into(),
        workspace_id: "surviving".into(),
        kind: "codex".into(),
        title: "Codex Chat".into(),
        payload: json!({}),
        created_at: now,
        updated_at: now,
    };
    set_active_cwd(
        &mut stale_tab,
        &removed_path.join("package").to_string_lossy(),
    );
    store.upsert_workspace_tab(stale_tab.clone()).await.unwrap();
    let cleanup = CodexCleanupPlan {
        server: None,
        fallback_cwd: Some(surviving_path.to_string_lossy().into_owned()),
        entries: vec![CodexCleanupEntry {
            tab_id: stale_tab.id.clone(),
            thread_id: None,
            turn_id: None,
            delete_thread: false,
            replacement_cwd: Some(surviving_path.to_string_lossy().into_owned()),
        }],
    };

    let outcome = run_runtime_mutation(
        None,
        store.clone(),
        RuntimeMutationRequest::RemoveWorkspace {
            workspace_id: "removed".into(),
            cascade_tabs: true,
        },
        Some(cleanup),
    )
    .await;
    assert!(outcome.result.is_ok());

    // Models an actor-side Codex event that loaded the tab before the worker
    // finished. The serialized repair must be the final durable write.
    store.upsert_workspace_tab(stale_tab).await.unwrap();
    assert_eq!(
        apply_cleanup_activity(&store, &outcome.pending_codex_cleanup)
            .await
            .unwrap(),
        vec!["codex-tab".to_string()]
    );
    let saved = store
        .find_workspace_tab("codex-tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        active_cwd(&saved).as_deref(),
        Some(surviving_path.to_string_lossy().as_ref())
    );
}
