use super::*;
use crate::runtime::{AutomationCleanupPolicy, WorkspaceTabRecord};

async fn successful() -> (tempfile::TempDir, RuntimeStore, AutomationRun, Workspace) {
    let (directory, store, run) = prepared().await;
    let (mut run, workspace) = store
        .allocate_automation_shared_workspace(
            &run,
            workspace("owned", "local", "/repo", WorkspaceKind::Main),
        )
        .await
        .unwrap();
    let mut definition = store
        .find_automation(&run.automation_id)
        .await
        .unwrap()
        .unwrap();
    definition.cleanup_policy = Some(AutomationCleanupPolicy::OnSuccess);
    store
        .upsert_automation(definition.clone(), definition.created_by)
        .await
        .unwrap();
    run.owned_tab = true;
    run.tab_id = Some("owned-tab".into());
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "owned-tab".into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Automation".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: serde_json::json!({"automationRunId":run.id,"automationOwned":true}),
        })
        .await
        .unwrap();
    run.status = AutomationRunStatus::Success;
    run.finished_at = Some(Utc::now());
    let run = store.save_automation_run(&run).await.unwrap();
    (directory, store, run, workspace)
}

#[tokio::test]
async fn successful_cleanup_retires_only_the_allocated_task_and_keeps_run_history() {
    let (directory, store, run, owned) = successful().await;
    store
        .insert_workspace(workspace("neighbor", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    store
        .retire_verified_automation_shared_workspace(&run, &owned)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(reopened.find_workspace(&owned.id).await.unwrap().is_none());
    assert!(reopened.find_workspace("neighbor").await.unwrap().is_some());
    assert!(reopened
        .find_workspace_tab("owned-tab")
        .await
        .unwrap()
        .is_none());
    assert!(reopened
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .is_some());
    assert!(reopened
        .workspace_retirement_receipt(&owned.id, &owned.instance_id)
        .await
        .unwrap()
        .is_some());
    let receipt: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM automationSharedWorkspaceAllocations WHERE runId = ?",
    )
    .bind(&run.id)
    .fetch_one(reopened.pool())
    .await
    .unwrap();
    assert_eq!(receipt, 1);
}

#[tokio::test]
async fn cleanup_rechecks_takeover_and_preserve_policy_inside_retirement() {
    let (_directory, store, run, owned) = successful().await;
    let mut taken_over = run.clone();
    taken_over.taken_over = true;
    store.save_automation_run(&taken_over).await.unwrap();
    assert!(store
        .retire_verified_automation_shared_workspace(&run, &owned)
        .await
        .is_err());
    assert!(store
        .retire_verified_automation_shared_workspace(&taken_over, &owned)
        .await
        .is_err());
    store.save_automation_run(&run).await.unwrap();
    let mut definition = store
        .find_automation(&run.automation_id)
        .await
        .unwrap()
        .unwrap();
    definition.cleanup_policy = None;
    store
        .upsert_automation(definition.clone(), definition.created_by)
        .await
        .unwrap();
    assert!(store
        .retire_verified_automation_shared_workspace(&run, &owned)
        .await
        .is_err());
    assert!(store.find_workspace(&owned.id).await.unwrap().is_some());
    assert!(store
        .workspace_retirement_receipt(&owned.id, &owned.instance_id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn cleanup_preserves_changed_task_metadata_and_foreign_tabs() {
    let (_directory, store, run, owned) = successful().await;
    let mut changed = owned.clone();
    changed.is_pinned = true;
    store.upsert_workspace(changed).await.unwrap();
    assert!(store
        .retire_verified_automation_shared_workspace(&run, &owned)
        .await
        .is_err());
    let mut changed = owned.clone();
    changed.name = "User task".into();
    store.upsert_workspace(changed.clone()).await.unwrap();
    assert!(store
        .retire_verified_automation_shared_workspace(&run, &changed)
        .await
        .is_err());
    store.upsert_workspace(owned.clone()).await.unwrap();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "user-tab".into(),
            workspace_id: owned.id.clone(),
            kind: "editor".into(),
            title: "Notes".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: serde_json::json!({}),
        })
        .await
        .unwrap();
    assert!(store
        .retire_verified_automation_shared_workspace(&run, &owned)
        .await
        .is_err());
    assert!(store
        .find_workspace_tab("user-tab")
        .await
        .unwrap()
        .is_some());
    assert!(store
        .workspace_retirement_receipt(&owned.id, &owned.instance_id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn cleanup_allows_shared_branch_updates_but_not_task_identity_replacement() {
    let (_directory, store, run, owned) = successful().await;
    let mut changed = owned.clone();
    changed.instance_id = "another-task".into();
    store.upsert_workspace(changed.clone()).await.unwrap();
    assert!(store
        .retire_verified_automation_shared_workspace(&run, &changed)
        .await
        .is_err());
    store.upsert_workspace(owned.clone()).await.unwrap();
    changed = owned.clone();
    changed.branch = Some("shared-branch-changed".into());
    let changed = store.upsert_workspace(changed).await.unwrap();
    store
        .retire_verified_automation_shared_workspace(&run, &changed)
        .await
        .unwrap();
}

#[tokio::test]
async fn cleanup_preserves_a_task_used_by_another_unfinished_run() {
    let (_directory, store, completed, owned) = successful().await;
    let mut dependent = run(&store, "local").await;
    dependent.workspace_id = Some(owned.id.clone());
    store.save_automation_run(&dependent).await.unwrap();
    let error = store
        .retire_verified_automation_shared_workspace(&completed, &owned)
        .await
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("Another automation still depends"));
    assert!(store
        .find_workspace_tab("owned-tab")
        .await
        .unwrap()
        .is_some());
    assert!(store
        .workspace_retirement_receipt(&owned.id, &owned.instance_id)
        .await
        .unwrap()
        .is_none());
}

#[path = "automation_cleanup_attempt_store_tests.rs"]
mod recovery;
