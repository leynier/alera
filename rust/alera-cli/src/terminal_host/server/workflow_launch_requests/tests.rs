use std::collections::HashMap;

use alera_core::runtime::{
    LaunchWorkflowTask, OrchestrationDispatchStatus, OrchestrationTaskStatus,
    WorkflowWorkspacePhase,
};
use sha2::{Digest, Sha256};

use super::*;
use crate::managed_workspace::workflow::{launch, tests::fixture::Fixture};
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};

mod completion;
mod final_preflight;
mod recovery;
mod reset;

async fn prepared(fixture: &Fixture) -> (LaunchWorkflowTask, PreparedLaunch) {
    fixture.integration().await;
    let workspace = fixture.task("fix").await;
    let input = LaunchWorkflowTask {
        request_id: "launch".into(),
        run_id: fixture.plan.run_id.clone(),
        revision: 1,
        task_id: fixture.task_id("fix").await,
        workspace_id: workspace.identity.workspace.id,
    };
    let result = launch::prepare(&fixture.store, &fixture.runtime, input.clone())
        .await
        .unwrap();
    (input, result)
}

#[tokio::test]
async fn workflow_launch_claim_restore_and_restart_never_duplicate_a_worker() {
    let fixture = Fixture::with_command("", "echo workflow-launch-test").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    let dir = tempfile::tempdir().unwrap();
    let (client, _responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(client))]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut events) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    let frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    let started = actor
        .spawn_workflow_launch(&record, &token, frozen)
        .await
        .unwrap();
    drop(locks);
    assert_eq!(started.status, WorkflowLaunchStatus::Started);
    let instance = actor.sessions[&record.terminal_handle].instance_id();
    assert_eq!(
        actor.sessions[&record.terminal_handle].workspace_id,
        input.workspace_id
    );
    assert!(matches!(
        launch::prepare(&fixture.store, &fixture.runtime, input.clone())
            .await
            .unwrap(),
        PreparedLaunch::Replay(_)
    ));
    assert!(launch::claim_and_validate(&fixture.store, &record)
        .await
        .is_err());
    actor.reconcile_spawn_on_create_tabs().await;
    assert_eq!(
        actor.sessions[&record.terminal_handle].instance_id(),
        instance
    );
    let close_error = actor
        .try_start_deferred_request(1, 1, "tab.remove", &json!({"id": record.terminal_handle}))
        .await
        .unwrap_err();
    assert!(close_error.wire_message().contains("reviewed cleanup"));
    assert!(fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .is_some());
    assert!(actor.sessions[&record.terminal_handle].running());
    let restart = json!({"sessionId":record.terminal_handle,"workspaceId":input.workspace_id,
        "tabId":record.terminal_handle,"workingDirectory":fixture.store.workflow_workspace(&input.workspace_id).await.unwrap().identity.workspace.path});
    assert!(actor.restart_terminal(1, &restart).await.is_err());
    assert!(actor.sessions[&record.terminal_handle].running());
    // Run the real startup callback against a harmless echo command, never a model.
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);
    let mut startup = false;
    let mut echoed = false;
    while let Ok(Some(event)) = tokio::time::timeout_at(deadline, events.recv()).await {
        startup |= matches!(
            event,
            crate::terminal_host::server::ServerCommand::TerminalStartupInput { .. }
        );
        actor.handle(event).await;
        echoed =
            String::from_utf8_lossy(&actor.sessions[&record.terminal_handle].buffer.to_bytes())
                .matches("workflow-launch-test")
                .count()
                >= 2;
        if startup && echoed {
            break;
        }
    }
    assert!(
        startup && echoed,
        "the harmless command must execute, not just create a PTY"
    );
    let dispatch = fixture
        .store
        .accept_orchestration_dispatch(
            &record.dispatch_id,
            &record.terminal_handle,
            &hex::encode(Sha256::digest(token.as_bytes())),
        )
        .await
        .unwrap();
    let context = actor
        .workflow_worker_context(&dispatch)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(context["ownerWorkspaceId"], "owner");
    assert_eq!(context["executionWorkspaceId"], input.workspace_id);
    assert!(context["workerInstructions"]
        .as_str()
        .unwrap()
        .contains("Commit the task changes"));
    assert!(actor
        .remove_terminal_session_tab(&record.terminal_handle)
        .await
        .unwrap());
    assert!(actor.sessions.is_empty());
    let attached = actor
        .attach_workflow_terminal(
            1,
            &record.terminal_handle,
            &input.workspace_id,
            &record.terminal_handle,
        )
        .await
        .unwrap();
    assert!(attached.is_some());
    assert!(!actor.sessions[&record.terminal_handle].running());
    let retained = fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .unwrap();
    actor
        .ensure_spawn_on_create_terminal(&retained)
        .await
        .unwrap();
    assert!(!actor.sessions[&record.terminal_handle].running());
    assert!(actor
        .require_workflow_spawn_permit(
            "foreign",
            &input.workspace_id,
            &record.terminal_handle,
            None
        )
        .await
        .is_err());
    assert!(actor
        .require_workflow_spawn_permit(
            &record.terminal_handle,
            &input.workspace_id,
            "foreign",
            None
        )
        .await
        .is_err());
    let attempt = fixture
        .store
        .workflow_workspace(&input.workspace_id)
        .await
        .unwrap();
    assert_eq!(attempt.phase, WorkflowWorkspacePhase::Attention);
    let retry = fixture
        .request(Some("fix"), Some(&input.workspace_id))
        .await
        .unwrap();
    assert_ne!(retry.identity.workspace.id, input.workspace_id);
    assert_eq!(retry.identity.attempt, 2);
}

