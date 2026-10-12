use super::*;

#[tokio::test]
async fn workflow_worktrees_snapshots_derive_retained_ownership_and_reject_replacement() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let attempt = fixture.task("fix").await;
    let checkout = git2::Repository::open(&attempt.identity.workspace.path).unwrap();
    checkout
        .set_head_detached(git2::Oid::from_str(&attempt.identity.base_sha).unwrap())
        .unwrap();
    let mut replacement = attempt.identity.workspace.clone();
    replacement.branch = Some("HEAD".into());
    assert!(fixture.store.upsert_workspace(replacement).await.is_err());
    std::fs::rename(
        &attempt.identity.workspace.path,
        Path::new(&attempt.identity.workspace.path).with_file_name("retained-checkout"),
    )
    .unwrap();
    fixture.store.reset_orchestration_tasks().await.unwrap();
    let snapshot = fixture
        .store
        .list_workspace_snapshots("project")
        .await
        .unwrap();
    assert_eq!(snapshot.len(), 3);
    for item in &snapshot {
        assert_eq!(item.workflow_owned, item.workspace.id != "owner");
    }
    let task = snapshot
        .iter()
        .find(|item| item.workspace.id == attempt.identity.workspace.id)
        .unwrap();
    assert_eq!(task.workspace.branch, attempt.identity.workspace.branch);
    assert_eq!(task.workspace.path, attempt.identity.workspace.path);
    let json = serde_json::to_value(&snapshot).unwrap();
    assert!(json.as_array().unwrap().iter().any(|item| {
        item["id"] == integration.identity.workspace.id && item["workflowOwned"] == true
    }));
    assert!(fixture
        .store
        .list_workspace_snapshots("another-project")
        .await
        .unwrap()
        .is_empty());
    let owner = fixture
        .store
        .find_workspace("owner")
        .await
        .unwrap()
        .unwrap();
    let mut forged = serde_json::to_value(&owner).unwrap();
    forged["workflowOwned"] = json!(true);
    fixture
        .store
        .upsert_workspace(serde_json::from_value(forged).unwrap())
        .await
        .unwrap();
    assert!(
        !fixture
            .store
            .list_workspace_snapshots("project")
            .await
            .unwrap()
            .iter()
            .find(|item| item.workspace.id == "owner")
            .unwrap()
            .workflow_owned
    );
}
