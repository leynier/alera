use super::*;

#[tokio::test]
async fn workflow_worktrees_receipts_survive_disabled_and_unset_reflog_policy() {
    for disabled in [true, false] {
        let fixture = Fixture::new("").await;
        let repo = git2::Repository::open(&fixture.source).unwrap();
        if disabled {
            repo.config()
                .unwrap()
                .set_bool("core.logAllRefUpdates", false)
                .unwrap();
        } else {
            let _ = repo.config().unwrap().remove("core.logAllRefUpdates");
        }
        let config_before = std::fs::read(repo.path().join("config")).unwrap();
        let integration = fixture.integration().await;
        let task = fixture.task("fix").await;
        assert_eq!(task.phase, Phase::Ready, "{task:?}");
        for record in [&integration, &task] {
            core_git::verify_workflow_worktree(
                &record.identity.repo_path,
                &record.identity.workspace.path,
                &record.identity.base_sha,
                &record.identity.workspace.id,
            )
            .unwrap();
        }
        assert_eq!(
            fixture.integration().await.identity.workspace.id,
            integration.identity.workspace.id
        );
        assert_eq!(
            std::fs::read(repo.path().join("config")).unwrap(),
            config_before
        );
    }
}

#[tokio::test]
async fn workflow_worktrees_setup_head_change_keeps_command_diagnostics() {
    let fixture = Fixture::new("git checkout --detach HEAD && echo setup-finished").await;
    fixture.integration().await;
    let attempt = fixture.task("fix").await;
    assert_eq!(attempt.phase, Phase::Attention);
    let report = attempt.setup_report.unwrap();
    let step = report.steps.last().unwrap();
    assert_eq!(step.exit_code, Some(0), "{step:?}");
    assert!(step
        .stdout_tail
        .as_ref()
        .unwrap()
        .contains("setup-finished"));
    assert!(attempt.error.is_some());
}

#[tokio::test]
async fn workflow_worktrees_post_setup_cancellation_or_missing_metadata_keeps_report() {
    for cancel in [false, true] {
        let fixture = Fixture::new("").await;
        fixture.integration().await;
        let reserved = fixture.reserve("fix").await;
        let id = &reserved.identity.workspace.id;
        fixture
            .store
            .transition_workflow_workspace(id, 1, Phase::Reserved, Phase::Creating, None, None)
            .await
            .unwrap();
        core_git::ensure_workflow_worktree(
            &reserved.identity.repo_path,
            &reserved.identity.workspace.path,
            &reserved.identity.base_sha,
            id,
        )
        .unwrap();
        fixture
            .store
            .transition_workflow_workspace(id, 1, Phase::Creating, Phase::Created, None, None)
            .await
            .unwrap();
        let running = fixture
            .store
            .transition_workflow_workspace(id, 1, Phase::Created, Phase::SetupRunning, None, None)
            .await
            .unwrap();
        if cancel {
            sqlx::query("UPDATE workflowRuns SET status = 'cancelled' WHERE run_id = ?")
                .bind(&fixture.plan.run_id)
                .execute(fixture.store.pool())
                .await
                .unwrap();
        } else {
            fixture.store.remove_workspace(id, true).await.unwrap();
        }
        let report = WorktreeSetupReport {
            steps: vec![WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Command,
                label: "Setup".into(),
                succeeded: true,
                exit_code: Some(0),
                message: None,
                stdout_tail: Some("completed before validation".into()),
                stderr_tail: None,
            }],
        };
        let finished = finish_setup(&fixture.store, running, 1, report.clone())
            .await
            .unwrap();
        assert_eq!(finished.phase, Phase::Attention);
        assert_eq!(finished.setup_report, Some(report));
        assert!(finished.error.is_some());
    }
}
