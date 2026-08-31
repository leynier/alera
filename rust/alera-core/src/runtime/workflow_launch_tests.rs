use super::workflow_integration_tests::fixture::ready_workspace;
use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::WorkflowDecision;

async fn prepared() -> (tempfile::TempDir, RuntimeStore, LaunchWorkflowTask) {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    ready_workspace(&dir, &store, &plan, None).await;
    let task: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'fix'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let workspace = ready_workspace(&dir, &store, &plan, Some(task.clone())).await;
    (
        dir,
        store,
        LaunchWorkflowTask {
            request_id: "launch".into(),
            run_id: plan.run_id,
            revision: 1,
            task_id: task,
            workspace_id: workspace.identity.workspace.id,
        },
    )
}

#[tokio::test]
async fn workflow_launch_replay_is_bound_and_never_claims_a_second_worker() {
    let (dir, store, request) = prepared().await;
    let hash = "a".repeat(64);
    let (one, two) = tokio::join!(
        store.reserve_workflow_launch(&request, &hash),
        store.reserve_workflow_launch(&request, &hash)
    );
    let (one, created_one) = one.unwrap();
    let (two, created_two) = two.unwrap();
    assert_ne!(created_one, created_two);
    assert_eq!(one.dispatch_id, two.dispatch_id);
    assert_eq!(one.terminal_handle, two.terminal_handle);
    let frozen = store.claim_workflow_launch(&one.id).await.unwrap();
    let page = store
        .workflow_launch_summaries(&WorkflowLaunchQuery {
            run_id: request.run_id.clone(),
            after_row: None,
        })
        .await
        .unwrap();
    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].id, one.id);
    assert!(page.next_after_row.is_none());
    assert!(!serde_json::to_string(&page)
        .unwrap()
        .contains("customPrompt"));
    assert_eq!(frozen.workspace.workspace.id, request.workspace_id);
    assert!(store.claim_workflow_launch(&one.id).await.is_err());
    store.mark_workflow_launch_started(&one.id).await.unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let replay = reopened
        .reserve_workflow_launch(&request, &"b".repeat(64))
        .await
        .unwrap();
    assert!(!replay.1);
    assert_eq!(replay.0.id, one.id);
    assert!(reopened.claim_workflow_launch(&one.id).await.is_err());
    let mut changed = request.clone();
    changed.revision += 1;
    assert!(store
        .reserve_workflow_launch(&changed, &hash)
        .await
        .unwrap_err()
        .to_string()
        .contains("different contents"));
    changed = request;
    changed.request_id = "different launch".into();
    assert!(store
        .reserve_workflow_launch(&changed, &hash)
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_launch_uses_approved_profile_and_preserves_owner_execution_split() {
    let (_dir, store, request) = prepared().await;
    let approved = store.validate_workflow_launch(&request).await.unwrap();
    let mut changed = store.find_agent_profile("profile").await.unwrap().unwrap();
    let revision = changed.revision;
    changed.name = "Changed Agent".into();
    changed.quota_group = Some("changed".into());
    changed.command = "changed-command".into();
    changed.custom_prompt = "Changed instructions".into();
    store
        .upsert_agent_profile(changed, Some(revision))
        .await
        .unwrap();
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    assert!(store
        .accept_orchestration_dispatch(
            &launch.dispatch_id,
            &launch.terminal_handle,
            &"a".repeat(64)
        )
        .await
        .is_err());
    let claimed = store.claim_workflow_launch(&launch.id).await.unwrap();
    assert_eq!(claimed.profile.command, approved.profile.command);
    assert_eq!(
        claimed.profile.custom_prompt,
        approved.profile.custom_prompt
    );
    let task = store
        .orchestration_task_by_id(&request.task_id)
        .await
        .unwrap()
        .unwrap();
    let dispatch = store
        .orchestration_dispatch_by_id(&launch.dispatch_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.workspace_id, "workspace");
    assert_eq!(dispatch.workspace_id, request.workspace_id);
    assert_eq!(dispatch.agent_profile.as_deref(), Some("Agent"));
    assert_eq!(dispatch.agent_quota_group.as_deref(), Some("workflow"));
    let inspection = store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: request.run_id.clone(),
            task_id: request.task_id.clone(),
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(inspection.profile.as_deref(), Some("Agent"));
    assert!(inspection
        .history
        .iter()
        .any(|entry| { entry.kind == "attempt" && entry.summary.as_deref() == Some("Agent") }));
    assert!(sqlx::query(
        "UPDATE orchestrationDispatchContexts SET workspace_id = 'workspace' WHERE id = ?"
    )
    .bind(&launch.dispatch_id)
    .execute(store.pool())
    .await
    .is_err());
    assert!(
        sqlx::query("UPDATE workflowLaunches SET terminal_handle = 'other' WHERE id = ?")
            .bind(&launch.id)
            .execute(store.pool())
            .await
            .is_err()
    );
    assert!(sqlx::query("DELETE FROM workflowLaunches WHERE id = ?")
        .bind(&launch.id)
        .execute(store.pool())
        .await
        .is_err());
    let receipt = serde_json::to_string(&launch).unwrap();
    assert!(!receipt.contains(&approved.profile.custom_prompt));
    assert!(!receipt.contains("contextHash"));
}

#[tokio::test]
async fn workflow_prepared_attempts_project_the_execution_workspace_before_launch() {
    let (_dir, store, request) = prepared().await;
    let workspace = store
        .workflow_workspace(&request.workspace_id)
        .await
        .unwrap();
    let inspect = || async {
        store
            .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
                run_id: request.run_id.clone(),
                task_id: request.task_id.clone(),
                cursor: None,
                limit: None,
            })
            .await
            .unwrap()
            .workflow
            .unwrap()
    };

    let ready = inspect().await;
    assert_eq!(ready.state, "ready");
    assert_eq!(ready.execution_workspace_id, request.workspace_id);
    assert_eq!(
        ready.worktree.as_deref(),
        Some(workspace.identity.workspace.path.as_str())
    );
    assert_eq!(ready.branch, workspace.identity.workspace.branch);
    assert_eq!(
        ready.base_sha.as_deref(),
        Some(workspace.identity.base_sha.as_str())
    );
    assert!(ready.error.is_none());

    store
        .transition_workflow_workspace(
            &request.workspace_id,
            request.revision,
            WorkflowWorkspacePhase::Ready,
            WorkflowWorkspacePhase::Attention,
            None,
            Some("Project setup failed"),
        )
        .await
        .unwrap();
    let attention = inspect().await;
    assert_eq!(attention.state, "attention");
    assert_eq!(attention.execution_workspace_id, request.workspace_id);
    assert_eq!(attention.error.as_deref(), Some("Project setup failed"));
}

