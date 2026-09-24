use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};
use crate::runtime::WorkspaceTabRecord;
use serde_json::json;

async fn owner() -> (tempfile::TempDir, RuntimeStore, RemoteAutomationCleanup) {
    let (root, store, _) = fixture().await;
    let workspace = store
        .insert_workspace(workspace("owned", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    let now = chrono::Utc::now();
    store
        .insert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"automationRunId":"run","automationOwned":true}),
        })
        .await
        .unwrap();
    (
        root,
        store,
        RemoteAutomationCleanup {
            run_id: "run".into(),
            workspace,
            tab_ids: vec!["tab".into()],
        },
    )
}

#[tokio::test]
async fn owner_cleanup_keeps_siblings_and_produces_a_durable_receipt() {
    let (root, store, scope) = owner().await;
    store
        .insert_workspace(workspace("sibling", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    store
        .require_remote_automation_cleanup(&scope, &scope.workspace)
        .await
        .unwrap();
    store
        .retire_verified_remote_automation_workspace(&scope, &scope.workspace)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    assert!(reopened.find_workspace("owned").await.unwrap().is_none());
    assert!(reopened.find_workspace_tab("tab").await.unwrap().is_none());
    assert!(reopened.find_workspace("sibling").await.unwrap().is_some());
    assert!(reopened
        .workspace_retirement_receipt("owned", &scope.workspace.instance_id)
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn user_tab_added_after_preflight_rolls_back_the_entire_retirement() {
    let (_root, store, scope) = owner().await;
    store
        .require_remote_automation_cleanup(&scope, &scope.workspace)
        .await
        .unwrap();
    let mut user = store.find_workspace_tab("tab").await.unwrap().unwrap();
    user.id = "user".into();
    user.payload = json!({});
    store.insert_workspace_tab(user).await.unwrap();
    assert!(store
        .retire_verified_remote_automation_workspace(&scope, &scope.workspace)
        .await
        .is_err());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_some());
    assert!(store.find_workspace_tab("user").await.unwrap().is_some());
    assert!(store
        .workspace_retirement_receipt("owned", &scope.workspace.instance_id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn owner_cleanup_rejects_changed_scope_identity_and_organization() {
    let (_root, store, scope) = owner().await;
    for changed in [
        RemoteAutomationCleanup {
            run_id: "other".into(),
            ..scope.clone()
        },
        RemoteAutomationCleanup {
            tab_ids: vec![],
            ..scope.clone()
        },
        RemoteAutomationCleanup {
            tab_ids: vec!["tab".into(), "tab".into()],
            ..scope.clone()
        },
    ] {
        assert!(store
            .require_remote_automation_cleanup(&changed, &scope.workspace)
            .await
            .is_err());
    }
    let mut replacement = scope.workspace.clone();
    replacement.instance_id = "replacement".into();
    assert!(store
        .require_remote_automation_cleanup(&scope, &replacement)
        .await
        .is_err());
    let mut edited = scope.workspace.clone();
    edited.is_pinned = true;
    store.upsert_workspace(edited).await.unwrap();
    assert!(store
        .retire_verified_remote_automation_workspace(&scope, &scope.workspace)
        .await
        .is_err());
    assert!(store.find_workspace("owned").await.unwrap().is_some());
}
