use super::*;

fn command(request: &LaunchWorkflowTask) -> ControlWorkflowExecution {
    ControlWorkflowExecution {
        request_id: "start".into(),
        run_id: request.run_id.clone(),
        revision: request.revision,
        expected_sequence: 0,
        action: WorkflowExecutionAction::Start,
    }
}

#[tokio::test]
async fn execution_replay_does_not_resume_a_later_pause() {
    let (dir, store, launch) = prepared().await;
    let start = command(&launch);
    let (one, two) = tokio::join!(
        store.control_workflow_execution(&start),
        store.control_workflow_execution(&start)
    );
    assert_eq!(one.unwrap().sequence, 1);
    assert_eq!(two.unwrap().sequence, 1);
    let mut pause = start.clone();
    pause.request_id = "pause".into();
    pause.expected_sequence = 1;
    pause.action = WorkflowExecutionAction::Pause;
    assert_eq!(
        store
            .control_workflow_execution(&pause)
            .await
            .unwrap()
            .sequence,
        2
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .control_workflow_execution(&start)
            .await
            .unwrap()
            .status,
        "running"
    );
    assert_eq!(
        reopened
            .workflow_execution(&launch.run_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "paused"
    );
    pause.action = WorkflowExecutionAction::Start;
    assert!(reopened
        .control_workflow_execution(&pause)
        .await
        .unwrap_err()
        .to_string()
        .contains("different contents"));
    pause.request_id = "stale start".into();
    assert!(reopened
        .control_workflow_execution(&pause)
        .await
        .unwrap_err()
        .to_string()
        .contains("changed"));
}

#[tokio::test]
async fn pause_blocks_reservation_and_final_spawn_boundary() {
    let (_dir, store, launch) = prepared().await;
    let mut pause = command(&launch);
    pause.action = WorkflowExecutionAction::Pause;
    store.control_workflow_execution(&pause).await.unwrap();
    assert!(store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap_err()
        .to_string()
        .contains("paused"));
    let mut start = command(&launch);
    start.request_id = "resume".into();
    start.expected_sequence = 1;
    store.control_workflow_execution(&start).await.unwrap();
    let (reserved, _) = store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&reserved.id).await.unwrap();
    pause.request_id = "pause again".into();
    pause.expected_sequence = 2;
    store.control_workflow_execution(&pause).await.unwrap();
    assert!(store
        .require_workflow_launch_spawnable(&reserved.id)
        .await
        .unwrap_err()
        .to_string()
        .contains("paused"));
}

#[tokio::test]
async fn execution_control_rejects_unapproved_or_obsolete_plans() {
    let (_dir, store, launch) = prepared().await;
    let mut start = command(&launch);
    start.revision += 1;
    assert!(store.control_workflow_execution(&start).await.is_err());
    start.revision = launch.revision;
    sqlx::query("UPDATE workflowRuns SET status='rejected' WHERE run_id=?")
        .bind(&launch.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store.control_workflow_execution(&start).await.is_err());
    assert!(store
        .workflow_execution(&launch.run_id)
        .await
        .unwrap()
        .is_none());
}
