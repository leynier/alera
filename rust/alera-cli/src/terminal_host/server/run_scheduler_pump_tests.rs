use std::collections::HashMap;

use super::ExecutionPump;
use crate::managed_workspace::run::tests::fixture::Fixture;
use crate::terminal_host::server::actor_test_harness::test_actor;
use alera_core::runtime::{
    WorkflowLaunchQuery, WorkflowLaunchStatus, WorkflowTerminalShutdownState,
    WorkflowWorkspaceQuery,
};

#[path = "run_scheduler_pump_tests/cancelled_integrations.rs"]
mod cancelled_integrations;

#[test]
fn execution_wake_survives_full_waiting_pages_until_cursor_wraps() {
    let mut pump = ExecutionPump {
        busy: true,
        dirty: true,
        ..ExecutionPump::default()
    };
    assert!(pump.settle_page(Some("run-01".into()), true));
    assert!(pump.dirty);
    assert!(pump.settle_page(Some("run-26".into()), true));
    assert!(pump.dirty);
    assert!(pump.settle_page(None, false));
    assert!(!pump.dirty);
    assert!(pump.cursor.is_none());
    assert!(!pump.settle_page(None, false));
}

#[tokio::test]
async fn cancellation_stops_only_matching_workers_while_execution_is_busy() {
    use crate::managed_workspace::run::launch::{self, PreparedLaunch};
    let fixture = Fixture::with_command("", "echo cancellation-test").await;
    fixture.integration().await;
    let workspace = fixture.task("fix").await;
    let request = alera_core::runtime::LaunchWorkflowTask {
        request_id: "worker".into(),
        run_id: fixture.plan.run_id.clone(),
        revision: 1,
        task_id: fixture.task_id("fix").await,
        workspace_id: workspace.identity.workspace.id.clone(),
    };
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = launch::prepare(&fixture.store, &fixture.runtime, request)
        .await
        .unwrap()
    else {
        panic!("fresh attempt");
    };
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox;
    let frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    actor
        .spawn_workflow_launch(&record, &token, frozen)
        .await
        .unwrap();
    drop(locks);
    let file = std::path::Path::new(&workspace.identity.workspace.path).join("retained-work.txt");
    std::fs::write(&file, "uncommitted work").unwrap();
    let cancelled = fixture
        .control(alera_core::runtime::RunControlAction::Cancel)
        .await
        .unwrap();
    // Model a still-running setup/integration pass. Cancellation owns a
    // separate lane and must not need that pass to finish.
    actor.workflow_execution.ready = true;
    actor.workflow_execution.busy = true;
    actor
        .sessions
        .get_mut(&record.terminal_handle)
        .unwrap()
        .workspace_id = "foreign-workspace".into();
    actor.wake_workflow_execution();
    assert_eq!(actor.workflow_workspace_jobs, 1);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(!actor.has_blocking_managed_workspace_jobs());
    drain_cancellation(&mut actor, &mut commands).await;
    assert_eq!(actor.workflow_workspace_jobs, 0);
    assert!(actor.sessions[&record.terminal_handle].running());
    let error: String = sqlx::query_scalar(
        "SELECT error FROM runCancellationTargets WHERE run_id = ? AND state = 'attention'",
    )
    .bind(&fixture.plan.run_id)
    .fetch_one(fixture.store.pool())
    .await
    .unwrap();
    assert!(error.contains("identity changed"));
    actor
        .sessions
        .get_mut(&record.terminal_handle)
        .unwrap()
        .workspace_id = workspace.identity.workspace.id.clone();
    fixture
        .store
        .retry_run_cancellation(
            &alera_core::runtime::RetryRunCancellation {
                request_id: "retry".into(),
                run_id: fixture.plan.run_id.clone(),
                expected_sequence: cancelled.sequence,
            },
            &crate::managed_workspace::run::tests::fixture::desktop(),
        )
        .await
        .unwrap();
    actor.wake_workflow_execution();
    drain_cancellation(&mut actor, &mut commands).await;
    assert_eq!(actor.workflow_workspace_jobs, 0);
    assert!(!actor.sessions.contains_key(&record.terminal_handle));
    assert_eq!(
        fixture
            .store
            .workflow_terminal_shutdown_state(
                &record.terminal_handle,
                &workspace.identity.workspace.id,
            )
            .await
            .unwrap(),
        WorkflowTerminalShutdownState::Verified
    );
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "uncommitted work");
    assert!(fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .is_some());
    assert!(fixture
        .store
        .find_workspace(&workspace.identity.workspace.id)
        .await
        .unwrap()
        .is_some());
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM runCancellationTargets WHERE run_id = ? AND state <> 'settled'",
    )
    .bind(&fixture.plan.run_id)
    .fetch_one(fixture.store.pool())
    .await
    .unwrap();
    assert_eq!(pending, 0);
    actor.workflow_execution.busy = false;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(actor.workflow_workspace_jobs, 0);
    actor.dispose().await;
}

