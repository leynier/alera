use super::workflow_integration_tests::fixture::ready_workspace;
use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::WorkflowDecision;

#[tokio::test]
async fn cleanup_preview_requires_a_closed_run_and_preserves_its_exact_receipt() {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let resource = ready_workspace(&dir, &store, &plan, None).await;
    let item = WorkflowCleanupItem {
        identity: resource.identity,
        git: crate::git::WorkflowCleanupGitPreview {
            head_sha: plan.integration_sha,
            dirty: false,
            operation_in_progress: false,
            locked: false,
            changed_paths: vec![],
            paths_truncated: false,
        },
        remove_branch: false,
    };
    let id = uuid::Uuid::new_v4().to_string();
    assert!(store
        .publish_workflow_cleanup_preview(&id, &plan.run_id, vec![item.clone()])
        .await
        .is_err());
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel-before-cleanup".into(),
            run_id: plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    let first = store
        .publish_workflow_cleanup_preview(&id, &plan.run_id, vec![item.clone()])
        .await
        .unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let replay = reopened
        .publish_workflow_cleanup_preview(&id, &plan.run_id, vec![item.clone()])
        .await
        .unwrap();
    assert_eq!(first.digest, replay.digest);
    assert_eq!(first.expires_at, replay.expires_at);
    assert_eq!(
        reopened.workflow_cleanup_preview(&id).await.unwrap().digest,
        first.digest
    );
    let mut changed = item.clone();
    changed.remove_branch = true;
    assert!(store
        .publish_workflow_cleanup_preview(&id, &plan.run_id, vec![changed])
        .await
        .is_err());
    assert!(store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &plan.run_id,
            vec![item.clone(), item.clone()]
        )
        .await
        .is_err());
    let mut foreign = item;
    foreign.identity.workspace.instance_id = uuid::Uuid::new_v4().to_string();
    assert!(store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &plan.run_id,
            vec![foreign]
        )
        .await
        .is_err());
    assert!(store
        .workflow_workspace(&first.items[0].identity.workspace.id)
        .await
        .is_ok());
}
