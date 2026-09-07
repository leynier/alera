use std::collections::HashMap;

use crate::managed_workspace::workflow::tests::fixture::Fixture;
use crate::terminal_host::server::actor_test_harness::test_actor;
use alera_core::runtime::{
    ControlWorkflowExecution, WorkflowExecutionAction, WorkflowLaunchQuery, WorkflowLaunchStatus,
    WorkflowWorkspaceQuery,
};

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
    let command = tokio::time::timeout(std::time::Duration::from_secs(5), commands.recv())
        .await
        .unwrap()
        .unwrap();
    actor.handle(command).await;
    assert!(!actor.workflow_execution.busy);
    assert!(!actor.workflow_execution.dirty);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(commands.try_recv().is_err());
    actor.dispose().await;
}
