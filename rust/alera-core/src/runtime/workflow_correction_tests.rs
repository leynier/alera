use super::workflow_plan_tests::{fixture, valid_profile};
use super::*;

#[tokio::test]
async fn workflow_correction_freezes_prior_selection_and_replays_after_submission() {
    let (dir, store, proposal) = fixture(false).await;
    let tasks = proposal.proposal.tasks.clone();
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    let mut profile = store.list_agent_profiles().await.unwrap().remove(0);
    let revision = profile.revision;
    profile.command = "changed after review".into();
    store
        .upsert_agent_profile(profile, Some(revision))
        .await
        .unwrap();
    let request = CreateWorkflowCorrection {
        request_id: "correction".into(),
        run_id: plan.run_id.clone(),
        revision: 1,
        plan_digest: plan.plan.digest.clone(),
        reason: "Add regression coverage".into(),
    };
    let (one, two) = tokio::join!(
        store.create_workflow_correction(request.clone(), valid_profile),
        store.create_workflow_correction(request.clone(), valid_profile)
    );
    let one = one.unwrap();
    assert_eq!(
        serde_json::to_value(&one).unwrap(),
        serde_json::to_value(two.unwrap()).unwrap()
    );
    assert_eq!(one.selection.profiles, plan.plan.profiles);
    assert_eq!(one.selection.recipe, plan.plan.recipe);
    assert_eq!(one.selection.source_workspace, plan.plan.source_workspace);
    assert_eq!(one.selection.source_sha, plan.plan.source_sha);
    assert!(one.selection.tasks.is_empty());
    assert!(one.request.proposal.tasks.is_empty());
    assert_eq!(one.correction.unwrap().reason, "Add regression coverage");
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
    let submitted = store
        .submit_workflow_proposal(&request.request_id, tasks)
        .await
        .unwrap();
    assert_eq!(submitted.revision, 2);
    assert_eq!(submitted.status, "prepared");
    assert_eq!(
        submitted.change_reason.as_deref(),
        Some("Add regression coverage")
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .create_workflow_correction(request.clone(), valid_profile)
            .await
            .unwrap()
            .id,
        request.request_id
    );
    let mut changed = request;
    changed.reason = "Different correction".into();
    assert!(reopened
        .create_workflow_correction(changed, valid_profile)
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_correction_refuses_stale_or_cancelled_runs_without_creating_a_draft() {
    let (_dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    let mut request = CreateWorkflowCorrection {
        request_id: "correction".into(),
        run_id: plan.run_id.clone(),
        revision: 2,
        plan_digest: plan.plan.digest.clone(),
        reason: "Fix the issue".into(),
    };
    assert!(store
        .create_workflow_correction(request.clone(), valid_profile)
        .await
        .is_err());
    request.revision = 1;
    request.plan_digest = "f".repeat(64);
    assert!(store
        .create_workflow_correction(request.clone(), valid_profile)
        .await
        .is_err());
    request.plan_digest = plan.plan.digest;
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel".into(),
            run_id: plan.run_id,
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    assert!(store
        .create_workflow_correction(request, valid_profile)
        .await
        .is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowProposalDrafts")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}
