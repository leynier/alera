use super::*;

fn receipt_ref(record: &WorkflowWorkspaceRecord) -> String {
    format!(
        "refs/alera/workflow-resources/{}",
        record.identity.workspace.id
    )
}

fn verify(record: &WorkflowWorkspaceRecord) -> Result<(), core_git::GitError> {
    let identity = &record.identity;
    core_git::verify_workflow_worktree(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.base_sha,
        &identity.workspace.id,
    )
}

fn ensure(record: &WorkflowWorkspaceRecord) -> Result<(), core_git::GitError> {
    let identity = &record.identity;
    core_git::ensure_workflow_worktree(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.base_sha,
        &identity.workspace.id,
    )
}

#[tokio::test]
async fn workflow_worktrees_ownership_survives_reflog_expiry_and_gc() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let task = fixture.task("fix").await;
    let repo = git2::Repository::open(&fixture.source).unwrap();
    let receipt = repo
        .find_reference(&receipt_ref(&integration))
        .unwrap()
        .target();
    alera_core::git_cli::git_in_dir(
        &fixture.source,
        &[
            "-c",
            "gc.reflogExpire=now",
            "-c",
            "gc.reflogExpireUnreachable=now",
            "gc",
            "--prune=now",
        ],
    )
    .unwrap();
    for record in [&integration, &task] {
        let branch = format!(
            "refs/heads/{}",
            record.identity.workspace.branch.as_ref().unwrap()
        );
        assert!(repo.reflog(&branch).unwrap().is_empty());
        verify(record).unwrap();
        ensure(record).unwrap();
    }
    assert_eq!(
        repo.find_reference(&receipt_ref(&integration))
            .unwrap()
            .target(),
        receipt
    );
    assert_eq!(
        serde_json::to_value(fixture.integration().await.identity).unwrap(),
        serde_json::to_value(integration.identity).unwrap()
    );
    assert_eq!(
        serde_json::to_value(fixture.task("fix").await.identity).unwrap(),
        serde_json::to_value(task.identity).unwrap()
    );
    assert_eq!(fixture.task("other").await.phase, Phase::Ready);
}

#[tokio::test]
async fn workflow_worktrees_partial_ref_creation_promotes_authentic_receipt() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let record = fixture.reserve("fix").await;
    let repo = git2::Repository::open(&fixture.source).unwrap();
    let identity = &record.identity;
    let branch = format!("refs/heads/{}", identity.workspace.branch.as_ref().unwrap());
    repo.reference(
        &branch,
        git2::Oid::from_str(&identity.base_sha).unwrap(),
        false,
        &format!(
            "alera workflow {} at {}",
            identity.workspace.id, identity.base_sha
        ),
    )
    .unwrap();
    assert!(repo.find_reference(&receipt_ref(&record)).is_err());
    ensure(&record).unwrap();
    assert!(repo.find_reference(&receipt_ref(&record)).is_ok());
    verify(&record).unwrap();
}

#[tokio::test]
async fn workflow_worktrees_complete_checkout_promotes_missing_durable_receipt() {
    let fixture = Fixture::new("").await;
    let record = fixture.integration().await;
    let repo = git2::Repository::open(&fixture.source).unwrap();
    repo.find_reference(&receipt_ref(&record))
        .unwrap()
        .delete()
        .unwrap();
    verify(&record).unwrap();
    assert!(repo.find_reference(&receipt_ref(&record)).is_ok());
}

#[tokio::test]
async fn workflow_worktrees_corrupt_or_foreign_receipt_is_never_replaced() {
    for bytes in [b"not json".as_slice(), b"{}"] {
        let fixture = Fixture::new("").await;
        let record = fixture.integration().await;
        let repo = git2::Repository::open(&fixture.source).unwrap();
        let oid = repo.blob(bytes).unwrap();
        repo.reference(&receipt_ref(&record), oid, true, "test corruption")
            .unwrap();
        assert!(verify(&record).is_err());
        assert!(ensure(&record).is_err());
        assert_eq!(
            repo.find_reference(&receipt_ref(&record)).unwrap().target(),
            Some(oid)
        );
    }
    let fixture = Fixture::new("").await;
    let original = fixture.integration().await;
    let other = fixture.task("fix").await;
    let repo = git2::Repository::open(&fixture.source).unwrap();
    let foreign = repo
        .find_reference(&receipt_ref(&other))
        .unwrap()
        .target()
        .unwrap();
    repo.reference(
        &receipt_ref(&original),
        foreign,
        true,
        "test foreign receipt",
    )
    .unwrap();
    assert!(verify(&original).is_err());
    assert!(ensure(&original).is_err());
    assert_eq!(
        repo.find_reference(&receipt_ref(&original))
            .unwrap()
            .target(),
        Some(foreign)
    );
}

#[tokio::test]
async fn workflow_worktrees_missing_proofs_and_replaced_destinations_fail_closed() {
    let fixture = Fixture::new("").await;
    let record = fixture.integration().await;
    let repo = git2::Repository::open(&fixture.source).unwrap();
    let mut changed = record.clone();
    changed.identity.workspace.path.push_str("-foreign");
    assert!(ensure(&changed).is_err());
    assert!(!Path::new(&changed.identity.workspace.path).exists());

    repo.find_reference(&receipt_ref(&record))
        .unwrap()
        .delete()
        .unwrap();
    let branch = format!(
        "refs/heads/{}",
        record.identity.workspace.branch.as_ref().unwrap()
    );
    repo.reflog_delete(&branch).unwrap();
    assert!(verify(&record).is_err());
    assert!(ensure(&record).is_err());
    assert!(repo.find_reference(&receipt_ref(&record)).is_err());
    assert!(Path::new(&record.identity.workspace.path)
        .join("shared.txt")
        .exists());
}

#[tokio::test]
async fn workflow_worktrees_durable_receipt_does_not_recreate_deleted_branch() {
    let fixture = Fixture::new("").await;
    let record = fixture.integration().await;
    let repo = git2::Repository::open(&fixture.source).unwrap();
    let branch = format!(
        "refs/heads/{}",
        record.identity.workspace.branch.as_ref().unwrap()
    );
    repo.find_reference(&branch).unwrap().delete().unwrap();
    assert!(ensure(&record).is_err());
    assert!(verify(&record).is_err());
    assert!(repo.find_reference(&branch).is_err());
    assert!(repo.find_reference(&receipt_ref(&record)).is_ok());
}
