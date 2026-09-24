use super::*;

#[tokio::test]
async fn clone_rejects_existing_empty_and_populated_directories() {
    let dir = tempfile::tempdir().unwrap();
    for populated in [false, true] {
        let destination = dir
            .path()
            .join(if populated { "populated" } else { "empty" });
        std::fs::create_dir(&destination).unwrap();
        if populated {
            std::fs::write(destination.join("keep"), "original").unwrap();
        }
        let error = clone_checkout(CloneCheckoutArgs {
            url: "/unused-source".into(),
            path: destination.to_str().unwrap().into(),
        })
        .await
        .unwrap_err();
        assert!(error.to_string().contains("new directory"));
        assert_eq!(
            std::fs::read_dir(&destination).unwrap().count(),
            usize::from(populated)
        );
    }
}

#[tokio::test]
async fn clones_an_isolated_repository_and_keeps_failed_destination() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    let repo = git2::Repository::init(&source).unwrap();
    repo.set_head("refs/heads/main").unwrap();
    let signature = git2::Signature::now("Test", "test@example.test").unwrap();
    let tree = repo.index().unwrap().write_tree().unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "Initial",
        &repo.find_tree(tree).unwrap(),
        &[],
    )
    .unwrap();
    let destination = dir.path().join("cloned");
    let result = clone_checkout(CloneCheckoutArgs {
        url: source.to_str().unwrap().into(),
        path: destination.to_str().unwrap().into(),
    })
    .await
    .unwrap();
    assert_eq!(result.branch.as_deref(), Some("main"));
    assert_eq!(
        result.path,
        destination.canonicalize().unwrap().to_str().unwrap()
    );
    assert_eq!(
        repo.head().unwrap().target(),
        git2::Repository::open(&destination)
            .unwrap()
            .head()
            .unwrap()
            .target()
    );
    let failed = dir.path().join("failed");
    let error = clone_checkout(CloneCheckoutArgs {
        url: dir.path().join("missing-source").to_str().unwrap().into(),
        path: failed.to_str().unwrap().into(),
    })
    .await
    .unwrap_err();
    assert!(error.to_string().contains("retained"));
    assert!(failed.is_dir());
}

#[cfg(unix)]
#[tokio::test]
async fn clone_rejects_symlink_destination_without_touching_its_target() {
    let dir = tempfile::tempdir().unwrap();
    let target = dir.path().join("target");
    std::fs::create_dir(&target).unwrap();
    std::fs::write(target.join("keep"), "original").unwrap();
    let link = dir.path().join("link");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    assert!(clone_checkout(CloneCheckoutArgs {
        url: "/unused-source".into(),
        path: link.to_str().unwrap().into()
    })
    .await
    .is_err());
    assert_eq!(
        std::fs::read_to_string(target.join("keep")).unwrap(),
        "original"
    );
    assert!(std::fs::symlink_metadata(&link).unwrap().is_symlink());
}
