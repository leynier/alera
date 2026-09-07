use std::collections::HashMap;

use crate::managed_workspace::workflow::tests::fixture::Fixture;
use crate::terminal_host::server::actor_test_harness::test_actor;
use alera_core::runtime::{
    ControlWorkflowExecution, WorkflowExecutionAction, WorkflowLaunchQuery, WorkflowLaunchStatus,
    WorkflowWorkspaceQuery,
};

#[tokio::test]
async fn cancellation_stops_only_matching_workers_while_execution_is_busy() {
    use crate::managed_workspace::workflow::launch::{self, PreparedLaunch};
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
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
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
    let mut cancel = ControlWorkflowExecution {
        request_id: "cancel".into(),
        run_id: fixture.plan.run_id.clone(),
        revision: 1,
        expected_sequence: 0,
        action: WorkflowExecutionAction::Cancel,
    };
    fixture
        .store
        .control_workflow_execution(&cancel)
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
    drain_cancellation(&mut actor, &mut commands).await;
    assert!(actor.sessions[&record.terminal_handle].running());
    let controls = fixture
        .store
        .workflow_run_controls(&fixture.plan.run_id, Some(1))
        .await
        .unwrap();
    assert!(controls
        .cancellation_error
        .unwrap()
        .contains("identity changed"));
    assert!(controls.can_cancel);
    actor
        .sessions
        .get_mut(&record.terminal_handle)
        .unwrap()
        .workspace_id = workspace.identity.workspace.id.clone();
    cancel.request_id = "retry".into();
    cancel.expected_sequence = 1;
    fixture
        .store
        .control_workflow_execution(&cancel)
        .await
        .unwrap();
    actor.wake_workflow_execution();
    drain_cancellation(&mut actor, &mut commands).await;
    assert!(!actor.sessions.contains_key(&record.terminal_handle));
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
    assert_eq!(
        fixture
            .store
            .workflow_run_controls(&fixture.plan.run_id, Some(1))
            .await
            .unwrap()
            .cancellation_pending,
        0
    );
    actor.workflow_execution.busy = false;
    assert_eq!(actor.managed_workspace_jobs, 0);
    actor.dispose().await;
}

async fn drain_cancellation(
    actor: &mut super::ServerActor,
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<
        crate::terminal_host::server::ServerCommand,
    >,
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
async fn execution_pump_launches_once_without_a_board_or_desktop_client() {
    let fixture = Fixture::with_command("", "echo execution-pump-test").await;
    fixture
        .store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "start".into(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Start,
        })
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.wake_workflow_execution();
    assert_eq!(actor.managed_workspace_jobs, 0);
    actor.workflow_execution.ready = true;
    actor.wake_workflow_execution();
    actor.wake_workflow_execution();
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
    loop {
        let command = tokio::time::timeout_at(deadline, commands.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
        let launches = fixture
            .store
            .workflow_launch_summaries(&WorkflowLaunchQuery {
                run_id: fixture.plan.run_id.clone(),
                after_row: None,
            })
            .await
            .unwrap();
        if launches.items.len() == 1
            && launches.items[0].status == WorkflowLaunchStatus::Started
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
    assert_eq!(workspaces.items.len(), 2);
    assert!(workspaces
        .items
        .iter()
        .all(|item| item.identity.attempt == i64::from(item.identity.task_id.is_some())));
    assert!(actor.clients.is_empty());
    assert_eq!(actor.managed_workspace_jobs, 0);
    actor.dispose().await;
}

#[tokio::test]
async fn waiting_execution_does_not_reschedule_itself() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.workflow_execution.ready = true;
    // Consume fixture initialization revisions before checking the idle lane.
    actor
        .runtime_store
        .take_orchestration_board_change()
        .await
        .unwrap();
    actor.wake_workflow_execution();
    while actor.managed_workspace_jobs > 0 {
        let command = tokio::time::timeout(std::time::Duration::from_secs(5), commands.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
    assert!(!actor.workflow_execution.busy);
    assert!(!actor.workflow_execution.dirty);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(commands.try_recv().is_err());
    actor.dispose().await;
}
