use super::*;

#[tokio::test]
async fn workflow_worktrees_reservations_are_idempotent_and_concurrency_is_bounded() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let (first, second) = tokio::join!(fixture.reserve("fix"), fixture.reserve("fix"));
    assert_eq!(first.identity.workspace.id, second.identity.workspace.id);
    fixture.task("other").await;
    assert!(fixture
        .request(Some("spare"), None)
        .await
        .unwrap_err()
        .to_string()
        .contains("concurrency"));
    let request = PrepareWorkflowWorkspace {
        request_id: "idempotent".into(),
        run_id: fixture.plan.run_id.clone(),
        revision: 1,
        task_id: Some(fixture.task_id("fix").await),
        retry_of: None,
    };
    let replay = fixture
        .store
        .reserve_workflow_workspace(&request, first.identity.workspace.clone())
        .await
        .unwrap();
    assert_eq!(replay.identity.workspace.id, first.identity.workspace.id);
    let mut changed = request.clone();
    changed.task_id = Some(fixture.task_id("other").await);
    assert!(fixture
        .store
        .reserve_workflow_workspace(&changed, first.identity.workspace.clone())
        .await
        .is_err());
    let mut foreign = request;
    foreign.request_id = "foreign".into();
    foreign.task_id = Some("another-run-task".into());
    assert!(fixture
        .store
        .reserve_workflow_workspace(&foreign, first.identity.workspace.clone())
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_worktrees_attention_is_aggregated_and_ownership_survives_reset() {
    let fixture = Fixture::new("exit 7").await;
    let integration = fixture.integration().await;
    let before = fixture
        .store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    let first = fixture.task("fix").await;
    let after = fixture
        .store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert!(after.revision > before.revision);
    assert_eq!(after.counts.attention, 1);
    let page = fixture
        .store
        .workflow_workspaces(&WorkflowWorkspaceQuery {
            run_id: fixture.plan.run_id.clone(),
            before_row: None,
            limit: Some(1),
        })
        .await
        .unwrap();
    assert_eq!(
        page.items[0].identity.workspace.id,
        first.identity.workspace.id
    );
    let page = fixture
        .store
        .workflow_workspaces(&WorkflowWorkspaceQuery {
            run_id: fixture.plan.run_id.clone(),
            before_row: page.next_before_row,
            limit: Some(1),
        })
        .await
        .unwrap();
    assert_eq!(
        page.items[0].identity.workspace.id,
        integration.identity.workspace.id
    );
    assert!(page.next_before_row.is_none());
    fixture.store.reset_orchestration_tasks().await.unwrap();
    assert!(fixture
        .store
        .workflow_workspace_owned(&first.identity.workspace.id)
        .await
        .unwrap());
    assert!(Path::new(&first.identity.workspace.path).exists());
    assert!(fixture
        .store
        .workflow_workspace(&first.identity.workspace.id)
        .await
        .is_ok());
    assert!(resume(
        &fixture.store,
        &fixture.runtime,
        &integration.identity.workspace.id,
        1
    )
    .await
    .is_err());
}

#[tokio::test]
async fn workflow_worktrees_cancelled_runs_and_replaced_owners_cannot_create_resources() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let reserved = fixture.reserve("fix").await;
    sqlx::query("UPDATE orchestrationCoordinatorRuns SET status = 'stopped' WHERE id = ?")
        .bind(&fixture.plan.run_id)
        .execute(fixture.store.pool())
        .await
        .unwrap();
    assert!(resume(
        &fixture.store,
        &fixture.runtime,
        &reserved.identity.workspace.id,
        1
    )
    .await
    .is_err());
    recovery::reconcile(&fixture.store, &fixture.runtime)
        .await
        .unwrap();
    assert_eq!(
        fixture
            .store
            .workflow_workspace(&reserved.identity.workspace.id)
            .await
            .unwrap()
            .phase,
        Phase::Attention
    );
    assert!(!Path::new(&reserved.identity.workspace.path).exists());

    let fixture = Fixture::new("").await;
    fixture.integration().await;
    sqlx::query("UPDATE workspaces SET instanceId = 'replacement' WHERE id = 'owner'")
        .execute(fixture.store.pool())
        .await
        .unwrap();
    assert!(fixture.request(Some("fix"), None).await.is_err());
    assert_eq!(
        fixture
            .store
            .workflow_workspaces(&WorkflowWorkspaceQuery {
                run_id: fixture.plan.run_id.clone(),
                before_row: None,
                limit: None,
            })
            .await
            .unwrap()
            .items
            .len(),
        1
    );
}

