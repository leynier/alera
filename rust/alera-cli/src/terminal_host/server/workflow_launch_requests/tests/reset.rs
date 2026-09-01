use super::*;

#[tokio::test]
async fn orchestration_reset_rejects_unsettled_workflow_launches() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh { record, locks, .. } = prepared else {
        panic!("fresh launch required")
    };
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();

    let error = actor
        .orchestration_reset(&json!({"tasks": true}))
        .await
        .unwrap_err();
    assert!(error
        .wire_message()
        .contains("settle active workflow workers"));
    assert!(fixture
        .store
        .orchestration_task_by_id(&input.task_id)
        .await
        .unwrap()
        .is_some());
    assert!(fixture
        .store
        .orchestration_dispatch_by_id(&record.dispatch_id)
        .await
        .unwrap()
        .is_some());

    fixture
        .store
        .settle_workflow_launch_without_session(&record.terminal_handle, "worker stopped")
        .await
        .unwrap();
    actor
        .orchestration_reset(&json!({"tasks": true}))
        .await
        .unwrap();
    assert!(fixture
        .store
        .orchestration_task_by_id(&input.task_id)
        .await
        .unwrap()
        .is_none());
    drop(locks);
}
