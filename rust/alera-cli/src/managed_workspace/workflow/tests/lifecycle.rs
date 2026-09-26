use super::integration_regressions::completed;
use super::*;

// Exercise the durable scheduler with real Git worktrees and signed desktop
// decisions. Only the worker's model response is simulated.
#[tokio::test]
async fn feature_delivery_lifecycle_requires_review_integration_and_both_human_gates() {
    let mut fixture = Fixture::with_recipe("", "codex", true).await;
    let run = fixture.plan.run_id.clone();
    assert!(fixture.request(None, None).await.is_err());
    assert!(matches!(
        fixture
            .store
            .workflow_execution_step(&run, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    fixture.approve("plan").await;
    assert!(matches!(
        fixture
            .store
            .workflow_execution_step(&run, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    let start = ControlWorkflowExecution {
        request_id: "lifecycle-start".into(),
        run_id: run.clone(),
        revision: 1,
        expected_sequence: 0,
        action: WorkflowExecutionAction::Start,
    };
    let state = fixture
        .store
        .control_workflow_execution(&start)
        .await
        .unwrap();
    assert_eq!(state.status, "running");
    assert_eq!(
        fixture
            .store
            .control_workflow_execution(&start)
            .await
            .unwrap()
            .sequence,
        state.sequence
    );
    assert!(
        matches!(fixture.store.workflow_execution_step(&run, 1).await.unwrap(),
        WorkflowExecutionStep::PrepareWorkspace(ref request) if request.task_id.is_none())
    );
    std::fs::write(fixture.source.join("shared.txt"), "uncommitted owner edit").unwrap();
    let target = fixture.integration().await;
    let mut integrated_sha = fixture.plan.integration_sha.clone();
    let mut attempts = Vec::new();
    for (logical, next, gate) in [
        (
            "foundation",
            Some("implementation"),
            Some("stage:foundation"),
        ),
        ("implementation", Some("product"), None),
        ("product", None, Some("stage:product")),
    ] {
        let task_id = fixture.task_id(logical).await;
        assert!(
            matches!(fixture.store.workflow_execution_step(&run, 1).await.unwrap(),
            WorkflowExecutionStep::PrepareWorkspace(ref request) if request.task_id.as_ref() == Some(&task_id))
        );
        let attempt = fixture.task(logical).await;
        assert_eq!(attempt.identity.base_sha, integrated_sha);
        assert!(
            matches!(fixture.store.workflow_execution_step(&run, 1).await.unwrap(),
            WorkflowExecutionStep::LaunchTask(ref request) if request.task_id == task_id)
        );
        let (request, _) = completed(&fixture, logical, &format!("{logical}\n")).await;
        assert!(
            matches!(fixture.store.workflow_execution_step(&run, 1).await.unwrap(),
            WorkflowExecutionStep::IntegrateResult(ref request) if request.task_id == task_id)
        );
        if let Some(next) = next {
            assert!(fixture.request(Some(next), None).await.is_err());
        }
        if let Some(gate) = gate {
            assert!(fixture
                .store
                .workflow_approval_challenge(&run, 1, gate, "desktop")
                .await
                .is_err());
        }
        let result = integration::integrate(&fixture.store, &fixture.runtime, request.clone())
            .await
            .unwrap();
        assert_eq!(result.state, WorkflowIntegrationState::Integrated);
        integrated_sha = result.receipt.as_ref().unwrap().integrated_sha.clone();
        // Reopen persistence between phases and replay the same receipt without
        // generating another squash commit or duplicating a task workspace.
        fixture.store = RuntimeStore::open(&fixture.runtime).await.unwrap();
        let replay = integration::integrate(&fixture.store, &fixture.runtime, request)
            .await
            .unwrap();
        assert_eq!(replay.receipt, result.receipt);
        if let Some(gate) = gate {
            assert!(matches!(
                fixture
                    .store
                    .workflow_execution_step(&run, 1)
                    .await
                    .unwrap(),
                WorkflowExecutionStep::Waiting
            ));
            assert!(fixture
                .store
                .complete_workflow_execution(&run, 1, state.sequence)
                .await
                .is_err());
            if let Some(next) = next {
                assert!(fixture.request(Some(next), None).await.is_err());
            }
            fixture.approve(gate).await;
        }
        attempts.push(attempt);
    }
    assert!(matches!(
        fixture
            .store
            .workflow_execution_step(&run, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Complete
    ));
    assert!(fixture
        .store
        .complete_workflow_execution(&run, 1, state.sequence)
        .await
        .unwrap());
    assert!(!fixture
        .store
        .complete_workflow_execution(&run, 1, state.sequence)
        .await
        .unwrap());
    let board = fixture
        .store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert_eq!(board.items[0].bucket, OrchestrationBoardBucket::History);
    assert_eq!(
        fixture
            .store
            .workflow_execution(&run)
            .await
            .unwrap()
            .unwrap()
            .status,
        "completed"
    );
    assert_eq!(
        std::fs::read_to_string(fixture.source.join("shared.txt")).unwrap(),
        "uncommitted owner edit"
    );
    let repo = git2::Repository::open(&target.identity.workspace.path).unwrap();
    assert_eq!(
        repo.head()
            .unwrap()
            .peel_to_commit()
            .unwrap()
            .id()
            .to_string(),
        integrated_sha
    );
    for attempt in attempts {
        assert!(Path::new(&attempt.identity.workspace.path).exists());
        assert!(repo
            .find_branch(
                attempt.identity.workspace.branch.as_deref().unwrap(),
                git2::BranchType::Local
            )
            .is_ok());
    }
}
