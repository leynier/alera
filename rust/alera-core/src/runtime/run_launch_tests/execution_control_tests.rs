use super::*;
use crate::runtime::run_plan_tests::{control, desktop};

fn command(request: &LaunchWorkflowTask, id: &str, sequence: i64) -> RunControl {
    RunControl {
        request_id: id.into(),
        run_id: request.run_id.clone(),
        expected_sequence: sequence,
        action: RunControlAction::Pause,
        reason: None,
        task_ids: None,
    }
}

async fn sequence(store: &RuntimeStore, run: &str) -> i64 {
    sqlx::query_scalar("SELECT control_sequence FROM orchestrationCoordinatorRuns WHERE id = ?")
        .bind(run)
        .fetch_one(store.pool())
        .await
        .unwrap()
}

#[tokio::test]
async fn control_replay_does_not_resume_a_later_pause() {
    let (dir, store, launch) = prepared().await;
    let start = sequence(&store, &launch.run_id).await;
    let pause = command(&launch, "pause", start);
    let actor = desktop();
    let (one, two) = tokio::join!(
        store.control_run(&pause, &actor),
        store.control_run(&pause, &actor)
    );
    assert_eq!(one.unwrap().sequence, start + 1);
    assert_eq!(two.unwrap().sequence, start + 1);
    let mut resume = command(&launch, "resume", start + 1);
    resume.action = RunControlAction::Resume;
    assert_eq!(
        store.control_run(&resume, &desktop()).await.unwrap().status,
        "running"
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let replay = reopened.control_run(&pause, &desktop()).await.unwrap();
    assert!(replay.replayed);
    assert_eq!(replay.status, "paused");
    assert_eq!(
        reopened
            .workflow_execution(&launch.run_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "running"
    );
    let mut different = pause.clone();
    different.action = RunControlAction::Resume;
    assert!(reopened
        .control_run(&different, &desktop())
        .await
        .unwrap_err()
        .to_string()
        .contains("different contents"));
    let stale = command(&launch, "stale-pause", start);
    assert!(reopened
        .control_run(&stale, &desktop())
        .await
        .unwrap_err()
        .to_string()
        .starts_with("run_sequence_stale:"));
}

#[tokio::test]
async fn pause_blocks_reservation_and_final_spawn_boundary() {
    let (_dir, store, launch) = prepared().await;
    control(&store, &launch.run_id, RunControlAction::Pause)
        .await
        .unwrap();
    assert!(store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap_err()
        .to_string()
        .contains("paused"));
    control(&store, &launch.run_id, RunControlAction::Resume)
        .await
        .unwrap();
    let (reserved, _) = store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&reserved.id).await.unwrap();
    control(&store, &launch.run_id, RunControlAction::Pause)
        .await
        .unwrap();
    assert!(store
        .require_workflow_launch_spawnable(&reserved.id)
        .await
        .unwrap_err()
        .to_string()
        .contains("paused"));
}

#[tokio::test]
async fn control_rejects_finished_runs_and_resume_waits_for_due_gates() {
    let (_dir, store, launch) = prepared().await;
    let resume = control(&store, &launch.run_id, RunControlAction::Resume)
        .await
        .unwrap_err();
    assert!(resume.to_string().starts_with("run_not_paused:"));
    control(&store, &launch.run_id, RunControlAction::Cancel)
        .await
        .unwrap();
    for action in [
        RunControlAction::Pause,
        RunControlAction::Cancel,
        RunControlAction::Replan,
    ] {
        assert!(control(&store, &launch.run_id, action).await.is_err());
    }
}
