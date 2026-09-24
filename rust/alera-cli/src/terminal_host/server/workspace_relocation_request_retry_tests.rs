use super::*;

#[tokio::test]
async fn prepare_hand_on_rejects_workflow_owned_worktree_before_relocation() {
    let mut fixture = Fixture::new().await;
    let source = fixture.child.clone();
    let mut original = source.clone();
    original.id = "retained-workflow-id".into();
    let identity = alera_core::runtime::WorkflowWorkspaceIdentity {
        workspace: original,
        repo_path: fixture.main_path.clone(),
        owner_workspace_id: "main".into(),
        run_id: "run".into(),
        revision: 1,
        task_id: None,
        attempt: 0,
        base_sha: alera_core::git::checkout_commit(&source.path).unwrap(),
    };
    let before_branch = alera_core::git::current_branch(&source.path).unwrap();
    let before_worktrees = alera_core::git::list_worktrees(&fixture.main_path)
        .unwrap()
        .len();
    sqlx::query(
        "INSERT INTO workflowWorkspaces
         (id, run_id, revision, task_id, attempt, path, identity, phase)
         VALUES (?, 'run', 1, NULL, 0, ?, ?, 'ready')",
    )
    .bind(&identity.workspace.id)
    .bind(&source.path)
    .bind(serde_json::to_string(&identity).unwrap())
    .execute(fixture.actor.runtime_store.pool())
    .await
    .unwrap();
    assert!(!fixture
        .actor
        .runtime_store
        .workflow_workspace_owned(&source.id)
        .await
        .unwrap());

    let error = match fixture.prepare_hand_on(true).await {
        Ok(_) => panic!("workflow-owned worktree should not relocate"),
        Err(error) => error,
    };
    assert!(error.to_string().contains("Workflow-owned"));
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_workspace(&source.id)
            .await
            .unwrap(),
        Some(source.clone())
    );
    assert!(Path::new(&source.path).exists());
    assert!(Path::new(&source.path).join("README.md").exists());
    assert_eq!(
        alera_core::git::current_branch(&source.path).unwrap(),
        before_branch
    );
    assert_eq!(
        alera_core::git::list_worktrees(&fixture.main_path)
            .unwrap()
            .len(),
        before_worktrees
    );
    let journal_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workspaceRelocations")
        .fetch_one(fixture.actor.runtime_store.pool())
        .await
        .unwrap();
    assert_eq!(journal_count, 0);
}

#[tokio::test]
async fn runtime_relocation_ids_replay_both_directions_without_losing_later_changes() {
    let mut fixture = Fixture::new().await;
    let destination = fixture._root.path().join("workspaces/request-retry");
    let hand_off_id = uuid::Uuid::new_v4().to_string();
    let hand_off = json!({
        "id": "main", "relocationId": hand_off_id, "branch": "request-retry",
        "path": destination.to_string_lossy(), "moveChanges": false,
        "sharedImpactConfirmed": true, "deferSetup": true,
    });
    let first = fixture
        .request_relocation("handOff", hand_off.clone())
        .await;
    assert_eq!(first["ok"], true, "{first}");
    std::fs::write(destination.join("after-first.txt"), "keep this").unwrap();
    let replay = fixture
        .request_relocation("handOff", hand_off.clone())
        .await;
    assert_eq!(replay["ok"], true, "{replay}");
    assert_eq!(
        replay["payload"]["workspace"]["instanceId"],
        first["payload"]["workspace"]["instanceId"]
    );
    assert_eq!(
        std::fs::read_to_string(destination.join("after-first.txt")).unwrap(),
        "keep this"
    );
    let hand_on = json!({"id": "main", "relocationId": uuid::Uuid::new_v4().to_string(), "sharedImpactConfirmed": true});
    let returning = fixture.request_relocation("handOn", hand_on.clone()).await;
    assert_eq!(returning["ok"], true, "{returning}");
    let marker = Path::new(&fixture.main_path).join("after-return.txt");
    std::fs::write(&marker, "later shared work").unwrap();
    let replay = fixture.request_relocation("handOn", hand_on).await;
    assert_eq!(replay["ok"], true, "{replay}");
    assert_eq!(
        std::fs::read_to_string(marker).unwrap(),
        "later shared work"
    );
    assert!(!destination.exists());
    let superseded = fixture.request_relocation("handOff", hand_off).await;
    assert_eq!(superseded["ok"], false, "{superseded}");
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM workspaceRelocations WHERE workspaceId = 'main'")
            .fetch_one(fixture.actor.runtime_store.pool())
            .await
            .unwrap();
    assert_eq!(count, 2);
}
