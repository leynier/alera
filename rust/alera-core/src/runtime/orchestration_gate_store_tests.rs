use super::{
    GateFilter, NewOrchestrationTask, NewRunPlan, OrchestrationCoordinatorStatus,
    OrchestrationGateStatus, OrchestrationTaskStatus, ResolveRunGate, RunActor, RunActorKind,
    RunGate, RunGateKind, RunPlanInput, RunPlanProposed, RunPlanStageInput, RuntimeStore,
    RUN_GATE_OPTIONS,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    seed_profile(&store).await;
    (dir, store)
}

async fn seed_profile(store: &RuntimeStore) {
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES ('policy-profile', 'Codex Sol', 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .execute(store.pool())
    .await
    .unwrap();
}

fn plan(stall_policy: &str) -> RunPlanInput {
    RunPlanInput {
        stages: vec![RunPlanStageInput {
            id: "impl".into(),
            title: None,
            profile: Some("Codex Sol".into()),
            fallbacks: Vec::new(),
            gate: false,
        }],
        stall_policy: Some(stall_policy.into()),
        ..RunPlanInput::default()
    }
}

async fn propose(store: &RuntimeStore, run_id: &str, stall_policy: &str) -> RunPlanProposed {
    store
        .propose_run_plan(run_id, plan(stall_policy), &RunActor::runtime())
        .await
        .unwrap()
}

async fn approval_run(store: &RuntimeStore) -> super::OrchestrationCoordinatorRun {
    store
        .create_planned_orchestration_coordinator_run(
            "audit",
            Some("coord"),
            2000,
            "ws",
            4,
            NewRunPlan {
                approval_required: true,
                ..NewRunPlan::default()
            },
        )
        .await
        .unwrap()
}

async fn resolve(
    store: &RuntimeStore,
    gate_id: &str,
    decision: &str,
    reason: Option<&str>,
) -> anyhow::Result<RunGate> {
    let digest = store
        .run_gate(gate_id)
        .await?
        .and_then(|gate| gate.evidence_digest);
    store
        .resolve_run_gate(
            &ResolveRunGate {
                request_id: uuid::Uuid::new_v4().to_string(),
                gate_id: gate_id.into(),
                decision: decision.into(),
                reason: reason.map(str::to_string),
                task_ids: None,
                expected_evidence_digest: digest,
                caller_terminal: None,
            },
            &RunActor::new(RunActorKind::Cli, None),
        )
        .await
        .map(|receipt| receipt.gate)
}

async fn task(store: &RuntimeStore, run_id: Option<&str>) -> String {
    store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "implement".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: Some("coord".to_string()),
            run_id: run_id.map(str::to_string),
            workspace_id: "ws".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap()
        .id
}

async fn run(store: &RuntimeStore, id: &str) -> super::OrchestrationCoordinatorRun {
    store
        .orchestration_coordinator_run_by_id(id)
        .await
        .unwrap()
        .unwrap()
}

#[tokio::test]
async fn a_new_run_starts_running_with_the_default_stall_policy() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();

    assert_eq!(run.status, OrchestrationCoordinatorStatus::Running);
    assert_eq!(run.execution_policy, None);
    assert!(!run.approval_required);
    assert_eq!(run.stall_policy, "ask");
    assert_eq!(run.isolation, "shared");
    assert!(!store.run_has_pending_plan_gate(&run.id).await.unwrap());
}

#[tokio::test]
async fn a_run_that_requires_approval_plans_then_waits_behind_a_plan_gate() {
    let (_dir, store) = store().await;
    let run = approval_run(&store).await;
    assert_eq!(run.status, OrchestrationCoordinatorStatus::Planning);
    assert!(run.holds_workspace());
    assert!(!store.run_has_pending_plan_gate(&run.id).await.unwrap());

    let proposed = propose(&store, &run.id, "wait").await;
    assert_eq!(proposed.status, "awaitingApproval");
    assert_eq!(proposed.revision, 1);
    assert!(store.run_has_pending_plan_gate(&run.id).await.unwrap());
    let gates = store.list_run_gates(&run.id).await.unwrap();
    assert_eq!(gates.len(), 1);
    assert_eq!(gates[0].kind, RunGateKind::Plan);
    assert_eq!(gates[0].options, RUN_GATE_OPTIONS);
    assert!(gates[0].task_id.is_empty());
    let stored = self::run(&store, &proposed.run_id).await;
    assert_eq!(stored.stall_policy, "wait");
    assert_eq!(stored.plan_revision, Some(1));
    assert!(stored
        .execution_policy
        .as_deref()
        .is_some_and(|policy| policy.contains("Codex Sol")));
}

