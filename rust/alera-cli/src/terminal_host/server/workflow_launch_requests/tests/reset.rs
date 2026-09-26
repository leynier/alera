use super::*;
use crate::terminal_host::session::Session;

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

#[tokio::test]
async fn orchestration_reset_allows_an_exited_completed_workflow_session() {
    let fixture = Fixture::new("").await;
    let (_input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    fixture
        .store
        .claim_workflow_launch(&record.id)
        .await
        .unwrap();
    fixture
        .store
        .mark_workflow_launch_started(&record.id)
        .await
        .unwrap();
    fixture
        .store
        .accept_orchestration_dispatch(
            &record.dispatch_id,
            &record.terminal_handle,
            &hex::encode(Sha256::digest(token.as_bytes())),
        )
        .await
        .unwrap();
    fixture
        .store
        .complete_workflow_orchestration_dispatch(
            &record.dispatch_id,
            &record.terminal_handle,
            r#"{"summary":"Done","completionKind":"success","artifacts":["shared.txt"],"filesModified":["shared.txt"],"validation":[{"id":"regression","passed":true,"evidence":"regression covered"},{"id":"checks","passed":true,"evidence":"focused checks passed"}]}"#,
            &"b".repeat(40),
        )
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([(
            record.terminal_handle.clone(),
            Session::driver_test_stub(&record.terminal_handle, 80, 24),
        )]),
    )
    .await;
    actor.runtime_store = fixture.store.clone();

    let error = actor
        .orchestration_reset(&json!({"tasks": true}))
        .await
        .unwrap_err();
    assert!(error
        .wire_message()
        .contains("settle active workflow workers"));
    actor
        .sessions
        .get_mut(&record.terminal_handle)
        .unwrap()
        .handle_exit(0);
    actor
        .orchestration_reset(&json!({"tasks": true}))
        .await
        .unwrap();
    assert!(fixture
        .store
        .orchestration_dispatch_by_id(&record.dispatch_id)
        .await
        .unwrap()
        .is_none());
    drop(locks);
}
