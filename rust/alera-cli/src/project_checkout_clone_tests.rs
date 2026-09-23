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
            path: Some(destination.to_str().unwrap().into()),
            name: None,
            projects_dir: None,
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
        path: Some(destination.to_str().unwrap().into()),
        name: None,
        projects_dir: None,
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
        path: Some(failed.to_str().unwrap().into()),
        name: None,
        projects_dir: None,
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
        path: Some(link.to_str().unwrap().into()),
        name: None,
        projects_dir: None,
    })
    .await
    .is_err());
    assert_eq!(
        std::fs::read_to_string(target.join("keep")).unwrap(),
        "original"
    );
    assert!(std::fs::symlink_metadata(&link).unwrap().is_symlink());
}

#[test]
fn a_default_clone_takes_the_first_free_name_and_rejects_paths() {
    let projects = tempfile::tempdir().unwrap();
    assert_eq!(
        first_free_destination(projects.path(), "alera"),
        projects.path().join("alera")
    );
    std::fs::create_dir(projects.path().join("alera")).unwrap();
    std::fs::write(
        projects.path().join("alera-2"),
        "a file also occupies the name",
    )
    .unwrap();
    assert_eq!(
        first_free_destination(projects.path(), "alera"),
        projects.path().join("alera-3")
    );
    for name in ["", " ", ".", "..", "a/b", "a\\b", "c:repo"] {
        assert!(default_clone_destination(name, None).is_err(), "{name:?}");
    }
}

#[test]
fn a_configured_projects_folder_is_expanded_on_this_host() {
    let home = std::path::Path::new(if cfg!(windows) {
        r"C:\Users\me"
    } else {
        "/home/me"
    });
    assert_eq!(
        expand_projects_dir("~/code", home).unwrap(),
        home.join("code")
    );
    assert_eq!(expand_projects_dir("~", home).unwrap(), home);
    assert_eq!(
        expand_projects_dir("$HOME/src", home).unwrap(),
        home.join("src")
    );
    assert_eq!(
        expand_projects_dir("projects", home).unwrap(),
        home.join("projects")
    );
    let absolute = if cfg!(windows) {
        r"D:\work"
    } else {
        "/srv/work"
    };
    assert_eq!(
        expand_projects_dir(absolute, home).unwrap(),
        std::path::PathBuf::from(absolute)
    );
    std::env::set_var("ALERA_TEST_PROJECTS_ROOT", absolute);
    assert_eq!(
        expand_projects_dir("%ALERA_TEST_PROJECTS_ROOT%", home).unwrap(),
        std::path::PathBuf::from(absolute)
    );
    std::env::remove_var("ALERA_TEST_PROJECTS_ROOT");
    assert!(expand_projects_dir("%ALERA_TEST_UNSET_VARIABLE%", home).is_err());
}
