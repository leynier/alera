use super::workflow_integration_tests::fixture::ready_workspace;
use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::WorkflowDecision;

#[tokio::test]
async fn cleanup_claims_are_exclusive_and_retire_each_resource_independently() {
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
            request_id: "cancel-for-cleanup-claims".into(),
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
    let first = store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &plan.run_id,
            items.clone(),
        )
        .await
        .unwrap();
    let second = store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &plan.run_id,
            items.clone(),
        )
        .await
        .unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let (a, b) = tokio::join!(
        store.claim_workflow_cleanup(&first.id, &first.digest),
        reopened.claim_workflow_cleanup(&second.id, &second.digest),
    );
    assert_ne!(a.is_ok(), b.is_ok());
    let winner = a.or(b).unwrap().preview;
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM workflowCleanupResources")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 2);
    store
        .mark_workflow_cleanup_attention(&winner.id, &winner.digest, "busy process")
        .await
        .unwrap();
    reopened
        .mark_workflow_cleanup_attention(&winner.id, &winner.digest, "later error")
        .await
        .unwrap();
    let attention = reopened.workflow_cleanup_status(&winner.id).await.unwrap();
    assert_eq!(attention.state, WorkflowCleanupState::Attention);
    assert_eq!(attention.error.as_deref(), Some("busy process"));
    assert!(store
        .claim_workflow_cleanup(&winner.id, &winner.digest)
        .await
        .is_err());
    assert!(store
        .resume_workflow_cleanup(&winner.id, "changed")
        .await
        .is_err());
    store
        .resume_workflow_cleanup(&winner.id, &winner.digest)
        .await
        .unwrap();
    let resumed = reopened.workflow_cleanup_status(&winner.id).await.unwrap();
    assert_eq!(resumed.state, WorkflowCleanupState::Applying);
    assert!(resumed.error.is_none());
    let one = &items[0].identity.workspace.id;
    sqlx::query("CREATE TRIGGER testRejectCleanupWorkspaceDelete BEFORE DELETE ON workspaces BEGIN SELECT RAISE(ABORT, 'injected retirement failure'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .record_workflow_cleanup_retirement(&winner.id, &winner.digest, one)
        .await
        .is_err());
    let retired: bool =
        sqlx::query_scalar("SELECT retired FROM workflowCleanupResources WHERE workspace_id=?")
            .bind(one)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert!(!retired);
    assert!(store.find_workspace(one).await.unwrap().is_some());
    sqlx::query("DROP TRIGGER testRejectCleanupWorkspaceDelete")
        .execute(store.pool())
        .await
        .unwrap();
    store
        .record_workflow_cleanup_retirement(&winner.id, &winner.digest, one)
        .await
        .unwrap();
    let state: String = sqlx::query_scalar("SELECT state FROM workflowCleanup WHERE id=?")
        .bind(&winner.id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(state, "applying");
    let replay = reopened
        .claim_workflow_cleanup(&winner.id, &winner.digest)
        .await
        .unwrap();
    assert_eq!(replay.retired_workspace_ids, vec![one.clone()]);
    let two = &items[1].identity.workspace.id;
    reopened
        .record_workflow_cleanup_retirement(&winner.id, &winner.digest, two)
        .await
        .unwrap();
    let state: String = sqlx::query_scalar("SELECT state FROM workflowCleanup WHERE id=?")
        .bind(&winner.id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(state, "retired");
    store
        .mark_workflow_cleanup_attention(&winner.id, &winner.digest, "stale failure")
        .await
        .unwrap();
    let status = reopened.workflow_cleanup_status(&winner.id).await.unwrap();
    assert_eq!(status.state, WorkflowCleanupState::Retired);
    assert!(status.error.is_none());
    assert_eq!(status.retired_workspace_ids.len(), 2);
    // The ledger never erases historical workspace identities.
    assert!(store.workflow_workspace(one).await.is_ok());
    assert!(store.workflow_workspace(two).await.is_ok());
    assert!(store.find_workspace(one).await.unwrap().is_none());
    assert!(store.find_workspace(two).await.unwrap().is_none());
    assert!(store
        .upsert_workspace(items[0].identity.workspace.clone())
        .await
        .is_err());
}

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
    let workspace_id = &first.items[0].identity.workspace.id;
    assert!(store
        .record_workflow_cleanup_retirement(&id, &first.digest, workspace_id)
        .await
        .is_err());
    assert!(store.claim_workflow_cleanup(&id, "stale").await.is_err());
    let overlapping = store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &plan.run_id,
            first.items.clone(),
        )
        .await
        .unwrap();
    let mut dirty = first.items.clone();
    dirty[0].git.dirty = true;
    let dirty = store
        .publish_workflow_cleanup_preview(&uuid::Uuid::new_v4().to_string(), &plan.run_id, dirty)
        .await
        .unwrap();
    assert!(store
        .claim_workflow_cleanup(&dirty.id, &dirty.digest)
        .await
        .is_err());
    let claimed = store
        .claim_workflow_cleanup(&id, &first.digest)
        .await
        .unwrap();
    assert!(claimed.retired_workspace_ids.is_empty());
    assert!(reopened
        .claim_workflow_cleanup(&overlapping.id, &overlapping.digest)
        .await
        .is_err());
    // Expiry fences a new confirmation, not recovery of an existing claim.
    sqlx::query("UPDATE workflowCleanup SET expires_at=0")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(reopened
        .claim_workflow_cleanup(&overlapping.id, &overlapping.digest)
        .await
        .unwrap_err()
        .to_string()
        .contains("expired"));
    let replay = reopened
        .claim_workflow_cleanup(&id, &first.digest)
        .await
        .unwrap();
    assert_eq!(replay.preview.digest, first.digest);
    assert!(reopened
        .record_workflow_cleanup_retirement(&id, &first.digest, "foreign-workspace")
        .await
        .is_err());
    reopened
        .record_workflow_cleanup_retirement(&id, &first.digest, workspace_id)
        .await
        .unwrap();
    reopened
        .record_workflow_cleanup_retirement(&id, &first.digest, workspace_id)
        .await
        .unwrap();
    let retired = store
        .claim_workflow_cleanup(&id, &first.digest)
        .await
        .unwrap();
    assert_eq!(retired.retired_workspace_ids, vec![workspace_id.clone()]);
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT state FROM workflowCleanup WHERE id=?")
            .bind(&id)
            .fetch_one(store.pool())
            .await
            .unwrap(),
        "retired"
    );
}
