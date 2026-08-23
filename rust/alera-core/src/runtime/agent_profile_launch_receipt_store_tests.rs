use chrono::Utc;
use serde_json::json;

use super::{
    AgentProfileLaunchReceiptOutcome, RuntimeStore, WorkspaceTabRecord,
    AGENT_PROFILE_LAUNCH_RECEIPT_CAPACITY_PER_SCOPE_WORKSPACE,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn tab(id: &str) -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: id.to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "terminal".to_string(),
        title: "Codex".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({"spawnOnCreate": true}),
    }
}

#[tokio::test]
async fn retries_replay_the_durable_result_after_reopen() {
    let (dir, store) = store().await;
    let result = json!({"tab": {"id": "tab-1"}, "agentType": "codex"});
    assert_eq!(
        store
            .record_agent_profile_launch(
                "mobile:device-1",
                "workspace-1",
                "mutation-1",
                "digest-1",
                &result,
                &tab("tab-1"),
            )
            .await
            .unwrap(),
        AgentProfileLaunchReceiptOutcome::Created
    );
    drop(store);

    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .record_agent_profile_launch(
                "mobile:device-1",
                "workspace-1",
                "mutation-1",
                "digest-1",
                &json!({"ignored": true}),
                &tab("tab-2"),
            )
            .await
            .unwrap(),
        AgentProfileLaunchReceiptOutcome::Replay(result)
    );
    assert!(reopened
        .find_workspace_tab("tab-1")
        .await
        .unwrap()
        .is_some());
    assert!(reopened
        .find_workspace_tab("tab-2")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn rejects_a_reused_id_with_a_different_payload() {
    let (_dir, store) = store().await;
    store
        .record_agent_profile_launch(
            "mobile:device-1",
            "workspace-1",
            "mutation-1",
            "digest-1",
            &json!({"tab": {"id": "tab-1"}}),
            &tab("tab-1"),
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .record_agent_profile_launch(
                "mobile:device-1",
                "workspace-1",
                "mutation-1",
                "digest-2",
                &json!({"tab": {"id": "tab-2"}}),
                &tab("tab-2"),
            )
            .await
            .unwrap(),
        AgentProfileLaunchReceiptOutcome::Conflict
    );
    assert!(store.find_workspace_tab("tab-2").await.unwrap().is_none());
}

#[tokio::test]
async fn scopes_mutation_ids_by_caller_and_workspace() {
    let (_dir, store) = store().await;
    for (scope, tab_id) in [("mobile:device-1", "tab-1"), ("mobile:device-2", "tab-2")] {
        assert_eq!(
            store
                .record_agent_profile_launch(
                    scope,
                    "workspace-1",
                    "shared-mutation",
                    "digest-1",
                    &json!({"tab": {"id": tab_id}}),
                    &tab(tab_id),
                )
                .await
                .unwrap(),
            AgentProfileLaunchReceiptOutcome::Created
        );
    }
    assert!(store.find_workspace_tab("tab-1").await.unwrap().is_some());
    assert!(store.find_workspace_tab("tab-2").await.unwrap().is_some());
}

#[tokio::test]
async fn removing_a_failed_tab_also_removes_its_receipt() {
    let (_dir, store) = store().await;
    store
        .record_agent_profile_launch(
            "mobile:device-1",
            "workspace-1",
            "mutation-1",
            "digest-1",
            &json!({"tab": {"id": "tab-1"}}),
            &tab("tab-1"),
        )
        .await
        .unwrap();

    store.remove_workspace_tab("tab-1").await.unwrap();

    assert!(store.find_workspace_tab("tab-1").await.unwrap().is_none());
    assert_eq!(
        store
            .find_agent_profile_launch_receipt(
                "mobile:device-1",
                "workspace-1",
                "mutation-1",
                "digest-1",
            )
            .await
            .unwrap(),
        None
    );
}

#[tokio::test]
async fn bounds_receipts_per_caller_and_workspace() {
    let (_dir, store) = store().await;
    for index in 0..=AGENT_PROFILE_LAUNCH_RECEIPT_CAPACITY_PER_SCOPE_WORKSPACE {
        let tab_id = format!("tab-{index}");
        store
            .record_agent_profile_launch(
                "mobile:device-1",
                "workspace-1",
                &format!("mutation-{index}"),
                &format!("digest-{index}"),
                &json!({"tab": {"id": tab_id}}),
                &tab(&tab_id),
            )
            .await
            .unwrap();
    }
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM agentProfileLaunchReceipts \
         WHERE callerScope = 'mobile:device-1' AND workspaceId = 'workspace-1'",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(
        count,
        AGENT_PROFILE_LAUNCH_RECEIPT_CAPACITY_PER_SCOPE_WORKSPACE
    );
}
