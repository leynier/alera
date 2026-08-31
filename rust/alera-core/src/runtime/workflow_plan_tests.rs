use std::collections::BTreeMap;

use chrono::Utc;
use serde_json::json;

use super::*;
use crate::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};

pub(super) async fn fixture(
    feature: bool,
) -> (tempfile::TempDir, RuntimeStore, PrepareWorkflowPlan) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let source = dir.path().join("source");
    let repo = git2::Repository::init(&source).unwrap();
    let tree = repo.index().unwrap().write_tree().unwrap();
    let signature = git2::Signature::now("test", "test@example.com").unwrap();
    let sha = repo
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            "initial",
            &repo.find_tree(tree).unwrap(),
            &[],
        )
        .unwrap();
    sqlx::query("INSERT INTO projects(id,name,repoPath,createdAt,updatedAt,kind)
        VALUES('project','Project',?,'2026-08-30T00:00:00Z','2026-08-30T00:00:00Z','gitRepository')")
        .bind(source.to_str().unwrap()).execute(store.pool()).await.unwrap();
    sqlx::query("INSERT INTO workspaces(id,instanceId,hostId,projectId,name,path,createdAt,updatedAt,kind,status)
        VALUES('workspace','instance','local','project','Workspace',?,'2026-08-30T00:00:00Z','2026-08-30T00:00:00Z','main','active')")
        .bind(source.to_str().unwrap()).execute(store.pool()).await.unwrap();
    let profile = AgentProfile {
        id: "profile".into(),
        name: "Agent".into(),
        sort_order: 0,
        agent_type: "codex".into(),
        command: "codex".into(),
        launch_mode: AgentProfileLaunchMode::Command,
        managed_config: None,
        custom_prompt: "User instructions".into(),
        description: String::new(),
        quota_group: None,
        revision: 0,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };
    store.upsert_agent_profile(profile, None).await.unwrap();
    let recipe = &builtin_workflow_recipes()[usize::from(feature)];
    let request = PrepareWorkflowPlan {
        request_id: uuid::Uuid::new_v4().to_string(),
        workspace_id: "workspace".into(),
        run_id: None,
        expected_revision: None,
        proposal: WorkflowPlanProposal {
            objective: "Deliver the scoped change".into(),
            source_sha: sha.to_string(),
            recipe_source: WorkflowRecipeSource::BuiltIn {
                id: recipe.id.clone(),
            },
            expected_recipe_digest: recipe.content_digest().unwrap(),
            coordinator_profile_id: "profile".into(),
            role_profiles: recipe
                .roles
                .iter()
                .map(|role| (role.id.clone(), "profile".into()))
                .collect::<BTreeMap<_, _>>(),
            max_concurrent: 4,
            tasks: recipe
                .stages
                .iter()
                .map(|stage| WorkflowPlanTask {
                    id: stage.id.clone(),
                    title: stage.name.clone(),
                    spec: stage.purpose.clone(),
                    stage_id: stage.id.clone(),
                    role_id: stage.roles[0].clone(),
                    depends_on: Vec::new(),
                    inputs: json!({"objective":"Deliver the scoped change"}),
                    corrects_task_id: None,
                })
                .collect(),
        },
    };
    (dir, store, request)
}

pub(super) fn valid_profile(profile: &AgentProfile) -> anyhow::Result<()> {
    anyhow::ensure!(profile.agent_type == "codex", "unsupported profile");
    Ok(())
}

pub(super) async fn decision(
    dir: &std::path::Path,
    store: &RuntimeStore,
    plan: &WorkflowPlanRevision,
    choice: WorkflowDecision,
) -> WorkflowDecisionReceipt {
    let challenge = store
        .workflow_approval_challenge(&plan.run_id, plan.revision, "plan", "desktop")
        .await
        .unwrap();
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: choice,
        reason: "Reviewed the exact plan".into(),
    };
    let key = DesktopWorkflowCredential::load_or_create(dir).unwrap();
    let proof = key.sign(&statement).unwrap();
    let verified = key.verify(statement.clone(), &proof).unwrap();
    let receipt = store.decide_workflow(verified, "desktop").await.unwrap();
    // Response loss and reconnect return the same receipt, never duplicate tasks.
    let replay = store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "reconnected")
        .await
        .unwrap();
    assert_eq!(receipt.decision_id, replay.decision_id);
    receipt
}

#[tokio::test]
async fn workflow_plan_preparation_is_durable_idempotent_and_non_executable() {
    let (dir, store, request) = fixture(false).await;
    let (first, second) = tokio::join!(
        store.prepare_workflow_plan(request.clone(), valid_profile),
        store.prepare_workflow_plan(request.clone(), valid_profile),
    );
    let first = first.unwrap();
    let second = second.unwrap();
    assert_eq!(first.run_id, second.run_id);
    assert_eq!(first.plan.digest, second.plan.digest);
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
    assert_eq!(first.plan.tasks[1].task.depends_on, vec!["fix"]);
    let mut reused = request.clone();
    reused.proposal.objective = "Another request".into();
    assert!(store
        .prepare_workflow_plan(reused, valid_profile)
        .await
        .is_err());
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .prepare_workflow_plan(request, valid_profile)
            .await
            .unwrap()
            .run_id,
        first.run_id
    );
    let board = store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert!(serde_json::to_string(&board).unwrap().contains("attention"));
}

