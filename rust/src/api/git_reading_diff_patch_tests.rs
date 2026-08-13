use std::fs;

use git2::{IndexAddOption, Oid, Repository, Signature};

use super::*;

#[test]
fn extracts_worktree_staged_commit_and_range_patches() {
    let directory = tempfile::tempdir().expect("tempdir");
    let repository = Repository::init(directory.path()).expect("repository");
    let file = directory.path().join("app.txt");
    fs::write(&file, "before\n").expect("initial file");
    let base = commit(&repository, "base");

    fs::write(&file, "worktree\n").expect("worktree file");
    let worktree = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        Some("app.txt".to_string()),
        None,
        Some(GitChangeArea::Unstaged),
        None,
        None,
        None,
    )
    .expect("worktree patch");
    assert!(worktree
        .windows(b"+worktree".len())
        .any(|row| row == b"+worktree"));

    let mut index = repository.index().expect("index");
    index
        .add_path(std::path::Path::new("app.txt"))
        .expect("stage");
    index.write().expect("write index");
    let staged = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        None,
    )
    .expect("staged patch");
    assert!(staged
        .windows(b"-before".len())
        .any(|row| row == b"-before"));

    let head = commit(&repository, "change");
    let commit_patch = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        None,
        Some(head.to_string()),
        Some(base.to_string()),
        None,
    )
    .expect("commit patch");
    let range_patch = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        None,
        None,
        None,
        Some(base.to_string()),
    )
    .expect("range patch");
    assert_eq!(range_patch, commit_patch);
}

#[test]
fn preserves_rename_sources_and_untracked_placeholders() {
    let directory = tempfile::tempdir().expect("tempdir");
    let repository = Repository::init(directory.path()).expect("repository");
    fs::write(directory.path().join("old.txt"), "unchanged content\n").expect("old file");
    let base = commit(&repository, "base");
    fs::rename(
        directory.path().join("old.txt"),
        directory.path().join("new.txt"),
    )
    .expect("rename");
    let mut index = repository.index().expect("index");
    index
        .add_all(["*"], IndexAddOption::DEFAULT, None)
        .expect("stage rename");
    index.write().expect("write rename index");
    let staged_rename = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        None,
    )
    .expect("staged rename patch");
    let staged_rename = String::from_utf8(staged_rename).expect("utf8 staged rename");
    assert!(staged_rename.contains("rename from old.txt"));
    assert!(staged_rename.contains("rename to new.txt"));
    let head = commit(&repository, "rename");

    let rename = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        Some("new.txt".to_string()),
        Some("old.txt".to_string()),
        None,
        Some(head.to_string()),
        Some(base.to_string()),
        None,
    )
    .expect("rename patch");
    let rename = String::from_utf8(rename).expect("utf8 rename");
    assert!(rename.contains("rename from old.txt"));
    assert!(rename.contains("rename to new.txt"));

    fs::write(directory.path().join("binary.bin"), [0, 1, 2, 3]).expect("binary file");
    fs::write(
        directory.path().join("large.txt"),
        vec![b'x'; 256 * 1024 + 1],
    )
    .expect("large file");
    let untracked = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Untracked),
        None,
        None,
        None,
    )
    .expect("untracked patch");
    let untracked = String::from_utf8(untracked).expect("utf8 placeholders");
    assert!(untracked.contains("Binary file /dev/null and b/binary.bin differ"));
    assert!(untracked.contains("Large file above the 256 KiB text preview limit"));
    assert!(untracked.contains("b/large.txt differ"));
}

#[test]
fn expands_dirty_submodule_worktrees() {
    let child_directory = tempfile::tempdir().expect("child tempdir");
    let child = Repository::init(child_directory.path()).expect("child repository");
    fs::write(child_directory.path().join("inside.txt"), "before\n").expect("child file");
    fs::write(child_directory.path().join("tracked.bin"), [0, 1, 2]).expect("tracked binary");
    commit(&child, "child base");

    let parent_directory = tempfile::tempdir().expect("parent tempdir");
    let parent = Repository::init(parent_directory.path()).expect("parent repository");
    fs::write(parent_directory.path().join("root.txt"), "root\n").expect("root file");
    commit(&parent, "parent base");
    let mut submodule = parent
        .submodule(
            child_directory.path().to_string_lossy().as_ref(),
            std::path::Path::new("deps/child"),
            true,
        )
        .expect("configure submodule");
    submodule.clone(None).expect("clone submodule");
    submodule.add_to_index(true).expect("index submodule");
    submodule.add_finalize().expect("finalize submodule");
    commit(&parent, "add submodule");

    fs::write(
        parent_directory.path().join("deps/child/inside.txt"),
        "after\n",
    )
    .expect("modify child");
    fs::write(
        parent_directory.path().join("deps/child/tracked.bin"),
        [0, 3, 2],
    )
    .expect("modify tracked binary");
    fs::write(
        parent_directory.path().join("deps/child/untracked.bin"),
        [0, 4, 2],
    )
    .expect("create untracked binary");
    let patch = git_reading_diff_patch(
        parent_directory.path().to_string_lossy().to_string(),
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("submodule patch");
    let patch = String::from_utf8(patch).expect("utf8 patch");
    assert!(patch.contains("diff --git a/deps/child/inside.txt"));
    assert!(patch.contains("-before"));
    assert!(patch.contains("+after"));
    assert!(
        patch.contains("Binary files a/deps/child/tracked.bin and b/deps/child/tracked.bin differ")
    );
    assert!(patch.contains("Binary file /dev/null and b/deps/child/untracked.bin differ"));
}

fn commit(repository: &Repository, message: &str) -> Oid {
    let mut index = repository.index().expect("index");
    index
        .add_all(["*"], IndexAddOption::DEFAULT, None)
        .expect("add files");
    index.write().expect("write index");
    let tree = repository
        .find_tree(index.write_tree().expect("tree id"))
        .expect("tree");
    let signature = Signature::now("Alera", "alera@example.com").expect("signature");
    let parent = repository
        .head()
        .ok()
        .and_then(|head| head.target())
        .map(|oid| repository.find_commit(oid).expect("parent"));
    let parents = parent.iter().collect::<Vec<_>>();
    repository
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )
        .expect("commit")
}