#[tokio::test]
async fn workflow_terminal_tabs_require_reviewed_cleanup() {
    let (_dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&launch.id).await.unwrap();
    let now = chrono::Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: launch.terminal_handle.clone(),
            workspace_id: request.workspace_id,
            kind: "terminal".into(),
            title: "Workflow Worker".into(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({
                "terminalSessionId": launch.terminal_handle,
            }),
        })
        .await
        .unwrap();

    let error = store
        .remove_workspace_tab(&launch.terminal_handle)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("reviewed cleanup"));
    assert!(store
        .find_workspace_tab(&launch.terminal_handle)
        .await
        .unwrap()
        .is_some());

    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "ordinary-tab".into(),
            workspace_id: "owner".into(),
            kind: "terminal".into(),
            title: "Ordinary".into(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({"terminalSessionId": "ordinary-tab"}),
        })
        .await
        .unwrap();
    store.remove_workspace_tab("ordinary-tab").await.unwrap();
    assert!(store
        .find_workspace_tab("ordinary-tab")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn workflow_launch_projects_active_attempts_without_masking_a_ready_result() {
    let (_dir, store, request) = prepared().await;
    let frozen = store.validate_workflow_launch(&request).await.unwrap();
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    for expected in ["reserved", "starting", "started"] {
        let inspection = store
            .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
                run_id: request.run_id.clone(),
                task_id: request.task_id.clone(),
                cursor: None,
                limit: None,
            })
            .await
            .unwrap();
        let workflow = inspection.workflow.unwrap();
        assert_eq!(workflow.state, expected);
        assert_eq!(workflow.execution_workspace_id, request.workspace_id);
        assert_eq!(
            workflow.worktree.as_deref(),
            Some(frozen.workspace.workspace.path.as_str())
        );
        assert_eq!(
            workflow.branch.as_deref(),
            frozen.workspace.workspace.branch.as_deref()
        );
        assert_eq!(workflow.base_sha.as_deref(), Some(launch.base_sha.as_str()));
        match expected {
            "reserved" => {
                store.claim_workflow_launch(&launch.id).await.unwrap();
            }
            "starting" => {
                store
                    .mark_workflow_launch_started(&launch.id)
                    .await
                    .unwrap();
            }
            _ => {}
        }
    }
    sqlx::query("UPDATE orchestrationTasks SET status = 'completed', result = ? WHERE id = ?")
        .bind(r#"{"summary":"Done","completionKind":"success","artifacts":[],"validation":[]}"#)
        .bind(&request.task_id)
        .execute(store.pool())
        .await
        .unwrap();
    let inspection = store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: request.run_id,
            task_id: request.task_id,
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(inspection.workflow.unwrap().state, "result_ready");
}