#[tokio::test]
async fn workflow_plan_validates_before_persisting_any_run_or_tasks() {
    let (_dir, store, request) = fixture(false).await;
    let mut invalids = Vec::new();
    let mut bad = request.clone();
    bad.proposal.tasks.pop();
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.tasks[0].depends_on.push("verify".into());
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.tasks[0].depends_on.push("missing".into());
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.tasks[0].inputs = json!({});
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.role_profiles.clear();
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.coordinator_profile_id = "missing".into();
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.source_sha = "main".into();
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.expected_recipe_digest = "old".into();
    invalids.push(bad);
    let mut bad = request.clone();
    bad.proposal.max_concurrent = 0;
    invalids.push(bad);
    for invalid in invalids {
        assert!(store
            .prepare_workflow_plan(invalid, valid_profile)
            .await
            .is_err());
    }
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationCoordinatorRuns")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}

#[tokio::test]
async fn workflow_plan_approval_freezes_snapshots_and_blocks_every_legacy_dispatch_frontier() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    assert!(store
        .resolve_orchestration_execution_policy(&plan.run_id, true)
        .await
        .is_err());
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let tasks = store
        .list_scoped_orchestration_tasks(None, Some(&plan.run_id), None)
        .await
        .unwrap();
    assert_eq!(tasks.len(), 2);
    for task in &tasks {
        assert_eq!(task.status, OrchestrationTaskStatus::Pending);
        assert!(task.role_contract.is_some());
        assert!(store
            .ensure_legacy_workflow_dispatch_allowed(&task.id)
            .await
            .is_err());
        sqlx::query("UPDATE orchestrationTasks SET status = 'ready' WHERE id = ?")
            .bind(&task.id)
            .execute(store.pool())
            .await
            .unwrap();
        assert!(store
            .create_scoped_orchestration_dispatch(
                &task.id,
                "worker",
                None,
                "workspace",
                "",
                None,
                "return-immediately",
                "keep-open",
            )
            .await
            .is_err());
        assert!(
            sqlx::query("UPDATE orchestrationTasks SET run_id = NULL WHERE id = ?")
                .bind(&task.id)
                .execute(store.pool())
                .await
                .is_err()
        );
        assert!(store
            .set_orchestration_task_stage(&task.id, Some("different"))
            .await
            .is_err());
    }
    let mut changed = store.find_agent_profile("profile").await.unwrap().unwrap();
    let revision = changed.revision;
    changed.command = "codex --different".into();
    store
        .upsert_agent_profile(changed, Some(revision))
        .await
        .unwrap();
    let saved = store
        .workflow_plan_revision(&plan.run_id, None)
        .await
        .unwrap();
    assert_eq!(saved.plan.profiles["profile"].command, "codex");
    assert!(store
        .workflow_approval_challenge(&plan.run_id, 1, "plan", "desktop")
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_approval_rejects_wrong_connection_expiry_and_stale_sha() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let challenge = store
        .workflow_approval_challenge(&plan.run_id, 1, "plan", "desktop")
        .await
        .unwrap();
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let proof = key.sign(&statement).unwrap();
    assert!(store
        .decide_workflow(key.verify(statement.clone(), &proof).unwrap(), "cli")
        .await
        .is_err());
    sqlx::query("UPDATE workflowRuns SET integration_sha = 'changed' WHERE run_id = ?")
        .bind(&plan.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .decide_workflow(key.verify(statement.clone(), &proof).unwrap(), "desktop")
        .await
        .is_err());
    sqlx::query("UPDATE workflowRuns SET integration_sha = ? WHERE run_id = ?")
        .bind(&plan.integration_sha)
        .bind(&plan.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("UPDATE workflowApprovalChallenges SET expires_at = 0")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_request_changes_creates_traceable_revision_and_requires_new_proposal() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request.clone(), valid_profile)
        .await
        .unwrap();
    let receipt = decision(dir.path(), &store, &plan, WorkflowDecision::RequestChanges).await;
    assert_eq!(receipt.current_revision, 2);
    let correction = store
        .workflow_plan_revision(&plan.run_id, None)
        .await
        .unwrap();
    assert_eq!(correction.previous_revision, Some(1));
    assert!(correction.change_reason.is_some());
    assert_eq!(correction.status, "changesRequested");
    assert!(store
        .workflow_approval_challenge(&plan.run_id, 2, "plan", "desktop")
        .await
        .is_err());
    let mut next = request;
    next.request_id = uuid::Uuid::new_v4().to_string();
    next.run_id = Some(plan.run_id.clone());
    next.expected_revision = Some(2);
    next.proposal.objective = "Address the review feedback".into();
    let revised = store
        .prepare_workflow_plan(next.clone(), valid_profile)
        .await
        .unwrap();
    assert_eq!(revised.revision, 3);
    next.request_id = uuid::Uuid::new_v4().to_string();
    assert!(store
        .prepare_workflow_plan(next, valid_profile)
        .await
        .is_err());
    decision(dir.path(), &store, &revised, WorkflowDecision::Reject).await;
    assert_eq!(
        store
            .workflow_plan_revision(&plan.run_id, None)
            .await
            .unwrap()
            .status,
        "rejected"
    );
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}

#[tokio::test]
async fn workflow_human_gates_require_integrated_evidence_and_reset_preserves_catalogs() {
    let (dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    for gate in ["stage:foundation", "stage:product"] {
        assert!(store
            .workflow_approval_challenge(&plan.run_id, 1, gate, "desktop")
            .await
            .is_err());
    }
    let gates: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowStageGates")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(gates, 2);
    store.reset_orchestration_tasks().await.unwrap();
    let runs: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowRuns")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(runs, 0);
    assert_eq!(store.list_agent_profiles().await.unwrap().len(), 1);
}
