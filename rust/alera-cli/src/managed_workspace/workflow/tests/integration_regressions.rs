use super::*;

async fn completed(
    fixture: &Fixture,
    logical: &str,
    content: &str,
) -> (IntegrateWorkflowResult, String) {
    let workspace = fixture.task(logical).await;
    assert_eq!(workspace.phase, Phase::Ready);
    let task = fixture.task_id(logical).await;
    let (launch, _) = fixture
        .store
        .reserve_workflow_launch(
            &LaunchWorkflowTask {
                request_id: Uuid::new_v4().to_string(),
                run_id: fixture.plan.run_id.clone(),
                revision: 1,
                task_id: task.clone(),
                workspace_id: workspace.identity.workspace.id.clone(),
            },
            &"a".repeat(64),
        )
        .await
        .unwrap();
    fixture
        .store
        .claim_workflow_launch(&launch.id)
        .await
        .unwrap();
    fixture
        .store
        .mark_workflow_launch_started(&launch.id)
        .await
        .unwrap();
    fixture
        .store
        .accept_orchestration_dispatch(
            &launch.dispatch_id,
            &launch.terminal_handle,
            &"a".repeat(64),
        )
        .await
        .unwrap();
    let repo = git2::Repository::open(&workspace.identity.workspace.path).unwrap();
    std::fs::write(
        Path::new(&workspace.identity.workspace.path).join("shared.txt"),
        content,
    )
    .unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("shared.txt")).unwrap();
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let signature = repo.signature().unwrap();
    let parent = repo.head().unwrap().peel_to_commit().unwrap();
    let sha = repo
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            "test: complete workflow result",
            &tree,
            &[&parent],
        )
        .unwrap()
        .to_string();
    let dispatch = launch.dispatch_id;
    let contract = &fixture
        .plan
        .plan
        .tasks
        .iter()
        .find(|t| t.task.id == logical)
        .unwrap()
        .contract
        .contract;
    let result = json!({"completionKind":"success","summary":"Completed","artifacts":["shared.txt"],
        "filesModified":["shared.txt"], "validation":contract.checklist.iter()
            .map(|c| json!({"id":c.id,"passed":true,"evidence":"focused checks passed"})).collect::<Vec<_>>()});
    fixture
        .store
        .complete_orchestration_dispatch(&dispatch, &launch.terminal_handle, &result.to_string())
        .await
        .unwrap();
    (
        IntegrateWorkflowResult {
            request_id: Uuid::new_v4().to_string(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            task_id: task,
            workspace_id: workspace.identity.workspace.id,
        },
        sha,
    )
}

#[tokio::test]
async fn workflow_integration_service_replays_and_prepares_dependents_at_the_integrated_sha() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let (request, _) = completed(&fixture, "fix", "fixed\n").await;
    let result = integration::integrate(&fixture.store, &fixture.runtime, request.clone())
        .await
        .unwrap();
    assert_eq!(
        result.state,
        WorkflowIntegrationState::Integrated,
        "{result:?}"
    );
    let repeated = integration::integrate(&fixture.store, &fixture.runtime, request)
        .await
        .unwrap();
    assert_eq!(result.request, repeated.request);
    let target = fixture.integration().await;
    assert_eq!(target.phase, Phase::Ready);
    for logical in ["other", "spare"] {
        let (request, _) = completed(&fixture, logical, "fixed\n").await;
        let done = integration::integrate(&fixture.store, &fixture.runtime, request)
            .await
            .unwrap();
        assert_eq!(done.state, WorkflowIntegrationState::Integrated, "{done:?}");
    }
    let dependent = fixture.task("verify").await;
    assert_eq!(dependent.phase, Phase::Ready, "{dependent:?}");
    assert_eq!(
        dependent.identity.base_sha,
        result.receipt.unwrap().integrated_sha
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&dependent.identity.workspace.path).join("shared.txt"))
            .unwrap(),
        "fixed\n"
    );
}