#[tokio::test]
async fn workflow_launch_recovery_page_excludes_terminal_history() {
    let (_dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    let page = store.workflow_launch_recovery_page(0).await.unwrap();
    assert_eq!(page.len(), 1);
    let sequence = page[0].0;
    assert!(store
        .workflow_launch_recovery_page(sequence)
        .await
        .unwrap()
        .is_empty());
    store.claim_workflow_launch(&launch.id).await.unwrap();
    assert_eq!(
        store.workflow_launch_recovery_page(0).await.unwrap()[0]
            .1
            .status,
        WorkflowLaunchStatus::Starting
    );
    store
        .mark_workflow_launch_started(&launch.id)
        .await
        .unwrap();
    assert_eq!(
        store.workflow_launch_recovery_page(0).await.unwrap()[0]
            .1
            .status,
        WorkflowLaunchStatus::Started
    );
    sqlx::query("UPDATE orchestrationDispatchContexts SET status = 'completed' WHERE id = ?")
        .bind(&launch.dispatch_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .workflow_launch_recovery_page(0)
        .await
        .unwrap()
        .is_empty());
    store
        .workflow_launch_attention(&launch.id, "Already settled")
        .await
        .unwrap();
    assert!(store
        .workflow_launch_recovery_page(0)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn workflow_launch_refuses_stale_approval_and_keeps_uncertain_attempt_reserved() {
    let (_dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    sqlx::query("UPDATE workflowRuns SET status = 'cancelled' WHERE run_id = ?")
        .bind(&request.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store.claim_workflow_launch(&launch.id).await.is_err());
    let attention = store
        .workflow_launch_attention(&launch.id, "Host restarted before launch confirmation")
        .await
        .unwrap();
    assert_eq!(attention.status, WorkflowLaunchStatus::Attention);
    assert!(store.claim_workflow_launch(&launch.id).await.is_err());
    assert_eq!(
        store
            .workflow_workspace(&request.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Ready
    );
    assert!(
        !store
            .reserve_workflow_launch(&request, &"a".repeat(64))
            .await
            .unwrap()
            .1
    );
}

#[tokio::test]
async fn workflow_launch_refuses_foreign_attempt_and_unintegrated_dependencies() {
    let (_dir, store, request) = prepared().await;
    let mut changed = request.clone();
    changed.workspace_id = "workspace".into();
    assert!(store.validate_workflow_launch(&changed).await.is_err());
    changed = request.clone();
    changed.task_id = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'verify'",
    )
    .bind(&request.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert!(store
        .validate_workflow_launch(&changed)
        .await
        .unwrap_err()
        .to_string()
        .contains("integrated"));
    assert!(store
        .reserve_workflow_launch(&request, "not-a-hash")
        .await
        .is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowLaunches")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}