#[tokio::test]
async fn approving_the_plan_gate_starts_the_run() {
    let (_dir, store) = store().await;
    let created = approval_run(&store).await;
    let proposed = propose(&store, &created.id, "ask").await;

    let resolved = resolve(
        &store,
        proposed.plan_gate_id.as_deref().unwrap(),
        "approve",
        None,
    )
    .await
    .unwrap();

    assert_eq!(resolved.status, OrchestrationGateStatus::Resolved);
    assert_eq!(resolved.resolution.as_deref(), Some("approve"));
    assert_eq!(resolved.actor_kind.as_deref(), Some("cli"));
    assert!(!store.run_has_pending_plan_gate(&created.id).await.unwrap());
    assert!(store.run_has_approved_plan_gate(&created.id).await.unwrap());
    assert_eq!(
        run(&store, &created.id).await.status,
        OrchestrationCoordinatorStatus::Running
    );
    let kinds: Vec<String> = store
        .run_events(&created.id, 50)
        .await
        .unwrap()
        .into_iter()
        .map(|event| event.kind)
        .collect();
    assert_eq!(
        kinds,
        [
            "created",
            "planProposed",
            "gateOpened",
            "gateResolved",
            "planApproved"
        ]
    );
}

#[tokio::test]
async fn rejecting_the_plan_cancels_the_run_with_the_reason() {
    let (_dir, store) = store().await;
    let created = approval_run(&store).await;
    let proposed = propose(&store, &created.id, "ask").await;

    resolve(
        &store,
        proposed.plan_gate_id.as_deref().unwrap(),
        "reject",
        Some("wrong scope"),
    )
    .await
    .unwrap();

    let run = run(&store, &created.id).await;
    assert_eq!(run.status, OrchestrationCoordinatorStatus::Cancelled);
    assert!(run.completed_at.is_some());
    assert_eq!(run.stop_reason.as_deref(), Some("wrong scope"));
    assert!(!run.holds_workspace());
}

#[tokio::test]
async fn a_gate_with_options_only_accepts_one_of_them() {
    let (_dir, store) = store().await;
    let created = approval_run(&store).await;
    let proposed = propose(&store, &created.id, "ask").await;
    let gate_id = proposed.plan_gate_id.unwrap();

    let error = resolve(&store, &gate_id, "Approve", None)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.starts_with("gate_invalid_resolution: "), "{error}");
    assert!(store.run_has_pending_plan_gate(&created.id).await.unwrap());

    let task_id = task(&store, None).await;
    let options = ["yes".to_string(), "no".to_string()];
    let decision = store
        .create_orchestration_gate(&task_id, "Ship it?", &options)
        .await
        .unwrap();
    assert!(resolve(&store, &decision.id, "maybe", None).await.is_err());
    resolve(&store, &decision.id, "yes", None).await.unwrap();
    let error = resolve(&store, &decision.id, "no", None)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.starts_with("gate_not_pending: "), "{error}");
}

