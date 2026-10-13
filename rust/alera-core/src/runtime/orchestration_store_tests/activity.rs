//! Activity leases, revival of stalled dispatches, and startup deadlines.

use super::*;

#[tokio::test]
async fn activity_renews_a_dispatch_and_revives_a_stalled_one() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("activity", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();

    assert_eq!(
        store
            .record_orchestration_activity(&dispatch.id)
            .await
            .unwrap(),
        ActivityOutcome::Recorded
    );

    let stalled = store
        .stall_expired_orchestration_dispatches("9999-01-01 00:00:00")
        .await
        .unwrap();
    assert_eq!(stalled.len(), 1);
    assert_eq!(
        store
            .record_orchestration_activity(&dispatch.id)
            .await
            .unwrap(),
        ActivityOutcome::Revived
    );
    let revived = store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(revived.status, OrchestrationDispatchStatus::Dispatched);
    let task = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Dispatched);
    assert_eq!(task.stalled_at, None);

    store
        .complete_orchestration_dispatch(&dispatch.id, "term_1", "{}")
        .await
        .unwrap();
    // Straggler activity from a completed dispatch is ignored.
    assert_eq!(
        store
            .record_orchestration_activity(&dispatch.id)
            .await
            .unwrap(),
        ActivityOutcome::Ignored
    );
}

#[tokio::test]
async fn a_stalled_dispatch_can_still_complete() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("slow", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();
    store
        .stall_expired_orchestration_dispatches("9999-01-01 00:00:00")
        .await
        .unwrap();

    let completed = store
        .complete_orchestration_dispatch(&dispatch.id, "term_1", r#"{"summary":"done"}"#)
        .await
        .unwrap();

    assert_eq!(completed.status, OrchestrationDispatchStatus::Completed);
    let task = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Completed);
}

#[tokio::test]
async fn unaccepted_dispatches_are_listed_past_the_threshold() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("startup", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &created.id,
            "term_1",
            None,
            "global",
            "coord",
            None,
            "keep-open",
        )
        .await
        .unwrap();

    let waiting = store
        .unaccepted_orchestration_dispatches("9999-01-01 00:00:00")
        .await
        .unwrap();
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].id, dispatch.id);
    assert!(store
        .unaccepted_orchestration_dispatches("2000-01-01 00:00:00")
        .await
        .unwrap()
        .is_empty());

    store
        .accept_orchestration_dispatch(&dispatch.id, "term_1", "")
        .await
        .unwrap();
    assert!(store
        .unaccepted_orchestration_dispatches("9999-01-01 00:00:00")
        .await
        .unwrap()
        .is_empty());
}
