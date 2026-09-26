use super::*;

fn advance_head(record: &WorkflowWorkspaceRecord) -> String {
    let repo = git2::Repository::open(&record.identity.workspace.path).unwrap();
    let parent = repo.head().unwrap().peel_to_commit().unwrap();
    let tree = parent.tree().unwrap();
    let signature = git2::Signature::now("Test", "test@example.com").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "advance integration",
        &tree,
        &[&parent],
    )
    .unwrap()
    .to_string()
}

#[tokio::test]
async fn workflow_worktrees_ready_replay_tracks_the_recorded_integration_tip() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let tip = advance_head(&integration);
    sqlx::query("UPDATE workflowRuns SET integration_sha = ? WHERE run_id = ?")
        .bind(&tip)
        .bind(&fixture.plan.run_id)
        .execute(fixture.store.pool())
        .await
        .unwrap();
    let replay = fixture.integration().await;
    assert_eq!(
        replay.identity.workspace.id,
        integration.identity.workspace.id
    );
    let task = fixture.task("fix").await;
    assert_eq!(task.phase, Phase::Ready, "{task:?}");
    assert_eq!(task.identity.base_sha, tip);
}

#[tokio::test]
async fn workflow_worktrees_creation_still_rejects_a_moved_branch() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    advance_head(&integration);
    let resource = &integration.identity;
    assert!(core_git::ensure_workflow_worktree(
        &resource.repo_path,
        &resource.workspace.path,
        &resource.base_sha,
        &resource.workspace.id,
    )
    .is_err());
    let replay = fixture.request(None, None).await.unwrap();
    assert_eq!(replay.phase, Phase::Attention);
    assert!(replay.error.unwrap().contains("expected integration"));
}
