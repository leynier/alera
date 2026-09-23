use super::*;

fn fixture() -> (tempfile::TempDir, String, git2::Repository) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("repository");
    let repo = git2::Repository::init(&path).unwrap();
    repo.set_head("refs/heads/main").unwrap();
    let tree = repo.index().unwrap().write_tree().unwrap();
    let signature = git2::Signature::now("Test", "test@example.test").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "Initial",
        &repo.find_tree(tree).unwrap(),
        &[],
    )
    .unwrap();
    (
        dir,
        path.canonicalize().unwrap().to_str().unwrap().into(),
        repo,
    )
}

fn args(repository: &str, path: &std::path::Path) -> CreateCheckoutWorktreeArgs {
    CreateCheckoutWorktreeArgs {
        repository: repository.into(),
        path: path.to_str().unwrap().into(),
        branch: "new-task".into(),
        source: "main".into(),
        reuse_existing_branch: false,
    }
}

#[tokio::test]
async fn creates_on_owner_repository_without_changing_main_branch_or_files() {
    let (dir, repository, repo) = fixture();
    std::fs::write(std::path::Path::new(&repository).join("shared"), "preserve").unwrap();
    let destination = dir.path().join("tasks/linked");
    let result = create(args(&repository, &destination)).await.unwrap();
    assert_eq!(result.repository_path, repository);
    assert_eq!(result.branch, "new-task");
    assert_eq!(
        alera_core::git::current_branch(&repository).unwrap(),
        "main"
    );
    assert_eq!(
        alera_core::git::current_branch(&result.path).unwrap(),
        "new-task"
    );
    assert_eq!(repo.worktrees().unwrap().len(), 1);
    assert_eq!(
        std::fs::read_to_string(std::path::Path::new(&repository).join("shared")).unwrap(),
        "preserve"
    );
    assert!(!destination.join("shared").exists());
    let mut reuse = args(&repository, &dir.path().join("second"));
    reuse.reuse_existing_branch = true;
    assert!(create(reuse)
        .await
        .unwrap_err()
        .to_string()
        .contains("already checked out"));
    assert_eq!(repo.worktrees().unwrap().len(), 1);
}

#[tokio::test]
async fn rejects_existing_destination_before_creating_branch() {
    let (dir, repository, repo) = fixture();
    let destination = dir.path().join("occupied");
    std::fs::create_dir(&destination).unwrap();
    std::fs::write(destination.join("keep"), "original").unwrap();
    assert!(create(args(&repository, &destination)).await.is_err());
    assert!(repo
        .find_branch("new-task", git2::BranchType::Local)
        .is_err());
    assert_eq!(
        std::fs::read_to_string(destination.join("keep")).unwrap(),
        "original"
    );
}

#[tokio::test]
async fn uses_remote_tracking_reference_already_present_on_owner_without_fetching() {
    let (dir, repository, repo) = fixture();
    repo.remote("origin", "https://example.invalid/repository.git")
        .unwrap();
    let main = repo.head().unwrap().peel_to_commit().unwrap();
    let signature = git2::Signature::now("Test", "test@example.test").unwrap();
    let remote_commit = repo
        .commit(
            Some("refs/remotes/origin/source"),
            &signature,
            &signature,
            "Remote-only commit",
            &main.tree().unwrap(),
            &[&main],
        )
        .unwrap();
    let mut request = args(&repository, &dir.path().join("remote-source"));
    request.source = "origin/source".into();
    let result = create(request).await.unwrap();
    assert_eq!(
        git2::Repository::open(&result.path)
            .unwrap()
            .head()
            .unwrap()
            .target(),
        Some(remote_commit)
    );
    assert_eq!(repo.head().unwrap().target(), Some(main.id()));
    let upstream = repo
        .find_branch("new-task", git2::BranchType::Local)
        .unwrap()
        .upstream()
        .unwrap();
    assert_eq!(upstream.name().unwrap(), Some("origin/source"));
}
