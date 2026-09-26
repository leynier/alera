use crate::runtime::workflow_integration_tests::fixture::ready_workspace;
use crate::runtime::workflow_plan_tests::{decision, fixture, valid_profile};
use crate::runtime::*;
use crate::workflow_approval::WorkflowDecision;

#[tokio::test]
async fn cleanup_abandonment_releases_only_unretired_claims_and_fences_old_operations() {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let integration = ready_workspace(&dir, &store, &plan, None).await;
    let task: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id=? AND logical_id='fix'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let task = ready_workspace(&dir, &store, &plan, Some(task)).await;
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel".into(),
            run_id: plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    let items = [integration, task]
        .into_iter()
        .map(|resource| WorkflowCleanupItem {
            identity: resource.identity,
            git: crate::git::WorkflowCleanupGitPreview {
                head_sha: plan.integration_sha.clone(),
                dirty: false,
                operation_in_progress: false,
                locked: false,
                changed_paths: vec![],
                paths_truncated: false,
            },
            remove_branch: false,
        })
        .collect::<Vec<_>>();
    let preview = store
        .publish_workflow_cleanup_preview(&uuid::Uuid::new_v4().to_string(), &plan.run_id, items)
        .await
        .unwrap();
    assert!(store
        .abandon_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .is_err());
    store
        .claim_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .unwrap();
    assert!(store
        .abandon_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .is_err());
    let retired = &preview.items[0].identity.workspace.id;
    let retained = &preview.items[1].identity.workspace.id;
    store
        .record_workflow_cleanup_retirement(&preview.id, &preview.digest, retired)
        .await
        .unwrap();
    store
        .mark_workflow_cleanup_attention(&preview.id, &preview.digest, "HEAD changed")
        .await
        .unwrap();
    store
        .require_retained_cleanup_resource(&preview.id, &preview.digest, retained)
        .await
        .unwrap();
    assert!(store
        .abandon_workflow_cleanup(&preview.id, "stale")
        .await
        .is_err());
    store
        .abandon_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    reopened
        .abandon_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .unwrap();
    let status = reopened.workflow_cleanup_status(&preview.id).await.unwrap();
    assert_eq!(status.state, WorkflowCleanupState::Abandoned);
    assert_eq!(status.error.as_deref(), Some("HEAD changed"));
    assert_eq!(status.retired_workspace_ids, vec![retired.clone()]);
    assert_eq!(
        serde_json::to_value(&status.preview).unwrap(),
        serde_json::to_value(&preview).unwrap()
    );
    assert!(reopened
        .require_workspace_outside_cleanup(retired)
        .await
        .is_err());
    reopened
        .require_workspace_outside_cleanup(retained)
        .await
        .unwrap();
    assert!(reopened
        .claim_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .is_err());
    assert!(reopened
        .resume_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .is_err());
    assert!(reopened
        .record_workflow_cleanup_retirement(&preview.id, &preview.digest, retained)
        .await
        .is_err());
    assert!(reopened
        .record_workflow_cleanup_retirement(&preview.id, &preview.digest, retired)
        .await
        .is_err());
    assert!(reopened
        .require_retained_cleanup_resource(&preview.id, &preview.digest, retained)
        .await
        .is_err());
    let page = reopened
        .workflow_cleanups(&WorkflowCleanupQuery {
            run_id: plan.run_id.clone(),
            before_row: None,
        })
        .await
        .unwrap();
    assert_eq!(page.items[0].state, "abandoned");
    let board = reopened
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert!(!board.items[0].cleanup_attention);
    assert!(!board.items[0].cleanup_applying);
    let fresh = reopened
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &plan.run_id,
            vec![preview.items[1].clone()],
        )
        .await
        .unwrap();
    reopened
        .claim_workflow_cleanup(&fresh.id, &fresh.digest)
        .await
        .unwrap();
    assert!(reopened
        .claim_workflow_cleanup(&preview.id, &preview.digest)
        .await
        .is_err());
}