#[tokio::test]
async fn a_decision_gate_without_options_takes_free_text_and_frees_its_task() {
    let (_dir, store) = store().await;
    let task_id = task(&store, None).await;
    let gate = store
        .create_orchestration_gate(&task_id, "Which path?", &[])
        .await
        .unwrap();
    assert_eq!(
        store
            .orchestration_task_by_id(&task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Blocked
    );

    resolve(&store, &gate.id, "/auth/callback/github", None)
        .await
        .unwrap();

    assert_eq!(
        store
            .orchestration_task_by_id(&task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Ready
    );
}

#[tokio::test]
async fn a_run_gate_is_opened_once_per_run_and_kind() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();

    let first = store
        .create_run_gate(&run.id, RunGateKind::Stage, "Foundation done?")
        .await
        .unwrap();
    let second = store
        .create_run_gate(&run.id, RunGateKind::Stage, "Foundation done?")
        .await
        .unwrap();

    assert_eq!(first.id, second.id);
    assert_eq!(first.options, RUN_GATE_OPTIONS);
    assert!(store
        .create_run_gate(&run.id, RunGateKind::Decision, "nope")
        .await
        .is_err());
    assert!(store
        .create_run_gate("run_missing", RunGateKind::Plan, "nope")
        .await
        .is_err());
}

#[tokio::test]
async fn gates_list_by_run_task_kind_and_status() {
    let (_dir, store) = store().await;
    let created = approval_run(&store).await;
    propose(&store, &created.id, "ask").await;
    let gate = resolve(
        &store,
        &store.list_run_gates(&created.id).await.unwrap()[0].id,
        "approve",
        None,
    )
    .await
    .unwrap();
    assert_eq!(gate.kind, RunGateKind::Plan);
    let task_id = task(&store, Some(&created.id)).await;
    store
        .create_orchestration_gate(&task_id, "Which path?", &[])
        .await
        .unwrap();

    let by_run = store
        .list_gates(&GateFilter {
            run_id: Some(created.id.clone()),
            ..GateFilter::default()
        })
        .await
        .unwrap();
    assert_eq!(by_run.len(), 2);
    let plans = store
        .list_gates(&GateFilter {
            run_id: Some(created.id.clone()),
            kind: Some(RunGateKind::Plan),
            status: Some(OrchestrationGateStatus::Resolved),
            ..GateFilter::default()
        })
        .await
        .unwrap();
    assert_eq!(plans.len(), 1);
    let by_task = store
        .list_gates(&GateFilter {
            task_id: Some(task_id.clone()),
            ..GateFilter::default()
        })
        .await
        .unwrap();
    assert_eq!(by_task.len(), 1);
    assert_eq!(by_task[0].kind, RunGateKind::Decision);
    // Plan gates are run-scoped and stay out of the task gate list.
    assert_eq!(
        store
            .list_orchestration_gates(None, None)
            .await
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn proposing_again_supersedes_the_gate_until_one_is_approved() {
    let (_dir, store) = store().await;
    let created = approval_run(&store).await;
    propose(&store, &created.id, "wait").await;
    let second = propose(&store, &created.id, "wait").await;
    assert_eq!(second.revision, 2);
    assert_eq!(second.status, "awaitingApproval");
    let gates = store.list_run_gates(&created.id).await.unwrap();
    assert_eq!(gates.len(), 2);
    assert_eq!(gates[0].status, OrchestrationGateStatus::Invalidated);
    assert_eq!(gates[1].status, OrchestrationGateStatus::Pending);

    resolve(&store, &gates[1].id, "approve", None)
        .await
        .unwrap();
    let third = propose(&store, &created.id, "ask").await;
    assert!(
        third.plan_gate_id.is_none(),
        "an approved shared run keeps running on a revised plan"
    );
    let stored = run(&store, &created.id).await;
    assert_eq!(stored.status, OrchestrationCoordinatorStatus::Running);
    assert_eq!(stored.stall_policy, "ask");
}

#[tokio::test]
async fn a_plan_without_required_approval_applies_at_once() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();

    let proposed = propose(&store, &created.id, "auto-failover").await;

    assert!(proposed.plan_gate_id.is_none());
    let stored = run(&store, &created.id).await;
    assert_eq!(stored.status, OrchestrationCoordinatorStatus::Running);
    assert_eq!(stored.stall_policy, "auto-failover");
    assert!(store.list_run_gates(&created.id).await.unwrap().is_empty());
}

#[tokio::test]
async fn proposing_for_a_finished_run_is_rejected() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();
    store
        .finish_orchestration_coordinator_run(
            &created.id,
            OrchestrationCoordinatorStatus::Completed,
        )
        .await
        .unwrap();

    let error = store
        .propose_run_plan(&created.id, plan("ask"), &RunActor::runtime())
        .await
        .unwrap_err();
    assert!(
        error.to_string().starts_with("run_not_planning:"),
        "{error}"
    );
}

#[tokio::test]
async fn a_task_can_be_bound_to_a_stage() {
    let (_dir, store) = store().await;
    let task_id = task(&store, None).await;

    store
        .set_orchestration_task_stage(&task_id, Some("impl"))
        .await
        .unwrap();
    let stored = store.orchestration_task_by_id(&task_id).await.unwrap();
    assert_eq!(stored.unwrap().stage_id.as_deref(), Some("impl"));

    assert!(store
        .set_orchestration_task_stage("task_missing", Some("impl"))
        .await
        .is_err());
}

#[tokio::test]
async fn a_digest_gate_needs_the_digest_and_a_person_outside_the_run() {
    let (_dir, store) = store().await;
    let created = approval_run(&store).await;
    let proposed = propose(&store, &created.id, "ask").await;
    let gate_id = proposed.plan_gate_id.unwrap();
    let digest = store
        .run_gate(&gate_id)
        .await
        .unwrap()
        .unwrap()
        .evidence_digest;
    let request = |digest: Option<String>, caller: Option<&str>| ResolveRunGate {
        request_id: uuid::Uuid::new_v4().to_string(),
        gate_id: gate_id.clone(),
        decision: "approve".into(),
        reason: None,
        task_ids: None,
        expected_evidence_digest: digest,
        caller_terminal: caller.map(str::to_string),
    };
    let cli = RunActor::new(RunActorKind::Cli, None);

    let missing = store
        .resolve_run_gate(&request(None, None), &cli)
        .await
        .unwrap_err();
    assert!(missing.to_string().starts_with("gate_stale:"), "{missing}");

    let own = store
        .resolve_run_gate(&request(digest.clone(), Some("coord")), &cli)
        .await
        .unwrap_err();
    assert!(own.to_string().starts_with("gate_not_resolvable:"), "{own}");

    let outsider = store
        .resolve_run_gate(&request(digest, Some("term-person")), &cli)
        .await
        .unwrap();
    assert_eq!(outsider.gate.status, OrchestrationGateStatus::Resolved);
}