#[tokio::test]
async fn workflow_launch_restart_before_spawn_retains_attention_and_requires_fresh_attempt() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh { record, locks, .. } = prepared else {
        panic!("fresh launch required")
    };
    drop(locks);
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    actor.reconcile_workflow_launches().await;
    let record = fixture.store.workflow_launch(&record.id).await.unwrap();
    assert_eq!(record.status, WorkflowLaunchStatus::Attention);
    assert!(actor.sessions.is_empty());
    assert!(matches!(
        launch::prepare(&fixture.store, &fixture.runtime, input.clone())
            .await
            .unwrap(),
        PreparedLaunch::Replay(_)
    ));
    assert!(fixture
        .store
        .claim_workflow_launch(&record.id)
        .await
        .is_err());
    let retry = fixture
        .request(Some("fix"), Some(&input.workspace_id))
        .await
        .unwrap();
    assert_eq!(retry.identity.attempt, 2);
}

#[tokio::test]
async fn workflow_launch_restart_settles_an_escalated_active_attempt() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
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
    drop(locks);
    fixture
        .store
        .workflow_launch_attention(&record.id, "Needs human review")
        .await
        .unwrap();

    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    actor.reconcile_workflow_launches().await;

    assert_eq!(
        fixture
            .store
            .workflow_workspace(&input.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
    );
    assert_eq!(
        fixture
            .store
            .orchestration_dispatch_by_id(&record.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::StartupFailed
    );
    assert_eq!(
        fixture
            .store
            .orchestration_task_by_id(&input.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Pending
    );
    let retry = fixture
        .request(Some("fix"), Some(&input.workspace_id))
        .await
        .unwrap();
    assert_eq!(retry.identity.attempt, 2);
}

#[tokio::test]
async fn workflow_launch_native_preflight_preserves_dirty_and_busy_resources() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let attempt = fixture.task("fix").await;
    let input = LaunchWorkflowTask {
        request_id: "launch".into(),
        run_id: fixture.plan.run_id.clone(),
        revision: 1,
        task_id: fixture.task_id("fix").await,
        workspace_id: attempt.identity.workspace.id,
    };
    let sentinel =
        std::path::Path::new(&integration.identity.workspace.path).join("uncommitted.txt");
    std::fs::write(&sentinel, "keep me").unwrap();
    assert!(
        launch::prepare(&fixture.store, &fixture.runtime, input.clone())
            .await
            .is_err()
    );
    assert_eq!(std::fs::read_to_string(&sentinel).unwrap(), "keep me");
    assert!(fixture
        .store
        .workflow_launch_for_request(&input)
        .await
        .unwrap()
        .is_none());

    std::fs::remove_file(&sentinel).unwrap();
    let tracked = std::path::Path::new(&attempt.identity.workspace.path).join("shared.txt");
    std::fs::write(&tracked, "preexisting tracked change").unwrap();
    let error = launch::prepare(&fixture.store, &fixture.runtime, input.clone())
        .await
        .err()
        .unwrap();
    assert!(error
        .to_string()
        .contains("workflow attempt has uncommitted changes"));
    assert_eq!(
        std::fs::read_to_string(&tracked).unwrap(),
        "preexisting tracked change"
    );
    assert!(fixture
        .store
        .workflow_launch_for_request(&input)
        .await
        .unwrap()
        .is_none());

    std::fs::write(&tracked, "initial").unwrap();
    let untracked =
        std::path::Path::new(&attempt.identity.workspace.path).join("preexisting-untracked.txt");
    std::fs::write(&untracked, "preexisting untracked change").unwrap();
    let error = launch::prepare(&fixture.store, &fixture.runtime, input.clone())
        .await
        .err()
        .unwrap();
    assert!(error
        .to_string()
        .contains("workflow attempt has uncommitted changes"));
    assert_eq!(
        std::fs::read_to_string(&untracked).unwrap(),
        "preexisting untracked change"
    );
    assert!(fixture
        .store
        .workflow_launch_for_request(&input)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn workflow_launch_acceptance_timeout_retains_the_attempt_without_relaunching() {
    let fixture = Fixture::with_command("", "echo workflow-timeout-test").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    actor
        .spawn_workflow_launch(&record, &token, frozen)
        .await
        .unwrap();
    drop(locks);
    sqlx::query(
        "UPDATE orchestrationDispatchContexts SET dispatched_at = '2020-01-01 00:00:00' WHERE id = ?",
    )
    .bind(&record.dispatch_id)
    .execute(fixture.store.pool())
    .await
    .unwrap();
    assert!(fixture
        .store
        .expire_unaccepted_orchestration_dispatches("2021-01-01 00:00:00")
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        fixture
            .store
            .orchestration_dispatch_by_id(&record.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::AwaitingAcceptance
    );
    actor
        .handle_workflow_launch_acceptance_timeout(&record.id)
        .await;
    assert!(actor.sessions.is_empty());
    let record = fixture.store.workflow_launch(&record.id).await.unwrap();
    assert_eq!(record.status, WorkflowLaunchStatus::Attention);
    assert!(record.error.unwrap().contains("startup deadline"));
    assert!(fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .is_some());
    actor.reconcile_spawn_on_create_tabs().await;
    assert!(actor.sessions.is_empty());
    assert!(matches!(
        launch::prepare(&fixture.store, &fixture.runtime, input)
            .await
            .unwrap(),
        PreparedLaunch::Replay(_)
    ));
}