#[tokio::test]
async fn workflow_worktrees_preserve_occupied_paths_and_refuse_replaced_metadata() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let record = fixture.reserve("fix").await;
    std::fs::create_dir_all(&record.identity.workspace.path).unwrap();
    let path = Path::new(&record.identity.workspace.path).join("unrelated.txt");
    std::fs::write(&path, "unrelated").unwrap();
    assert_eq!(
        resume(
            &fixture.store,
            &fixture.runtime,
            &record.identity.workspace.id,
            1
        )
        .await
        .unwrap()
        .phase,
        Phase::Attention
    );
    assert_eq!(std::fs::read_to_string(path).unwrap(), "unrelated");
    let ready = fixture.task("other").await;
    assert_eq!(ready.phase, Phase::Ready);
    let mut replacement = ready.identity.workspace.clone();
    replacement.instance_id = Uuid::new_v4().to_string();
    assert!(fixture.store.upsert_workspace(replacement).await.is_err());
    fixture
        .store
        .remove_workspace(&ready.identity.workspace.id, true)
        .await
        .unwrap();
    assert_eq!(
        resume(
            &fixture.store,
            &fixture.runtime,
            &ready.identity.workspace.id,
            1
        )
        .await
        .unwrap()
        .phase,
        Phase::Attention
    );
    assert!(Path::new(&ready.identity.workspace.path).exists());
}

#[tokio::test]
async fn workflow_worktrees_refuse_dirty_integration_without_touching_it() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let path = Path::new(&integration.identity.workspace.path).join("shared.txt");
    std::fs::write(&path, "user integration change").unwrap();
    let attempt = fixture.task("fix").await;
    assert_eq!(attempt.phase, Phase::Attention);
    assert!(!Path::new(&attempt.identity.workspace.path).exists());
    assert_eq!(
        std::fs::read_to_string(path).unwrap(),
        "user integration change"
    );
}

#[tokio::test]
async fn workflow_worktrees_recovery_skips_live_setup_and_does_not_repeat_commands() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let record = fixture.reserve("fix").await;
    let id = &record.identity.workspace.id;
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Reserved, Phase::Creating, None, None)
        .await
        .unwrap();
    core_git::ensure_workflow_worktree(
        &record.identity.repo_path,
        &record.identity.workspace.path,
        &record.identity.base_sha,
        id,
    )
    .unwrap();
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Creating, Phase::Created, None, None)
        .await
        .unwrap();
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Created, Phase::SetupRunning, None, None)
        .await
        .unwrap();
    let lock = resource_lock(&fixture.runtime, id).unwrap().unwrap();
    recovery::reconcile(&fixture.store, &fixture.runtime)
        .await
        .unwrap();
    assert_eq!(
        fixture.store.workflow_workspace(id).await.unwrap().phase,
        Phase::SetupRunning
    );
    drop(lock);
    recovery::reconcile(&fixture.store, &fixture.runtime)
        .await
        .unwrap();
    assert_eq!(
        fixture.store.workflow_workspace(id).await.unwrap().phase,
        Phase::Attention
    );
}

#[tokio::test]
async fn workflow_worktrees_recovery_waits_for_the_integration_lock() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let record = fixture.reserve("fix").await;
    let integration_lock = resource_lock(&fixture.runtime, &integration.identity.workspace.id)
        .unwrap()
        .unwrap();

    recovery::reconcile(&fixture.store, &fixture.runtime)
        .await
        .unwrap();
    assert_eq!(
        fixture
            .store
            .workflow_workspace(&record.identity.workspace.id)
            .await
            .unwrap()
            .phase,
        Phase::Reserved
    );

    drop(integration_lock);
    recovery::reconcile(&fixture.store, &fixture.runtime)
        .await
        .unwrap();
    assert_eq!(
        fixture
            .store
            .workflow_workspace(&record.identity.workspace.id)
            .await
            .unwrap()
            .phase,
        Phase::Ready
    );
}
