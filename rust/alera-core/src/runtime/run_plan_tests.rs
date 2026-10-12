use std::collections::BTreeMap;

use chrono::Utc;
use serde_json::json;

use super::*;

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
        quota_group: Some("workflow".into()),
        show_in_new_tab_menu: true,
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

/// A person's decision on a run gate, as the tests make it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::runtime) enum WorkflowDecision {
    Approve,
    Reject,
    RequestChanges,
}

impl WorkflowDecision {
    pub(in crate::runtime) fn as_str(self) -> &'static str {
        match self {
            WorkflowDecision::Approve => "approve",
            WorkflowDecision::Reject => "reject",
            WorkflowDecision::RequestChanges => "requestChanges",
        }
    }
}

pub(in crate::runtime) fn desktop() -> RunActor {
    RunActor::new(RunActorKind::Desktop, None)
}

/// The pending, due gate of a run with this kind and scope.
pub(in crate::runtime) async fn pending_gate(
    store: &RuntimeStore,
    run_id: &str,
    kind: RunGateKind,
    scope: Option<&str>,
) -> Option<RunGate> {
    store
        .run_gates(&RunGateFilter {
            run_id: run_id.into(),
            kind: Some(kind),
            status: Some("pending".into()),
            ..RunGateFilter::default()
        })
        .await
        .unwrap()
        .into_iter()
        .find(|gate| gate.due && scope.is_none_or(|scope| gate.scope == scope))
}

pub(in crate::runtime) async fn resolve(
    store: &RuntimeStore,
    gate: &RunGate,
    choice: WorkflowDecision,
) -> anyhow::Result<RunGateResolution> {
    store
        .resolve_run_gate(
            &ResolveRunGate {
                request_id: uuid::Uuid::new_v4().to_string(),
                gate_id: gate.id.clone(),
                decision: choice.as_str().into(),
                reason: Some("Reviewed the exact plan".into()),
                task_ids: None,
                expected_evidence_digest: gate.evidence_digest.clone(),
                caller_terminal: None,
            },
            &desktop(),
        )
        .await
}

/// Resolves the pending plan gate of `plan` and checks that a replay of the
/// same request returns the same receipt.
pub(super) async fn decision(
    _dir: &std::path::Path,
    store: &RuntimeStore,
    plan: &WorkflowPlanRevision,
    choice: WorkflowDecision,
) -> RunGateResolution {
    let gate = pending_gate(store, &plan.run_id, RunGateKind::Plan, None)
        .await
        .expect("a pending plan gate");
    assert_eq!(
        gate.evidence_digest.as_deref(),
        Some(plan.plan.digest.as_str())
    );
    let request = ResolveRunGate {
        request_id: uuid::Uuid::new_v4().to_string(),
        gate_id: gate.id.clone(),
        decision: choice.as_str().into(),
        reason: Some("Reviewed the exact plan".into()),
        task_ids: None,
        expected_evidence_digest: gate.evidence_digest.clone(),
        caller_terminal: None,
    };
    let receipt = store.resolve_run_gate(&request, &desktop()).await.unwrap();
    // Response loss and reconnect return the same receipt, never duplicate tasks.
    let replay = store.resolve_run_gate(&request, &desktop()).await.unwrap();
    assert!(replay.replayed);
    assert_eq!(receipt.gate, replay.gate);
    receipt
}

/// Opens the stage gate that became due and resolves it.
pub(in crate::runtime) async fn stage_decision(
    store: &RuntimeStore,
    run_id: &str,
    stage: &str,
    choice: WorkflowDecision,
) -> anyhow::Result<RunGateResolution> {
    store.open_due_stage_gates(run_id).await?;
    let gate = pending_gate(store, run_id, RunGateKind::Stage, Some(stage))
        .await
        .ok_or_else(|| anyhow::anyhow!("stage {stage} is not due"))?;
    resolve(store, &gate, choice).await
}

pub(super) async fn run_status(store: &RuntimeStore, run_id: &str) -> String {
    sqlx::query_scalar("SELECT status FROM orchestrationCoordinatorRuns WHERE id = ?")
        .bind(run_id)
        .fetch_one(store.pool())
        .await
        .unwrap()
}

#[tokio::test]
async fn preparing_a_plan_creates_one_run_awaiting_approval_with_pending_tasks() {
    let (_dir, store, request) = fixture(false).await;
    let (first, second) = tokio::join!(
        store.prepare_workflow_plan(request.clone(), valid_profile),
        store.prepare_workflow_plan(request.clone(), valid_profile),
    );
    let first = first.unwrap();
    let second = second.unwrap();
    assert_eq!(first.run_id, second.run_id);
    assert_eq!(first.plan.digest, second.plan.digest);
    assert_eq!(run_status(&store, &first.run_id).await, "awaitingApproval");
    let tasks = store
        .list_scoped_orchestration_tasks(None, Some(&first.run_id), None)
        .await
        .unwrap();
    assert_eq!(tasks.len(), 2);
    assert!(tasks
        .iter()
        .all(|task| task.status == OrchestrationTaskStatus::Pending));
    assert_eq!(first.plan.tasks[1].task.depends_on, vec!["fix"]);
    let mut reused = request.clone();
    reused.proposal.objective = "Another request".into();
    assert!(store
        .prepare_workflow_plan(reused, valid_profile)
        .await
        .is_err());
    let board = store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert_eq!(board.counts.attention, 1);
    assert_eq!(board.items[0].pending_gate_kinds, vec!["plan"]);
    assert_eq!(board.items[0].isolation, "isolated");
}