#[tokio::test]
async fn workflow_integration_service_conflict_is_attention_and_preserves_parallel_attempts() {
    let fixture = Fixture::new("").await;
    let target = fixture.integration().await;
    fixture.task("other").await;
    let (first, _) = completed(&fixture, "fix", "first\n").await;
    let first = integration::integrate(&fixture.store, &fixture.runtime, first)
        .await
        .unwrap();
    assert_eq!(
        first.state,
        WorkflowIntegrationState::Integrated,
        "{first:?}"
    );
    let (second, _) = completed(&fixture, "other", "conflict\n").await;
    let result = integration::integrate(&fixture.store, &fixture.runtime, second)
        .await
        .unwrap();
    assert_eq!(
        result.state,
        WorkflowIntegrationState::Conflict,
        "{result:?}"
    );
    assert_eq!(result.conflict_paths, vec!["shared.txt"]);
    assert_eq!(
        std::fs::read_to_string(Path::new(&target.identity.workspace.path).join("shared.txt"))
            .unwrap(),
        "first\n"
    );
    let board = fixture
        .store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert_eq!(board.counts.attention, 1);
    let summaries = fixture
        .store
        .workflow_integration_summaries(&WorkflowIntegrationQuery {
            run_id: fixture.plan.run_id.clone(),
            after_row: None,
        })
        .await
        .unwrap();
    assert_eq!(summaries.items.len(), 2);
    assert!(summaries.next_after_row.is_none());
}

#[tokio::test]
async fn workflow_integration_service_recovers_git_receipt_after_restart_without_reapplying() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let (input, sha) = completed(&fixture, "fix", "fixed\n").await;
    let record = fixture
        .store
        .reserve_workflow_integration(&input, &sha)
        .await
        .unwrap();
    core_git::prepare_workflow_integration(&record.request).unwrap();
    let receipt = core_git::apply_workflow_integration(&record.request).unwrap();
    let reopened = RuntimeStore::open(&fixture.runtime).await.unwrap();
    integration::reconcile(&reopened, &fixture.runtime)
        .await
        .unwrap();
    let done = reopened
        .workflow_integration(&record.request.id)
        .await
        .unwrap();
    assert_eq!(done.state, WorkflowIntegrationState::Integrated, "{done:?}");
    assert_eq!(done.receipt, Some(receipt));
    integration::reconcile(&reopened, &fixture.runtime)
        .await
        .unwrap();
}

#[tokio::test]
async fn workflow_integration_service_skips_live_operation_and_retains_dirty_failure() {
    let fixture = Fixture::new("").await;
    let target = fixture.integration().await;
    let (input, sha) = completed(&fixture, "fix", "fixed\n").await;
    let record = fixture
        .store
        .reserve_workflow_integration(&input, &sha)
        .await
        .unwrap();
    let lock = resource_lock(&fixture.runtime, &target.identity.workspace.id)
        .unwrap()
        .unwrap();
    integration::reconcile(&fixture.store, &fixture.runtime)
        .await
        .unwrap();
    assert_eq!(
        fixture
            .store
            .workflow_integration(&record.request.id)
            .await
            .unwrap()
            .state,
        WorkflowIntegrationState::Pending
    );
    assert!(
        integration::integrate(&fixture.store, &fixture.runtime, input.clone())
            .await
            .is_err()
    );
    drop(lock);
    std::fs::write(
        Path::new(&target.identity.workspace.path).join("shared.txt"),
        "user edit",
    )
    .unwrap();
    let result = integration::integrate(&fixture.store, &fixture.runtime, input)
        .await
        .unwrap();
    assert_eq!(result.state, WorkflowIntegrationState::Attention);
    assert!(result.error.is_some());
    assert_eq!(
        std::fs::read_to_string(Path::new(&target.identity.workspace.path).join("shared.txt"))
            .unwrap(),
        "user edit"
    );
}
