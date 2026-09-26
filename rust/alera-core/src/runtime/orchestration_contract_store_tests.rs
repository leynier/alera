use serde_json::json;

use super::orchestration_role_contract_tests::{result, snapshot};
use super::*;

fn task(deps: Vec<String>) -> NewOrchestrationTask {
    NewOrchestrationTask {
        spec: "Implement the scoped change".into(),
        task_title: None,
        display_name: None,
        deps,
        parent_id: None,
        created_by_terminal_handle: None,
        run_id: None,
        workspace_id: "workspace".into(),
        coordinator_handle: "coordinator".into(),
        result_schema: None,
    }
}

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

async fn dispatch(store: &RuntimeStore, task_id: &str) -> OrchestrationDispatchContext {
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            task_id,
            "worker",
            None,
            "workspace",
            "coordinator",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&dispatch.id, "worker", "")
        .await
        .unwrap()
}

#[tokio::test]
async fn role_contract_snapshot_survives_restart_and_cannot_be_replaced() {
    let (dir, store) = store().await;
    let frozen = snapshot();
    let created = store
        .create_orchestration_task_with_contract(task(vec![]), Some(frozen.clone()))
        .await
        .unwrap();
    assert_eq!(created.role_contract, Some(frozen.clone()));
    for replacement in [None, Some("{}".to_string())] {
        assert!(
            sqlx::query("UPDATE orchestrationTasks SET role_contract = ? WHERE id = ?")
                .bind(replacement)
                .bind(&created.id)
                .execute(store.pool())
                .await
                .is_err()
        );
    }
    store.pool().close().await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .role_contract,
        Some(frozen)
    );
    assert_eq!(
        reopened.list_orchestration_tasks(None).await.unwrap().len(),
        1
    );
}

#[tokio::test]
async fn role_contract_invalid_creation_is_atomic() {
    let (_dir, store) = store().await;
    let mut forged = snapshot();
    forged.inputs = json!({"objective": "silently changed"});
    assert!(store
        .create_orchestration_task_with_contract(task(vec![]), Some(forged))
        .await
        .is_err());
    let mut ambiguous = task(vec![]);
    ambiguous.result_schema = Some("{}".into());
    assert!(store
        .create_orchestration_task_with_contract(ambiguous, Some(snapshot()))
        .await
        .is_err());
    assert!(store
        .create_orchestration_task_with_contract(task(vec!["unknown".into()]), Some(snapshot()))
        .await
        .is_err());
    assert!(store
        .list_orchestration_tasks(None)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn role_contract_migration_preserves_pre_contract_tasks() {
    let (dir, store) = store().await;
    let created = store.create_orchestration_task(task(vec![])).await.unwrap();
    sqlx::query("DROP TRIGGER orchestrationRoleContractImmutable")
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("ALTER TABLE orchestrationTasks DROP COLUMN role_contract")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap(),
        created
    );
    reopened
        .create_orchestration_task_with_contract(task(vec![]), Some(snapshot()))
        .await
        .unwrap();
}

#[tokio::test]
async fn role_contract_invalid_completion_preserves_dispatch_and_blocked_dependents() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task_with_contract(task(vec![]), Some(snapshot()))
        .await
        .unwrap();
    let dependent = store
        .create_orchestration_task(task(vec![created.id.clone()]))
        .await
        .unwrap();
    let dispatch = dispatch(&store, &created.id).await;
    let mut invalid = result();
    invalid["validation"] = json!([]);
    assert!(store
        .complete_orchestration_dispatch(&dispatch.id, "worker", &invalid.to_string())
        .await
        .is_err());
    let unchanged = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(unchanged.status, OrchestrationTaskStatus::Dispatched);
    assert!(unchanged.result.is_none());
    assert_eq!(
        store
            .orchestration_dispatch_by_id(&dispatch.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Dispatched
    );
    assert_eq!(
        store
            .orchestration_task_by_id(&dependent.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Pending
    );
    assert!(store
        .update_orchestration_task_status(
            &created.id,
            OrchestrationTaskStatus::Completed,
            Some(&result().to_string())
        )
        .await
        .is_err());
    store
        .complete_orchestration_dispatch(&dispatch.id, "worker", &result().to_string())
        .await
        .unwrap();
    assert_eq!(
        store
            .orchestration_task_by_id(&dependent.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Ready
    );
}

#[tokio::test]
async fn role_contract_duplicate_completion_cannot_replace_evidence_or_reopen_task() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task_with_contract(task(vec![]), Some(snapshot()))
        .await
        .unwrap();
    let dispatch = dispatch(&store, &created.id).await;
    store
        .complete_orchestration_dispatch(&dispatch.id, "worker", &result().to_string())
        .await
        .unwrap();
    store
        .complete_orchestration_dispatch(&dispatch.id, "worker", "changed evidence")
        .await
        .unwrap();
    assert!(store
        .complete_orchestration_dispatch(&dispatch.id, "other", &result().to_string())
        .await
        .is_err());
    assert_eq!(
        store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .result,
        Some(result().to_string())
    );
    for status in [
        OrchestrationTaskStatus::Ready,
        OrchestrationTaskStatus::Completed,
        OrchestrationTaskStatus::Failed,
    ] {
        assert!(store
            .update_orchestration_task_status(&created.id, status, Some("replace"))
            .await
            .is_err());
    }
}

#[tokio::test]
async fn role_contract_failures_retries_and_cancellation_do_not_require_success_evidence() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task_with_contract(task(vec![]), Some(snapshot()))
        .await
        .unwrap();
    let first = dispatch(&store, &created.id).await;
    store
        .fail_orchestration_dispatch_with_result(&first.id, "tests failed", Some("honest failure"))
        .await
        .unwrap();
    let retried = dispatch(&store, &created.id).await;
    assert_ne!(first.id, retried.id);
    assert_eq!(
        store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .role_contract,
        Some(snapshot())
    );
    store
        .cancel_orchestration_task(&created.id, "cancelled by user")
        .await
        .unwrap();
    assert_eq!(
        store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Cancelled
    );
}

#[tokio::test]
async fn role_contract_legacy_creation_and_completion_keep_existing_shape() {
    let (_dir, store) = store().await;
    let created = store.create_orchestration_task(task(vec![])).await.unwrap();
    let serialized = serde_json::to_value(&created).unwrap();
    assert!(serialized.get("role_contract").is_none());
    assert_eq!(
        serde_json::from_value::<OrchestrationTask>(serialized).unwrap(),
        created
    );
    store
        .update_orchestration_task_status(
            &created.id,
            OrchestrationTaskStatus::Completed,
            Some("legacy free text"),
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .result
            .as_deref(),
        Some("legacy free text")
    );
}