#[tokio::test]
async fn an_invalid_plan_leaves_the_run_planning_without_tasks_or_revisions() {
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
    bad.proposal.max_concurrent = 0;
    invalids.push(bad);
    for (index, mut invalid) in invalids.into_iter().enumerate() {
        invalid.request_id = format!("invalid-{index}");
        assert!(store
            .prepare_workflow_plan(invalid, valid_profile)
            .await
            .is_err());
        sqlx::query("UPDATE orchestrationCoordinatorRuns SET status = 'cancelled', completed_at = datetime('now')")
            .execute(store.pool())
            .await
            .unwrap();
    }
    let mut missing = request.clone();
    missing.proposal.coordinator_profile_id = "missing".into();
    assert!(store
        .prepare_workflow_plan(missing, valid_profile)
        .await
        .is_err());
    for table in ["orchestrationTasks", "runPlanRevisions", "runGates"] {
        let count: i64 =
            sqlx::query_scalar(sqlx::AssertSqlSafe(format!("SELECT COUNT(*) FROM {table}")))
                .fetch_one(store.pool())
                .await
                .unwrap();
        assert_eq!(count, 0, "{table}");
    }
}

#[tokio::test]
async fn an_approved_plan_runs_with_frozen_snapshots_and_no_terminal_dispatch() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let receipt = decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    assert_eq!(receipt.run_status.as_deref(), Some("running"));
    assert_eq!(receipt.gate.actor_kind.as_deref(), Some("desktop"));
    let tasks = store
        .list_scoped_orchestration_tasks(None, Some(&plan.run_id), None)
        .await
        .unwrap();
    assert_eq!(tasks.len(), 2);
    for task in &tasks {
        assert_eq!(task.status, OrchestrationTaskStatus::Pending);
        assert!(task.role_contract.is_some());
        assert!(store
            .ensure_terminal_dispatch_allowed(&task.id)
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
                Some(&plan.run_id),
                "workspace",
                "",
                None,
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
    assert!(pending_gate(&store, &plan.run_id, RunGateKind::Plan, None)
        .await
        .is_none());
}

#[tokio::test]
async fn a_stale_digest_cannot_decide_and_a_finished_gate_cannot_be_decided_again() {
    let (_dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let gate = pending_gate(&store, &plan.run_id, RunGateKind::Plan, None)
        .await
        .unwrap();
    let stale = store
        .resolve_run_gate(
            &ResolveRunGate {
                request_id: "stale".into(),
                gate_id: gate.id.clone(),
                decision: "approve".into(),
                reason: None,
                task_ids: None,
                expected_evidence_digest: Some("0".repeat(64)),
                caller_terminal: None,
            },
            &desktop(),
        )
        .await
        .unwrap_err();
    assert!(stale.to_string().starts_with("gate_stale:"), "{stale}");
    let invalid = store
        .resolve_run_gate(
            &ResolveRunGate {
                request_id: "invalid".into(),
                gate_id: gate.id.clone(),
                decision: "maybe".into(),
                reason: None,
                task_ids: None,
                expected_evidence_digest: None,
                caller_terminal: None,
            },
            &desktop(),
        )
        .await
        .unwrap_err();
    assert!(invalid.to_string().starts_with("gate_invalid_resolution:"));
    resolve(&store, &gate, WorkflowDecision::Approve)
        .await
        .unwrap();
    let again = resolve(&store, &gate, WorkflowDecision::Reject)
        .await
        .unwrap_err();
    assert!(again.to_string().starts_with("gate_not_pending:"));
}

#[tokio::test]
async fn stage_gates_wait_for_their_stage_and_reset_preserves_catalogs() {
    let (dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    for stage in ["foundation", "product"] {
        assert!(
            stage_decision(&store, &plan.run_id, stage, WorkflowDecision::Approve)
                .await
                .is_err()
        );
    }
    let gates: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM runGates WHERE kind = 'stage' AND status = 'pending'
            AND evidence_digest IS NULL",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(gates, 2);
    store.reset_orchestration_tasks().await.unwrap();
    let runs: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationCoordinatorRuns")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(runs, 0);
    assert_eq!(store.list_agent_profiles().await.unwrap().len(), 1);
}

/// A person's `runs.control` command against the run's current sequence.
pub(in crate::runtime) async fn control(
    store: &RuntimeStore,
    run_id: &str,
    action: RunControlAction,
) -> anyhow::Result<RunControlReceipt> {
    let sequence: i64 = sqlx::query_scalar(
        "SELECT control_sequence FROM orchestrationCoordinatorRuns WHERE id = ?",
    )
    .bind(run_id)
    .fetch_one(store.pool())
    .await?;
    store
        .control_run(
            &RunControl {
                request_id: uuid::Uuid::new_v4().to_string(),
                run_id: run_id.into(),
                expected_sequence: sequence,
                action,
                reason: Some("Requested in a test".into()),
                task_ids: None,
            },
            &desktop(),
        )
        .await
}