async fn drain_cancellation(
    actor: &mut super::ServerActor,
    commands: &mut crate::terminal_host::server::ServerInboxReceiver,
) {
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
    while actor.workflow_execution.cancelling {
        let command = tokio::time::timeout_at(deadline, commands.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
}

#[tokio::test]
async fn execution_pump_launches_to_concurrency_without_a_board_or_desktop_client() {
    let fixture = Fixture::with_command("", "echo execution-pump-test").await;
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox;
    actor.wake_workflow_execution();
    assert_eq!(actor.managed_workspace_jobs, 0);
    actor.workflow_execution.ready = true;
    actor.wake_workflow_execution();
    actor.wake_workflow_execution();
    assert!(actor.workflow_workspace_jobs > 0);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(!actor.has_blocking_managed_workspace_jobs());
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
    loop {
        let command = match tokio::time::timeout_at(deadline, commands.recv()).await {
            Ok(Some(command)) => command,
            _ => {
                let launches = fixture
                    .store
                    .workflow_launch_summaries(&WorkflowLaunchQuery {
                        run_id: fixture.plan.run_id.clone(),
                        after_row: None,
                    })
                    .await
                    .unwrap();
                panic!(
                    "execution stalled: busy={}, cancelling={}, dirty={}, cursor={:?}, jobs={}, launches={:?}",
                    actor.workflow_execution.busy,
                    actor.workflow_execution.cancelling,
                    actor.workflow_execution.dirty,
                    actor.workflow_execution.cursor,
                    actor.workflow_workspace_jobs,
                    launches.items,
                );
            }
        };
        actor.handle(command).await;
        let launches = fixture
            .store
            .workflow_launch_summaries(&WorkflowLaunchQuery {
                run_id: fixture.plan.run_id.clone(),
                after_row: None,
            })
            .await
            .unwrap();
        if launches.items.len() == 2
            && launches
                .items
                .iter()
                .all(|launch| launch.status == WorkflowLaunchStatus::Started)
            && !actor.workflow_execution.busy
            && !actor.workflow_execution.cancelling
        {
            break;
        }
    }
    let workspaces = fixture
        .store
        .workflow_workspaces(&WorkflowWorkspaceQuery {
            run_id: fixture.plan.run_id.clone(),
            before_row: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(workspaces.items.len(), 3);
    assert!(workspaces
        .items
        .iter()
        .all(|item| item.identity.attempt == i64::from(item.identity.task_id.is_some())));
    assert!(actor.clients.is_empty());
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(actor.workflow_workspace_jobs, 0);
    actor.dispose().await;
}

#[tokio::test]
async fn waiting_execution_does_not_reschedule_itself() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox;
    actor.workflow_execution.ready = true;
    // Consume fixture initialization revisions before checking the idle lane.
    actor
        .runtime_store
        .take_orchestration_board_change()
        .await
        .unwrap();
    actor.wake_workflow_execution();
    while actor.workflow_workspace_jobs > 0 {
        let command = tokio::time::timeout(std::time::Duration::from_secs(5), commands.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
    assert!(!actor.workflow_execution.busy);
    assert!(!actor.workflow_execution.dirty);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(actor.workflow_workspace_jobs, 0);
    assert!(commands.try_recv().is_err());
    actor.dispose().await;
}
